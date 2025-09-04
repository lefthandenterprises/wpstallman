#!/usr/bin/env bash
# Lint an AppImage for WPStallman
# Usage:
#   tools/dev/lint/lint_appimage.sh [path/to/WPStallman-*.AppImage]
# Defaults to latest in artifacts/packages/

set -uo pipefail

die(){ echo "ERROR: $*" >&2; exit 1; }
note(){ echo -e "\033[1;32m==> $*\033[0m"; }
warn(){ echo -e "\033[1;33mWARN:\033[0m $*"; }
have(){ command -v "$1" >/dev/null 2>&1; }

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
if REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"; then :; else
  REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
fi

PKG_DIR="$REPO_ROOT/artifacts/packages"
APPIMG="${1:-}"
if [[ -z "$APPIMG" ]]; then
  APPIMG="$(ls -1t "$PKG_DIR"/WPStallman-*.AppImage 2>/dev/null | head -n1 || true)"
fi
[[ -n "$APPIMG" && -f "$APPIMG" ]] || die "No AppImage found. Pass a path or build one first."

note "Linting: $APPIMG"
file "$APPIMG" | sed 's/^/  /' || true

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pushd "$TMP" >/dev/null

# -------- extract --------
EXTRACTED=0
chmod +x "$APPIMG" 2>/dev/null || true
if "$APPIMG" --appimage-extract >/dev/null 2>&1; then
  EXTRACTED=1
elif have unsquashfs; then
  # fallback; may require squashfs-tools
  if unsquashfs -d squashfs-root "$APPIMG" >/dev/null 2>&1; then
    EXTRACTED=1
  fi
fi

[[ "$EXTRACTED" -eq 1 ]] || die "Unable to extract AppImage (need runtime or squashfs-tools)"

APPDIR="$TMP/squashfs-root"
[[ -d "$APPDIR" ]] || die "No squashfs-root after extraction"

# -------- basic structure --------
FAIL=0

if [[ ! -x "$APPDIR/AppRun" ]]; then
  warn "Missing or non-executable AppRun"
  FAIL=1
fi

DESK="$(find "$APPDIR" -maxdepth 1 -type f -name '*.desktop' | head -n1 || true)"
if [[ -z "$DESK" ]]; then
  warn "No top-level .desktop found in AppDir"
  FAIL=1
else
  note "desktop-file: $(basename "$DESK")"
  if have desktop-file-validate; then
    if ! desktop-file-validate "$DESK"; then
      warn "desktop-file-validate reported issues"
      FAIL=1
    fi
  else
    warn "desktop-file-validate not installed (sudo apt install -y desktop-file-utils)"
  fi
  echo "  Desktop Exec/Icon lines:"
  grep -E '^(Exec|Icon)=' "$DESK" | sed 's/^/    /' || true
fi

# -------- icon checks --------
if have identify; then
  for sz in 64 128 256; do
    ic="$APPDIR/usr/share/icons/hicolor/${sz}x${sz}/apps/wpstallman.png"
    if [[ ! -f "$ic" ]]; then
      warn "Missing icon in AppDir: $ic"
      FAIL=1
    else
      read -r w h < <(identify -format "%w %h" "$ic" 2>/dev/null || echo "0 0")
      if [[ "$w" != "$sz" || "$h" != "$sz" ]]; then
        warn "Icon $ic is ${w}x${h}, expected ${sz}x${sz}"
        FAIL=1
      fi
    fi
  done
else
  warn "ImageMagick not installed; skipping icon dimension checks (sudo apt install -y imagemagick)"
fi

# -------- optional: appstream/metainfo --------
META="$(find "$APPDIR/usr/share/metainfo" -maxdepth 1 -type f -name '*.xml' 2>/dev/null | head -n1 || true)"
if [[ -n "$META" ]]; then
  note "AppStream metainfo: $(basename "$META")"
  if have appstreamcli; then
    if ! appstreamcli validate "$META"; then
      warn "appstreamcli reported issues"
      # not failing hard; up to you:
      # FAIL=1
    fi
  else
    warn "appstreamcli not installed (sudo apt install -y appstream)"
  fi
fi

popd >/dev/null

if [[ "$FAIL" -ne 0 ]]; then
  die "appimage lint FAILED"
else
  note "appimage lint OK"
fi
