#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/build/release"
ARCHIVE_PATH="$OUTPUT_DIR/Cliploom.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/Cliploom.app"
SUBMISSION_ZIP="$OUTPUT_DIR/Cliploom-notarization.zip"
FINAL_ZIP="$OUTPUT_DIR/Cliploom-macOS.zip"

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION to the full Developer ID Application identity.}"
: "${NOTARY_KEYCHAIN_PROFILE:?Set NOTARY_KEYCHAIN_PROFILE to an xcrun notarytool keychain profile.}"

BUNDLE_ID="${CLIPLOOM_BUNDLE_ID:-com.local.PasteBox}"

if ! security find-identity -v -p codesigning |
  grep -Fq "$DEVELOPER_ID_APPLICATION"; then
  echo "Developer ID signing identity was not found in the current keychain." >&2
  exit 1
fi

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

xcodebuild \
  -project "$ROOT_DIR/PasteBox.xcodeproj" \
  -scheme PasteBox \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  archive \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ditto -c -k --keepParent "$APP_PATH" "$SUBMISSION_ZIP"
xcrun notarytool submit "$SUBMISSION_ZIP" \
  --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
  --wait
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose=2 "$APP_PATH"

ditto -c -k --keepParent "$APP_PATH" "$FINAL_ZIP"
rm -f "$SUBMISSION_ZIP"

echo "Release ready: $FINAL_ZIP"
