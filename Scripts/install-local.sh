#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${TMPDIR:-/tmp}/CliploomLocalInstall"
APP_PATH="$DERIVED_DATA/Build/Products/Debug/Cliploom.app"
ENTITLEMENTS="$DERIVED_DATA/Build/Intermediates.noindex/PasteBox.build/Debug/PasteBox.build/Cliploom.app.xcent"
DESTINATION="/Applications/Cliploom.app"
LEGACY_DESTINATION="/Applications/PasteBox.app"
SIGNING_DIR="$HOME/Library/Application Support/PasteBox/LocalSigning"
KEYCHAIN="$HOME/Library/Keychains/PasteBoxLocalSigning.keychain-db"
KEYCHAIN_PASSWORD_FILE="$SIGNING_DIR/keychain-password"
CERTIFICATE="$SIGNING_DIR/PasteBoxLocalSigning.pem"
IDENTITY_NAME="PasteBox Local Signing"
TCC_MIGRATION_MARKER="$SIGNING_DIR/accessibility-signing-migration-v1"

create_signing_identity() {
  local config="$SIGNING_DIR/openssl.cnf"
  local private_key="$SIGNING_DIR/private-key.pem"
  local archive="$SIGNING_DIR/identity.p12"
  local archive_password

  mkdir -p "$SIGNING_DIR"
  chmod 700 "$SIGNING_DIR"
  umask 077

  openssl rand -hex 32 > "$KEYCHAIN_PASSWORD_FILE"
  archive_password="$(openssl rand -hex 32)"

  cat > "$config" <<EOF
[req]
distinguished_name = distinguished_name
x509_extensions = extensions
prompt = no

[distinguished_name]
CN = $IDENTITY_NAME
O = PasteBox Local

[extensions]
basicConstraints = critical,CA:TRUE,pathlen:0
keyUsage = critical,digitalSignature,keyCertSign
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
EOF

  openssl req -new -newkey rsa:2048 -nodes -x509 -days 3650 \
    -config "$config" \
    -keyout "$private_key" \
    -out "$CERTIFICATE"

  openssl pkcs12 -export -legacy \
    -inkey "$private_key" \
    -in "$CERTIFICATE" \
    -name "$IDENTITY_NAME" \
    -passout "pass:$archive_password" \
    -out "$archive"

  security delete-keychain "$KEYCHAIN" 2>/dev/null || true
  security create-keychain -p "$(cat "$KEYCHAIN_PASSWORD_FILE")" "$KEYCHAIN"
  security set-keychain-settings -lut 21600 "$KEYCHAIN"
  security unlock-keychain -p "$(cat "$KEYCHAIN_PASSWORD_FILE")" "$KEYCHAIN"
  security import "$archive" \
    -k "$KEYCHAIN" \
    -P "$archive_password" \
    -T /usr/bin/codesign \
    -T /usr/bin/security
  security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "$(cat "$KEYCHAIN_PASSWORD_FILE")" \
    "$KEYCHAIN"

  rm -f "$config" "$private_key" "$archive"
}

if [[ ! -f "$CERTIFICATE" || ! -f "$KEYCHAIN_PASSWORD_FILE" || ! -f "$KEYCHAIN" ]]; then
  create_signing_identity
fi

security unlock-keychain -p "$(cat "$KEYCHAIN_PASSWORD_FILE")" "$KEYCHAIN"

if ! security verify-cert -c "$CERTIFICATE" -p codeSign >/dev/null 2>&1; then
  echo "Cliploom needs one administrator confirmation to trust its local signing certificate."
  osascript - "$CERTIFICATE" <<'APPLESCRIPT'
on run arguments
  set certificatePath to item 1 of arguments
  do shell script "/usr/bin/security add-trusted-cert -d -r trustRoot -p codeSign -k /Library/Keychains/System.keychain " & quoted form of certificatePath with administrator privileges
end run
APPLESCRIPT
fi

CERTIFICATE_SHA1="$(
  openssl x509 -in "$CERTIFICATE" -noout -fingerprint -sha1 |
    cut -d= -f2 |
    tr -d :
)"

if ! security find-identity -v -p codesigning "$KEYCHAIN" | grep -q "$CERTIFICATE_SHA1"; then
  echo "Cliploom local signing identity is unavailable." >&2
  exit 1
fi

xcodebuild \
  -project "$ROOT_DIR/PasteBox.xcodeproj" \
  -scheme PasteBox \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  build

for nested_code in \
  "$APP_PATH/Contents/MacOS/__preview.dylib" \
  "$APP_PATH/Contents/MacOS/Cliploom.debug.dylib"
do
  if [[ -e "$nested_code" ]]; then
    codesign \
      --force \
      --keychain "$KEYCHAIN" \
      --sign "$CERTIFICATE_SHA1" \
      "$nested_code"
  fi
done

codesign \
  --force \
  --keychain "$KEYCHAIN" \
  --sign "$CERTIFICATE_SHA1" \
  --entitlements "$ENTITLEMENTS" \
  "$APP_PATH"

codesign --verify --deep --strict "$APP_PATH"

pkill -x Cliploom 2>/dev/null || true
pkill -x PasteBox 2>/dev/null || true
rm -rf "$DESTINATION"
rm -rf "$LEGACY_DESTINATION"
ditto "$APP_PATH" "$DESTINATION"

/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
  -f "$DESTINATION"

if [[ ! -f "$TCC_MIGRATION_MARKER" ]]; then
  tccutil reset Accessibility com.local.PasteBox
  touch "$TCC_MIGRATION_MARKER"
fi

open "$DESTINATION"

/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
  -u "$APP_PATH" 2>/dev/null || true

rm -rf "$DERIVED_DATA"
