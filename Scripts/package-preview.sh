#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/build/preview"
DERIVED_DATA="$OUTPUT_DIR/DerivedData"
STAGING_DIR="$OUTPUT_DIR/DMG"
APP_PATH="$DERIVED_DATA/Build/Products/Release/Cliploom.app"
SIGNING_REQUIREMENT='=designated => identifier "com.local.PasteBox"'

VERSION="$(
  xcodebuild \
    -project "$ROOT_DIR/PasteBox.xcodeproj" \
    -scheme PasteBox \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -showBuildSettings |
  awk -F ' = ' '/MARKETING_VERSION =/ { print $2; exit }'
)"

if [[ -z "$VERSION" ]]; then
  echo "Unable to read MARKETING_VERSION." >&2
  exit 1
fi

DMG_PATH="$OUTPUT_DIR/Cliploom-$VERSION-macOS-universal-unnotarized.dmg"
CHECKSUM_PATH="$OUTPUT_DIR/SHA256SUMS.txt"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

xcodebuild \
  -project "$ROOT_DIR/PasteBox.xcodeproj" \
  -scheme PasteBox \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Cliploom.app was not produced." >&2
  exit 1
fi

codesign \
  --force \
  --deep \
  --sign - \
  --options runtime \
  --requirements "$SIGNING_REQUIREMENT" \
  "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ARCHITECTURES="$(lipo -archs "$APP_PATH/Contents/MacOS/Cliploom")"
if [[ "$ARCHITECTURES" != *arm64* || "$ARCHITECTURES" != *x86_64* ]]; then
  echo "Expected a Universal binary, found: $ARCHITECTURES" >&2
  exit 1
fi

mkdir -p "$STAGING_DIR"
ditto "$APP_PATH" "$STAGING_DIR/Cliploom.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "Cliploom $VERSION" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

(
  cd "$OUTPUT_DIR"
  shasum -a 256 "$(basename "$DMG_PATH")" > "$CHECKSUM_PATH"
)

echo "Preview package ready: $DMG_PATH"
echo "Architectures: $ARCHITECTURES"
echo "This package is ad-hoc signed and not notarized."
