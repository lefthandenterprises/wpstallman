#!/usr/bin/env bash
set -euo pipefail

# Resolve repo root
SCRIPT_DIR="$(cd -- "$(dirname "$0")" >/dev/null 2>&1 && pwd -P)"
if git -C "$SCRIPT_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
  REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
else
  # tools/dev/iconpack -> repo-root
  REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
fi

# Default output location (overridable via env OUTDIR=...)
OUTDIR="${OUTDIR:-$REPO_ROOT/artifacts/icons}"
mkdir -p "$OUTDIR"


# create_icons_from_png.sh
# Generate multi-size PNGs, .ICO (Windows, RGBA), and .ICNS (macOS)
# from a *transparent* master PNG (e.g., a 1024x1024 export from Inkscape).
#
# Usage:
#   ./create_icons_from_png.sh /path/to/master.png [basename]
#
# Examples:
#   ./create_icons_from_png.sh WPS-1024.png WPS
#   # -> build/WPS-16.png ... WPS-1024.png, WPS.ico, WPS.icns
#
# Deps:
#   - ImageMagick ('magick' or 'convert')
#   - icnsutils (png2icns)

usage() {
  cat <<'EOF'
Usage:
  ./create_icons_from_png.sh /path/to/master.png [basename]

If [basename] is omitted, it's derived from the PNG filename.
Outputs go to ./build
EOF
}

if [[ $# -lt 1 ]]; then
  usage; exit 1
fi

MASTER_SRC="$1"
BASENAME="${2:-}"

if [[ ! -f "$MASTER_SRC" ]]; then
  echo "ERROR: File not found: $MASTER_SRC" >&2
  exit 1
fi

if [[ -z "$BASENAME" ]]; then
  fn="${MASTER_SRC##*/}"
  BASENAME="${fn%.*}"
fi

OUTDIR="${OUTDIR:-$REPO_ROOT/artifacts/icons}"

mkdir -p "$OUTDIR"

# --- Check dependencies ---
have_cmd(){ command -v "$1" >/dev/null 2>&1; }

if have_cmd magick; then MAGICK="magick"
elif have_cmd convert; then MAGICK="convert"
else
  echo "ERROR: Need ImageMagick. Try: sudo apt install imagemagick" >&2
  exit 1
fi

if ! have_cmd png2icns; then
  echo "ERROR: Need png2icns. Try: sudo apt install icnsutils" >&2
  exit 1
fi

# Normalize master: ensure RGBA & sRGB; also copy into build/ as the canonical 1024
MASTER="${OUTDIR}/${BASENAME}-1024.png"
$MAGICK "$MASTER_SRC" \
  -background none -alpha on -colorspace sRGB -type TrueColorAlpha \
  -resize 1024x1024 \
  PNG32:"$MASTER"

if [[ ! -f "$MASTER" ]]; then
  echo "ERROR: Failed to prepare $MASTER" >&2
  exit 1
fi

# Sizes to generate
SIZES=(16 24 32 48 64 128 256 512 1024)

echo "==> Creating resized PNGs (RGBA)…"
for s in "${SIZES[@]}"; do
  out="${OUTDIR}/${BASENAME}-${s}.png"
  $MAGICK "$MASTER" \
    -background none -alpha on -colorspace sRGB -type TrueColorAlpha \
    -resize ${s}x${s} \
    PNG32:"$out"
done

# Windows ICO (multi-res RGBA)
ICO="${OUTDIR}/${BASENAME}.ico"
echo "==> Building multi-size ICO: $ICO"
$MAGICK \
  PNG32:"${OUTDIR}/${BASENAME}-16.png" \
  PNG32:"${OUTDIR}/${BASENAME}-24.png" \
  PNG32:"${OUTDIR}/${BASENAME}-32.png" \
  PNG32:"${OUTDIR}/${BASENAME}-48.png" \
  PNG32:"${OUTDIR}/${BASENAME}-64.png"  \
  PNG32:"${OUTDIR}/${BASENAME}-128.png" \
  PNG32:"${OUTDIR}/${BASENAME}-256.png" \
  "$ICO"

# macOS ICNS (sizes png2icns accepts reliably)
ICNS="${OUTDIR}/${BASENAME}.icns"
echo "==> Building ICNS: $ICNS"
png2icns "$ICNS" \
  "${OUTDIR}/${BASENAME}-16.png" \
  "${OUTDIR}/${BASENAME}-32.png" \
  "${OUTDIR}/${BASENAME}-128.png" \
  "${OUTDIR}/${BASENAME}-256.png" \
  "${OUTDIR}/${BASENAME}-512.png" \
  "${OUTDIR}/${BASENAME}-1024.png"

echo ""
echo "Done."
echo "Outputs in: $OUTDIR"
echo " - ${BASENAME}.ico  (Windows, RGBA frames)"
echo " - ${BASENAME}.icns (macOS)"
echo " - ${BASENAME}-*.png (PNG sizes, RGBA)"

