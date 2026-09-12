#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NATIVE_ARCH="$(uname -m)"
ARCH_SETTING="${CALCOUNT_DMG_ARCHS:-universal}"
DERIVED_DATA="$PROJECT_DIR/DerivedData-DMG"
DIST_DIR="$PROJECT_DIR/dist"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/calendar-countdown-dmg.XXXXXX")"

case "$ARCH_SETTING" in
  native)
    ARCHS="$NATIVE_ARCH"
    DEST_ARCH="$NATIVE_ARCH"
    ONLY_ACTIVE_ARCH=YES
    ARCH_LABEL="$NATIVE_ARCH"
    ;;
  universal|"")
    ARCHS="arm64 x86_64"
    DEST_ARCH="arm64"
    ONLY_ACTIVE_ARCH=NO
    ARCH_LABEL="universal"
    ;;
  *)
    ARCHS="$ARCH_SETTING"
    DEST_ARCH="${ARCHS%% *}"
    if [[ "$ARCHS" == *" "* ]]; then
      ONLY_ACTIVE_ARCH=NO
    else
      ONLY_ACTIVE_ARCH=YES
    fi
    ARCH_LABEL="${ARCHS// /-}"
    ;;
esac

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

cd "$PROJECT_DIR"
"$SCRIPT_DIR/bootstrap.sh"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Config/App-Info.plist")"
DMG_PATH="$DIST_DIR/CalendarCountdown-${VERSION}-macos-${ARCH_LABEL}.dmg"
RELEASE_NOTES="$PROJECT_DIR/Docs/RELEASE_NOTES_${VERSION}.md"
if [[ ! -f "$RELEASE_NOTES" ]]; then
  echo "Release notes not found for version $VERSION: $RELEASE_NOTES" >&2
  exit 1
fi

xcodebuild \
  -project CalendarCountdown.xcodeproj \
  -scheme CalendarCountdown \
  -configuration Release \
  -destination "platform=macOS,arch=${DEST_ARCH}" \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS="$ARCHS" \
  ONLY_ACTIVE_ARCH="$ONLY_ACTIVE_ARCH" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_SOURCE="$DERIVED_DATA/Build/Products/Release/CalendarCountdown.app"
CLI_SOURCE="$DERIVED_DATA/Build/Products/Release/calcount"
APP_TARGET="$STAGING_DIR/知行.app"
CLI_TARGET="$STAGING_DIR/calcount"

# Never launch APP_SOURCE. Launch Services would then prefer this DerivedData
# copy over /Applications/知行.app and create a second menu-bar instance.
if [[ ! -d "$APP_SOURCE" ]]; then
  echo "Release build did not produce $APP_SOURCE" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
ditto "$APP_SOURCE" "$APP_TARGET"
ditto "$CLI_SOURCE" "$CLI_TARGET"
ditto "$PROJECT_DIR/Docs/first-batch.example.json" "$STAGING_DIR/导入格式示例.json"
ditto "$PROJECT_DIR/Docs/tracked-events.example.json" "$STAGING_DIR/追踪清单格式示例.json"
ditto "$PROJECT_DIR/Docs/INSTALL_LOCAL.md" "$STAGING_DIR/安装说明.md"
ditto "$PROJECT_DIR/Docs/PRODUCT.md" "$STAGING_DIR/产品与数据边界.md"
ditto "$RELEASE_NOTES" "$STAGING_DIR/版本说明.md"
ditto "$PROJECT_DIR/../LICENSE" "$STAGING_DIR/LICENSE.txt"
ln -s /Applications "$STAGING_DIR/Applications"

codesign --force --sign - --timestamp=none --options runtime \
  --requirements '=designated => identifier "app.calendarcountdown.CalendarCountdown.Widget"' \
  --entitlements "$PROJECT_DIR/Config/Widget-Local.entitlements" \
  "$APP_TARGET/Contents/PlugIns/CalendarCountdownWidget.appex"
codesign --force --sign - --timestamp=none --options runtime \
  --requirements '=designated => identifier "app.calendarcountdown.CalendarCountdown"' \
  --entitlements "$PROJECT_DIR/Config/App-Local.entitlements" \
  "$APP_TARGET"
codesign --force --sign - --timestamp=none --options runtime \
  --requirements '=designated => identifier "app.calendarcountdown.CalendarCountdown.CLI"' \
  --entitlements "$PROJECT_DIR/Config/CLI.entitlements" \
  "$CLI_TARGET"

codesign --verify --deep --strict --verbose=2 "$APP_TARGET"
codesign --verify --strict --verbose=2 "$CLI_TARGET"

hdiutil create \
  -volname "知行 ${VERSION}" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH"

shasum -a 256 "$DMG_PATH"
echo "$DMG_PATH"
