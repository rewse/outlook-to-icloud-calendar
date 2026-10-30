#!/bin/bash
# Imports a code-signing identity from a .p12 into a throwaway keychain on a
# CI runner, so build-app.sh can sign with it. The password comes from
# P12_PASSWORD. Writes the keychain path to $GITHUB_ENV as SIGNING_KEYCHAIN;
# delete it with `security delete-keychain` when the job ends.
# Usage: ci-import-signing-identity.sh <p12>
set -euo pipefail

CERT_NAME="Outlook2iCloudCal Developer"

# This changes the user's keychain search list and the admin trust settings,
# which must never happen on a developer's Mac.
if [ "${CI:-}" != "true" ]; then
    echo "error: $0 only runs on CI" >&2
    exit 1
fi
if [ "$#" -ne 1 ]; then
    echo "usage: $0 <p12>" >&2
    exit 2
fi
P12="$1"
: "${P12_PASSWORD:?P12_PASSWORD is not set}"
: "${RUNNER_TEMP:?RUNNER_TEMP is not set}"

KEYCHAIN="$RUNNER_TEMP/signing.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -hex 16)"
CERT_PEM="$RUNNER_TEMP/signing-cert.pem"
trap 'rm -f "$CERT_PEM"' EXIT

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
# Export the path right away, so the cleanup step deletes the keychain even
# when a later step fails with the key already imported.
echo "SIGNING_KEYCHAIN=$KEYCHAIN" >> "${GITHUB_ENV:-/dev/null}"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$P12" -k "$KEYCHAIN" -f pkcs12 -P "$P12_PASSWORD" -T /usr/bin/codesign
# Lets codesign use the key without a UI prompt.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
    -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null

# Keep the existing keychains searchable after adding this one.
EXISTING=()
while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    EXISTING+=("${line//\"/}")
done < <(security list-keychains -d user)
security list-keychains -d user -s "$KEYCHAIN" ${EXISTING[@]+"${EXISTING[@]}"}

# A self-signed certificate is a valid code-signing identity only once it is
# trusted for code signing. Changing user trust settings needs a UI prompt, so
# use the admin domain, which passwordless sudo on the runner allows.
security find-certificate -c "$CERT_NAME" -p "$KEYCHAIN" > "$CERT_PEM"
sudo security add-trusted-cert -d -r trustRoot -p codeSign -k "$KEYCHAIN" "$CERT_PEM"

if ! LC_ALL=C security find-identity -v -p codesigning "$KEYCHAIN" | grep -q "$CERT_NAME"; then
    echo "error: '$CERT_NAME' is not a valid code-signing identity after import" >&2
    exit 1
fi
echo "Imported '$CERT_NAME' into $KEYCHAIN"
