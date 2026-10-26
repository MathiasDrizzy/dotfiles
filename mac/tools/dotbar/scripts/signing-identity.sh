#!/usr/bin/env bash
# Makes, once, the certificate dotbar is signed with: "dotbar Local Signing", self-signed, in the login keychain.
# macOS keeps the permissions it grants (Location, Accessibility) for the app's signature. Signed ad hoc, every build has
# a new one and the permissions were lost at each rebuild; signed with this certificate, every build has the same one,
# so they are granted once and kept, across rebuilds and restarts. No paid developer account is needed: the certificate
# never leaves this Mac and is only used for dotbar.
#   scripts/signing-identity.sh   prints the identity's name (creating it if it is missing)
set -euo pipefail

NAME="dotbar Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# An identity is the certificate with its private key: a certificate left without its key cannot sign.
if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -qF "\"$NAME\""; then
  echo "$NAME"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASS="$(/usr/bin/openssl rand -hex 16)" # only protects the bundle between here and the import below
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$NAME" \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
  -out "$WORK/identity.p12" -passout "pass:$PASS" >/dev/null 2>&1
# -T: codesign may use the key without asking for the keychain's password at every build.
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null
echo "$NAME"
