#!/usr/bin/env bash
# ============================================================
# W. P. Stallman — Cross-Platform Packaging from Linux (net8)
# Publishes GUI + CLI (self-contained) and packages win/deb/appimage/mac
# ============================================================
set -euo pipefail

# ---------- Resolve repo root ----------
SCRIPT_DIR="$(cd -- "$(dirname "$0")" >/dev/null 2>&1 && pwd -P)"
# Try git root; otherwise climb up from build/package to repo root
if git -C "$SCRIPT_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
  REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
else
  for CAND in "$SCRIPT_DIR/../.." "$SCRIPT_DIR/.." "$SCRIPT_DIR"; do
    if [[ -d "$CAND/src" ]] || compgen -G "$CAND/*.sln" > /dev/null; then
      REPO_ROOT="$(cd "$CAND" && pwd -P)"; break
    fi
  done
  REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd -P)}"
fi

# ---------- Config ----------
APP_NAME="${APP_NAME:-W. P. Stallman}"
APP_ID="${APP_ID:-com.wpstallman.app}"
VERSION="${VERSION:-1.0.0}"
OUT="${PUBLISH_DIR:-artifacts}"

# Auto-detect projects
if [[ -f "$REPO_ROOT/src/src/WPStallman.GUI/WPStallman.GUI.csproj" ]]; then
  GUI_CSPROJ="$REPO_ROOT/src/src/WPStallman.GUI/WPStallman.GUI.csproj"
elif [[ -f "$REPO_ROOT/src/WPStallman.GUI/WPStallman.GUI.csproj" ]]; then
  GUI_CSPROJ="$REPO_ROOT/src/WPStallman.GUI/WPStallman.GUI.csproj"
else
  echo "Cannot find WPStallman.GUI.csproj"; exit 1
fi

if [[ -f "$REPO_ROOT/src/src/WPStallman.CLI/WPStallman.CLI.csproj" ]]; then
  CLI_CSPROJ="$REPO_ROOT/src/src/WPStallman.CLI/WPStallman.CLI.csproj"
elif [[ -f "$REPO_ROOT/src/WPStallman.CLI/WPStallman.CLI.csproj" ]]; then
  CLI_CSPROJ="$REPO_ROOT/src/WPStallman.CLI/WPStallman.CLI.csproj"
else
  echo "Cannot find WPStallman.CLI.csproj"; exit 1
fi

# Output folders
BUILD="$REPO_ROOT/$OUT/build"
PKG="$REPO_ROOT/$OUT/packages"
NSIS="$REPO_ROOT/$OUT/nsis"
mkdir -p "$BUILD" "$PKG" "$NSIS"

# Packaging assets
DESKTOP_FILE="${DESKTOP_FILE:-$REPO_ROOT/build/assets/wpstallman.desktop}"
ICON_PNG="${ICON_PNG:-$REPO_ROOT/build/assets/wpstallman.png}"

# Tools
APPIMAGETOOL="${APPIMAGETOOL:-appimagetool}"
MAKENSIS="${MAKENSIS:-makensis}"

# RIDs
RID_WIN="win-x64"
RID_LIN="linux-x64"
RID_OSX_X64="osx-x64"
RID_OSX_ARM="osx-arm64"

# Publish roots (net8.0)
GUI_PUB_BASE="$(dirname "$GUI_CSPROJ")/bin/Release/net8.0"
CLI_PUB_BASE="$(dirname "$CLI_CSPROJ")/bin/Release/net8.0"

GUI_PUB_WIN="$GUI_PUB_BASE/$RID_WIN/publish"
GUI_PUB_LIN="$GUI_PUB_BASE/$RID_LIN/publish"
GUI_PUB_OSX_X64="$GUI_PUB_BASE/$RID_OSX_X64/publish"
GUI_PUB_OSX_ARM="$GUI_PUB_BASE/$RID_OSX_ARM/publish"

CLI_PUB_WIN="$CLI_PUB_BASE/$RID_WIN/publish"
CLI_PUB_LIN="$CLI_PUB_BASE/$RID_LIN/publish"
CLI_PUB_OSX_X64="$CLI_PUB_BASE/$RID_OSX_X64/publish"
CLI_PUB_OSX_ARM="$CLI_PUB_BASE/$RID_OSX_ARM/publish"

# ---------- Helpers ----------
note() { echo -e "\033[1;32m==> $*\033[0m"; }
warn() { echo -e "\033[1;33mWARNING:\033[0m $*"; }
die()  { echo -e "\033[1;31mERROR:\033[0m $*"; exit 1; }

# ---------- Desktop entry helper ----------
create_desktop_entry() {
  # $1 = target root (AppDir or DEB_ROOT)
  # $2 = desktop id (usually $APP_ID)
  # $3 = app name (human readable)
  # $4 = exec path (relative for AppImage; absolute for .deb)
  # $5 = comment/description
  local TARGET="$1"; local DESKID="$2"; local NAME="$3"; local EXEC_PATH="$4"; local COMMENT="${5:-$APP_NAME}"

  mkdir -p "$TARGET/usr/share/applications" \
           "$TARGET/usr/share/icons/hicolor/64x64/apps" \
           "$TARGET/usr/share/icons/hicolor/128x128/apps" \
           "$TARGET/usr/share/icons/hicolor/256x256/apps"

  # Hard-set to the actual WM_CLASS reported by xprop
  local WMCLASS="WPStallman.GUI"

  # Desktop path: root for AppImage; standard path for .deb
  local DESKTOP_PATH
  if [[ "$TARGET" == *"/AppDir" ]]; then
    DESKTOP_PATH="$TARGET/${DESKID}.desktop"
  else
    DESKTOP_PATH="$TARGET/usr/share/applications/${DESKID}.desktop"
  fi

  cat > "$DESKTOP_PATH" <<EOF
[Desktop Entry]
Type=Application
Name=${NAME}
Comment=${COMMENT}
Exec=${EXEC_PATH} %U
Icon=${DESKID}
Categories=Development;
Terminal=false
StartupWMClass=${WMCLASS}
EOF

  # Icon: prefer explicit ICON_PNG; else fall back to payload assets
  local ICON_SRC=""
  if [[ -n "${ICON_PNG:-}" && -f "$ICON_PNG" ]]; then
    ICON_SRC="$ICON_PNG"
  elif [[ -f "$TARGET/usr/lib/$APP_ID/wwwroot/img/WPS-256.png" ]]; then
    ICON_SRC="$TARGET/usr/lib/$APP_ID/wwwroot/img/WPS-256.png"
  elif [[ -f "$TARGET/usr/lib/$APP_ID/wwwroot/img/WPS-512.png" ]]; then
    ICON_SRC="$TARGET/usr/lib/$APP_ID/wwwroot/img/WPS-512.png"
  fi

  if [[ -n "$ICON_SRC" ]]; then
    install -m644 "$ICON_SRC" "$TARGET/usr/share/icons/hicolor/64x64/apps/${DESKID}.png"
    install -m644 "$ICON_SRC" "$TARGET/usr/share/icons/hicolor/128x128/apps/${DESKID}.png"
    install -m644 "$ICON_SRC" "$TARGET/usr/share/icons/hicolor/256x256/apps/${DESKID}.png"
    # Root copy helps older appimagetool builds resolve Icon=${DESKID}
    cp -f "$ICON_SRC" "$TARGET/${DESKID}.png" 2>/dev/null || true
  else
    warn "No icon found; ${DESKID}.png missing at AppDir/ (AppImage may show a generic icon)."
  fi

  # Minimal AppRun if missing (AppImage only)
  if [[ "$TARGET" == *"/AppDir" ]] && [[ ! -x "$TARGET/AppRun" ]]; then
    cat > "$TARGET/AppRun" <<'ARUN'
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "$0")")"
export DOTNET_BUNDLE_EXTRACT_BASE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/WPStallman/dotnet_bundle"
exec "$HERE/USR_EXEC_REL" "$@"
ARUN
    sed -i "s|USR_EXEC_REL|usr/lib/${APP_ID}/WPStallman.GUI|g" "$TARGET/AppRun"
    chmod +x "$TARGET/AppRun"
  fi

  # Log the desktop fields we care about (visible in build output)
  note "Desktop written: $DESKTOP_PATH"
  grep -E '^(Name|Exec|Icon|StartupWMClass)=' "$DESKTOP_PATH" | sed 's/^/  /' || true
  note "StartupWMClass set to: ${WMCLASS}"

  # Validate (non-fatal)
  if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate "$DESKTOP_PATH" || echo "WARNING: desktop-file-validate issues for $DESKTOP_PATH"
  fi
}

# ---------- Build (publish) ----------
build_all() {
  note "Publishing GUI + CLI (self-contained, net8.0)"
  dotnet publish "$GUI_CSPROJ" -c Release -r "$RID_WIN" --self-contained true /p:PublishSingleFile=true
  dotnet publish "$GUI_CSPROJ" -c Release -r "$RID_LIN" --self-contained true /p:PublishSingleFile=true
  dotnet publish "$GUI_CSPROJ" -c Release -r "$RID_OSX_X64" --self-contained true /p:PublishSingleFile=true
  dotnet publish "$GUI_CSPROJ" -c Release -r "$RID_OSX_ARM" --self-contained true /p:PublishSingleFile=true

  dotnet publish "$CLI_CSPROJ" -c Release -r "$RID_WIN" --self-contained true /p:PublishSingleFile=true
  dotnet publish "$CLI_CSPROJ" -c Release -r "$RID_LIN" --self-contained true /p:PublishSingleFile=true
  dotnet publish "$CLI_CSPROJ" -c Release -r "$RID_OSX_X64" --self-contained true /p:PublishSingleFile=true
  dotnet publish "$CLI_CSPROJ" -c Release -r "$RID_OSX_ARM" --self-contained true /p:PublishSingleFile=true
}

# ---------- Windows (NSIS) ----------
win_nsis() {
  if ! command -v "$MAKENSIS" >/dev/null 2>&1 ; then
    warn "makensis not found; skipping Windows NSIS."
    return
  fi

  note "Building Windows NSIS installer"
  NSI="$REPO_ROOT/build/package/installer.nsi"
  if [[ ! -f "$NSI" ]]; then
    warn "Missing $NSI; skipping NSIS."
    return
  fi

  mkdir -p "$NSIS"
"$MAKENSIS" \
  -DVERSION="$VERSION" \
  -DOUTDIR="$PKG" \
  -DAPP_NAME="$APP_NAME" \
  -DAPP_ID="$APP_ID" \
  -DGUI_PAYLOAD="$GUI_PUB_WIN" \
  -DCLI_PAYLOAD="$CLI_PUB_WIN" \
  "$NSI" || warn "NSIS warnings above"

  note "NSIS: $PKG/WPStallman-$VERSION-setup-win-x64.exe"
}

# ---------- Linux .deb (GUI + CLI) ----------
linux_deb() {
  note "Building Linux .deb (GUI + CLI)"
  local DEB_ROOT="$BUILD/deb"
  local DEB_NAME="wpstallman_${VERSION}_amd64"
  rm -rf "$DEB_ROOT"
  mkdir -p "$DEB_ROOT/DEBIAN" "$DEB_ROOT/usr/lib/$APP_ID" \
           "$DEB_ROOT/usr/share/applications" "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps"

  rsync -a "$GUI_PUB_LIN/." "$DEB_ROOT/usr/lib/$APP_ID/"
  rsync -a "$CLI_PUB_LIN/." "$DEB_ROOT/usr/lib/$APP_ID/"

  # Ensure default desktop/icon within DEB staging if not provided
  create_desktop_entry "$DEB_ROOT" "$APP_ID" "$APP_NAME" "/usr/lib/$APP_ID/WPStallman.GUI" "WordPress plugin project manager"

  # Allow explicit desktop/icon override for .deb (kept in standard paths)
  [[ -f "$DESKTOP_FILE" ]] && install -m644 "$DESKTOP_FILE" "$DEB_ROOT/usr/share/applications/$APP_ID.desktop"
  [[ -f "$ICON_PNG"   ]] && install -m644 "$ICON_PNG"     "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps/$APP_ID.png"

  cat > "$DEB_ROOT/DEBIAN/control" <<EOF
Package: wpstallman
Version: $VERSION
Section: utils
Priority: optional
Architecture: amd64
Maintainer: WPStallman <support@example.com>
Description: $APP_NAME (GUI and CLI)
Depends: libgtk-3-0, libwebkit2gtk-4.0-37 | libwebkit2gtk-4.1-0, libjavascriptcoregtk-4.0-18, libnotify4, libgdk-pixbuf-2.0-0
EOF

  if command -v fpm >/dev/null 2>&1 ; then
    fpm -s dir -t deb -n wpstallman -v "$VERSION" -C "$DEB_ROOT" \
      --deb-no-default-config-files \
      --force \
      -p "$PKG/${DEB_NAME}.deb" .
  else
    rm -f "$PKG/${DEB_NAME}.deb" 2>/dev/null || true
    dpkg-deb --build "$DEB_ROOT" "$PKG/${DEB_NAME}.deb"
  fi
  note "DEB: $PKG/${DEB_NAME}.deb"
}

# ---------- Linux AppImage (includes CLI) ----------
linux_appimage() {
  if ! command -v "$APPIMAGETOOL" >/dev/null 2>&1 ; then
    warn "appimagetool not found; skipping AppImage."
    return
  fi
  note "Building AppImage (GUI + CLI)"

  local APPDIR="$BUILD/AppDir"  # local to avoid unbound var elsewhere
  rm -rf "$APPDIR"
  mkdir -p "$APPDIR/usr/lib/$APP_ID" "$APPDIR/usr/share/applications" "$APPDIR/usr/share/icons/hicolor/256x256/apps"

  # Copy payload
  rsync -a "$GUI_PUB_LIN/." "$APPDIR/usr/lib/$APP_ID/"
  rsync -a "$CLI_PUB_LIN/." "$APPDIR/usr/lib/$APP_ID/"

  # AppRun: prefer provided, else generate simple one
  local APP_RUN="$REPO_ROOT/build/package/AppRun"
  if [[ -f "$APP_RUN" ]]; then
    install -m755 "$APP_RUN" "$APPDIR/AppRun"
  else
    cat > "$APPDIR/AppRun" <<'EOF'
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "$0")")"
export DOTNET_BUNDLE_EXTRACT_BASE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/WPStallman/dotnet_bundle"
exec "$HERE/usr/lib/com.wpstallman.app/WPStallman.GUI" "$@"
EOF
    chmod +x "$APPDIR/AppRun"
  fi

  # Ensure default desktop/icon within AppDir (and log fields)
  create_desktop_entry "$APPDIR" "$APP_ID" "$APP_NAME" "usr/lib/$APP_ID/WPStallman.GUI" "WordPress plugin project manager"

  "$APPIMAGETOOL" "$APPDIR" "$PKG/WPStallman-$VERSION-x86_64.AppImage"
  note "AppImage: $PKG/WPStallman-$VERSION-x86_64.AppImage"
}

# ---------- macOS bundles (unsigned, zipped) ----------
mac_bundles() {
  note "Zipping macOS .app bundles if present (GUI)"
  if [[ -d "$GUI_PUB_OSX_X64/W. P. Stallman.app" ]]; then
    (cd "$GUI_PUB_OSX_X64" && zip -qr "$PKG/WPStallman-$VERSION-macos-x64.zip" "W. P. Stallman.app")
    note "macOS x64 GUI: $PKG/WPStallman-$VERSION-macos-x64.zip"
  else
    warn "No GUI .app at $GUI_PUB_OSX_X64 — add your .app creation step."
  fi
  if [[ -d "$GUI_PUB_OSX_ARM/W. P. Stallman.app" ]]; then
    (cd "$GUI_PUB_OSX_ARM" && zip -qr "$PKG/WPStallman-$VERSION-macos-arm64.zip" "W. P. Stallman.app")
    note "macOS ARM GUI: $PKG/WPStallman-$VERSION-macos-arm64.zip"
  else
    warn "No GUI .app at $GUI_PUB_OSX_ARM — add your .app creation step."
  fi

  # Ship CLI as tarballs
  if [[ -f "$CLI_PUB_OSX_X64/WPStallman.CLI" ]]; then
    (cd "$CLI_PUB_OSX_X64" && tar -czf "$PKG/WPStallman-CLI-$VERSION-macos-x64.tar.gz" WPStallman.CLI*)
    note "macOS x64 CLI: $PKG/WPStallman-CLI-$VERSION-macos-x64.tar.gz"
  fi
  if [[ -f "$CLI_PUB_OSX_ARM/WPStallman.CLI" ]]; then
    (cd "$CLI_PUB_OSX_ARM" && tar -czf "$PKG/WPStallman-CLI-$VERSION-macos-arm64.tar.gz" WPStallman.CLI*)
    note "macOS ARM CLI: $PKG/WPStallman-CLI-$VERSION-macos-arm64.tar.gz"
  fi
}

# ---------- Run ----------
build_all
win_nsis
linux_deb
linux_appimage
mac_bundles

note "All done. Packages in: $PKG"