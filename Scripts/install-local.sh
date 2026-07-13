#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${TMPDIR:-/tmp}/CliploomLocalInstall"
APP_PATH="$DERIVED_DATA/Build/Products/Debug/Cliploom.app"
ENTITLEMENTS="$DERIVED_DATA/Build/Intermediates.noindex/PasteBox.build/Debug/PasteBox.build/Cliploom.app.xcent"
DESTINATION="/Applications/Cliploom.app"
LEGACY_DESTINATION="/Applications/PasteBox.app"
LOCAL_SIGNING_IDENTITY="${CLIPLOOM_LOCAL_SIGNING_IDENTITY:-Cliploom Local Development}"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

find_signing_identity() {
  security find-identity -v -p codesigning |
    awk -F '"' -v name="$LOCAL_SIGNING_IDENTITY" '$2 == name { print $2; found = 1 } END { exit found ? 0 : 1 }'
}

create_local_signing_identity() {
  local work_dir
  local temporary_password
  work_dir="$(mktemp -d)"
  temporary_password="cliploom-local-signing"

  openssl req \
    -x509 \
    -newkey rsa:2048 \
    -nodes \
    -days 3650 \
    -subj "/CN=$LOCAL_SIGNING_IDENTITY/" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -keyout "$work_dir/cert.key" \
    -out "$work_dir/cert.crt" >/dev/null 2>&1

  openssl pkcs12 \
    -export \
    -legacy \
    -inkey "$work_dir/cert.key" \
    -in "$work_dir/cert.crt" \
    -out "$work_dir/cert.p12" \
    -passout "pass:$temporary_password" >/dev/null 2>&1

  security import "$work_dir/cert.p12" \
    -k "$LOGIN_KEYCHAIN" \
    -P "$temporary_password" \
    -A \
    -T /usr/bin/codesign >/dev/null

  security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "$LOGIN_KEYCHAIN" \
    "$work_dir/cert.crt" >/dev/null 2>&1 || true

  rm -rf "$work_dir"
}

resolve_signing_identity() {
  if find_signing_identity >/dev/null; then
    echo "$LOCAL_SIGNING_IDENTITY"
    return
  fi

  echo "Creating local code signing identity: $LOCAL_SIGNING_IDENTITY" >&2
  create_local_signing_identity

  if find_signing_identity >/dev/null; then
    echo "$LOCAL_SIGNING_IDENTITY"
    return
  fi

  echo "Unable to create a valid local signing identity." >&2
  exit 1
}

SIGNING_IDENTITY="$(resolve_signing_identity)"

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
      --sign "$SIGNING_IDENTITY" \
      "$nested_code"
  fi
done

codesign \
  --force \
  --sign "$SIGNING_IDENTITY" \
  --entitlements "$ENTITLEMENTS" \
  "$APP_PATH"

codesign --verify --deep --strict "$APP_PATH"

pkill -x Cliploom 2>/dev/null || true
pkill -x PasteBox 2>/dev/null || true
rm -rf "$LEGACY_DESTINATION"
if [[ -d "$DESTINATION" ]]; then
  find "$DESTINATION" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  ditto "$APP_PATH/" "$DESTINATION/"
else
  ditto "$APP_PATH" "$DESTINATION"
fi

/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
  -f "$DESTINATION"

open "$DESTINATION"

/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
  -u "$APP_PATH" 2>/dev/null || true

rm -rf "$DERIVED_DATA"
