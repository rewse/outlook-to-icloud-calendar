#!/bin/bash
# Fails unless the app is validly signed by the expected certificate. The
# calendar permission is tied to this designated requirement, so an app signed
# by any other certificate (or ad hoc) must never ship.
# Usage: check-signature.sh <app>
# The expected SHA-1 comes from EXPECTED_SIGNING_SHA1, or else from
# scripts/signing-certificate-sha1.
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <app>" >&2
    exit 2
fi
APP="$1"
BUNDLE_ID="io.github.rewse.Outlook2iCloudCal"

if [ ! -d "$APP" ]; then
    echo "error: $APP not found" >&2
    exit 1
fi

SHA1="${EXPECTED_SIGNING_SHA1:-$(cat "$(dirname "$0")/signing-certificate-sha1")}"
SHA1="$(echo "$SHA1" | tr '[:upper:]' '[:lower:]')"
WANT="designated => identifier \"$BUNDLE_ID\" and certificate root = H\"$SHA1\""

if ! codesign --verify --deep --strict "$APP" 2>/dev/null; then
    echo "error: $APP has no valid signature" >&2
    exit 1
fi
GOT="$(codesign -d -r- "$APP" 2>&1 | grep '^designated => ' || true)"
if [ "$GOT" != "$WANT" ]; then
    echo "error: designated requirement of $APP is '$GOT', want '$WANT'" >&2
    exit 1
fi
