#!/usr/bin/env bash
# Lint a Debian package for WPStallman
# Usage:
#   tools/dev/lint/lint_deb.sh [path/to/pkg.deb]
# Defaults to latest: artifacts/packages/wpstallman_*.deb

set -uo pipefail

# -------- helpers --------
die(){ echo "ERROR: $*" >&2; exit 1; }
note(){ echo -e "\033[1;32m==> $*\033[0m"; }
warn(){ echo -e "\033[1;33mWARN:\033[0m $*"; }
have(){ command -v "$1" >/dev/null 2>&1; }

# -------- resolve repo root --------
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
if REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"; then :; else
  REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
fi

PKG_DIR="$REPO_ROOT/artifacts/packages"
DEB="${1:-}"
if [[ -z "$DEB" ]]; then
  # prefer wpstallman_*_amd64.deb, else any .deb
  DEB="$(ls -1t "$PKG_DIR"/wpstallman_*_amd64.deb 2>/dev/null | head -n1 || true)"
  [[ -n "$DEB" ]] || DEB="$(ls -1t "$PKG_DIR"/*.deb 2>/dev/null | head -n1 || true)"
fi
[[ -n "$DEB" && -f "$DEB" ]] || die "No .deb found. Pass a path or build one first."

note "Linting: $DEB"

# -------- show control + contents (useful context) --------
have dpkg-deb || die "dpkg-deb is required"
dpkg-deb -I "$DEB" | sed 's/^/  /' || true

# -------- run lintian --------
if ! have lintian; then
  warn "lintian not installed. Install with: sudo apt install -y lintian"
else
  LINT_OUT="$(mktemp)"
  set +e
  lintian -EviIL+pedantic --no-tag-display-limit "$DEB" | tee "$LINT_OUT"
  LINT_RC=$?
  set -e
fi

# -------- extract for extra checks --------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
dpkg-deb -x "$DEB" "$TMP/root"

# desktop file check
DESK="$(find "$TMP/root/usr/share/applications" -maxdepth 1 -type f -name '*.desktop' | head -n1 || true)"
if [[ -z "$DESK" ]]; then
  warn "No .desktop found under usr/share/applications/"
  DESK_OK=0
else
  note "desktop-file: $(basename "$DESK")"
  if have desktop-file-validate; then
    if ! desktop-file-validate "$DESK"; then
      warn "desktop-file-validate reported issues"
      DESK_OK=0
    else
      DESK_OK=1
    fi
  else
    warn "desktop-file-validate not installed (sudo apt install -y desktop-file-utils)"
    DESK_OK=1
  fi
fi

# icon size checks
ICON_OK=1
if have identify; then
  for sz in 64 128 256; do
    ic="$TMP/root/usr/share/icons/hicolor/${sz}x${sz}/apps/wpstallman.png"
    if [[ ! -f "$ic" ]]; then
      warn "Missing icon: $ic"
      ICON_OK=0
    else
      read -r w h < <(identify -format "%w %h" "$ic" 2>/dev/null || echo "0 0")
      if [[ "$w" != "$sz" || "$h" != "$sz" ]]; then
        warn "Icon $ic is ${w}x${h}, expected ${sz}x${sz}"
        ICON_OK=0
      fi
    fi
  done
else
  warn "ImageMagick not installed; skipping icon dimension checks (sudo apt install -y imagemagick)"
fi

# -------- decide exit code --------
FAIL=0
[[ "${DESK_OK:-0}" -eq 1 ]] || FAIL=1
[[ "${ICON_OK:-1}" -eq 1 ]] || FAIL=1
if [[ -n "${LINT_RC:-0}" && "$LINT_RC" -ne 0 ]]; then
  # lintian returns nonzero when it finds serious issues
  FAIL=1
fi

if [[ "$FAIL" -ne 0 ]]; then
  die "deb lint FAILED"
else
  note "deb lint OK"
fi
