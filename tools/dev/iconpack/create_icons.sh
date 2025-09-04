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


usage() {
  cat <<'EOF'
Usage:
  ./create_icons.sh /path/to/logo.svg [basename] [export_id]

Examples:
  ./create_icons.sh ../logo/WP-Stallman-Logo.svg WPS
  ./create_icons.sh ../logo/WP-Stallman-Logo.svg WPS tophat

Outputs go to ./build:
  WPS-16..1024.png, WPS.ico (Windows RGBA), WPS.icns (macOS)
Deps:
  - rsvg-convert OR inkscape (SVG -> PNG)
  - ImageMagick (magick or convert)
  - icnsutils (png2icns)
EOF
}

if [[ $# -lt 1 ]]; then usage; exit 1; fi

SVG="$1"
BASENAME="${2:-}"
EXPORT_ID="${3:-}"     # optional: bare id (e.g. tophat), not "#tophat"

if [[ ! -f "$SVG" ]]; then
  echo "ERROR: File not found: $SVG" >&2
  exit 1
fi

if [[ -z "$BASENAME" ]]; then
  fn="${SVG##*/}"
  BASENAME="${fn%.*}"
fi

OUTDIR="${OUTDIR:-$REPO_ROOT/artifacts/icons}"
mkdir -p "$OUTDIR"

have_cmd(){ command -v "$1" >/dev/null 2>&1; }

# Choose exporter (prefer rsvg, fallback to inkscape)
EXPORTER=""
if have_cmd rsvg-convert; then
  EXPORTER="rsvg-convert"
elif have_cmd inkscape; then
  EXPORTER="inkscape"
else
  echo "ERROR: Need rsvg-convert or inkscape. Try: sudo apt install librsvg2-bin inkscape" >&2
  exit 1
fi

# If you want to force inkscape for testing, uncomment next line:
# EXPORTER="inkscape"

# ImageMagick
if have_cmd magick; then MAGICK="magick"
elif have_cmd convert; then MAGICK="convert"
else
  echo "ERROR: Need ImageMagick. Try: sudo apt install imagemagick" >&2
  exit 1
fi

# icnsutils
if ! have_cmd png2icns; then
  echo "ERROR: Need png2icns. Try: sudo apt install icnsutils" >&2
  exit 1
fi

MASTER="${OUTDIR}/${BASENAME}-1024.png"

echo "==> Exporting 1024x1024 master from SVG with $EXPORTER ..."
if [[ "$EXPORTER" == "rsvg-convert" ]]; then
  # rsvg-convert has no export-id option; it renders the whole doc
  rsvg-convert -w 1024 -h 1024 "$SVG" -o "$MASTER"
else
  # Inkscape 1.x
  if [[ -n "$EXPORT_ID" ]]; then
    inkscape "$SVG" \
      --export-type=png \
      --export-id="$EXPORT_ID" \
      --export-filename="$MASTER" \
      -w 1024 -h 1024 \
      --export-background-opacity=0
  else
    inkscape "$SVG" \
      --export-type=png \
      --export-filename="$MASTER" \
      -w 1024 -h 1024 \
      --export-background-opacity=0
  fi
fi

# Verify master exists where we expect it
if [[ ! -f "$MASTER" ]]; then
  echo "ERROR: Failed to create $MASTER" >&2
  exit 1
fi

# Sizes for app assets
SIZES=(16 24 32 48 64 128 256 512 1024)

echo "==> Creating resized PNGs (RGBA) ..."
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

# macOS ICNS (limit to sizes png2icns accepts reliably)
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

