#!/usr/bin/env bash
# Mount a CalendarCountdown DMG and install 知行.app into /Applications.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUNDLE_ID="app.calendarcountdown.CalendarCountdown"
PROCESS_NAME="CalendarCountdown"
INSTALL_DIR="${CALCOUNT_INSTALL_DIR:-/Applications}"
CLI_DEST="${CALCOUNT_CLI_DEST:-/usr/local/bin/calcount}"
RELAUNCH_MODE="${CALCOUNT_RELAUNCH:-auto}"
DRY_RUN=0
DMG_PATH=""
MOUNT_POINT=""
WAS_RUNNING=0

usage() {
  cat <<'EOF'
Usage: install-dmg.sh [--dry-run] [dmg-path]

If dmg-path is omitted, the newest CalendarCountdown-*.dmg under Source/dist is used.
The running app is quit before the bundle is replaced. By default it is reopened
only if it was running (CALCOUNT_RELAUNCH=auto|1|0).
EOF
}

cleanup() {
  if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null \
      || hdiutil detach "$MOUNT_POINT" -force 2>/dev/null \
      || true
  fi
}

latest_dmg() {
  local dist_dir="$PROJECT_DIR/dist"
  if [[ ! -d "$dist_dir" ]]; then
    return 1
  fi
  local candidate=""
  candidate="$(ls -t "$dist_dir"/CalendarCountdown-*.dmg 2>/dev/null | head -n 1 || true)"
  [[ -n "$candidate" && -f "$candidate" ]] || return 1
  printf '%s\n' "$candidate"
}

app_is_running() {
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/product-instances.sh"
  [[ "$(count_product_main_processes)" -gt 0 ]]
}

quit_app() {
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/product-instances.sh"
  if [[ "$(count_product_main_processes)" -gt 0 ]]; then
    WAS_RUNNING=1
  fi
  quit_product_instances
}

should_relaunch() {
  case "$RELAUNCH_MODE" in
    1|true|yes) return 0 ;;
    0|false|no) return 1 ;;
    *) [[ "$WAS_RUNNING" == "1" ]] ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      DMG_PATH="$1"
      shift
      ;;
  esac
done

if [[ -z "$DMG_PATH" ]]; then
  DMG_PATH="$(latest_dmg)" || {
    echo "No DMG found under $PROJECT_DIR/dist. Run package-dmg.sh or install-local.sh first." >&2
    exit 1
  }
fi

if [[ ! -f "$DMG_PATH" ]]; then
  echo "DMG not found: $DMG_PATH" >&2
  exit 1
fi

if [[ ! -d "$INSTALL_DIR" || ! -w "$INSTALL_DIR" ]]; then
  echo "Install directory is not writable: $INSTALL_DIR" >&2
  exit 1
fi

echo "Using DMG: $DMG_PATH"

if [[ "$DRY_RUN" == "1" ]]; then
  echo "Would quit $BUNDLE_ID if running"
  echo "Would install 知行.app → $INSTALL_DIR/知行.app"
  echo "Would copy calcount → $CLI_DEST if that directory is writable"
  echo "Relaunch mode: $RELAUNCH_MODE"
  exit 0
fi

trap cleanup EXIT

attach_output="$(hdiutil attach -nobrowse -readonly "$DMG_PATH")"
MOUNT_POINT="$(printf '%s\n' "$attach_output" | sed -n 's#.*\(/Volumes/.*\)$#\1#p' | tail -n 1)"
if [[ -z "$MOUNT_POINT" || ! -d "$MOUNT_POINT" ]]; then
  echo "Failed to mount $DMG_PATH" >&2
  exit 1
fi

SRC_APP="$MOUNT_POINT/知行.app"
if [[ ! -d "$SRC_APP" ]]; then
  SRC_APP="$(find "$MOUNT_POINT" -maxdepth 1 -name '*.app' -type d | head -n 1 || true)"
fi
if [[ -z "$SRC_APP" || ! -d "$SRC_APP" ]]; then
  echo "No .app bundle found in $MOUNT_POINT" >&2
  exit 1
fi

quit_app

rm -rf "$INSTALL_DIR/知行.app" "$INSTALL_DIR/CalendarCountdown.app"
ditto "$SRC_APP" "$INSTALL_DIR/知行.app"
xattr -dr com.apple.quarantine "$INSTALL_DIR/知行.app" 2>/dev/null || true
echo "Installed $INSTALL_DIR/知行.app"

if [[ -f "$MOUNT_POINT/calcount" ]]; then
  cli_dir="$(dirname "$CLI_DEST")"
  if [[ -d "$cli_dir" && -w "$cli_dir" ]]; then
    ditto "$MOUNT_POINT/calcount" "$CLI_DEST"
    chmod +x "$CLI_DEST"
    xattr -dr com.apple.quarantine "$CLI_DEST" 2>/dev/null || true
    echo "Installed $CLI_DEST"
  else
    echo "Skipped CLI install; $cli_dir is not writable" >&2
  fi
fi

if should_relaunch; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/product-instances.sh"
  open_official_app
  echo "Relaunched $INSTALL_DIR/知行.app"
  sleep 1
  remaining="$(count_product_main_processes)"
  if [[ "$remaining" -ne 1 ]]; then
    echo "Expected exactly one 知行 main process after install, found $remaining:" >&2
    list_product_main_processes >&2
    exit 1
  fi
  only_exe="$(list_product_main_processes | awk -F'\t' '{print $2}')"
  if [[ "$only_exe" != "$INSTALL_DIR/知行.app/Contents/MacOS/CalendarCountdown" ]]; then
    echo "Official process path mismatch: $only_exe" >&2
    exit 1
  fi
fi
