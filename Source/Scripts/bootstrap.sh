#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
  echo "Generated $PROJECT_DIR/CalendarCountdown.xcodeproj with XcodeGen"
else
  python3 "$SCRIPT_DIR/generate_ios_pbxproj.py"
  echo "XcodeGen is not installed; patched $PROJECT_DIR/CalendarCountdown.xcodeproj from HEAD using generate_ios_pbxproj.py"
fi
