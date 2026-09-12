#!/usr/bin/env bash
# Shared helpers for locating and quitting 知行 / CalendarCountdown macOS instances.
# Never use killall. Only signal PIDs whose executable path was verified.

APP_BUNDLE_ID="${APP_BUNDLE_ID:-app.calendarcountdown.CalendarCountdown}"
LEGACY_BUNDLE_IDS="${LEGACY_BUNDLE_IDS:-com.hashxjhuang.CalendarCountdown}"
PROCESS_NAME="${PROCESS_NAME:-CalendarCountdown}"
INSTALL_DIR="${CALCOUNT_INSTALL_DIR:-/Applications}"
OFFICIAL_APP="${OFFICIAL_APP:-$INSTALL_DIR/知行.app}"
OFFICIAL_EXE="$OFFICIAL_APP/Contents/MacOS/$PROCESS_NAME"

is_derived_data_product_path() {
  local path="$1"
  [[ "$path" == *"/Library/Developer/Xcode/DerivedData/"*"/Build/Products/"*"/CalendarCountdown.app"* ]]
}

is_product_main_executable() {
  local path="$1"
  [[ "$path" == *"/Contents/MacOS/$PROCESS_NAME" && "$path" != *".appex/"* ]]
}

is_official_executable() {
  local path="$1"
  [[ "$path" == "$OFFICIAL_EXE" ]]
}

bundle_id_for_executable() {
  local exe="$1"
  local app="${exe%/Contents/MacOS/$PROCESS_NAME}"
  local plist="$app/Contents/Info.plist"
  if [[ -f "$plist" ]]; then
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || true
  fi
}

is_recognized_bundle_id() {
  local bundle_id="$1"
  [[ "$bundle_id" == "$APP_BUNDLE_ID" ]] && return 0
  local legacy
  for legacy in $LEGACY_BUNDLE_IDS; do
    [[ "$bundle_id" == "$legacy" ]] && return 0
  done
  return 1
}

list_product_main_processes() {
  ps -ax -o pid=,command= | awk -v name="$PROCESS_NAME" '
    $2 ~ /\/Contents\/MacOS\// {
      exe=$2
      n=split(exe, parts, "/")
      if (parts[n] == name && exe !~ /\.appex\//) {
        print $1 "\t" exe
      }
    }
  '
}

verify_pid_executable() {
  local pid="$1"
  local expected="$2"
  local actual=""
  actual="$(ps -p "$pid" -o command= 2>/dev/null | awk '{print $1}')"
  [[ -n "$actual" && "$actual" == "$expected" ]]
}

quit_pid_term() {
  local pid="$1"
  local expected="$2"
  if ! verify_pid_executable "$pid" "$expected"; then
    echo "Refusing to signal PID $pid; executable is not $expected" >&2
    return 1
  fi
  kill -TERM "$pid" 2>/dev/null || true
}

wait_pid_exit() {
  local pid="$1"
  local i=0
  while ps -p "$pid" >/dev/null 2>&1 && [[ $i -lt 40 ]]; do
    sleep 0.25
    i=$((i + 1))
  done
  ! ps -p "$pid" >/dev/null 2>&1
}

quit_product_instances() {
  local remaining=0
  local preserved=0
  local pid exe bundle_id

  if [[ -d "$OFFICIAL_APP" ]]; then
    osascript -e "tell application id \"$APP_BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    sleep 0.4
  fi

  while IFS=$'\t' read -r pid exe; do
    [[ -n "$pid" && -n "$exe" ]] || continue
    if is_official_executable "$exe" || is_derived_data_product_path "$exe"; then
      if ps -p "$pid" >/dev/null 2>&1; then
        quit_pid_term "$pid" "$exe" || true
        if ! wait_pid_exit "$pid"; then
          echo "PID $pid did not exit after SIGTERM: $exe" >&2
          remaining=$((remaining + 1))
        else
          echo "Quit verified instance PID $pid ($exe)"
        fi
      fi
      continue
    fi

    bundle_id="$(bundle_id_for_executable "$exe")"
    if is_recognized_bundle_id "$bundle_id"; then
      if ps -p "$pid" >/dev/null 2>&1; then
        quit_pid_term "$pid" "$exe" || true
        if wait_pid_exit "$pid"; then
          echo "Quit historical instance PID $pid ($exe)"
        else
          echo "Historical instance PID $pid did not exit: $exe" >&2
          remaining=$((remaining + 1))
        fi
      fi
      continue
    fi

    echo "Preserved unrecognized CalendarCountdown-named process PID $pid ($exe) bundle_id=${bundle_id:-unknown}" >&2
    preserved=$((preserved + 1))
  done < <(list_product_main_processes)

  if [[ "$remaining" -gt 0 ]]; then
    echo "Some product instances are still running." >&2
    return 1
  fi
  return 0
}

open_official_app() {
  if [[ ! -d "$OFFICIAL_APP" ]]; then
    echo "Official app is missing: $OFFICIAL_APP" >&2
    return 1
  fi
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$OFFICIAL_APP" >/dev/null 2>&1 || true
  open "$OFFICIAL_APP"
}

count_product_main_processes() {
  list_product_main_processes | awk 'NF {c++} END {print c+0}'
}
