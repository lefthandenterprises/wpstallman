#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Publish Master Icon
#   1. Converts DRS-1200.png → DRS.ico using ImageMagick 6
#   2. Saves to src/WPStallman.Assets/Logo/DRS.ico (canonical copy)
#   3. Replaces all other DRS.ico files in repo with this master copy
# -----------------------------------------------------------------------------

ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_PNG="$ROOT/src/WPStallman.Assets/Logo/DRS-1200.png"
OUT_ICO="$ROOT/src/WPStallman.Assets/Logo/DRS.ico"

echo "== Publish Master Icon =="
echo "[INFO] ROOT     : $ROOT"
echo "[INFO] SRC_PNG  : $SRC_PNG"
echo "[INFO] OUT_ICO  : $OUT_ICO"
echo

if [[ ! -f "$SRC_PNG" ]]; then
  echo "[ERR] Missing source image: $SRC_PNG"
  exit 1
fi

# --- Step 1: Generate master ICO using ImageMagick 6 ---
echo "[INFO] Converting PNG → ICO..."
convert "$SRC_PNG" \
  -background none -alpha on -colorspace sRGB \
  \( -clone 0 -resize 256x256 -define icon:format=bmp \) \
  \( -clone 0 -resize 128x128 -define icon:format=bmp \) \
  \( -clone 0 -resize 64x64  -define icon:format=bmp \) \
  \( -clone 0 -resize 48x48  -define icon:format=bmp \) \
  \( -clone 0 -resize 32x32  -define icon:format=bmp \) \
  \( -clone 0 -resize 24x24  -define icon:format=bmp \) \
  \( -clone 0 -resize 16x16  -define icon:format=bmp \) \
  -delete 0 -alpha on "$OUT_ICO"

echo "[OK] Master ICO generated: $OUT_ICO"
echo

# --- Step 2: Replace all other DRS.ico copies ---
echo "[INFO] Propagating master ICO across repo..."

# Find all .ico files named DRS.ico except the master copy
mapfile -t targets < <(find "$ROOT" -type f -name "DRS.ico" ! -path "$OUT_ICO")

if [[ ${#targets[@]} -eq 0 ]]; then
  echo "[WARN] No other DRS.ico files found to replace."
else
  for f in "${targets[@]}"; do
    echo "  → Replacing: ${f#$ROOT/}"
    cp -f "$OUT_ICO" "$f"
  done
  echo "[OK] Replaced ${#targets[@]} file(s)."
fi

echo
echo "[DONE] Master icon propagated successfully."
