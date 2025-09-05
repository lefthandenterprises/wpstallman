#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

: "${VERSION:=1.0.0}"
: "${APP_NAME:=W. P. Stallman}"
: "${APP_ID:=com.wpstallman.app}"

# Linux GUI publish dir (already built)
GUI_DIR="${GUI_DIR:-$ROOT/src/WPStallman.GUI/bin/Release/net8.0/linux-x64/publish}"

# Icon input:
#   1) explicit env ICON_PNG, or
#   2) artifacts/icons/WPS-256.png (if present), or
#   3) artifacts/icons/wpstallman.png (your current file)
ICON_PNG="${ICON_PNG:-}"
if [ -z "${ICON_PNG}" ]; then
  if   [ -f "$ROOT/artifacts/icons/WPS-256.png" ]; then ICON_PNG="$ROOT/artifacts/icons/WPS-256.png"
  elif [ -f "$ROOT/artifacts/icons/hicolor/256x256/apps/wpstallman.png" ]; then ICON_PNG="$ROOT/artifacts/icons/hicolor/256x256/apps/wpstallman.png"
  fi
fi

OUTDIR="$ROOT/artifacts/packages"
APPDIR="$(mktemp -d)/AppDir"

note(){ printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }
die(){  printf "\n\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }

command -v appimagetool >/dev/null || die "appimagetool not found. See https://github.com/AppImage/AppImageKit."
[ -d "$GUI_DIR" ] || die "GUI_DIR not found: $GUI_DIR"
[ -n "$ICON_PNG" ] || die "ICON_PNG not set and no fallback icon found in artifacts/icons/. Set ICON_PNG=/path/to/icon.png"
[ -f "$ICON_PNG" ] || die "ICON_PNG not found: $ICON_PNG"

mkdir -p "$OUTDIR" \
         "$APPDIR/usr/bin" \
         "$APPDIR/usr/share/applications" \
         "$APPDIR/usr/share/icons/hicolor/256x256/apps"

# 1) Copy app payload (Linux GUI)
cp -a "$GUI_DIR/." "$APPDIR/usr/bin/"

# Ensure your Linux GUI binary is executable (rename if different)
if [ -f "$APPDIR/usr/bin/WPStallman.GUI" ]; then
  chmod +x "$APPDIR/usr/bin/WPStallman.GUI"
fi

# 2) Desktop entry (Icon must match ${APP_ID}, no extension)
cat > "$APPDIR/${APP_ID}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Exec=wpstallman-gui
Icon=${APP_ID}
Terminal=false
Categories=Utility;
EOF

# 3) Launcher that runs your GUI binary (rename target if needed)
cat > "$APPDIR/usr/bin/wpstallman-gui" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/WPStallman.GUI" "$@"
EOF
chmod +x "$APPDIR/usr/bin/wpstallman-gui"

# 4) Prepare icon: ensure 256x256, copy to both standard icon path AND top-level as ${APP_ID}.png
ICON_256="$APPDIR/usr/share/icons/hicolor/256x256/apps/${APP_ID}.png"
ICON_TOP="$APPDIR/${APP_ID}.png"

maybe_resize() {
  local src="$1" dst="$2"
  # If ImageMagick present, ensure 256x256; else copy as-is
  if command -v convert >/dev/null 2>&1; then
    convert "$src" -resize 256x256\! "$dst"
  else
    cp -a "$src" "$dst"
  fi
}

maybe_resize "$ICON_PNG" "$ICON_256"
cp -a "$ICON_256" "$ICON_TOP"

# 5) AppRun
cat > "$APPDIR/AppRun" <<'EOF'
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "$0")")"
export PATH="$HERE/usr/bin:$PATH"
exec "$HERE/usr/bin/wpstallman-gui" "$@"
EOF
chmod +x "$APPDIR/AppRun"

# 6) Build AppImage
APPIMAGE="$OUTDIR/${APP_NAME// /_}-${VERSION}-x86_64.AppImage"
note "Building AppImage -> $APPIMAGE"
appimagetool "$APPDIR" "$APPIMAGE"
note "Wrote $APPIMAGE"
