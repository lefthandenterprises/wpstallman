#!/usr/bin/env bash
set -euo pipefail

# Resolve repo root based on this script's location
SCRIPT_DIR="$(cd -- "$(dirname "$0")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

SRC="$REPO_ROOT/WPStallman.Assets/logo"
DST="$REPO_ROOT/WPStallman.GUI/wwwroot/img"

# Optional: make globs with no matches expand to nothing (avoid cp errors)
shopt -s nullglob

mkdir -p "$DST"

echo "==> Copying icons from $SRC to $DST"

# Copy all sizes
if compgen -G "$SRC/APP-*.png" > /dev/null; then
  cp "$SRC"/APP-*.png "$DST"/
else
  echo "[WARN] No APP-*.png files found in $SRC"
fi

# Copy ICO and ICNS (if present)
for f in "$SRC/app.ico" "$SRC/app.icns"; do
  if [[ -f "$f" ]]; then
    cp "$f" "$DST"/
  else
    echo "[WARN] Missing $(basename "$f") in $SRC (skipping)"
  fi
done

echo "Done. Final contents of $DST:"
ls -1 "$DST"
