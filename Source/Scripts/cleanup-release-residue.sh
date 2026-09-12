#!/usr/bin/env bash
# Remove reproducible build/package residue while preserving release archives and user data.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PROJECT_DIR/.." && pwd)"
PRESERVE_DMG="${1:-}"
INSTALL_DIR="${CALCOUNT_INSTALL_DIR:-/Applications}"
TRASH_DIR="/Users/$(id -un)/.Trash"
APP_BUNDLE_ID="app.calendarcountdown.CalendarCountdown"

if [[ ! -f "$PROJECT_DIR/project.yml" || ! -d "$REPO_ROOT/Releases" ]]; then
  echo "Refusing cleanup: expected CalendarCountdown repository layout was not found." >&2
  exit 1
fi

if [[ -n "$PRESERVE_DMG" ]]; then
  if [[ ! -f "$PRESERVE_DMG" ]]; then
    echo "Cannot preserve missing DMG: $PRESERVE_DMG" >&2
    exit 1
  fi
  PRESERVE_DMG="$(cd "$(dirname "$PRESERVE_DMG")" && pwd -P)/$(basename "$PRESERVE_DMG")"
fi

while IFS= read -r -d '' derived_dir; do
  case "$derived_dir" in
    "$PROJECT_DIR"/DerivedData*) rm -rf "$derived_dir" ;;
    *) echo "Refusing unexpected DerivedData path: $derived_dir" >&2; exit 1 ;;
  esac
done < <(find "$PROJECT_DIR" -maxdepth 1 -type d -name 'DerivedData*' -print0)

DIST_DIR="$PROJECT_DIR/dist"
if [[ -d "$DIST_DIR" ]]; then
  while IFS= read -r -d '' dmg_path; do
    resolved_dmg="$(cd "$(dirname "$dmg_path")" && pwd -P)/$(basename "$dmg_path")"
    if [[ -n "$PRESERVE_DMG" && "$resolved_dmg" == "$PRESERVE_DMG" ]]; then
      continue
    fi
    rm -f "$dmg_path"
  done < <(find "$DIST_DIR" -maxdepth 1 -type f -name 'CalendarCountdown-*.dmg' -print0)
fi

find "$REPO_ROOT" \
  -path "$REPO_ROOT/.git" -prune -o \
  -type f \( -name '.DS_Store' -o -name '*.swp' -o -name '*.tmp' -o -name '*~' \) \
  -delete

# A previous local installer created versioned backup bundles next to the live
# app. They are not build products, so remove only our positively identified
# backups and use Trash to keep this cleanup recoverable.
if [[ -d "$INSTALL_DIR" && -d "$TRASH_DIR" ]]; then
  while IFS= read -r -d '' backup_app; do
    info_plist="$backup_app/Contents/Info.plist"
    bundle_id=""
    if [[ -f "$info_plist" ]]; then
      bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist" 2>/dev/null || true)"
    fi
    if [[ "$bundle_id" != "$APP_BUNDLE_ID" ]]; then
      echo "Preserved unrecognized app backup: $backup_app" >&2
      continue
    fi

    trash_target="$TRASH_DIR/$(basename "$backup_app")"
    if [[ -e "$trash_target" ]]; then
      echo "Preserved backup because Trash already contains: $trash_target" >&2
      continue
    fi
    mv "$backup_app" "$TRASH_DIR/"
    echo "Moved old app backup to Trash: $trash_target"
  done < <(find "$INSTALL_DIR" -maxdepth 1 -type d -name '知行.app.backup-*' -print0)
fi

echo "Release residue cleaned."
if [[ -n "$PRESERVE_DMG" ]]; then
  echo "Preserved current DMG: $PRESERVE_DMG"
fi
