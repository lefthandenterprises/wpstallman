#!/usr/bin/env bash
set -euo pipefail

note(){ printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }
warn(){ printf "\033[1;33mWARNING:\033[0m %s\n" "$*"; }
die(){  printf "\n\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 2; }

# ---------- repo root ----------
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ---------- inputs / defaults ----------
RID="${RID:-linux-x64}"
VARIANT="${VARIANT:-glibc2.39}"               # glibc2.35 | glibc2.39 | current

# Debian architecture (prefer dpkg; fallback map)
ARCH="${ARCH:-$(dpkg --print-architecture 2>/dev/null || true)}"
if [ -z "${ARCH:-}" ]; then
  case "$(uname -m)" in
    x86_64) ARCH=amd64 ;;
    aarch64|arm64) ARCH=arm64 ;;
    armv7l|armv7hf|armhf) ARCH=armhf ;;
    i386|i686) ARCH=i386 ;;
    *) ARCH=amd64 ;;
  esac
fi

# Staged input (produced by stage_variants.sh)
GUI_DIR="${GUI_DIR:-$ROOT/artifacts/dist/WPStallman.GUI-${RID}-${VARIANT}}"
CLI_DIR="${CLI_DIR:-$ROOT/src/WPStallman.CLI/bin/Release/net8.0/${RID}/publish}"

# App identity / metadata
APP_NAME="${APP_NAME:-W. P. Stallman}"
APP_ID="${APP_ID:-com.wpstallman.app}"        # used for /usr/lib/<APP_ID> and .desktop Icon
MAIN_BIN="${MAIN_BIN:-WPStallman.GUI}"        # main executable filename in publish dir
VERSION="${VERSION:-1.0.0}"
MAINTAINER="${MAINTAINER:-Patrick Driscoll <patrick@lefthandenterprises.com>}"
DESCRIPTION="${DESCRIPTION:-WordPress plugin project manager}"

# Icons (prefer payload icon)
ICON_PNG="${ICON_PNG:-$GUI_DIR/wwwroot/img/WPS-256.png}"

# Variant-aware output directory for .deb
LINUXVAR_DIR="${LINUXVAR_DIR:-$ROOT/artifacts/packages/linuxvariants/$VARIANT}"
OUTDIR="${OUTDIR:-$LINUXVAR_DIR}"
mkdir -p "$OUTDIR"

# Build temp dirs
BUILD="${BUILD:-$ROOT/artifacts/build}"
DEBROOT="$BUILD/debroot"
DEBIAN="$DEBROOT/DEBIAN"
INSTALL_PREFIX="$DEBROOT/usr/lib/$APP_ID"
BIN_LINK_DIR="$DEBROOT/usr/bin"

# Output .deb filename
SAFE_APP_NAME="$(printf '%s' "$APP_NAME" | tr ' /' '__')"
OUT_DEB="${OUT_DEB:-$OUTDIR/${SAFE_APP_NAME}_${VERSION}_${ARCH}.deb}"

# Optional: 1 = hard fail if Photino.Native.so cannot be pre-copied, 0 = warn & rely on single-file extraction
REQUIRE_PHOTINO_NATIVE="${REQUIRE_PHOTINO_NATIVE:-0}"

# ---------- sanity checks on inputs ----------
[ -d "$GUI_DIR" ] || die "GUI_DIR not found: $GUI_DIR"
[ -x "$GUI_DIR/$MAIN_BIN" ] || die "GUI binary not found: $GUI_DIR/$MAIN_BIN"
[ -f "$GUI_DIR/wwwroot/index.html" ] || die "Missing wwwroot in $GUI_DIR/wwwroot/index.html"

# ---------- clean build root (handle leftover root-owned files gracefully) ----------
mkdir -p "$BUILD"
if [ -d "$DEBROOT" ]; then
  rm -rf "$DEBROOT" 2>/dev/null || { note "Escalating to sudo to clean $DEBROOT…"; sudo rm -rf "$DEBROOT"; }
fi
mkdir -p "$INSTALL_PREFIX" "$DEBIAN" "$BIN_LINK_DIR"

# ---------- stage payload ----------
note "Staging payload into deb tree"
rsync -a "$GUI_DIR/." "$INSTALL_PREFIX/"
# CLI optional
[ -d "$CLI_DIR" ] && rsync -a "$CLI_DIR/." "$INSTALL_PREFIX/" || true

# Ensure basic presence
[ -x "$INSTALL_PREFIX/$MAIN_BIN" ] || die "Missing $MAIN_BIN in $INSTALL_PREFIX"
[ -f "$INSTALL_PREFIX/wwwroot/index.html" ] || die "Missing wwwroot/index.html in $INSTALL_PREFIX"

# ---------- best-effort: ensure Photino native present (not required for single-file publish) ----------
ensure_photino_native() {
  local dest="$INSTALL_PREFIX"
  # if present, ensure both names exist for good measure
  if [[ -f "$dest/libPhotino.Native.so" || -f "$dest/Photino.Native.so" ]]; then
    [[ -f "$dest/libPhotino.Native.so" && ! -e "$dest/Photino.Native.so" ]] && ln -sf libPhotino.Native.so "$dest/Photino.Native.so"
    [[ -f "$dest/Photino.Native.so"    && ! -e "$dest/libPhotino.Native.so" ]] && ln -sf Photino.Native.so "$dest/libPhotino.Native.so"
    return 0
  fi

  note "Locating Photino native for .deb…"
  local cand=""
  # 1) Sibling of publish dir (…/net8.0/linux-x64)
  for name in libPhotino.Native.so Photino.Native.so; do
    [[ -z "$cand" && -f "$GUI_DIR/../$name" ]] && cand="$GUI_DIR/../$name"
  done
  # 2) runtimes/linux-x64/native under publish root
  [[ -z "$cand" ]] && cand="$(find "$GUI_DIR/.." -maxdepth 8 -path '*/runtimes/linux-x64/native/*photino.native*.so' -type f -print -quit 2>/dev/null || true)"
  # 3) NuGet cache fallback
  if [[ -z "$cand" ]]; then
    local NUPKG="${NUGET_PACKAGES:-$HOME/.nuget/packages}"
    cand="$(find "$NUPKG/photino.native" -path '*/runtimes/linux-x64/native/*photino.native*.so' -type f 2>/dev/null | sort -V | tail -n1 || true)"
  fi

  [[ -z "$cand" ]] && return 1

  note "  candidate: $cand"
  cp -f "$cand" "$dest/libPhotino.Native.so"
  ln -sf libPhotino.Native.so "$dest/Photino.Native.so"
  return 0
}

if ! ensure_photino_native; then
  if [[ "$REQUIRE_PHOTINO_NATIVE" == "1" ]]; then
    die "Photino native not found; set REQUIRE_PHOTINO_NATIVE=0 to allow relying on single-file extraction."
  else
    warn "Photino native not pre-copied; will rely on .NET single-file runtime extraction at first launch."
  fi
fi

# ---------- wrapper in /usr/bin to set env and launch ----------
WRAP="$BIN_LINK_DIR/wpstallman"
cat > "$WRAP" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
APP_ID="com.wpstallman.app"
HERE="/usr/lib/${APP_ID}"
# Keep dotnet single-file extraction out of /tmp and stable between runs
export DOTNET_BUNDLE_EXTRACT_BASE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/WPStallman/dotnet_bundle"
# Allow resolver to find Photino.Native.so if pre-copied
export LD_LIBRARY_PATH="$HERE:${LD_LIBRARY_PATH:-}"
exec "$HERE/WPStallman.GUI" "$@"
EOF
chmod 0755 "$WRAP"

# ---------- .desktop entry ----------
DESKTOP_FILE="$DEBROOT/usr/share/applications/${APP_ID}.desktop"
mkdir -p "$(dirname "$DESKTOP_FILE")"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Comment=WordPress plugin project manager
Exec=wpstallman %U
Icon=${APP_ID}
Categories=Development;
Terminal=false
StartupWMClass=WPStallman.GUI
EOF
chmod 0644 "$DESKTOP_FILE"

# ---------- icons ----------
install_icon() { # size, src
  local size="$1"; local src="$2"
  local dir="$DEBROOT/usr/share/icons/hicolor/${size}x${size}/apps"
  mkdir -p "$dir"
  install -m644 "$src" "$dir/${APP_ID}.png"
}

ICON_SRC=""
if [[ -f "$ICON_PNG" ]]; then
  ICON_SRC="$ICON_PNG"
elif [[ -f "$INSTALL_PREFIX/wwwroot/img/WPS-256.png" ]]; then
  ICON_SRC="$INSTALL_PREFIX/wwwroot/img/WPS-256.png"
elif [[ -f "$INSTALL_PREFIX/wwwroot/img/WPS-512.png" ]]; then
  ICON_SRC="$INSTALL_PREFIX/wwwroot/img/WPS-512.png"
fi

if [[ -n "$ICON_SRC" ]]; then
  install_icon 64  "$ICON_SRC"
  install_icon 128 "$ICON_SRC"
  install_icon 256 "$ICON_SRC"
else
  warn "No icon source found; desktop may show a generic icon."
fi

# ---------- control metadata ----------
mkdir -p "$DEBIAN"
cat > "$DEBIAN/control" <<EOF
Package: wpstallman-gui
Version: $VERSION
Section: utils
Priority: optional
Architecture: $ARCH
Maintainer: $MAINTAINER
Description: $DESCRIPTION
EOF
chmod 0644 "$DEBIAN/control"

# (Optional) postinst/postrm to update icon cache (not strictly required)
# cat > "$DEBIAN/postinst" <<'EOF'
# #!/bin/sh
# set -e
# command -v update-icon-caches >/dev/null 2>&1 && update-icon-caches /usr/share/icons/hicolor || true
# exit 0
# EOF
# chmod 0755 "$DEBIAN/postinst"

# ---------- build .deb ----------
note "Building .deb -> $OUT_DEB"
dpkg-deb --build "$DEBROOT" "$OUT_DEB"
note "Wrote $OUT_DEB"
