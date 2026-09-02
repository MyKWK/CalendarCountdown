#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="1.0.2"
DERIVED_DATA="$PROJECT_DIR/DerivedData-DMG"
DIST_DIR="$PROJECT_DIR/dist"
DMG_PATH="$DIST_DIR/CalendarCountdown-${VERSION}-macos-universal.dmg"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/calendar-countdown-dmg.XXXXXX")"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

cd "$PROJECT_DIR"
"$SCRIPT_DIR/bootstrap.sh"

xcodebuild \
  -project CalendarCountdown.xcodeproj \
  -scheme CalendarCountdown \
  -configuration Release \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_SOURCE="$DERIVED_DATA/Build/Products/Release/CalendarCountdown.app"
CLI_SOURCE="$DERIVED_DATA/Build/Products/Release/calcount"
APP_TARGET="$STAGING_DIR/日历倒数.app"
CLI_TARGET="$STAGING_DIR/calcount"

mkdir -p "$DIST_DIR"
ditto "$APP_SOURCE" "$APP_TARGET"
ditto "$CLI_SOURCE" "$CLI_TARGET"
ditto "$PROJECT_DIR/Docs/first-batch.example.json" "$STAGING_DIR/导入格式示例.json"
ditto "$PROJECT_DIR/Docs/tracked-events.example.json" "$STAGING_DIR/追踪清单格式示例.json"
ditto "$PROJECT_DIR/Docs/INSTALL_LOCAL.md" "$STAGING_DIR/安装说明.md"
ditto "$PROJECT_DIR/Docs/PRODUCT.md" "$STAGING_DIR/产品与数据边界.md"
ditto "$PROJECT_DIR/Docs/RELEASE_NOTES_1.0.2.md" "$STAGING_DIR/版本说明.md"
ditto "$PROJECT_DIR/../LICENSE" "$STAGING_DIR/LICENSE.txt"
ln -s /Applications "$STAGING_DIR/Applications"

codesign --force --sign - --timestamp=none --options runtime \
  --requirements '=designated => identifier "app.calendarcountdown.CalendarCountdown.Widget"' \
  --entitlements "$PROJECT_DIR/Config/Widget.entitlements" \
  "$APP_TARGET/Contents/PlugIns/CalendarCountdownWidget.appex"
codesign --force --sign - --timestamp=none --options runtime \
  --requirements '=designated => identifier "app.calendarcountdown.CalendarCountdown"' \
  --entitlements "$PROJECT_DIR/Config/App.entitlements" \
  "$APP_TARGET"
codesign --force --sign - --timestamp=none --options runtime \
  --requirements '=designated => identifier "app.calendarcountdown.CalendarCountdown.CLI"' \
  --entitlements "$PROJECT_DIR/Config/CLI.entitlements" \
  "$CLI_TARGET"

codesign --verify --deep --strict --verbose=2 "$APP_TARGET"
codesign --verify --strict --verbose=2 "$CLI_TARGET"

hdiutil create \
  -volname "日历倒数 ${VERSION}" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH"

shasum -a 256 "$DMG_PATH"
echo "$DMG_PATH"
