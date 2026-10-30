#!/bin/bash
# Fails unless a release tag is "v" followed by CFBundleShortVersionString, so
# a release is never published under a version the app does not report.
# Usage: check-tag-version.sh <tag> [<Info.plist>]
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "usage: $0 <tag> [<Info.plist>]" >&2
    exit 2
fi
TAG="$1"
PLIST="${2:-$(dirname "$0")/../Resources/Info.plist}"

VERSION="$(python3 -I -c 'import plistlib, sys
with open(sys.argv[1], "rb") as f:
    print(plistlib.load(f)["CFBundleShortVersionString"])' "$PLIST")"

if [ "$TAG" != "v$VERSION" ]; then
    echo "error: tag $TAG does not match CFBundleShortVersionString $VERSION" >&2
    exit 1
fi
