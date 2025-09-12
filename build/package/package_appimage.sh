#!/usr/bin/env bash
set -euo pipefail

note(){ printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }
warn(){ printf "\033[1;33mWARNING:\033[0m %s\n" "$*"; }
die(){  printf "\n\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Inputs (override via env)
: "${VERSION:=1.0.0}"
: "${APP_NAME:=W. P. Stallman}"
: "${APP_ID:=com.wpstallman.app}"            # also Desktop Icon= and root ${APP_ID}.png
: "${MAIN_BIN:=WPStallman.GUI}"              # name of GUI binary in publish dir
: "${GUI_DIR:=$ROOT/src/WPStallman.GUI/bin/Release/net8.0/linux-x64/publish}"
: "${CLI_DIR:=$ROOT/src/WPStallman.CLI/bin/Release/net8.0/linux-x64/publish}"
: "${ICON_PNG:=$ROOT/artifacts/icons/WPS-256.png}"

BUILD="$ROOT/artifacts/build"
OUTDIR="$ROOT/artifacts/packages"
APPDIR="$BUILD/AppDir"

ensure_photino_native() {
  local dest="$APPDIR/usr/lib/$APP_ID"
  [[ -f "$dest/libPhotino.Native.so" || -f "$dest/Photino.Native.so" ]] && {
    [[ -f "$dest/libPhotino.Native.so" && ! -e "$dest/Photino.Native.so" ]] && ln -sf libPhotino.Native.so "$dest/Photino.Native.so"
    [[ -f "$dest/Photino.Native.so"    && ! -e "$dest/libPhotino.Native.so" ]] && ln -sf Photino.Native.so "$dest/libPhotino.Native.so"
    return 0
  }

  note "Locating Photino native for AppImage…"
  local cand=""
  # From GUI publish sibling dir (.../net8.0/linux-x64)
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


mkdir -p "$BUILD" "$OUTDIR"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/lib/$APP_ID" "$APPDIR/usr/share/applications" \
         "$APPDIR/usr/share/icons/hicolor/64x64/apps" \
         "$APPDIR/usr/share/icons/hicolor/128x128/apps" \
         "$APPDIR/usr/share/icons/hicolor/256x256/apps"

# 1) Copy payload
note "Staging payload into AppDir"
rsync -a "$GUI_DIR/." "$APPDIR/usr/lib/$APP_ID/"
rsync -a "$CLI_DIR/." "$APPDIR/usr/lib/$APP_ID/" || true

# 2) Sanity checks (+ self-heal for libPhotino.Native.so)
[[ -x "$APPDIR/usr/lib/$APP_ID/$MAIN_BIN" ]] || die "Missing $MAIN_BIN in AppDir"
if ! ensure_photino_native; then
  die "Missing Photino native in AppDir and NuGet cache fallback failed."
fi

# 3) Desktop entry (root so old appimagetool finds it)
DESKTOP="$APPDIR/$APP_ID.desktop"
cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Comment=WordPress plugin project manager
Exec=usr/lib/${APP_ID}/${MAIN_BIN} %U
Icon=${APP_ID}
Categories=Development;
Terminal=false
StartupWMClass=WPStallman.GUI
EOF
note "Desktop written: $DESKTOP"
grep -E '^(Name|Exec|Icon|StartupWMClass)=' "$DESKTOP" | sed 's/^/  /'

# 4) Icons (fallback to payload PNG if ICON_PNG missing)
ICON_SRC=""
if [[ -n "${ICON_PNG:-}" && -f "$ICON_PNG" ]]; then
  ICON_SRC="$ICON_PNG"
elif [[ -f "$APPDIR/usr/lib/$APP_ID/wwwroot/img/WPS-256.png" ]]; then
  ICON_SRC="$APPDIR/usr/lib/$APP_ID/wwwroot/img/WPS-256.png"
elif [[ -f "$APPDIR/usr/lib/$APP_ID/wwwroot/img/WPS-512.png" ]]; then
  ICON_SRC="$APPDIR/usr/lib/$APP_ID/wwwroot/img/WPS-512.png"
fi
if [[ -n "$ICON_SRC" ]]; then
  install -m644 "$ICON_SRC" "$APPDIR/usr/share/icons/hicolor/64x64/apps/${APP_ID}.png"
  install -m644 "$ICON_SRC" "$APPDIR/usr/share/icons/hicolor/128x128/apps/${APP_ID}.png"
  install -m644 "$ICON_SRC" "$APPDIR/usr/share/icons/hicolor/256x256/apps/${APP_ID}.png"
  cp -f "$ICON_SRC" "$APPDIR/${APP_ID}.png" 2>/dev/null || true
else
  warn "No icon source found; AppImage will still build but the desktop may show a generic icon."
fi

# 5) AppRun with LD_LIBRARY_PATH
cat > "$APPDIR/AppRun" <<'EOF'
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "$0")")"
export DOTNET_BUNDLE_EXTRACT_BASE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/WPStallman/dotnet_bundle"
export LD_LIBRARY_PATH="$HERE/usr/lib/com.wpstallman.app:${LD_LIBRARY_PATH}"
exec "$HERE/usr/lib/com.wpstallman.app/WPStallman.GUI" "$@"
EOF
chmod +x "$APPDIR/AppRun"

# 6) Build AppImage
APPIMAGE="$OUTDIR/${APP_NAME// /_}-${VERSION}-x86_64.AppImage"
note "Building AppImage -> $APPIMAGE"
appimagetool "$APPDIR" "$APPIMAGE"
note "Wrote $APPIMAGE"
