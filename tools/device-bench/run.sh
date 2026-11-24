#!/bin/bash
# run.sh — drive the on-device bench from the Mac. See README.md.
#
#   tools/device-bench/run.sh push    copy the corpus into Ouispr's Documents on the iPhone
#   tools/device-bench/run.sh start [fresh]  launch Ouispr with --device-bench (it runs by itself);
#                                     it resumes after the last clip written, unless `fresh`
#   tools/device-bench/run.sh status  print the phase and how many clips are done
#   tools/device-bench/run.sh pull    copy the results back to build/device-bench/out
#   tools/device-bench/run.sh wait    poll every 2 minutes until done or failed, then pull
#
# Environment: DEVICE (default: first paired iPhone), BUNDLE (default com.pivi.dictus.2TAS4PL5SA,
# the id scripts/install-on-device.sh signs with), CORPUS (default build/device-bench/corpus).
set -euo pipefail
cd "$(dirname "$0")/../.."

BUNDLE="${BUNDLE:-com.pivi.dictus.2TAS4PL5SA}"
CORPUS="${CORPUS:-build/device-bench/corpus}"
OUT="build/device-bench/out"
DEVICE="${DEVICE:-$(xcrun devicectl list devices 2>/dev/null | awk '/iPhone/ && /available/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) {print $i; exit}}')}"
[ -n "$DEVICE" ] || { echo "No paired iPhone found. Plug it in and unlock it."; exit 1; }

copy_from() {  # <remote> <local-dir>
  xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer \
    --domain-identifier "$BUNDLE" --source "$1" --destination "$2" >/dev/null
}

case "${1:-}" in
  push)
    [ -f "$CORPUS/corpus.tsv" ] || { echo "No corpus at $CORPUS (see README.md)."; exit 1; }
    xcrun devicectl device copy to --device "$DEVICE" --domain-type appDataContainer \
      --domain-identifier "$BUNDLE" --source "$CORPUS" --destination Documents/device-bench/corpus
    ;;
  start)
    ARGS=(--device-bench); [ "${2:-}" = fresh ] && ARGS+=(--device-bench-fresh)
    xcrun devicectl device process launch --device "$DEVICE" --terminate-existing "$BUNDLE" "${ARGS[@]}"
    echo "Started. Keep the iPhone unlocked, on the cable, with Ouispr in front."
    ;;
  status|pull)
    mkdir -p "$OUT"
    copy_from Documents/device-bench/out "$OUT"
    echo "phase: $(tr '\n' ' ' < "$OUT/phase.txt" 2>/dev/null || echo '?')"
    echo "progress: $(cat "$OUT/progress.txt" 2>/dev/null || echo '?')"
    if [ "$1" = pull ]; then echo "results: $OUT/results.tsv"; fi
    ;;
  wait)
    while true; do
      "$0" status || true
      phase="$(head -1 "$OUT/phase.txt" 2>/dev/null || echo '?')"
      [ "$phase" = done ] || [ "$phase" = failed ] && break
      sleep 120
    done
    "$0" pull
    ;;
  *)
    sed -n '2,12p' "$0"; exit 2 ;;
esac
