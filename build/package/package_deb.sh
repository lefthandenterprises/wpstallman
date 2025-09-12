#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

note(){ printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }
warn(){ printf "\033[1;33mWARNING:\033[0m %s\n" "$*"; }
die(){  printf "\n\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }

# Inputs
: "${VERSION:=1.0.0}"
: "${APP_NAME:=W. P. Stallman}"
: "${APP_ID:=com.wpstallman.app}"
: "${MAINTAINER:=Left Hand Enterprises, LLC <support@example.com>}"
: "${ARCH:=amd64}"

: "${GUI_DIR:=$ROOT/src/WPStallman.GUI/bin/Release/net8.0/linux-x64/publish}"
: "${CLI_DIR:=$ROOT/src/WPStallman.CLI/bin/Release/net8.0/linux-x64/publish}"
: "${ICON_PNG:=$ROOT/artifacts/icons/WPS-256.png}"

BUILD="$ROOT/artifacts/build"
OUTDIR="$ROOT/artifacts/packages"
DEB_ROOT="$BUILD/deb"
DEB_NAME="wpstallman_${VERSION}_${ARCH}.deb"

ensure_photino_native() {
  local dest="$DEB_ROOT/usr/lib/$APP_ID"
  [[ -f "$dest/libPhotino.Native.so" || -f "$dest/Photino.Native.so" ]] && {
    [[ -f "$dest/libPhotino.Native.so" && ! -e "$dest/Photino.Native.so" ]] && ln -sf libPhotino.Native.so "$dest/Photino.Native.so"
    [[ -f "$dest/Photino.Native.so"    && ! -e "$dest/libPhotino.Native.so" ]] && ln -sf Photino.Native.so "$dest/libPhotino.Native.so"
    return 0
  }

  note "Locating Photino native for .deb…"
  local cand=""
  if [[ -n "${GUI_DIR:-}" ]]; then
    for name in libPhotino.Native.so Photino.Native.so; do
      [[ -z "$cand" && -f "$GUI_DIR/../$name" ]] && cand="$GUI_DIR/../$name"
    done
  fi
  [[ -z "$cand" ]] && cand="$(find "$dest" -maxdepth 6 -type f -iname '*photino.native*.so' -print -quit 2>/dev/null || true)"
  [[ -z "$cand" && -n "${GUI_DIR:-}" ]] && cand="$(find "$GUI_DIR/.." -maxdepth 8 -path '*/runtimes/linux-x64/native/*photino.native*.so' -type f -print -quit 2>/dev/null || true)"
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



rm -rf "$DEB_ROOT"
mkdir -p "$DEB_ROOT/DEBIAN" \
         "$DEB_ROOT/usr/lib/$APP_ID" \
         "$DEB_ROOT/usr/bin" \
         "$DEB_ROOT/usr/share/applications" \
         "$DEB_ROOT/usr/share/icons/hicolor/64x64/apps" \
         "$DEB_ROOT/usr/share/icons/hicolor/128x128/apps" \
         "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps"

# 1) Payload
note "Staging payload for .deb"
rsync -a "$GUI_DIR/." "$DEB_ROOT/usr/lib/$APP_ID/"
rsync -a "$CLI_DIR/." "$DEB_ROOT/usr/lib/$APP_ID/" || true

# Sanity (+ self-heal)
[[ -x "$DEB_ROOT/usr/lib/$APP_ID/WPStallman.GUI" ]] || die "Missing GUI binary"
if ! ensure_photino_native; then
  die "Missing Photino native in .deb payload and NuGet cache fallback failed."
fi


# 2) Wrapper in /usr/bin to set LD_LIBRARY_PATH
cat > "$DEB_ROOT/usr/bin/wpstallman" <<'SH'
#!/usr/bin/env bash
export LD_LIBRARY_PATH="/usr/lib/com.wpstallman.app:${LD_LIBRARY_PATH}"
exec "/usr/lib/com.wpstallman.app/WPStallman.GUI" "$@"
SH
chmod 755 "$DEB_ROOT/usr/bin/wpstallman"

# 3) Desktop entry (Exec points to wrapper)
DESKTOP="$DEB_ROOT/usr/share/applications/${APP_ID}.desktop"
cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Comment=WordPress plugin project manager
Exec=/usr/bin/wpstallman %U
Icon=${APP_ID}
Categories=Development;
Terminal=false
StartupWMClass=WPStallman.GUI
EOF

# 4) Icons (fallback to payload)
ICON_SRC=""
if [[ -n "${ICON_PNG:-}" && -f "$ICON_PNG" ]]; then
  ICON_SRC="$ICON_PNG"
elif [[ -f "$DEB_ROOT/usr/lib/$APP_ID/wwwroot/img/WPS-256.png" ]]; then
  ICON_SRC="$DEB_ROOT/usr/lib/$APP_ID/wwwroot/img/WPS-256.png"
elif [[ -f "$DEB_ROOT/usr/lib/$APP_ID/wwwroot/img/WPS-512.png" ]]; then
  ICON_SRC="$DEB_ROOT/usr/lib/$APP_ID/wwwroot/img/WPS-512.png"
fi
if [[ -n "$ICON_SRC" ]]; then
  install -m644 "$ICON_SRC" "$DEB_ROOT/usr/share/icons/hicolor/64x64/apps/${APP_ID}.png"
  install -m644 "$ICON_SRC" "$DEB_ROOT/usr/share/icons/hicolor/128x128/apps/${APP_ID}.png"
  install -m644 "$ICON_SRC" "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps/${APP_ID}.png"
else
  warn "No icon source found; desktop may show generic icon."
fi

# 5) Control file (deps include either WebKitGTK 4.1 or 4.0)
cat > "$DEB_ROOT/DEBIAN/control" <<EOF
Package: wpstallman
Version: $VERSION
Section: utils
Priority: optional
Architecture: $ARCH
Maintainer: $MAINTAINER
Description: $APP_NAME (GUI and CLI)
Depends: libgtk-3-0, libnotify4, libgdk-pixbuf-2.0-0, libnss3, libjavascriptcoregtk-4.1-0 | libjavascriptcoregtk-4.0-18, libwebkit2gtk-4.1-0 | libwebkit2gtk-4.0-37
EOF

mkdir -p "$OUTDIR"

# 6) Build .deb
if command -v fpm >/dev/null 2>&1 ; then
  note "Building .deb via fpm"
  fpm -s dir -t deb -n wpstallman -v "$VERSION" -C "$DEB_ROOT" \
    --deb-no-default-config-files --force \
    -p "$OUTDIR/$DEB_NAME" .
else
  note "Building .deb via dpkg-deb"
  rm -f "$OUTDIR/$DEB_NAME" 2>/dev/null || true
  dpkg-deb --build "$DEB_ROOT" "$OUTDIR/$DEB_NAME"
fi

note "Wrote $OUTDIR/$DEB_NAME"
