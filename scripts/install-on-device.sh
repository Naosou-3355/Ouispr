#!/bin/bash
# install-on-device.sh — build Ouispr and install it on a cable-connected iPhone with a
# free Apple ID (Personal Team), without AltStore or AltServer.
#
# A free Apple ID cannot use the project's own team, bundle identifiers or App Group, so
# for the build only this script signs with `<id>.<TEAM>` and `group.solutions.pivi.dictus.<TEAM>`,
# the names AltStore used, and writes ALTAppGroups into each Info.plist so AppGroup.identifier
# finds the group (see OuisprCore/Sources/OuisprCore/AppGroup.swift). It restores the files
# afterwards, so nothing it changes is ever committed.
#
# A free Apple ID's signature lasts 7 days: run this again to renew it.
#
# Usage: scripts/install-on-device.sh [TEAM_ID] [DEVICE_ID]
#   TEAM_ID   defaults to 2TAS4PL5SA
#   DEVICE_ID defaults to the first paired iPhone `devicectl` lists
set -euo pipefail

cd "$(dirname "$0")/.."
TEAM="${1:-2TAS4PL5SA}"
DEVICE="${2:-$(xcrun devicectl list devices 2>/dev/null | awk '/iPhone/ && /available/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) {print $i; exit}}')}"
[ -n "$DEVICE" ] || { echo "No paired iPhone found. Plug it in, unlock it and tap Trust."; exit 1; }

GROUP="group.solutions.pivi.dictus.$TEAM"
TARGETS=(OuisprApp OuisprKeyboard OuisprShare OuisprWidgets)
FILES=(Ouispr.xcodeproj/project.pbxproj)
for t in "${TARGETS[@]}"; do FILES+=("$t/$t.entitlements" "$t/Info.plist"); done

# Back the files up and copy them back on exit: `git checkout` would bring back the
# index's copy, which is not the working tree's when the files have uncommitted changes.
BACKUP="$(mktemp -d)"
for f in "${FILES[@]}"; do mkdir -p "$BACKUP/$(dirname "$f")"; cp -p "$f" "$BACKUP/$f"; done
restore() { for f in "${FILES[@]}"; do cp -p "$BACKUP/$f" "$f"; done; rm -rf "$BACKUP"; }
trap restore EXIT

sed -i '' \
  -e "s/DEVELOPMENT_TEAM = [A-Z0-9]*;/DEVELOPMENT_TEAM = $TEAM;/" \
  -e "s/PRODUCT_BUNDLE_IDENTIFIER = com\.pivi\.dictus;/PRODUCT_BUNDLE_IDENTIFIER = com.pivi.dictus.$TEAM;/" \
  -e "s/PRODUCT_BUNDLE_IDENTIFIER = com\.pivi\.dictus\.keyboard;/PRODUCT_BUNDLE_IDENTIFIER = com.pivi.dictus.$TEAM.keyboard;/" \
  -e "s/PRODUCT_BUNDLE_IDENTIFIER = com\.pivi\.dictus\.share;/PRODUCT_BUNDLE_IDENTIFIER = com.pivi.dictus.$TEAM.share;/" \
  -e "s/PRODUCT_BUNDLE_IDENTIFIER = com\.pivi\.dictus\.widgets;/PRODUCT_BUNDLE_IDENTIFIER = com.pivi.dictus.$TEAM.widgets;/" \
  Ouispr.xcodeproj/project.pbxproj
for t in "${TARGETS[@]}"; do
  sed -i '' "s#<string>group.solutions.pivi.dictus</string>#<string>$GROUP</string>#" "$t/$t.entitlements"
  /usr/libexec/PlistBuddy -c "Add :ALTAppGroups array" -c "Add :ALTAppGroups:0 string $GROUP" "$t/Info.plist"
done

xcodebuild -project Ouispr.xcodeproj -scheme OuisprApp -configuration Release \
  -destination "id=$DEVICE" -derivedDataPath build \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build

xcrun devicectl device install app --device "$DEVICE" build/Build/Products/Release-iphoneos/OuisprApp.app
echo "Installed. Unlock the iPhone and open Ouispr."
