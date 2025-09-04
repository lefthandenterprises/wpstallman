#!/usr/bin/env bash
# package_icons_from_master.sh
# Generate icons from a master PNG/SVG, stage Linux hicolor, promote 256px to build/assets,
# and build ICO/ICNS when tools are available.

set -euo pipefail
shopt -s nullglob nocasematch

# Debug: set ICON_DEBUG=1 for tracing
if [[ "${ICON_DEBUG:-0}" == "1" ]]; then
  set -x
  set -o errtrace
  trap 'echo "FAILED at line $LINENO: $BASH_COMMAND" >&2' ERR
fi

have(){ command -v "$1" >/dev/null 2>&1; }
die(){ echo "ERROR: $*" >&2; exit 1; }
log(){ printf '%s\n' "$*" >&2; }

# ----- resolve repo root -----
SCRIPT_DIR="$(cd -- "$(dirname "$0")" >/dev/null 2>&1 && pwd -P)"
if REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"; then :; else
  REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
fi

# ----- args -----
MASTER=""
BASENAME="WPS"
APP_ICON_NAME="wpstallman"
OUTDIR_REL="artifacts/icons"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --master) MASTER="$2"; shift 2;;
    --basename) BASENAME="$2"; shift 2;;
    --app-icon-name) APP_ICON_NAME="$2"; shift 2;;
    --outdir) OUTDIR_REL="$2"; shift 2;;
    --dry-run) DRY_RUN=1; shift;;
    -h|--help) sed -n '1,160p' "$0"; exit 0;;
    *) die "Unknown arg: $1";;
  esac
done

# ----- tools -----
have convert    || die "ImageMagick 'convert' is required (sudo apt install -y imagemagick)"
IDENTIFY_OK=0; have identify && IDENTIFY_OK=1
PNG2ICNS_OK=0; have png2icns && PNG2ICNS_OK=1
INKSCAPE_OK=0; have inkscape && INKSCAPE_OK=1
RSVG_OK=0;     have rsvg-convert && RSVG_OK=1

log "==> ICON PACK BEGIN"
ASSETS_DIR="$REPO_ROOT/src/WPStallman.Assets"
[[ -d "$ASSETS_DIR" ]] || die "Assets dir not found: $ASSETS_DIR"

# ----- master detection -----
if [[ -z "$MASTER" ]]; then
  if [[ -f "$ASSETS_DIR/WPS-1024.png" ]]; then
    MASTER="$ASSETS_DIR/WPS-1024.png"
  else
    CANDIDATES=()
    while IFS= read -r -d '' f; do CANDIDATES+=("$f"); done < <(find "$ASSETS_DIR" -type f -iname '*.png' -print0)
    if (( ${#CANDIDATES[@]} == 0 )); then
      die "No PNGs found; specify --master <path.svg|png>"
    fi
    if (( IDENTIFY_OK )); then
      best=""; best_area=0
      for f in "${CANDIDATES[@]}"; do
        read -r w h < <(identify -format "%w %h" "$f" 2>/dev/null || echo "0 0")
        area=$((w*h)); if (( area > best_area )); then best="$f"; best_area=$area; fi
      done
      MASTER="$best"
    else
      MASTER="${CANDIDATES[0]}"
    fi
  fi
fi

# ----- rasterize SVG master if needed -----
TMP_DIR="$(mktemp -d)"; trap 'rm -rf "$TMP_DIR"' EXIT
EXT="${MASTER##*.}"; MASTER_PNG="$MASTER"
if [[ "${EXT,,}" == "svg" ]]; then
  MASTER_PNG="$TMP_DIR/master-1024.png"
  if (( INKSCAPE_OK )); then
    inkscape "$MASTER" --export-type=png --export-filename="$MASTER_PNG" -w 1024 -h 1024
  elif (( RSVG_OK )); then
    rsvg-convert -w 1024 -h 1024 -o "$MASTER_PNG" "$MASTER"
  else
    die "SVG master provided but neither inkscape nor rsvg-convert is available"
  fi
fi

# Verify size (non-fatal warning)
if (( IDENTIFY_OK )); then
  if ! dims="$(identify -format '%w %h' "$MASTER_PNG" 2>/dev/null)"; then
    dims="0 0"
  fi
  mw="${dims%% *}"   # first number
  mh="${dims##* }"   # last number
  if [ "${mw:-0}" -lt 256 ] || [ "${mh:-0}" -lt 256 ]; then
    log "WARN: master is ${mw}x${mh}; upscaling may reduce quality"
  fi
fi


# ----- output dirs -----
OUTDIR="$OUTDIR_REL"; [[ "$OUTDIR" = /* ]] || OUTDIR="$REPO_ROOT/$OUTDIR"
GEN="$OUTDIR/generated"
HICOLOR="$OUTDIR/hicolor"
PKG_ASSET="$REPO_ROOT/build/assets/$APP_ICON_NAME.png"
ICO_OUT="$OUTDIR/${BASENAME}.ico"
ICNS_OUT="$OUTDIR/${BASENAME}.icns"

mkdir -p "$GEN" "$HICOLOR/64x64/apps" "$HICOLOR/128x128/apps" "$HICOLOR/256x256/apps"
mkdir -p "$(dirname "$PKG_ASSET")"

# ----- sizes -----
ICO_SIZES=(16 32 48 64 128 256)
ICNS_SIZES=(16 32 128 256 512 1024)   # mac-valid (skip 64)
LINUX_SIZES=(64 128 256)

declare -A need=()
for s in "${ICO_SIZES[@]}" "${ICNS_SIZES[@]}" "${LINUX_SIZES[@]}"; do need[$s]=1; done

# ----- generate -----
for s in "${!need[@]}"; do
  convert "$MASTER_PNG" -resize ${s}x${s} -gravity center -background none -extent ${s}x${s} \
          "$GEN/${BASENAME}-${s}.png"
done

# sanity dimensions (best effort; avoid process substitution with set -e)
if (( IDENTIFY_OK )); then
  for s in "${!need[@]}"; do
    dims="$(identify -format '%w %h' "$GEN/${BASENAME}-${s}.png" 2>/dev/null || echo '')"
    if [[ -z "$dims" ]]; then
      die "identify failed for $GEN/${BASENAME}-${s}.png"
    fi
    w="${dims%% *}"
    h="${dims##* }"
    if [[ "$w" != "$s" || "$h" != "$s" ]]; then
      die "Generated $GEN/${BASENAME}-${s}.png is ${w}x${h}, expected ${s}x${s}"
    fi
  done
fi


# ----- stage Linux hicolor -----
cp "$GEN/${BASENAME}-64.png"  "$HICOLOR/64x64/apps/$APP_ICON_NAME.png"
cp "$GEN/${BASENAME}-128.png" "$HICOLOR/128x128/apps/$APP_ICON_NAME.png"
cp "$GEN/${BASENAME}-256.png" "$HICOLOR/256x256/apps/$APP_ICON_NAME.png"

# promote 256px for packagers
cp "$GEN/${BASENAME}-256.png" "$PKG_ASSET"

# ----- ICO -----
frames=()
for s in "${ICO_SIZES[@]}"; do
  frames+=("$GEN/${BASENAME}-${s}.png")
done
convert "${frames[@]}" "$ICO_OUT" || log "WARN: ICO build failed"

# ----- ICNS -----
if (( PNG2ICNS_OK )); then
  inputs=()
  for s in "${ICNS_SIZES[@]}"; do
    inputs+=("$GEN/${BASENAME}-${s}.png")
  done
  png2icns "$ICNS_OUT" "${inputs[@]}" || log "WARN: ICNS build failed"
else
  log "INFO: png2icns not found; skipping ICNS"
fi


log "==> ICON PACK END"
echo "Generated frames: $GEN"
echo "Hicolor staged:   $HICOLOR"
echo "Packager PNG:     $PKG_ASSET"
echo "ICO:              $ICO_OUT"
echo "ICNS:             $ICNS_OUT (if built)"
exit 0
