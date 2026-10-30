#!/bin/bash
# Packs build/Outlook2iCloudCal.app into build/Outlook2iCloudCal-<version>.dmg
# and writes its SHA-256 next to it. Refuses an app that the expected
# certificate did not sign (see check-signature.sh).
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/Outlook2iCloudCal.app"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
DMG_NAME="Outlook2iCloudCal-$VERSION.dmg"

# Drop the previous output first, so a failed check leaves no DMG behind.
rm -f "build/$DMG_NAME" "build/$DMG_NAME.sha256"
scripts/check-signature.sh "$APP"

STAGE="$(mktemp -d build/dmg.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Outlook2iCloudCal.app"
ln -s /Applications "$STAGE/Applications"
cp Resources/DMG-README.txt "$STAGE/README.txt"

hdiutil create -volname Outlook2iCloudCal -srcfolder "$STAGE" \
    -format UDZO -ov "build/$DMG_NAME" >/dev/null
(cd build && shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256")
echo "Built build/$DMG_NAME"
