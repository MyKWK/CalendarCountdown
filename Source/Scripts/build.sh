#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"
"$SCRIPT_DIR/bootstrap.sh"
xcodebuild \
  -project CalendarCountdown.xcodeproj \
  -scheme CalendarCountdown \
  -configuration Debug \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
