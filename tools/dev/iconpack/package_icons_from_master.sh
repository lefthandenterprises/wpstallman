#!/usr/bin/env bash
# package_icons_from_master.sh
# Generate icons from a master image, then stage for Linux (.deb), Windows (.ico), macOS (.icns).
#
# Usage:
#   tools/dev/iconpack/package_icons_from_master.sh \
#     [--master <path.{png|svg}>] \
#     [--basename WPS] \
#     [--app-icon-name wpstallman] \
#     [--outdir artifacts/icons] \
#     [--dry-run]
#
# Defaults:
#   --master auto-detects the largest PNG in src/WPStallman.Assets, or falls back to WPS-1024.png if present
#   --basename WPS           (prefix for generated files, e.g., WPS-256.png, WPS.ico/.icns)
#   --app-icon-name wpstallman  (used for hicolor filenames + .desktop Icon=)
#   --outdir artifacts/icons
#
set -euo pipefail
shopt -s nullglob nocasematch

have(){ command -v "$1" >/dev/null 2>&1; }
die(){ echo "ERROR: $*" >&2; exit 1; }
log(){ printf '%s\n' "$*" >&2; }
run(){ if [[ "${DRY_RUN:-0}" == "1" ]]; then log "[DRY] $*"; else eval "$@"; fi; }

# ----- resolve repo root -----
SCRIPT_DIR="$(cd -- "$(dirname "$0")" >/dev/null 2>&1 && pwd -P)"
if git -C "$SCRIPT_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
  REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
else
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
    -h|--help) sed -n '1,140p' "$0"; exit 0;;
    *) die "Unknown arg: $1";;
  esac
done

# ----- tools -----
have convert || die "ImageMagick 'convert' is required (sudo apt install imagemagick)."
IDENTIFY_OK=0; have identify && IDENTIFY_OK=1
PNG2ICNS_OK=0; have png2icns && PNG2ICNS_OK=1
INKSCAPE_OK=0; have inkscape && INKSCAPE_OK=1
RSVG_OK=0; have rsvg-convert && RSVG_OK=1

# ----- master detection -----
ASSETS_DIR="$REPO_ROOT/src/WPStallman.Assets"
[[ -d "$ASSETS_DIR" ]] || die "Assets directory not found: $ASSETS_DIR"

if [[ -z "$MASTER" ]]; then
  # Prefer explicit 1024 first
  if [[ -f "$ASSETS_DIR/WPS-1024.png" ]]; then
    MASTER="$ASSETS_DIR/WPS-1024.png"
  else
    # Pick the largest PNG by pixel area
    CANDIDATES=()
    while IFS= read -r -d '' f; do CANDIDATES+=("$f"); done < <(find "$ASSETS_DIR" -type f -iname '*.png' -print0)
    if (( ${#CANDIDATES[@]} )); then
      if (( IDENTIFY_OK )); then
        best=""; best_area=0
        for f in "${CANDIDATES[@]}"; do
          read -r w h < <(identify -format "%w %h" "$f" 2>/dev/null || echo "0 0")
          area=$((w*h))
          if (( area > best_area )); then best_area=$area; best="$f"; fi
        done
        MASTER="$best"
      else
        # Fall back to longest name heuristic
        IFS=$'\n' MASTER="$(printf '%s\n' "${CANDIDATES[@]}" | awk '{print length, $0}' | sort -nr | head -n1 | cut -d' ' -f2-)"
      fi
    fi
  fi
fi

# Allow SVG as master; rasterize to 1024 PNG
TMP_DIR="$(mktemp -d)"
cleanup(){ rm -rf "$TMP_DIR"; }
trap cleanup EXIT

if [[ -z "$MASTER" ]]; then
  die "No master image found. Supply --master <path.png|path.svg>."
fi

EXT="${MASTER##*.}"
MASTER_PNG="$MASTER"
if [[ "${EXT,,}" == "svg" ]]; then
  MASTER_PNG="$TMP_DIR/master-1024.png"
  if (( INKSCAPE_OK )); then
    run "inkscape \"$MASTER\" --export-type=png --export-filename=\"$MASTER_PNG\" -w 1024 -h 1024"
  elif (( RSVG_OK )); then
    run "rsvg-convert -w 1024 -h 1024 -o \"$MASTER_PNG\" \"$MASTER\""
  else
    die "SVG master provided but neither inkscape nor rsvg-convert is available."
  fi
fi

# Verify master size; warn if undersized
if (( IDENTIFY_OK )); then
  read -r mw mh < <(identify -format "%w %h" "$MASTER_PNG" 2>/dev/null || echo "0 0")
  if (( mw < 256 || mh < 256 )); then
    log "WARN: master is ${mw}x${mh}; upscaling may look bad."
  fi
fi

# ----- output dirs -----
OUTDIR="$OUTDIR_REL"; [[ "$OUTDIR" = /* ]] || OUTDIR="$REPO_ROOT/$OUTDIR"
GEN="$OUTDIR/generated"
HICOLOR="$OUTDIR/hicolor"
PKG_ASSET="$REPO_ROOT/build/assets/$APP_ICON_NAME.png"
ICO_OUT="$OUTDIR/${BASENAME}.ico"
ICNS_OUT="$OUTDIR/${BASENAME}.icns"

run "mkdir -p \"$GEN\" \"$HICOLOR/64x64/apps\" \"$HICOLOR/128x128/apps\" \"$HICOLOR/256x256/apps\""
run "mkdir -p \"$(dirname "$PKG_ASSET")\""

# ----- generate sizes -----
# Windows/ICO sizes (and handy for previews)
ICO_SIZES=(16 32 48 64 128 256)
# Mac/ICNS valid bases (do NOT feed 64)
ICNS_SIZES=(16 32 128 256 512 1024)
# Linux hicolor we ship
LINUX_SIZES=(64 128 256)

# Generate all unique sizes we care about
declare -A need
for s in "${ICO_SIZES[@]}" "${ICNS_SIZES[@]}" "${LINUX_SIZES[@]}"; do need[$s]=1; done
for s in "${!need[@]}"; do
  run "convert \"$MASTER_PNG\" -resize ${s}x${s} -gravity center -background none -extent ${s}x${s} \"$GEN/${BASENAME}-${s}.png\""
done

# Verify dimensions (best effort)
if (( IDENTIFY_OK )); then
  for s in "${!need[@]}"; do
    read -r w h < <(identify -format "%w %h" "$GEN/${BASENAME}-${s}.png")
    if [[ "$w" != "$s" || "$h" != "$s" ]]; then
      die "Generated ${GEN}/${BASENAME}-${s}.png is ${w}x${h}, expected ${s}x${s}"
    fi
  done
fi

# ----- stage Linux hicolor -----
run "cp \"$GEN/${BASENAME}-64.png\"  \"$HICOLOR/64x64/apps/$APP_ICON_NAME.png\""
run "cp \"$GEN/${BASENAME}-128.png\" \"$HICOLOR/128x128/apps/$APP_ICON_NAME.png\""
run "cp \"$GEN/${BASENAME}-256.png\" \"$HICOLOR/256x256/apps/$APP_ICON_NAME.png\""

# Promote 256px for packagers
run "cp \"$GEN/${BASENAME}-256.png\" \"$PKG_ASSET\""

# ----- build ICO -----
# Include 16,32,48,64,128,256 (Windows is fine with 64)
ICO_FRAMES=()
for s in "${ICO_SIZES[@]}"; do ICO_FRAMES+=("$GEN/${BASENAME}-${s}.png"); done
run "convert ${ICO_FRAMES[*]} \"$ICO_OUT\""

# ----- build ICNS (only mac-valid sizes) -----
if (( PNG2ICNS_OK )); then
  ICNS_INPUTS=()
  for s in "${ICNS_SIZES[@]}"; do ICNS_INPUTS+=("$GEN/${BASENAME}-${s}.png"); done
  # png2icns rejects 64; we skip it by design
  run "png2icns \"$ICNS_OUT\" ${ICNS_INPUTS[*]}"
else
  log \"INFO: 'png2icns' not found; skipping ICNS.\"
fi

echo "OK."
echo "Generated: $GEN"
echo "Hicolor:   $HICOLOR (.../64x64|128x128|256x256/apps/$APP_ICON_NAME.png)"
echo "Pack PNG:  $PKG_ASSET"
echo "ICO:       $ICO_OUT"
echo "ICNS:      $ICNS_OUT (if built)"
