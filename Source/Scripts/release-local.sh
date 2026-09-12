#!/usr/bin/env bash
# Validate, package, archive, install, verify, and clean a complete local release.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PROJECT_DIR/.." && pwd)"
INSTALL_APP="${CALCOUNT_INSTALL_DIR:-/Applications}/知行.app"

cleanup_on_failure() {
  "$SCRIPT_DIR/cleanup-release-residue.sh" >/dev/null 2>&1 || true
}
trap cleanup_on_failure EXIT

"$SCRIPT_DIR/cleanup-release-residue.sh"
"$SCRIPT_DIR/test.sh"

xcodebuild \
  -project "$PROJECT_DIR/CalendarCountdown.xcodeproj" \
  -scheme CalendarCountdownMobile \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$PROJECT_DIR/DerivedData-Mobile" \
  CODE_SIGNING_ALLOWED=NO \
  build

export CALCOUNT_DMG_ARCHS=universal
"$SCRIPT_DIR/package-dmg.sh"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Config/App-Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PROJECT_DIR/Config/App-Info.plist")"
DMG_NAME="CalendarCountdown-${VERSION}-macos-universal.dmg"
DMG_PATH="$PROJECT_DIR/dist/$DMG_NAME"
RELEASE_DIR="$REPO_ROOT/Releases/$VERSION"
RELEASE_DMG="$RELEASE_DIR/$DMG_NAME"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "Expected Universal DMG was not produced: $DMG_PATH" >&2
  exit 1
fi

mkdir -p "$RELEASE_DIR"
rm -f "$RELEASE_DMG" "$RELEASE_DIR/SHA256SUMS"
ditto "$DMG_PATH" "$RELEASE_DMG"
(
  cd "$RELEASE_DIR"
  shasum -a 256 "$DMG_NAME" > SHA256SUMS
)

"$SCRIPT_DIR/install-dmg.sh" "$DMG_PATH"
"$SCRIPT_DIR/dev-state.sh" write-install

INSTALLED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INSTALL_APP/Contents/Info.plist")"
INSTALLED_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INSTALL_APP/Contents/Info.plist")"
if [[ "$INSTALLED_VERSION" != "$VERSION" || "$INSTALLED_BUILD" != "$BUILD" ]]; then
  echo "Installed version mismatch: expected $VERSION ($BUILD), got $INSTALLED_VERSION ($INSTALLED_BUILD)." >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$INSTALL_APP"
APP_ARCHS="$(lipo -archs "$INSTALL_APP/Contents/MacOS/CalendarCountdown")"
if [[ " $APP_ARCHS " != *' arm64 '* || " $APP_ARCHS " != *' x86_64 '* ]]; then
  echo "Installed app is not Universal: $APP_ARCHS" >&2
  exit 1
fi

trap - EXIT
if [[ ! -f "$DMG_PATH" ]]; then
  # The release archive is created before installation. Some installer paths may
  # remove the transient dist artifact, so restore it from that verified archive
  # before cleanup preserves the current downloadable DMG.
  ditto "$RELEASE_DMG" "$DMG_PATH"
fi
"$SCRIPT_DIR/cleanup-release-residue.sh" "$DMG_PATH"

echo "Release complete: 知行 $VERSION ($BUILD)"
echo "Installed app: $INSTALL_APP"
echo "Architectures: $APP_ARCHS"
echo "DMG: $DMG_PATH"
echo "Archive: $RELEASE_DMG"
echo "SHA-256: $(awk '{print $1}' "$RELEASE_DIR/SHA256SUMS")"
