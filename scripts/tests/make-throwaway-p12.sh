#!/bin/bash
# Writes a throwaway "Outlook2iCloudCal Developer" identity to <out.p12> for
# the CI smoke test and prints its SHA-1. The password comes from
# P12_PASSWORD. Uses the same certificate extensions as
# create-signing-identity.sh.
# Usage: make-throwaway-p12.sh <out.p12>
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <out.p12>" >&2
    exit 2
fi
OUT="$1"
: "${P12_PASSWORD:?P12_PASSWORD is not set}"

WORK_DIR="$(mktemp -d "${RUNNER_TEMP:-/tmp}/throwaway-cert.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
umask 077

cat > "$WORK_DIR/cert.cnf" <<CNF
[req]
distinguished_name = req_dn
x509_extensions = v3_codesign
prompt = no
[req_dn]
CN = Outlook2iCloudCal Developer
O = Outlook2iCloudCal
[v3_codesign]
keyUsage = digitalSignature
extendedKeyUsage = codeSigning
basicConstraints = CA:false
CNF

OPENSSL_LEGACY=()
case "$(openssl version)" in
    OpenSSL\ 3.*) OPENSSL_LEGACY=(-legacy) ;;
esac

openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -config "$WORK_DIR/cert.cnf" \
    -keyout "$WORK_DIR/key.pem" -out "$WORK_DIR/cert.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$WORK_DIR/key.pem" -in "$WORK_DIR/cert.pem" \
    -out "$OUT" -passout env:P12_PASSWORD ${OPENSSL_LEGACY[@]+"${OPENSSL_LEGACY[@]}"}
openssl x509 -in "$WORK_DIR/cert.pem" -noout -fingerprint -sha1 \
    | sed 's/.*=//; s/://g'
