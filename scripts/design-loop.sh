#!/bin/bash
# design-loop.sh — one pass of the design iteration loop on the iOS Simulator.
#
# Builds OuisprApp from a checkout, installs it on a dedicated simulator ("Ouispr Loop"),
# opens a screen, then captures it under every rendering variant an agent must check:
# light/dark × default text/largest accessibility text × animations/Reduce Motion.
# With --video it also records each variant from launch, cuts the recording into frames,
# tiles them into a filmstrip and writes a per-frame motion profile (how much of the
# screen changed between two frames), so easing, duration and settling can be read
# without watching the video.
#
# Nothing here touches a physical iPhone, records from the microphone or downloads a model.
# The simulator is headless (Xcode 27 has no Simulator.app) and is kept between passes so
# each pass is an incremental build (~1 min) instead of a cold one (~10 min).
#
# Usage:
#   scripts/design-loop.sh [--src DIR] [--name NAME] [--no-build] [--goto LABEL]...
#                          [--variants LIST] [--video SECONDS] [--settle SECONDS]
#
#   --src DIR        checkout to build (default: this script's repository)
#   --name NAME      short name for the pass, used in the output directory (default: pass)
#   --no-build       reinstall the last build of --src instead of building
#   --goto LABEL     after launch, tap the element with this accessibility label;
#                    repeatable, applied in order ("tab:Modèles" taps a tab bar item)
#   --variants LIST  comma-separated, from: light dark light-xl dark-xl light-rm dark-rm
#                    (default: all six; -xl = accessibility-extra-extra-extra-large text,
#                    -rm = Reduce Motion on)
#   --video SECONDS  record each variant for this long from launch (default: no video)
#   --settle SECONDS wait before the screenshot (default: 3)
#
# Output: ~/dev/ouispr-evidence/design-loop/<time>-<sha>-<name>/, with one PNG per
# variant, grid.png (all variants side by side, in the --variants order), and with
# --video: <variant>.mp4, <variant>-strip.png (frames at 20 fps, left to right, top to
# bottom) and <variant>-motion.csv. summary.txt lists everything and ends with
# "LOOP DONE <dir>".
set -euo pipefail

SCRIPT_REPO=$(cd "$(dirname "$0")/.." && pwd)
SRC=$SCRIPT_REPO
NAME=pass
BUILD=yes
GOTO=()
VARIANTS="light,dark,light-xl,dark-xl,light-rm,dark-rm"
VIDEO=0
SETTLE=3

while [ $# -gt 0 ]; do
  case "$1" in
    --src) SRC=$(cd "$2" && pwd); shift 2 ;;
    --name) NAME=$2; shift 2 ;;
    --no-build) BUILD=no; shift ;;
    --goto) GOTO+=("$2"); shift 2 ;;
    --variants) VARIANTS=$2; shift 2 ;;
    --video) VIDEO=$2; shift 2 ;;
    --settle) SETTLE=$2; shift 2 ;;
    -h|--help) sed -n '2,38p' "$0"; exit 0 ;;
    *) echo "error: unknown option $1" >&2; exit 2 ;;
  esac
done

die() { echo "error: $*" >&2; exit 1; }
say() { echo "[design-loop] $*"; }

APP_ID=${OUISPR_LOOP_APP_ID:-com.pivi.dictus}
APP_GROUP=${OUISPR_LOOP_APP_GROUP:-group.solutions.pivi.dictus}
DEVICE_NAME=${OUISPR_LOOP_DEVICE:-Ouispr Loop}
DEVICE_TYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro
# iOS 26 rather than 27: on 27 the system may mount no third-party keyboard
# (docs/agents/simulator.md), and the keyboard screens are part of what this loop checks.
RUNTIME=${OUISPR_LOOP_RUNTIME:-$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
ids = [r["identifier"] for r in json.load(sys.stdin)["runtimes"]
       if r["isAvailable"] and r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-26")]
print(sorted(ids)[-1] if ids else "")')}
[ -n "$RUNTIME" ] || die "no iOS 26 simulator runtime installed (set OUISPR_LOOP_RUNTIME)"

DERIVED_DATA="$SRC/build/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/OuisprApp.app"
SHA=$(git -C "$SRC" rev-parse --short HEAD)
# "+dirty" only for uncommitted changes to what the app is built from.
DIRTY=$([ -n "$(git -C "$SRC" status --porcelain -- Ouispr OuisprApp OuisprKeyboard OuisprCore \
  OuisprWidgets OuisprShare Ouispr.xcodeproj ':!*.xcstrings')" ] && echo "+dirty" || true)
OUT="${OUISPR_LOOP_EVIDENCE:-$HOME/dev/ouispr-evidence/design-loop}/$(date +%Y%m%d-%H%M%S)-$SHA$DIRTY-$NAME"
mkdir -p "$OUT"

# --- Device: created once, kept, never erased ---------------------------------
UDID=$(xcrun simctl list devices -j | python3 -c '
import json, sys
name = sys.argv[1]
for devs in json.load(sys.stdin)["devices"].values():
    for d in devs:
        if d["name"] == name and d["isAvailable"]:
            print(d["udid"]); sys.exit(0)' "$DEVICE_NAME" || true)
if [ -z "$UDID" ]; then
  UDID=$(xcrun simctl create "$DEVICE_NAME" "$DEVICE_TYPE" "$RUNTIME")
  # French device with the Ouispr keyboard enabled, written while it is shut down.
  PREFS="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Library/Preferences/.GlobalPreferences.plist"
  python3 - "$PREFS" <<'PY'
import os, plistlib, sys
path = sys.argv[1]
prefs = plistlib.load(open(path, "rb")) if os.path.exists(path) else {}
prefs["AppleLanguages"], prefs["AppleLocale"] = ["fr-FR", "en-GB"], "fr_FR"
prefs["AppleKeyboards"] = ["fr_FR@sw=AZERTY-French;hw=Automatic", "emoji@sw=Emoji",
                           "com.pivi.dictus.keyboard"]
prefs["AppleKeyboardsExpanded"] = 1
os.makedirs(os.path.dirname(path), exist_ok=True)
plistlib.dump(prefs, open(path, "wb"))
PY
  say "created $DEVICE_NAME $UDID"
fi
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl status_bar "$UDID" override --time "09:41" --batteryState charged \
  --batteryLevel 100 --cellularBars 4 --wifiBars 3 >/dev/null 2>&1 || true

# --- Build and install --------------------------------------------------------
if [ "$BUILD" = yes ]; then
  XCSTRINGS_BEFORE=$(git -C "$SRC" diff --name-only -- '*.xcstrings')
  if [ ! -d "$DERIVED_DATA/SourcePackages/checkouts" ]; then
    say "resolving packages (fresh checkout)"
    (cd "$SRC" && xcodebuild -resolvePackageDependencies -project Ouispr.xcodeproj \
      -scheme OuisprApp -derivedDataPath "$DERIVED_DATA") >"$OUT/resolve.log" 2>&1 \
      || die "package resolution failed, see $OUT/resolve.log"
  fi
  say "building $SHA$DIRTY from $SRC"
  START=$(date +%s)
  (cd "$SRC" && xcodebuild build -project Ouispr.xcodeproj -scheme OuisprApp \
    -configuration Debug -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$DERIVED_DATA") >"$OUT/build.log" 2>&1 \
    || { grep -E "error:" "$OUT/build.log" | head -20 >&2; die "build failed, see $OUT/build.log"; }
  say "built in $(( $(date +%s) - START )) s"
  # The build rewrites Localizable.xcstrings: build noise, never committed (CLAUDE.md).
  if [ -z "$XCSTRINGS_BEFORE" ]; then
    CHANGED=$(git -C "$SRC" diff --name-only -- '*.xcstrings')
    [ -z "$CHANGED" ] || (cd "$SRC" && echo "$CHANGED" | xargs git checkout --)
  fi
fi
[ -d "$APP_PATH" ] || die "no build at $APP_PATH (drop --no-build)"
xcrun simctl install "$UDID" "$APP_PATH"

# Skip onboarding: the flag lives in the App Group suite, so a launch argument does not
# reach it. The container exists only once the app is installed.
GROUP_DIR=$(xcrun simctl get_app_container "$UDID" "$APP_ID" groups \
  | awk -F'\t' -v g="$APP_GROUP" '$1 == g { print $2 }')
[ -n "$GROUP_DIR" ] || die "no App Group container for $APP_GROUP (unsigned build?)"
xcrun simctl spawn "$UDID" defaults write \
  "$GROUP_DIR/Library/Preferences/$APP_GROUP.plist" ouispr.hasCompletedOnboarding -bool YES

# Warm-up launch: the first launch after an install shows one-time sheets (what's new)
# and the freshly booted system posts its own notifications. Both would land in the first
# variant's capture; letting them pass here keeps every variant comparable.
xcrun simctl launch "$UDID" "$APP_ID" >/dev/null || die "warm-up launch failed"
sleep 6
xcrun simctl terminate "$UDID" "$APP_ID" >/dev/null 2>&1 || true

# --- One variant: settings, relaunch, navigate, capture ------------------------
set_reduce_motion() {
  # Not exposed by `simctl ui`: written to the accessibility domain, read by the app at
  # launch (each variant relaunches the app).
  xcrun simctl spawn "$UDID" defaults write com.apple.Accessibility ReduceMotionEnabled -bool "$1"
}

navigate() {
  local target
  for target in ${GOTO[@]+"${GOTO[@]}"}; do
    if [[ "$target" == tab:* ]]; then
      axe tap --label "${target#tab:}" --element-type RadioButton --udid "$UDID" >/dev/null \
        || die "could not tap tab ${target#tab:}"
    else
      axe tap --label "$target" --udid "$UDID" >/dev/null || die "could not tap '$target'"
    fi
    sleep 1
  done
}

capture_variant() {
  local v=$1 appearance=${1%%-*} size=large rm=NO
  case "$v" in *-xl) size=accessibility-extra-extra-extra-large ;; *-rm) rm=YES ;; esac
  xcrun simctl terminate "$UDID" "$APP_ID" >/dev/null 2>&1 || true
  xcrun simctl ui "$UDID" appearance "$appearance"
  xcrun simctl ui "$UDID" content_size "$size"
  set_reduce_motion "$rm"
  sleep 1

  local rec_pid=""
  if [ "$VIDEO" != 0 ]; then
    xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$OUT/$v.mp4" >/dev/null 2>&1 &
    rec_pid=$!
    sleep 1   # recordVideo needs a moment before its first frame
  fi
  xcrun simctl launch "$UDID" "$APP_ID" >/dev/null || die "launch failed ($v)"
  navigate
  if [ -n "$rec_pid" ]; then
    sleep "$VIDEO"
    kill -INT "$rec_pid"; wait "$rec_pid" 2>/dev/null || true
  else
    sleep "$SETTLE"
  fi
  xcrun simctl io "$UDID" screenshot "$OUT/$v.png" >/dev/null 2>&1 || die "screenshot failed ($v)"

  if [ -n "$rec_pid" ] && [ -s "$OUT/$v.mp4" ]; then
    # Filmstrip: 20 fps, 10 frames per row, each frame 180 px wide.
    local frames
    frames=$(ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames \
      -of csv=p=0 "$OUT/$v.mp4" 2>/dev/null || echo 0)
    local rows=$(( (VIDEO * 20 + 9) / 10 + 1 ))
    ffmpeg -v error -y -i "$OUT/$v.mp4" -vf "fps=20,scale=180:-2,tile=10x$rows:padding=4:color=gray" \
      -frames:v 1 "$OUT/$v-strip.png"
    # Motion profile: mean luma difference between consecutive frames (0 = still).
    # A smooth ease-out shows as a peak decaying to 0; a hard stop as a cliff; an endless
    # loop never reaches 0. Times are seconds from the start of the recording.
    ffmpeg -v error -i "$OUT/$v.mp4" -vf "tblend=all_mode=difference,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-" \
      -f null - 2>/dev/null | python3 -c '
import sys
t = None
print("time_s,change")
for line in sys.stdin:
    if line.startswith("frame:"):
        t = float(line.split("pts_time:")[1])
    elif "YAVG=" in line and t is not None:
        print("%.3f,%.3f" % (t, float(line.split("=")[1])))' >"$OUT/$v-motion.csv"
    echo "$v: video ${VIDEO}s, $frames frames" >>"$OUT/summary.txt"
  fi
  echo "$v: $v.png (appearance=$appearance text=$size reduceMotion=$rm)" >>"$OUT/summary.txt"
  say "captured $v"
}

{
  echo "commit: $SHA$DIRTY ($SRC)"
  echo "device: $DEVICE_NAME $UDID ($RUNTIME)"
  echo "goto: ${GOTO[*]:-(home)}"
} >"$OUT/summary.txt"

IFS=',' read -r -a VLIST <<<"$VARIANTS"
for v in "${VLIST[@]}"; do
  case "$v" in light|dark|light-xl|dark-xl|light-rm|dark-rm) ;; *) die "unknown variant $v" ;; esac
  capture_variant "$v"
done

# Leave the device as a person would find it.
xcrun simctl ui "$UDID" appearance light
xcrun simctl ui "$UDID" content_size large
set_reduce_motion NO

# Grid: every variant side by side, 400 px wide each, in the --variants order.
INPUTS=(); FILTER=""; i=0
for v in "${VLIST[@]}"; do
  INPUTS+=(-i "$OUT/$v.png"); FILTER+="[$i:v]scale=400:-2[s$i];"; i=$((i + 1))
done
if [ "$i" -gt 1 ]; then
  STACK=""; for j in $(seq 0 $((i - 1))); do STACK+="[s$j]"; done
  ffmpeg -v error -y "${INPUTS[@]}" -filter_complex "${FILTER}${STACK}hstack=inputs=$i" "$OUT/grid.png"
  echo "grid: grid.png (left to right: ${VARIANTS//,/, })" >>"$OUT/summary.txt"
fi

echo "LOOP DONE $OUT" | tee -a "$OUT/summary.txt"
