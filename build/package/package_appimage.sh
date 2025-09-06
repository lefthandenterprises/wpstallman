#!/usr/bin/env bash
set -euo pipefail

# ---------- helpers FIRST (so they're available everywhere) ----------
note(){ printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }
die(){  printf "\n\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }

# ---------- repo paths ----------
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ---------- inputs (override via env) ----------
: "${VERSION:=1.0.0}"
: "${APP_NAME:=W. P. Stallman}"
: "${APP_ID:=com.wpstallman.app}"            # must match Desktop Entry Icon and top-level ${APP_ID}.png
: "${MAIN_BIN:=WPStallman.GUI}"              # name of your Linux GUI binary inside publish dir

# Linux GUI publish dir (already built)
GUI_DIR="${GUI_DIR:-$ROOT/src/WPStallman.GUI/bin/Release/net8.0/linux-x64/publish}"

# Icon input: explicit ICON_PNG or fallbacks
ICON_PNG="${ICON_PNG:-}"
if [ -z "$ICON_PNG" ]; then
  if   [ -f "$ROOT/artifacts/icons/WPS-256.png" ]; then ICON_PNG="$ROOT/artifacts/icons/WPS-256.png"
  elif [ -f "$ROOT/artifacts/icons/hicolor/256x256/apps/wpstallman.png" ]; then ICON_PNG="$ROOT/artifacts/icons/hicolor/256x256/apps/wpstallman.png"
  fi
fi

# ---------- tool checks ----------
command -v appimagetool >/dev/null || die "appimagetool not found. Install AppImageKit (see github.com/AppImage/AppImageKit)."

# ---------- sanity checks ----------
[ -d "$GUI_DIR" ] || die "GUI_DIR not found: $GUI_DIR"
[ -n "$ICON_PNG" ] || die "ICON_PNG not set and no fallback icon found."
[ -f "$ICON_PNG" ] || die "ICON_PNG not found: $ICON_PNG"

# ---------- prepare AppDir ----------
OUTDIR="$ROOT/artifacts/packages"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT
APPDIR="$TMPROOT/AppDir"

mkdir -p "$OUTDIR" \
         "$APPDIR/usr/bin" \
         "$APPDIR/usr/share/applications" \
         "$APPDIR/usr/share/icons/hicolor/256x256/apps"

# 1) copy app payload
cp -a "$GUI_DIR/." "$APPDIR/usr/bin/"

# Add this section after the "1) copy app payload" section
# 1b) copy wwwroot
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WWWROOT_SOURCE="${WWWROOT_SOURCE:-$REPO_ROOT/src/WPStallman.GUI/wwwroot}"

if [ -d "$WWWROOT_SOURCE" ]; then
  mkdir -p "$APPDIR/usr/bin/wwwroot"
  cp -a "$WWWROOT_SOURCE/." "$APPDIR/usr/bin/wwwroot/"
  note "Copied wwwroot from $WWWROOT_SOURCE to $APPDIR/usr/bin/wwwroot"
else
  die "wwwroot directory not found at $WWWROOT_SOURCE"
fi



# ensure main binary is executable
if [ -f "$APPDIR/usr/bin/$MAIN_BIN" ]; then
  chmod +x "$APPDIR/usr/bin/$MAIN_BIN"
else
  die "Expected main binary not found: $APPDIR/usr/bin/$MAIN_BIN (set MAIN_BIN if different)"
fi

# 2) desktop entry (Icon must be ${APP_ID}, no extension)
cat > "$APPDIR/${APP_ID}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Exec=wpstallman-gui
Icon=${APP_ID}
Terminal=false
Categories=Utility;
EOF

# 3) launcher script
cat > "$APPDIR/usr/bin/wpstallman-gui" <<EOF
#!/usr/bin/env bash
set -euo pipefail
HERE="\$(cd "\$(dirname "\$0")" && pwd)"
exec "\$HERE/$MAIN_BIN" "\$@"
EOF
chmod +x "$APPDIR/usr/bin/wpstallman-gui"

# 4) icons — copy/resize to hicolor and top-level as ${APP_ID}.png
ICON_256="$APPDIR/usr/share/icons/hicolor/256x256/apps/${APP_ID}.png"
ICON_TOP="$APPDIR/${APP_ID}.png"
if command -v convert >/dev/null 2>&1; then
  convert "$ICON_PNG" -resize 256x256\! "$ICON_256"
else
  cp -a "$ICON_PNG" "$ICON_256"
fi
cp -a "$ICON_256" "$ICON_TOP"

# 5) AppRun
cat > "$APPDIR/AppRun" <<'EOF'
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "$0")")"
export PATH="$HERE/usr/bin:$PATH"
exec "$HERE/usr/bin/wpstallman-gui" "$@"
EOF
chmod +x "$APPDIR/AppRun"

# 6) build AppImage
APPIMAGE="$OUTDIR/${APP_NAME// /_}-${VERSION}-x86_64.AppImage"
note "Building AppImage -> $APPIMAGE"
appimagetool "$APPDIR" "$APPIMAGE"
note "Wrote $APPIMAGE"
