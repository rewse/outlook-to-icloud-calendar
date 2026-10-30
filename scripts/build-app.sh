#!/bin/bash
# Builds build/Outlook2iCloudCal.app and signs it with the "Outlook2iCloudCal
# Developer" identity. Never falls back to ad-hoc signing, so the signature
# (and the calendar permission tied to it) stays stable across rebuilds.
set -euo pipefail

CERT_NAME="Outlook2iCloudCal Developer"
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if ! LC_ALL=C security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo "error: signing identity '$CERT_NAME' not found. Run 'make cert' first." >&2
    exit 1
fi

swift build -c release --product Outlook2iCloudCal
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/Outlook2iCloudCal.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Outlook2iCloudCal" "$APP/Contents/MacOS/Outlook2iCloudCal"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Compiles each string catalog into en.lproj and ja.lproj.
for catalog in Resources/Localizable.xcstrings Resources/InfoPlist.xcstrings; do
    xcrun xcstringstool compile "$catalog" --output-directory "$APP/Contents/Resources"
done

# actool fails to open a relative path when the checkout sits under a
# symlinked directory such as /tmp, so hand it a physical absolute path.
ICON_TMP="$(cd "$(mktemp -d build/icon.XXXXXX)" && pwd -P)"
trap 'rm -rf "$ICON_TMP"' EXIT
swift scripts/make-icon.swift "$ICON_TMP/AppIcon.icon"
# actool emits Assets.car (the Icon Composer icon used by macOS 26 and later),
# AppIcon.icns (the fallback for earlier macOS), and the matching Info.plist keys.
xcrun actool "$ICON_TMP/AppIcon.icon" --compile "$APP/Contents/Resources" \
    --app-icon AppIcon --platform macosx --minimum-deployment-target 15.0 \
    --output-partial-info-plist "$ICON_TMP/AppIcon-Info.plist" \
    --output-format human-readable-text --errors --warnings >/dev/null
/usr/libexec/PlistBuddy -c "Merge $ICON_TMP/AppIcon-Info.plist" "$APP/Contents/Info.plist"

codesign --force --options runtime \
    --entitlements Resources/Outlook2iCloudCal.entitlements \
    --sign "$CERT_NAME" "$APP"
echo "Built $APP"
