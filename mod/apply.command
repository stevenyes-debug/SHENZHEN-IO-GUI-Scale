#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCHER="$SCRIPT_DIR/ShenzhenScalePatcher"
GAME_DIR="${SHENZHEN_IO_DIR:-$HOME/Library/Application Support/Steam/steamapps/common/SHENZHEN IO}"

SCALE="${1:-}"
if [ -z "$SCALE" ]; then
  printf 'GUI scale (1-4, default 2): '
  read -r SCALE
  SCALE="${SCALE:-2}"
fi

case "$SCALE" in
  1|2|3|4) ;;
  *) echo "scale must be 1-4"; exit 1 ;;
esac

if [ -f "$PATCHER" ]; then
  :
else
  echo "missing patcher: $PATCHER"
  exit 1
fi

APP="$GAME_DIR/Shenzhen IO.app"
EXE="$APP/Contents/MacOS/Shenzhen.exe"

if [ -f "$EXE" ]; then
  :
else
  echo "missing game: $EXE"
  exit 1
fi

ORIGINAL="$EXE.scale-original"
PATCHED_HASH_FILE="$EXE.scale-patched.sha256"
CURRENT_HASH="$(shasum -a 256 "$EXE" | awk '{print $1}')"

if [ -f "$ORIGINAL" ]; then
  ORIGINAL_HASH="$(shasum -a 256 "$ORIGINAL" | awk '{print $1}')"
  PATCHED_HASH=""
  if [ -f "$PATCHED_HASH_FILE" ]; then
    PATCHED_HASH="$(cat "$PATCHED_HASH_FILE")"
  fi
  if [ "$CURRENT_HASH" = "$ORIGINAL_HASH" ] || [ "$CURRENT_HASH" = "$PATCHED_HASH" ]; then
    :
  else
    cp "$EXE" "$ORIGINAL"
    echo "Steam update detected; backup refreshed"
  fi
else
  cp "$EXE" "$ORIGINAL"
  echo "original Shenzhen.exe backed up"
fi

TMP="$(mktemp "${TMPDIR:-/tmp}/shenzhen-scale.XXXXXX")"
trap 'rm -f "$TMP"' EXIT

"$PATCHER" "$ORIGINAL" "$TMP" "$SCALE"
cp "$TMP" "$EXE"
chmod +x "$EXE"
shasum -a 256 "$EXE" | awk '{print $1}' > "$PATCHED_HASH_FILE"

echo
echo "done: ${SCALE}x GUI scale patch applied"
echo "launch the game from Steam normally"
echo "restore: double-click restore.command"
