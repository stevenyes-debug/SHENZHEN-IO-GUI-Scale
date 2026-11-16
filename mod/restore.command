#!/bin/bash
set -euo pipefail

GAME_DIR="${SHENZHEN_IO_DIR:-$HOME/Library/Application Support/Steam/steamapps/common/SHENZHEN IO}"
APP="$GAME_DIR/Shenzhen IO.app"
EXE="$APP/Contents/MacOS/Shenzhen.exe"
ORIGINAL="$EXE.scale-original"
PATCHED_HASH_FILE="$EXE.scale-patched.sha256"

if [ -f "$ORIGINAL" ]; then
  cp "$ORIGINAL" "$EXE"
  chmod +x "$EXE"
  rm -f "$PATCHED_HASH_FILE"
  echo "restored original Shenzhen.exe"
else
  echo "no backup found: $ORIGINAL"
  exit 1
fi
