#!/usr/bin/env bash
set -euo pipefail

# Repo root
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Inputs (override via env if needed)
: "${VERSION:=1.0.0}"
: "${APP_NAME:=W. P. Stallman}"
: "${APP_ID:=com.wpstallman.app}"                # used for desktop id, binary link, etc.
: "${MAINTAINER:=Left Hand Enterprises, LLC <support@example.com>}"
: "${ARCH:=amd64}"

# Publish dirs (already built)
GUI_DIR="${GUI_DIR:-$ROOT/src/WPStallman.GUI/bin/Release/net8.0-windows/win-x64/publish}"
CLI_DIR="${CLI_DIR:-$ROOT/src/WPStallman.CLI/bin/Release/net8.0/linux-x64/publish}"

OUTDIR="$ROOT/artifacts/packages"
PKGROOT="$(mktemp -d)"
DEBROOT="$PKGROOT/${APP_ID}_${VERSION}_${ARCH}"
INSTALL_PREFIX="/opt/${APP_ID}"

note(){ printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }
die(){  printf "\n\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }

command -v dpkg-deb >/dev/null || die "dpkg-deb not found (sudo apt-get install dpkg-dev)."
[ -d "$CLI_DIR" ] || die "CLI_DIR not found: $CLI_DIR"

mkdir -p "$DEBROOT/DEBIAN" "$DEBROOT$INSTALL_PREFIX/GUI" "$DEBROOT$INSTALL_PREFIX/CLI" "$OUTDIR"

# Copy payloads
# On Linux we ship the CLI build; GUI on Linux is optional (Photino GTK build if you have it).
if [ -d "$GUI_DIR" ] && [ -f "$GUI_DIR/WPStallman.GUI.exe" ]; then
  cp -a "$GUI_DIR/." "$DEBROOT$INSTALL_PREFIX/GUI/"
fi
cp -a "$CLI_DIR/." "$DEBROOT$INSTALL_PREFIX/CLI/"

# Icon detection (same as AppImage)
ICON_PNG="${ICON_PNG:-}"
if [ -z "${ICON_PNG}" ]; then
  if   [ -f "$ROOT/artifacts/icons/WPS-256.png" ]; then ICON_PNG="$ROOT/artifacts/icons/WPS-256.png"
  elif [ -f "$ROOT/artifacts/icons/hicolor/256x256/apps/wpstallman.png" ]; then ICON_PNG="$ROOT/artifacts/icons/hicolor/256x256/apps/wpstallman.png"
  fi
fi

# Desktop + icon
DESKTOP_DIR="$DEBROOT/usr/share/applications"
ICON_DIR="$DEBROOT/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$DESKTOP_DIR" "$ICON_DIR"

cat > "$DESKTOP_DIR/${APP_ID}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Exec=$INSTALL_PREFIX/GUI/WPStallman.GUI
Icon=${APP_ID}
Terminal=false
Categories=Utility;
EOF

if [ -n "${ICON_PNG}" ] && [ -f "${ICON_PNG}" ]; then
  install -m 0644 "${ICON_PNG}" "${ICON_DIR}/${APP_ID}.png"
fi


# Desktop entry + icon (optional)
DESKTOP_DIR="$DEBROOT/usr/share/applications"
ICON_DIR="$DEBROOT/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$DESKTOP_DIR" "$ICON_DIR"

cat > "$DESKTOP_DIR/${APP_ID}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Exec=$INSTALL_PREFIX/GUI/WPStallman.GUI.exe
Icon=${APP_ID}
Terminal=false
Categories=Utility;
EOF

# If you have a PNG icon at artifacts/icons/WPS-256.png
if [ -f "$ROOT/artifacts/icons/WPS-256.png" ]; then
  install -m 0644 "$ROOT/artifacts/icons/WPS-256.png" "$ICON_DIR/${APP_ID}.png"
fi

# Control file
cat > "$DEBROOT/DEBIAN/control" <<EOF
Package: ${APP_ID}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Maintainer: ${MAINTAINER}
Description: ${APP_NAME}
 ${APP_NAME} packaged for Debian/Ubuntu.
EOF

# Postinst: create convenient symlink for CLI
mkdir -p "$DEBROOT/DEBIAN"
cat > "$DEBROOT/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
ln -sf /opt/com.wpstallman.app/CLI/WPStallman.CLI /usr/local/bin/wpstallman-cli || true
exit 0
EOF
chmod 0755 "$DEBROOT/DEBIAN/postinst"

# Build .deb
note "Building .deb"
DEB="$OUTDIR/${APP_ID}_${VERSION}_${ARCH}.deb"
dpkg-deb --build "$DEBROOT" "$DEB"
note "Wrote $DEB"

# Cleanup tmp
rm -rf "$PKGROOT"
