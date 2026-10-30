#!/bin/bash
# Creates the self-signed code-signing identity "Outlook2iCloudCal Developer"
# in the login keychain. Does nothing when the identity already exists.
set -euo pipefail

CERT_NAME="Outlook2iCloudCal Developer"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if LC_ALL=C security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo "Signing identity '$CERT_NAME' already exists."
    exit 0
fi

WORK_DIR="$(mktemp -d /tmp/outlook2icloudcal-cert.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT
umask 077

cat > "$WORK_DIR/cert.cnf" <<CNF
[req]
distinguished_name = req_dn
x509_extensions = v3_codesign
prompt = no
[req_dn]
CN = $CERT_NAME
O = Outlook2iCloudCal
[v3_codesign]
keyUsage = digitalSignature
extendedKeyUsage = codeSigning
basicConstraints = CA:false
CNF

# macOS's LibreSSL writes the PKCS#12 scheme `security import` reads; OpenSSL 3
# needs -legacy to do the same.
OPENSSL_LEGACY=""
case "$(openssl version)" in
    OpenSSL\ 3.*) OPENSSL_LEGACY="-legacy" ;;
esac

P12_PASSWORD="outlook2icloudcal"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK_DIR/key.pem" -out "$WORK_DIR/cert.pem" -config "$WORK_DIR/cert.cnf"
# shellcheck disable=SC2086 # OPENSSL_LEGACY is intentionally unquoted (may be empty)
openssl pkcs12 -export -inkey "$WORK_DIR/key.pem" -in "$WORK_DIR/cert.pem" \
    -out "$WORK_DIR/identity.p12" -passout "pass:$P12_PASSWORD" $OPENSSL_LEGACY
security import "$WORK_DIR/identity.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign

# A self-signed certificate is only a valid code-signing identity once it is
# trusted for code signing.
openssl x509 -in "$WORK_DIR/cert.pem" -out "$WORK_DIR/trust.pem"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK_DIR/trust.pem"

echo "Created signing identity '$CERT_NAME'."
