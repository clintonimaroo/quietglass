#!/bin/bash
set -euo pipefail
quietglass_identity="QuietGlass Local Development"
if security find-identity -v -p codesigning | /usr/bin/grep -Fq "\"$quietglass_identity\""; then
    printf '%s\n' 'The existing QuietGlass signing identity is ready.'
    exit 0
fi
if security find-certificate -c "$quietglass_identity" >/dev/null 2>&1; then
    printf '%s\n' 'A QuietGlass certificate already exists. Repair it in Keychain Access instead of replacing its identity.' >&2
    exit 1
fi
umask 077
quietglass_temp="$(mktemp -d "${TMPDIR:-/tmp}/quietglass-signing.XXXXXX")"
trap 'rm -rf "$quietglass_temp"' EXIT
quietglass_keychain="$(security default-keychain -d user | /usr/bin/sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//')"
cat > "$quietglass_temp/certificate.cnf" <<'CONFIG'
[req]
distinguished_name = subject
x509_extensions = extensions
prompt = no
[subject]
CN = QuietGlass Local Development
[extensions]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CONFIG
/usr/bin/openssl req -new -newkey rsa:3072 -nodes -x509 -sha256 -days 3650 \
    -config "$quietglass_temp/certificate.cnf" \
    -keyout "$quietglass_temp/private.pem" -out "$quietglass_temp/certificate.pem" 2>/dev/null
/usr/bin/openssl rand -hex 32 > "$quietglass_temp/password"
/usr/bin/openssl pkcs12 -export -name "$quietglass_identity" \
    -inkey "$quietglass_temp/private.pem" -in "$quietglass_temp/certificate.pem" \
    -out "$quietglass_temp/identity.p12" -passout "file:$quietglass_temp/password"
security import "$quietglass_temp/identity.p12" -k "$quietglass_keychain" \
    -P "$(cat "$quietglass_temp/password")" -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$quietglass_keychain" "$quietglass_temp/certificate.pem"
security find-identity -v -p codesigning
