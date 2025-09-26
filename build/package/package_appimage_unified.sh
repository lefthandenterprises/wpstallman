#!/usr/bin/env bash
set -euo pipefail

note(){ printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }
warn(){ printf "\033[1;33mWARNING:\033[0m %s\n" "$*"; }
die(){  printf "\n\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 2; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ----- inputs -----
RID="${RID:-linux-x64}"

LEG_DIR="${LEG_DIR:-$ROOT/artifacts/dist/WPStallman.GUI-${RID}-glibc2.35}"
MOD_DIR="${MOD_DIR:-$ROOT/artifacts/dist/WPStallman.GUI-${RID}-glibc2.39}"

LAUNCHER_DIR="${LAUNCHER_DIR:-$ROOT/src/WPStallman.Launcher/bin/Release/net8.0/${RID}/publish}"

APP_NAME="${APP_NAME:-W. P. Stallman}"
APP_ID="${APP_ID:-com.wpstallman.app}"
VERSION="${VERSION:-1.0.0}"
ARCH="${ARCH:-$(uname -m)}"

ICON_PNG="${ICON_PNG:-$MOD_DIR/wwwroot/img/WPS-256.png}"

OUTBASE="${OUTBASE:-$ROOT/artifacts/packages/linuxvariants/unified}"
OUTDIR="$OUTBASE"
mkdir -p "$OUTDIR"

SAFE_NAME="$(printf '%s' "$APP_NAME" | tr ' /' '__')"
OUT_APPIMAGE="${OUT_APPIMAGE:-$OUTDIR/${SAFE_NAME}_${VERSION}_${ARCH}.AppImage}"

BUILD="${BUILD:-$ROOT/artifacts/build}"
APPDIR="$BUILD/AppDirUnified"

# sanity
[ -d "$LEG_DIR" ] || die "Legacy staged dir missing: $LEG_DIR"
[ -d "$MOD_DIR" ] || die "Modern staged dir missing: $MOD_DIR"
[ -x "$LEG_DIR/WPStallman.GUI" ] || die "Legacy GUI missing: $LEG_DIR/WPStallman.GUI"
[ -x "$MOD_DIR/WPStallman.GUI" ] || die "Modern GUI missing: $MOD_DIR/WPStallman.GUI"
[ -d "$LAUNCHER_DIR" ] || die "Launcher publish dir missing: $LAUNCHER_DIR"
[ -x "$LAUNCHER_DIR/WPStallman.Launcher" ] || die "Launcher binary missing in publish (ensure SelfContained=true)"

# clean build dir (recover if root-owned)
if [ -d "$APPDIR" ]; then
  rm -rf "$APPDIR" 2>/dev/null || { note "Escalating to sudo to clean $APPDIR…"; sudo rm -rf "$APPDIR"; }
fi
mkdir -p \
  "$APPDIR/usr/lib/$APP_ID" \
  "$APPDIR/usr/lib/$APP_ID/variants/glibc2.35" \
  "$APPDIR/usr/lib/$APP_ID/variants/glibc2.39" \
  "$APPDIR/usr/share/applications" \
  "$APPDIR/usr/share/icons/hicolor/64x64/apps" \
  "$APPDIR/usr/share/icons/hicolor/128x128/apps" \
  "$APPDIR/usr/share/icons/hicolor/256x256/apps"

# 1) copy launcher
note "Copying launcher"
rsync -a "$LAUNCHER_DIR/." "$APPDIR/usr/lib/$APP_ID/"

# 2) copy variants
note "Copying variants"
rsync -a --delete "$LEG_DIR/." "$APPDIR/usr/lib/$APP_ID/variants/glibc2.35/"
rsync -a --delete "$MOD_DIR/." "$APPDIR/usr/lib/$APP_ID/variants/glibc2.39/"

# 3) desktop file (points to Launcher via AppRun)
DESKTOP="$APPDIR/$APP_ID.desktop"
cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Comment=WordPress plugin project manager (unified)
Exec=usr/lib/${APP_ID}/WPStallman.Launcher %U
Icon=${APP_ID}
Categories=Development;
Terminal=false
StartupWMClass=WPStallman.GUI
EOF
install -m644 "$DESKTOP" "$APPDIR/usr/share/applications/${APP_ID}.desktop"

# 4) icons
ICON_SRC=""
if [[ -f "$ICON_PNG" ]]; then
  ICON_SRC="$ICON_PNG"
elif [[ -f "$MOD_DIR/wwwroot/img/WPS-256.png" ]]; then
  ICON_SRC="$MOD_DIR/wwwroot/img/WPS-256.png"
fi
if [[ -n "$ICON_SRC" ]]; then
  install -m644 "$ICON_SRC" "$APPDIR/usr/share/icons/hicolor/64x64/apps/${APP_ID}.png"
  install -m644 "$ICON_SRC" "$APPDIR/usr/share/icons/hicolor/128x128/apps/${APP_ID}.png"
  install -m644 "$ICON_SRC" "$APPDIR/usr/share/icons/hicolor/256x256/apps/${APP_ID}.png"
  cp -f "$ICON_SRC" "$APPDIR/${APP_ID}.png" 2>/dev/null || true
else
  warn "No icon source found"
fi

# 5) AppRun -> runs Launcher, sets env for self-contained & ICU-lite
cat > "$APPDIR/AppRun" <<'EOF'
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "$0")")"
APP_ID="com.wpstallman.app"

# Keep .NET single-file extraction cache stable between runs
export DOTNET_BUNDLE_EXTRACT_BASE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/WPStallman/dotnet_bundle"

# Some distros lack ICU; use invariant globalization rather than failing hard
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

# Let native loader find libs sitting next to whichever variant the launcher picks
export LD_LIBRARY_PATH="$HERE/usr/lib/${APP_ID}:${LD_LIBRARY_PATH:-}"

exec "$HERE/usr/lib/${APP_ID}/WPStallman.Launcher" "$@"
EOF
chmod +x "$APPDIR/AppRun"

# 6) appimagetool bootstrap & build
APPTOOLS_DIR="${APPTOOLS_DIR:-$ROOT/build/tools}"
APPIMAGETOOL="${APPIMAGETOOL:-appimagetool}"
if ! command -v "$APPIMAGETOOL" >/dev/null 2>&1; then
  mkdir -p "$APPTOOLS_DIR"
  APPIMAGETOOL="$APPTOOLS_DIR/appimagetool-x86_64.AppImage"
  if [[ ! -x "$APPIMAGETOOL" ]]; then
    note "Bootstrapping appimagetool -> $APPIMAGETOOL"
    curl -fsSL -o "$APPIMAGETOOL" \
      https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
    chmod +x "$APPIMAGETOOL"
  fi
fi

note "Building Unified AppImage -> $OUT_APPIMAGE"
APPIMAGE_EXTRACT_AND_RUN=1 "$APPIMAGETOOL" "$APPDIR" "$OUT_APPIMAGE"
note "Wrote $OUT_APPIMAGE"

# 7) copy debug runner next to the unified AppImage
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
DEBUG_RUNNER_SRC="$SCRIPT_DIR/run-wpst-debug.sh"
if [[ -f "$DEBUG_RUNNER_SRC" ]]; then
  cp -f "$DEBUG_RUNNER_SRC" "$OUTDIR/run-wpst-debug.sh"
  chmod +x "$OUTDIR/run-wpst-debug.sh"
  note "Debug runner: $OUTDIR/run-wpst-debug.sh"
else
  warn "No debug runner at $DEBUG_RUNNER_SRC; skipping copy."
fi
