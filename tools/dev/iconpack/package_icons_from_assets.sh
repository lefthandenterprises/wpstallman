#!/usr/bin/env bash
# package_icons_from_assets.sh
# Discover existing PNG icon sizes in src/WPStallman.Assets and package them:
# - Stage correct hicolor icons (64/128/256) under artifacts/icons/hicolor/.../apps/wpstallman.png
# - Build a Windows .ico (16,32,48,64,128,256) if possible
# - Build a macOS .icns if png2icns is available (optional)
# - Promote a 256px PNG to build/assets/wpstallman.png for packagers
#
# Usage:
#   tools/dev/iconpack/package_icons_from_assets.sh [--basename WPS] [--app-icon-name wpstallman] [--source DIR] [--dry-run]
#
# Defaults:
#   --basename        WPS                      (used for ICO/ICNS filenames in artifacts/icons)
#   --app-icon-name   wpstallman               (filename for hicolor/icons + .desktop Icon=)
#   --source          src/WPStallman.Assets    (searched recursively for *-16/32/48/64/128/256/512/1024.png)
#
set -euo pipefail
shopt -s nullglob nocasematch

# ---------- helpers ----------
have_cmd(){ command -v "$1" >/dev/null 2>&1; }
die(){ echo "ERROR: $*" >&2; exit 1; }
log(){ printf '%s\n' "$*" >&2; }
run(){ if [[ "${DRY_RUN:-0}" == "1" ]]; then log "[DRY] $*"; else eval "$@"; fi; }

# ---------- resolve repo root ----------
SCRIPT_DIR="$(cd -- "$(dirname "$0")" >/dev/null 2>&1 && pwd -P)"
if git -C "$SCRIPT_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
  REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
else
  # Assume tools/dev/iconpack/.. -> repo root
  REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
fi

# ---------- args ----------
BASENAME="WPS"
APP_ICON_NAME="wpstallman"
SOURCE_REL="src/WPStallman.Assets"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --basename) BASENAME="$2"; shift 2;;
    --app-icon-name) APP_ICON_NAME="$2"; shift 2;;
    --source) SOURCE_REL="$2"; shift 2;;
    --dry-run) DRY_RUN=1; shift;;
    -h|--help)
      sed -n '1,120p' "$0"; exit 0;;
    *) die "Unknown arg: $1";;
  esac
done

SOURCE_DIR="$SOURCE_REL"
[[ "$SOURCE_DIR" = /* ]] || SOURCE_DIR="$REPO_ROOT/$SOURCE_DIR"
[[ -d "$SOURCE_DIR" ]] || die "Source dir not found: $SOURCE_DIR"

OUTDIR="$REPO_ROOT/artifacts/icons"
HICOLOR="$OUTDIR/hicolor"
PKG_ASSET="$REPO_ROOT/build/assets/$APP_ICON_NAME.png"
ICO_OUT="$OUTDIR/${BASENAME}.ico"
ICNS_OUT="$OUTDIR/${BASENAME}.icns"

run "mkdir -p \"$OUTDIR\" \"$HICOLOR/64x64/apps\" \"$HICOLOR/128x128/apps\" \"$HICOLOR/256x256/apps\""
run "mkdir -p \"$(dirname "$PKG_ASSET")\""

# ---------- find PNGs by size ----------
# Prefer files that have size tokens in name (e.g., *-256.png). If ImageMagick is available, verify dimensions.
sizes=(16 32 48 64 128 256 512 1024)
declare -A files_by_size
for s in "${sizes[@]}"; do files_by_size[$s]=""; done

# first pass: name-based
while IFS= read -r -d '' f; do
  base="$(basename "$f")"
  for s in "${sizes[@]}"; do
    if [[ "$base" =~ (^|[^0-9])(${s})([^0-9]|\.png$) ]]; then
      files_by_size[$s]="$f"
      break
    fi
  done
done < <(find "$SOURCE_DIR" -type f -iregex '.*\.png$' -print0)

# second pass: dimension-based (optional) to choose better matches
if have_cmd identify; then
  for s in "${sizes[@]}"; do
    best="${files_by_size[$s]}"
    if [[ -z "$best" ]]; then
      while IFS= read -r -d '' f; do
        read -r w h < <(identify -format "%w %h" "$f" 2>/dev/null || echo "0 0")
        if [[ "$w" == "$s" && "$h" == "$s" ]]; then
          files_by_size[$s]="$f"; break
        fi
      done < <(find "$SOURCE_DIR" -type f -iregex '.*\.png$' -print0)
    fi
  done
else
  log "WARN: ImageMagick 'identify' not found; relying on filename sizes only."
fi

# require at least 64/128/256
for need in 64 128 256; do
  [[ -n "${files_by_size[$need]}" ]] || die "Missing ${need}x${need} PNG in assets (e.g., *-${need}.png)."
done

log "Discovered PNGs:"
for s in "${sizes[@]}"; do
  f="${files_by_size[$s]}"
  [[ -n "$f" ]] && log "  ${s}x${s}: $f"
done

# ---------- stage hicolor icons ----------
run "cp \"${files_by_size[64]}\"  \"$HICOLOR/64x64/apps/$APP_ICON_NAME.png\""
run "cp \"${files_by_size[128]}\" \"$HICOLOR/128x128/apps/$APP_ICON_NAME.png\""
run "cp \"${files_by_size[256]}\" \"$HICOLOR/256x256/apps/$APP_ICON_NAME.png\""

# Promote 256px into build/assets/<name>.png for packagers
run "cp \"${files_by_size[256]}\" \"$PKG_ASSET\""

# ---------- build ICO (if convert available) ----------
if have_cmd convert; then
  frames=()
  for s in 16 32 48 64 128 256; do
    if [[ -n "${files_by_size[$s]}" ]]; then frames+=("${files_by_size[$s]}"); fi
  done
  if ((${#frames[@]})); then
    # shellcheck disable=SC2145
    run "convert ${frames[*]} \"$ICO_OUT\""
  else
    log "WARN: No frames for ICO were found; skipping ${ICO_OUT}"
  fi
else
  log "WARN: ImageMagick 'convert' not found; skipping ICO."
fi

# ---------- build ICNS (if png2icns available) ----------
if have_cmd png2icns; then
  inputs=()
  for s in 16 32 64 128 256 512 1024; do
    if [[ -n "${files_by_size[$s]}" ]]; then inputs+=("${files_by_size[$s]}"); fi
  done
  if ((${#inputs[@]})); then
    # shellcheck disable=SC2145
    run "png2icns \"$ICNS_OUT\" ${inputs[*]}"
  else
    log "WARN: No PNG inputs for ICNS; skipping ${ICNS_OUT}"
  fi
else
  log "INFO: 'png2icns' not found; skipping ICNS."
fi

echo "Done."
echo "Staged hicolor icons under: $HICOLOR"
echo "Primary packaging PNG:       $PKG_ASSET"
echo "ICO (if built):              $ICO_OUT"
echo "ICNS (if built):             $ICNS_OUT"
