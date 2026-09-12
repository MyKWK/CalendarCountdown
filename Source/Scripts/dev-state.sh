#!/usr/bin/env bash
# Shared fingerprint and stamp helpers for local test → DMG install.
# Usage:
#   ./dev-state.sh fingerprint
#   ./dev-state.sh write-tests
#   ./dev-state.sh write-install
#   ./dev-state.sh action
#   ./dev-state.sh skipped
#   ./dev-state.sh mark-dirty <conversation-id>
#   ./dev-state.sh clear-dirty
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PROJECT_DIR/.." && pwd)"
STATE_DIR="${CALCOUNT_STATE_DIR:-$REPO_ROOT/.cursor/state}"
TESTS_STAMP="$STATE_DIR/tests-passed.fingerprint"
INSTALL_STAMP="$STATE_DIR/dmg-installed.fingerprint"
DIRTY_STAMP="$STATE_DIR/dirty-session"
SKIP_FILE="$STATE_DIR/skip-auto-install"

APP_PATHS=(
  Source/App
  Source/Core
  Source/Persistence
  Source/Services
  Source/CalendarBridge
  Source/Widget
  Source/CLI
  Source/Localization
  Source/Resources
  Source/Config
  Source/project.yml
)

ensure_state_dir() {
  mkdir -p "$STATE_DIR"
}

is_skipped() {
  [[ "${CALCOUNT_SKIP_AUTO_INSTALL:-}" == "1" ]] || [[ -f "$SKIP_FILE" ]]
}

fingerprint() {
  (
    cd "$REPO_ROOT"
    git rev-parse HEAD
    git diff HEAD -- "${APP_PATHS[@]}"
    git ls-files --others --exclude-standard -- "${APP_PATHS[@]}" | sort | while IFS= read -r file; do
      printf 'UNTRACKED %s\n' "$file"
      git hash-object "$file"
    done
  ) | shasum -a 256 | awk '{print $1}'
}

read_stamp() {
  local path="$1"
  if [[ -f "$path" ]]; then
    tr -d '[:space:]' < "$path"
  fi
}

write_stamp() {
  local path="$1"
  ensure_state_dir
  fingerprint > "$path"
}

conversation_is_dirty() {
  local conversation_id="${1:-}"
  local current
  current="$(fingerprint)"
  [[ -f "$DIRTY_STAMP" ]] || return 1
  local dirty_id dirty_fp
  dirty_id="$(awk -F'\t' 'NR==1 {print $1}' "$DIRTY_STAMP")"
  dirty_fp="$(awk -F'\t' 'NR==1 {print $2}' "$DIRTY_STAMP" | tr -d '[:space:]')"
  [[ "$dirty_fp" == "$current" ]] || return 1
  if [[ -n "$conversation_id" && "$dirty_id" != "unknown" ]]; then
    [[ "$dirty_id" == "$conversation_id" ]]
  fi
}

mark_dirty() {
  local conversation_id="${1:-unknown}"
  ensure_state_dir
  printf '%s\t%s\n' "$conversation_id" "$(fingerprint)" > "$DIRTY_STAMP"
}

clear_dirty() {
  rm -f "$DIRTY_STAMP"
}

desired_action() {
  local conversation_id="${1:-}"
  if is_skipped; then
    printf 'none\n'
    return 0
  fi

  local current tests_fp installed_fp
  current="$(fingerprint)"
  tests_fp="$(read_stamp "$TESTS_STAMP")"
  installed_fp="$(read_stamp "$INSTALL_STAMP")"

  if [[ -n "$current" && "$current" == "$installed_fp" ]]; then
    printf 'none\n'
    return 0
  fi

  if [[ -n "$current" && "$current" == "$tests_fp" ]]; then
    printf 'install\n'
    return 0
  fi

  if conversation_is_dirty "$conversation_id"; then
    printf 'test-and-install\n'
    return 0
  fi

  printf 'none\n'
}

usage() {
  cat <<'EOF'
Usage: dev-state.sh <command> [conversation-id]

Commands:
  fingerprint       Print the current macOS app source fingerprint
  write-tests             Record that unit tests passed for this fingerprint
  write-install           Record that the local DMG was installed for this fingerprint
  tests-fingerprint       Print the recorded passing-test fingerprint
  installed-fingerprint   Print the recorded installed fingerprint
  action [id]             Print none | install | test-and-install
  skipped           Exit 0 if auto-install is disabled
  mark-dirty [id]   Mark this conversation as having edited app sources
  clear-dirty       Clear the in-conversation dirty marker
EOF
}

main() {
  local command="${1:-}"
  case "$command" in
    fingerprint)
      fingerprint
      ;;
    write-tests)
      write_stamp "$TESTS_STAMP"
      ;;
    write-install)
      write_stamp "$INSTALL_STAMP"
      clear_dirty
      ;;
    tests-fingerprint)
      read_stamp "$TESTS_STAMP"
      ;;
    installed-fingerprint)
      read_stamp "$INSTALL_STAMP"
      ;;
    action)
      desired_action "${2:-}"
      ;;
    skipped)
      if is_skipped; then
        exit 0
      fi
      exit 1
      ;;
    mark-dirty)
      mark_dirty "${2:-unknown}"
      ;;
    clear-dirty)
      clear_dirty
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
