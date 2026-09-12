#!/usr/bin/env bash
# Package a local ad-hoc DMG and install it into /Applications.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORCE="${CALCOUNT_FORCE_INSTALL:-0}"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: install-local.sh [--dry-run] [--force]

Packages a local-arch DMG (set CALCOUNT_DMG_ARCHS=universal for a release-style
universal image) and installs 知行 into /Applications.

Skips work when the current app-source fingerprint is already installed,
unless --force or CALCOUNT_FORCE_INSTALL=1 is set.
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

current="$("$SCRIPT_DIR/dev-state.sh" fingerprint)"
installed_fp="$("$SCRIPT_DIR/dev-state.sh" installed-fingerprint || true)"

if [[ "$FORCE" != "1" && -n "$installed_fp" && "$current" == "$installed_fp" ]]; then
  echo "Already installed for fingerprint $current"
  exit 0
fi

if [[ "$DRY_RUN" == "1" ]]; then
  echo "Would package a local DMG and install fingerprint $current"
  echo "Would quit app.calendarcountdown.CalendarCountdown if running"
  echo "Would replace ${CALCOUNT_INSTALL_DIR:-/Applications}/知行.app"
  echo "Relaunch mode: ${CALCOUNT_RELAUNCH:-auto}"
  exit 0
fi

export CALCOUNT_DMG_ARCHS="${CALCOUNT_DMG_ARCHS:-native}"
dmg_path="$("$SCRIPT_DIR/package-dmg.sh" | tail -n 1)"
if [[ -z "$dmg_path" || ! -f "$dmg_path" ]]; then
  echo "package-dmg.sh did not produce a DMG" >&2
  exit 1
fi

"$SCRIPT_DIR/install-dmg.sh" "$dmg_path"
"$SCRIPT_DIR/dev-state.sh" write-install
echo "Installed local DMG for fingerprint $current"
echo "$dmg_path"
