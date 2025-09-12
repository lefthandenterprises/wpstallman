#!/usr/bin/env bash
set -euo pipefail

echo "[runner] argv: $*"
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# If running from artifacts, SCRIPT_DIR will be that folder; if running from build/package, we’ll still auto-pick the right file below.

# Resolve the directory containing the AppImage (default: the folder this script is in)
DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
echo "[runner] script dir: $DIR"

APPIMG="${1:-}"
if [[ -z "$APPIMG" ]]; then
  shopt -s nullglob
  imgs=("$DIR"/*.AppImage)
  shopt -u nullglob
  if ((${#imgs[@]}==0)); then
    echo "[runner] No .AppImage found in: $DIR"
    echo "[runner] Contents:"
    ls -la "$DIR" || true
    exit 1
  fi
  # pick newest by mtime (first in ls -t)
  APPIMG="$(ls -t "$DIR"/*.AppImage | head -n1)"
fi

if [[ ! -f "$APPIMG" ]]; then
  echo "[runner] Not a file: $APPIMG"
  exit 1
fi

chmod +x "$APPIMG" 2>/dev/null || true

TS="$(date +%Y%m%d-%H%M%S)"
LOG="$DIR/wpst-appimage-debug-$TS.log"

# Debug env
export APPIMAGE_DEBUG=1
export DOTNET_BUNDLE_EXTRACT_BASE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/WPStallman/dotnet_bundle"

echo "[runner] Using AppImage: $APPIMG"
echo "[runner] Log file      : $LOG"
echo "[runner] APPIMAGE_DEBUG=1"
echo "[runner] DOTNET_BUNDLE_EXTRACT_BASE_DIR=$DOTNET_BUNDLE_EXTRACT_BASE_DIR"
echo "[runner] pwd=$(pwd)"
echo "----- output begins -----"
"$APPIMG" 2>&1 | tee "$LOG"
RC=${PIPESTATUS[0]}
echo "----- output ends -----"
echo "[runner] Exit code: $RC"
echo "[runner] Log saved: $LOG"

# Hint if FUSE fails
if [[ $RC -ne 0 ]] && grep -qiE 'fuse|squashfs' "$LOG"; then
  echo
  echo "[runner] It looks like a FUSE issue. Try:"
  echo "  \"$APPIMG\" --appimage-extract"
  echo "  export LD_LIBRARY_PATH=\"\$PWD/squashfs-root/usr/lib/com.wpstallman.app:\$LD_LIBRARY_PATH\""
  echo "  squashfs-root/usr/lib/com.wpstallman.app/WPStallman.GUI"
fi

exit $RC
