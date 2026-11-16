#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$(find "$HOME/Library/Application Support/SHENZHEN IO" -maxdepth 2 -name config.cfg -print -quit 2>/dev/null || true)"

if [ -n "$CONFIG" ]; then
  cp "$SCRIPT_DIR/config-original.cfg" "$CONFIG"
  echo "restored config: $CONFIG"
else
  echo "config.cfg not found"
  exit 1
fi
