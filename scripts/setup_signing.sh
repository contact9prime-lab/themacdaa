#!/usr/bin/env bash
# Creates a STABLE self-signed code-signing identity ("Macda Dev") in the login
# keychain. Signing every build with the same identity gives Macda a stable
# "designated requirement", so macOS TCC permissions (Microphone, Screen
# Recording) persist across rebuilds instead of resetting every time.
#
# One-time. Safe to re-run (it no-ops if the identity already exists).
set -euo pipefail

CERT_NAME="Macda Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "✓ Signing identity '$CERT_NAME' already exists — nothing to do."
  exit 0
fi

echo "▶︎ Creating self-signed code-signing identity '$CERT_NAME'…"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/openssl.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = v3
prompt = no
[ dn ]
CN = $CERT_NAME
[ v3 ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/openssl.cnf" >/dev/null 2>&1

openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$CERT_NAME" -out "$TMP/identity.p12" -passout pass:macda >/dev/null 2>&1 || \
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$CERT_NAME" -out "$TMP/identity.p12" -passout pass:macda >/dev/null 2>&1

# -A: allow all apps (incl. codesign) to use the key without a per-use prompt.
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P macda -A -T /usr/bin/codesign >/dev/null 2>&1

echo "✓ Created '$CERT_NAME'. Future builds will sign with it (stable TCC)."
