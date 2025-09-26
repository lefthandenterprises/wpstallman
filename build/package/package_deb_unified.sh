#!/usr/bin/env bash
set -euo pipefail

note(){ printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }
warn(){ printf "\033[1;33mWARNING:\033[0m %s\n" "$*"; }
die(){  printf "\n\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 2; }

# ---------- repo root ----------
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ---------- inputs / defaults ----------
RID="${RID:-linux-x64}"

# staged variants (already produced by your stage_variants.sh)
LEG_DIR="${LEG_DIR:-$ROOT/artifacts/dist/WPStallman.GUI-${RID}-glibc2.35}"
MOD_DIR="${MOD_DIR:-$ROOT/artifacts/dist/WPStallman.GUI-${RID}-glibc2.39}"

# launcher publish (must be self-contained as we patched)
LAUNCHER_DIR="${LAUNCHER_DIR:-$ROOT/src/WPStallman.Launcher/bin/Release/net8.0/${RID}/publish}"

APP_NAME="${APP_NAME:-W. P. Stallman}"
APP_ID="${APP_ID:-com.wpstallman.app}"       # used for install root + .desktop Icon
MAIN_LAUNCHER="${MAIN_LAUNCHER:-WPStallman.Launcher}"
MAIN_BIN_NAME="${MAIN_BIN_NAME:-WPStallman.GUI}"  # name of each GUI binary
VERSION="${VERSION:-1.0.0}"
MAINTAINER="${MAINTAINER:-W. P. Stallman <noreply@example.com>}"
DESCRIPTION="${DESCRIPTION:-WordPress plugin project manager (unified launcher + glibc2.35/2.39 variants)}"

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

# icons (prefer modern variant)
ICON_PNG="${ICON_PNG:-$MOD_DIR/wwwroot/img/WPS-256.png}"

# variant-aware output location (unified bucket)
OUTDIR="${OUTDIR:-$ROOT/artifacts/packages/linuxvariants/unified}"
mkdir -p "$OUTDIR"

# build dirs
BUILD="${BUILD:-$ROOT/artifacts/build}"
DEBROOT="$BUILD/debroot-unified"
DEBIAN="$DEBROOT/DEBIAN"
INSTALL_PREFIX="$DEBROOT/usr/lib/$APP_ID"
BIN_LINK_DIR="$DEBROOT/usr/bin"

# .deb filename
SAFE_APP_NAME="$(printf '%s' "$APP_NAME" | tr ' /' '__')"
OUT_DEB="${OUT_DEB:-$OUTDIR/${SAFE_APP_NAME}_${VERSION}_${ARCH}.deb}"

# Optional requirement: 1 = hard fail if Photino.Native.so cannot be pre-copied; 0 = warn & rely on single-file extraction
REQUIRE_PHOTINO_NATIVE="${REQUIRE_PHOTINO_NATIVE:-0}"

# ---------- sanity ----------
[ -d "$LEG_DIR" ] || die "Legacy staged dir missing: $LEG_DIR"
[ -d "$MOD_DIR" ] || die "Modern staged dir missing: $MOD_DIR"
[ -x "$LEG_DIR/$MAIN_BIN_NAME" ] || die "Legacy GUI missing: $LEG_DIR/$MAIN_BIN_NAME"
[ -x "$MOD_DIR/$MAIN_BIN_NAME" ] || die "Modern GUI missing: $MOD_DIR/$MAIN_BIN_NAME"
[ -d "$LAUNCHER_DIR" ] || die "Launcher publish dir missing: $LAUNCHER_DIR"
[ -x "$LAUNCHER_DIR/$MAIN_LAUNCHER" ] || die "Launcher binary missing in publish (ensure SelfContained=true)"

# ---------- clean build root (recover if root-owned) ----------
mkdir -p "$BUILD"
if [ -d "$DEBROOT" ]; then
  rm -rf "$DEBROOT" 2>/dev/null || { note "Escalating to sudo to clean $DEBROOT…"; sudo rm -rf "$DEBROOT"; }
fi
mkdir -p "$INSTALL_PREFIX" "$DEBIAN" "$BIN_LINK_DIR"

# ---------- stage payload ----------
note "Staging launcher"
rsync -a "$LAUNCHER_DIR/." "$INSTALL_PREFIX/"

note "Staging variants"
mkdir -p "$INSTALL_PREFIX/variants/glibc2.35" "$INSTALL_PREFIX/variants/glibc2.39"
rsync -a --delete "$LEG_DIR/." "$INSTALL_PREFIX/variants/glibc2.35/"
rsync -a --delete "$MOD_DIR/." "$INSTALL_PREFIX/variants/glibc2.39/"

# ---------- best-effort: ensure Photino native present (not required for single-file publish) ----------
ensure_photino_native_into() {
  local dest="$1"  # e.g., $INSTALL_PREFIX/variants/glibc2.39 or glibc2.35
  if [[ -f "$dest/libPhotino.Native.so" || -f "$dest/Photino.Native.so" ]]; then
    [[ -f "$dest/libPhotino.Native.so" && ! -e "$dest/Photino.Native.so" ]] && ln -sf libPhotino.Native.so "$dest/Photino.Native.so"
    [[ -f "$dest/Photino.Native.so"    && ! -e "$dest/libPhotino.Native.so" ]] && ln -sf Photino.Native.so "$dest/libPhotino.Native.so"
    return 0
  fi

  local cand=""
  # 1) sibling of publish dir (…/net8.0/linux-x64)
  for name in libPhotino.Native.so Photino.Native.so; do
    [[ -z "$cand" && -f "$dest/../$name" ]] && cand="$dest/../$name"
  done
  # 2) runtimes/linux-x64/native beneath this variant root
  [[ -z "$cand" ]] && cand="$(find "$dest/.." -maxdepth 8 -path '*/runtimes/linux-x64/native/*photino.native*.so' -type f -print -quit 2>/dev/null || true)"
  # 3) NuGet cache fallback
  if [[ -z "$cand" ]]; then
    local NUPKG="${NUGET_PACKAGES:-$HOME/.nuget/packages}"
    cand="$(find "$NUPKG/photino.native" -path '*/runtimes/linux-x64/native/*photino.native*.so' -type f 2>/dev/null | sort -V | tail -n1 || true)"
  fi

  [[ -z "$cand" ]] && return 1

  note "  Photino candidate for $(basename "$dest"): $cand"
  cp -f "$cand" "$dest/libPhotino.Native.so"
  ln -sf libPhotino.Native.so "$dest/Photino.Native.so"
  return 0
}

note "Ensuring Photino native (best-effort) in each variant"
ok1=0; ok2=0
ensure_photino_native_into "$INSTALL_PREFIX/variants/glibc2.35" && ok1=1 || true
ensure_photino_native_into "$INSTALL_PREFIX/variants/glibc2.39" && ok2=1 || true
if [[ $REQUIRE_PHOTINO_NATIVE -eq 1 && ( $ok1 -eq 0 || $ok2 -eq 0 ) ]]; then
  die "Photino native not found for all variants; set REQUIRE_PHOTINO_NATIVE=0 to allow single-file extraction."
fi
if [[ $ok1 -eq 0 || $ok2 -eq 0 ]]; then
  warn "Photino native not pre-copied for some variants; relying on .NET single-file extraction at first launch."
fi

# ---------- wrapper in /usr/bin to run the launcher ----------
WRAP="$BIN_LINK_DIR/wpstallman"
cat > "$WRAP" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
APP_ID="com.wpstallman.app"
BASE="/usr/lib/${APP_ID}"

# Stable cache for .NET single-file extraction
export DOTNET_BUNDLE_EXTRACT_BASE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/WPStallman/dotnet_bundle"

# Some machines are missing ICU; use invariant globalization to avoid runtime failure
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

# Allow native resolution when a variant ships libPhotino.Native.so
export LD_LIBRARY_PATH="$BASE:${LD_LIBRARY_PATH:-}"

exec "$BASE/WPStallman.Launcher" "$@"
EOF
chmod 0755 "$WRAP"

# ---------- .desktop ----------
DESKTOP_FILE="$DEBROOT/usr/share/applications/${APP_ID}.desktop"
mkdir -p "$(dirname "$DESKTOP_FILE")"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Comment=WordPress plugin project manager (unified)
Exec=wpstallman %U
Icon=${APP_ID}
Categories=Development;
Terminal=false
StartupWMClass=WPStallman.GUI
EOF
chmod 0644 "$DESKTOP_FILE" 2>/dev/null || true
chmod 0644 "$DEBROOT/usr/share/applications/${APP_ID}.desktop"

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
elif [[ -f "$MOD_DIR/wwwroot/img/WPS-256.png" ]]; then
  ICON_SRC="$MOD_DIR/wwwroot/img/WPS-256.png"
elif [[ -f "$LEG_DIR/wwwroot/img/WPS-256.png" ]]; then
  ICON_SRC="$LEG_DIR/wwwroot/img/WPS-256.png"
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

# (Optional) postinst to refresh icon cache can be added if you like.

# ---------- build .deb ----------
note "Building unified .deb -> $OUT_DEB"
dpkg-deb --build "$DEBROOT" "$OUT_DEB"
note "Wrote $OUT_DEB"
