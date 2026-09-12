#!/usr/bin/env bash
# Compatibility entry point for the complete local release workflow.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "$SCRIPT_DIR/release-local.sh" "$@"
