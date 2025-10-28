#!/usr/bin/env bash
set -euo pipefail

note(){ printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[WARN]\033[0m %s\n" "$*" >&2; }
die(){  printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; exit 1; }

# ------------------------------------------------------------
# Resolve paths
# ------------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"

# ------------------------------------------------------------
# Load metadata (release.meta) and derive defaults
# ------------------------------------------------------------
META="${META:-$ROOT/build/package/release.meta}"
if [[ -f "$META" ]]; then
  set -a; source "$META"; set +a
else
  warn "No release.meta at $META; using defaults."
fi

# Version resolution: prefer APP_VERSION from meta or Directory.Build.props
APPVER="${APPVER:-${APP_VERSION:-$(grep -m1 -oP '(?<=<Version>)[^<]+' "$ROOT/Directory.Build.props" 2>/dev/null || echo 1.0.0)}}"

# Lanes (environment overrides welcome)
DO_APPIMAGE_ONLY="${DO_APPIMAGE_ONLY:-0}"   # 1 = don't build/publish payloads, just package AppImage
DO_MODERN="${DO_MODERN:-1}"                 # 0/1 (gtk4.1)
DO_LEGACY="${DO_LEGACY:-1}"                 # 0/1 (gtk4.0 jammy)
DO_DEB="${DO_DEB:-1}"
DO_WINDOWS="${DO_WINDOWS:-1}"
DO_VERIFY="${DO_VERIFY:-1}"

# Expected helper scripts
PUBLISH_MODERN="${PUBLISH_MODERN:-$SCRIPT_DIR/publish_modern_docker.sh}"
PUBLISH_LEGACY="${PUBLISH_LEGACY:-$SCRIPT_DIR/publish_legacy_docker.sh}"
MAKE_APPIMAGE="${MAKE_APPIMAGE:-$SCRIPT_DIR/make_appimage.sh}"
PKG_DEB="${PKG_DEB:-$SCRIPT_DIR/package_deb_unified.sh}"
REL_WINDOWS="${REL_WINDOWS:-$SCRIPT_DIR/release_windows.sh}"
VERIFY_APPIMAGE="${VERIFY_APPIMAGE:-$SCRIPT_DIR/verify_appimage.sh}"
VERIFY_DEB="${VERIFY_DEB:-$SCRIPT_DIR/verify_deb.sh}"

# Output dirs
mkdir -p "$ROOT/artifacts/build" "$ROOT/artifacts/packages" \
         "$ROOT/artifacts/packages/appimage" "$ROOT/artifacts/packages/deb" \
         "$ROOT/artifacts/packages/zip" "$ROOT/artifacts/packages/nsis"

# Helpful echo of config
note "Root            : $ROOT"
note "Meta file       : $META"
note "App Version     : $APPVER"
note "Lanes — modern  : $DO_MODERN ; legacy: $DO_LEGACY ; deb: $DO_DEB ; windows: $DO_WINDOWS ; verify: $DO_VERIFY"
note "AppImage only   : $DO_APPIMAGE_ONLY"

# ------------------------------------------------------------
# ----- build lanes -----
# ------------------------------------------------------------
if [[ "${DO_APPIMAGE_ONLY}" -eq 0 ]]; then
  if [[ "${DO_MODERN}" -eq 1 ]]; then
    note "== Building Modern (gtk4.1) =="
    META="$META" APPVER="$APPVER" DOCKERFILE="${DOCKERFILE_MODERN:-}" "$PUBLISH_MODERN"
    echo
  else
    warn "Skipping Modern build (DO_MODERN=0)"
  fi

  if [[ "${DO_LEGACY}" -eq 1 ]]; then
    note "== Building Legacy (gtk4.0 jammy) =="
    # Optionally pin Photino via LEGACY_PNET/LEGACY_PNATIVE env outside
    META="$META" APPVER="$APPVER" DOCKERFILE="${DOCKERFILE_LEGACY:-}" "$PUBLISH_LEGACY"
    echo
  else
    warn "Skipping Legacy build (DO_LEGACY=0)"
  fi
else
  warn "DO_APPIMAGE_ONLY=1 → skipping Modern/Legacy builds"
fi

# ------------------------------------------------------------
# Package: AppImage
# ------------------------------------------------------------
note "==> Package (Linux): AppImage"
if [[ -x "$MAKE_APPIMAGE" ]]; then
  META="$META" APPVER="$APPVER" "$MAKE_APPIMAGE" || warn "AppImage build failed."
else
  warn "make_appimage.sh not found at $MAKE_APPIMAGE — skipping AppImage."
fi

# ------------------------------------------------------------
# Package: DEB
# ------------------------------------------------------------
if [[ "${DO_DEB}" -eq 1 ]]; then
  note "==> Package (Linux): DEB"
  if [[ -x "$PKG_DEB" ]]; then
    META="$META" APPVER="$APPVER" "$PKG_DEB" || warn ".deb build failed."
  else
    warn "package_deb_unified.sh not found at $PKG_DEB — skipping DEB."
  fi
else
  warn "Skipping DEB packaging (DO_DEB=0)"
fi

# ------------------------------------------------------------
# Package: Windows (ZIP + NSIS)
# ------------------------------------------------------------
if [[ "${DO_WINDOWS}" -eq 1 ]]; then
  note "==> Package (Windows): ZIP + NSIS"
  if [[ -x "$REL_WINDOWS" ]]; then
    META="$META" APPVER="$APPVER" "$REL_WINDOWS" || die "Windows packaging failed."
  else
    die "release_windows.sh not found at $REL_WINDOWS"
  fi
else
  warn "Skipping Windows packaging (DO_WINDOWS=0)"
fi

# ------------------------------------------------------------
# Verify artifacts (best effort)
# ------------------------------------------------------------
if [[ "${DO_VERIFY}" -eq 1 ]]; then
  note "==> Verify artifacts"
  if [[ -x "$VERIFY_APPIMAGE" ]]; then
    META="$META" APPVER="$APPVER" "$VERIFY_APPIMAGE" || warn "AppImage verification failed."
  fi
  if [[ -x "$VERIFY_DEB" ]]; then
    META="$META" APPVER="$APPVER" "$VERIFY_DEB" || warn ".deb verification failed."
  fi
else
  warn "Skipping verification (DO_VERIFY=0)"
fi

note "All packaging steps attempted."
