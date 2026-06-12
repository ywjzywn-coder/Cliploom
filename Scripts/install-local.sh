#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${TMPDIR:-/tmp}/CliploomLocalInstall"
APP_PATH="$DERIVED_DATA/Build/Products/Debug/Cliploom.app"
ENTITLEMENTS="$DERIVED_DATA/Build/Intermediates.noindex/PasteBox.build/Debug/PasteBox.build/Cliploom.app.xcent"
DESTINATION="/Applications/Cliploom.app"
LEGACY_DESTINATION="/Applications/PasteBox.app"
SIGNING_REQUIREMENT='=designated => identifier "com.local.PasteBox"'

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
      --sign - \
      "$nested_code"
  fi
done

codesign \
  --force \
  --sign - \
  --entitlements "$ENTITLEMENTS" \
  --requirements "$SIGNING_REQUIREMENT" \
  "$APP_PATH"

codesign --verify --deep --strict "$APP_PATH"

pkill -x Cliploom 2>/dev/null || true
pkill -x PasteBox 2>/dev/null || true
rm -rf "$DESTINATION"
rm -rf "$LEGACY_DESTINATION"
ditto "$APP_PATH" "$DESTINATION"

/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
  -f "$DESTINATION"

open "$DESTINATION"

/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
  -u "$APP_PATH" 2>/dev/null || true

rm -rf "$DERIVED_DATA"
