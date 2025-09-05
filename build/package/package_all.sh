#!/usr/bin/env bash
# ============================================================
# W. P. Stallman — Cross-Platform Packaging from Linux (net8)
# Publishes GUI + CLI (self-contained) and packages win/deb/appimage/mac
# Lintian-friendly .deb: proper control, copyright, changelog,
# icon handling, and permissions.
# ============================================================
set -euo pipefail

# ---------- Resolve repo root (robust) ----------
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
if REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"; then :; else
  for CAND in "$SCRIPT_DIR/../.." "$SCRIPT_DIR/.." "$SCRIPT_DIR"; do
    if [[ -d "$CAND/src" && -f "$CAND/src/WPStallman.GUI/WPStallman.GUI.csproj" ]]; then
      REPO_ROOT="$(cd "$CAND" && pwd -P)"; break
    fi
  done
  REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd -P)}"
fi

# ---------- Helpers ----------
note() { echo -e "\033[1;32m==> $*\033[0m"; }
warn() { echo -e "\033[1;33mWARN:\033[0m $*"; }
die()  { echo -e "\033[1;31mERROR:\033[0m $*"; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }

# ---------- Config ----------
APP_NAME="${APP_NAME:-W. P. Stallman}"
APP_ID="${APP_ID:-com.wpstallman.app}"
VERSION="${VERSION:-1.0.0}"
OUT="${PUBLISH_DIR:-artifacts}"

# Debian metadata (edit to your real info)
MAINT_NAME="${MAINT_NAME:-Patrick Driscoll}"
MAINT_EMAIL="${MAINT_EMAIL:-lefthandenterprises@outlook.com}"         # must be routable (no local hostnames)
HOMEPAGE="${HOMEPAGE:-https://lefthandenterprises.com/wpstallman}"    # put a real URL

# Packaging assets (desktop + icon produced by icon packer)
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

# Auto-detect projects
if   [[ -f "$REPO_ROOT/src/WPStallman.GUI/WPStallman.GUI.csproj" ]]; then GUI_CSPROJ="$REPO_ROOT/src/WPStallman.GUI/WPStallman.GUI.csproj"
elif [[ -f "$REPO_ROOT/WPStallman.GUI/WPStallman.GUI.csproj" ]]; then       GUI_CSPROJ="$REPO_ROOT/WPStallman.GUI/WPStallman.GUI.csproj"
else die "Cannot find WPStallman.GUI.csproj"; fi

if   [[ -f "$REPO_ROOT/src/WPStallman.CLI/WPStallman.CLI.csproj" ]]; then CLI_CSPROJ="$REPO_ROOT/src/WPStallman.CLI/WPStallman.CLI.csproj"
elif [[ -f "$REPO_ROOT/WPStallman.CLI/WPStallman.CLI.csproj" ]]; then       CLI_CSPROJ="$REPO_ROOT/WPStallman.CLI/WPStallman.CLI.csproj"
else die "Cannot find WPStallman.CLI.csproj"; fi

# Output folders
BUILD="$REPO_ROOT/$OUT/build"
PKG="$REPO_ROOT/$OUT/packages"
NSIS="$REPO_ROOT/$OUT/nsis"
mkdir -p "$BUILD" "$PKG" "$NSIS"

# ---- Icons (default to WPS-1024.png) ----
ICON_MASTER="${ICON_MASTER:-$REPO_ROOT/src/WPStallman.Assets/logo/WPS-1024.png}"
REFRESH_ICONS="${REFRESH_ICONS:-1}"
ICON_BASENAME="${ICON_BASENAME:-WPS}"

refresh_icons() {
  if [[ "${REFRESH_ICONS}" != "1" ]]; then
    echo "Icons: refresh disabled (REFRESH_ICONS=0)" >&2; return 0
  fi
  if [[ ! -f "$ICON_MASTER" ]]; then
    echo "Icons: ICON_MASTER not found: $ICON_MASTER - skipping icon refresh" >&2; return 0
  fi
  echo "Icons: generating from $ICON_MASTER" >&2
  bash "$REPO_ROOT/tools/dev/iconpack/package_icons_from_master.sh" \
    --master "$ICON_MASTER" 2>&1 | tee "$REPO_ROOT/artifacts/icons/iconpack.log" || {
    echo "WARN: icon generation failed — see artifacts/icons/iconpack.log" >&2
  }
}

# Publish roots
GUI_PUB_BASE_WIN="$(dirname "$GUI_CSPROJ")/bin/Release/net8.0-windows"
GUI_PUB_BASE_UNIX="$(dirname "$GUI_CSPROJ")/bin/Release/net8.0"
CLI_PUB_BASE="$(dirname "$CLI_CSPROJ")/bin/Release/net8.0"  # adjust if CLI multi-targets later

GUI_PUB_WIN="$GUI_PUB_BASE_WIN/$RID_WIN/publish"
GUI_PUB_LIN="$GUI_PUB_BASE_UNIX/$RID_LIN/publish"
GUI_PUB_OSX_X64="$GUI_PUB_BASE_UNIX/$RID_OSX_X64/publish"
GUI_PUB_OSX_ARM="$GUI_PUB_BASE_UNIX/$RID_OSX_ARM/publish"

CLI_PUB_WIN="$CLI_PUB_BASE/$RID_WIN/publish"
CLI_PUB_LIN="$CLI_PUB_BASE/$RID_LIN/publish"
CLI_PUB_OSX_X64="$CLI_PUB_BASE/$RID_OSX_X64/publish"
CLI_PUB_OSX_ARM="$CLI_PUB_BASE/$RID_OSX_ARM/publish"


# ---------- Desktop entry helper ----------
create_desktop_entry() {
  # $1 = target root (AppDir or DEB_ROOT)
  # $2 = desktop id (Icon= and file stem), e.g., "wpstallman"
  # $3 = App Name (human readable)
  # $4 = Exec path (relative for AppImage; absolute for .deb)
  # $5 = Comment/description (optional)
  local TARGET="$1"; local DESKID="$2"; local NAME="$3"; local EXEC_PATH="$4"; local COMMENT="${5:-$APP_NAME}"

  mkdir -p "$TARGET/usr/share/applications" \
           "$TARGET/usr/share/icons/hicolor/64x64/apps" \
           "$TARGET/usr/share/icons/hicolor/128x128/apps" \
           "$TARGET/usr/share/icons/hicolor/256x256/apps"

  local WMCLASS="WPStallman.GUI"
  local DESKTOP_PATH
  if [[ "$TARGET" == *"/AppDir" ]]; then
    DESKTOP_PATH="$TARGET/${DESKID}.desktop"   # top-level for AppImage
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
Keywords=WordPress;Plugin;CLI;GUI;Development;
Terminal=false
StartupWMClass=${WMCLASS}
EOF

  # Install icon into hicolor; do NOT drop a root-level PNG for .deb
  local ICON_SRC=""
  if [[ -f "$ICON_PNG" ]]; then
    ICON_SRC="$ICON_PNG"
  elif [[ -f "$TARGET/usr/lib/$APP_ID/wwwroot/img/WPS-256.png" ]]; then
    ICON_SRC="$TARGET/usr/lib/$APP_ID/wwwroot/img/WPS-256.png"
  fi
  if [[ -n "$ICON_SRC" ]]; then
    install -m644 "$ICON_SRC" "$TARGET/usr/share/icons/hicolor/64x64/apps/${DESKID}.png"
    install -m644 "$ICON_SRC" "$TARGET/usr/share/icons/hicolor/128x128/apps/${DESKID}.png"
    install -m644 "$ICON_SRC" "$TARGET/usr/share/icons/hicolor/256x256/apps/${DESKID}.png"
    # ONLY for AppImage help old launchers resolve Icon= (place beside .desktop)
    if [[ "$TARGET" == *"/AppDir" ]]; then
      cp -f "$ICON_SRC" "$TARGET/${DESKID}.png" 2>/dev/null || true
    fi
  else
    warn "No icon source found for ${DESKID}"
  fi

  note "Desktop written: $DESKTOP_PATH"
  grep -E '^(Name|Exec|Icon|StartupWMClass)=' "$DESKTOP_PATH" | sed 's/^/  /' || true

  if have desktop-file-validate; then
    desktop-file-validate "$DESKTOP_PATH" || warn "desktop-file-validate issues for $DESKTOP_PATH"
  fi
}

# Map a RuntimeIdentifier to the correct TFM for this repo

tfm_for() {
  case "$1" in
    win-*)   echo "net8.0-windows" ;;
    *)       echo "net8.0" ;;
  esac
}

build_all() {
  note "Publishing GUI + CLI (self-contained, single-file)"

  # --- GUI (RID→TFM) ---
  dotnet publish "$GUI_CSPROJ" -c Release -r "$RID_WIN"     -p:TargetFramework="$(tfm_for "$RID_WIN")"     -p:SelfContained=true -p:PublishSingleFile=true
  dotnet publish "$GUI_CSPROJ" -c Release -r "$RID_LIN"     -p:TargetFramework="$(tfm_for "$RID_LIN")"     -p:SelfContained=true -p:PublishSingleFile=true
  dotnet publish "$GUI_CSPROJ" -c Release -r "$RID_OSX_X64" -p:TargetFramework="$(tfm_for "$RID_OSX_X64")" -p:SelfContained=true -p:PublishSingleFile=true
  dotnet publish "$GUI_CSPROJ" -c Release -r "$RID_OSX_ARM" -p:TargetFramework="$(tfm_for "$RID_OSX_ARM")" -p:SelfContained=true -p:PublishSingleFile=true

  # --- CLI (always net8.0) ---
  dotnet publish "$CLI_CSPROJ" -c Release -r "$RID_WIN"     -p:TargetFramework=net8.0 -p:SelfContained=true -p:PublishSingleFile=true
  dotnet publish "$CLI_CSPROJ" -c Release -r "$RID_LIN"     -p:TargetFramework=net8.0 -p:SelfContained=true -p:PublishSingleFile=true
  dotnet publish "$CLI_CSPROJ" -c Release -r "$RID_OSX_X64" -p:TargetFramework=net8.0 -p:SelfContained=true -p:PublishSingleFile=true
  dotnet publish "$CLI_CSPROJ" -c Release -r "$RID_OSX_ARM" -p:TargetFramework=net8.0 -p:SelfContained=true -p:PublishSingleFile=true
}



# ---------- Windows (NSIS) ----------
win_nsis() {
  if ! command -v "$MAKENSIS" >/dev/null 2>&1 ; then
    warn "makensis not found; skipping Windows NSIS."
    return
  fi

  note "Building Windows NSIS installer"

  # Optional icon (won’t fail if missing)
  ICON_ICO_PATH=""
  if [[ -f "$REPO_ROOT/artifacts/icons/${ICON_BASENAME}.ico" ]]; then
    ICON_ICO_PATH="$REPO_ROOT/artifacts/icons/${ICON_BASENAME}.ico"
  fi

  local NSI="$REPO_ROOT/build/package/installer.nsi"
  if [[ ! -f "$NSI" ]]; then
    warn "Missing $NSI; skipping NSIS."
    return
  fi

  # Fail fast if Windows publish outputs aren’t there
  [[ -f "$GUI_PUB_WIN/WPStallman.GUI.exe" ]] || die "No GUI exe at $GUI_PUB_WIN; did publish for win-x64 run?"
  [[ -f "$CLI_PUB_WIN/WPStallman.CLI.exe" ]] || die "No CLI exe at $CLI_PUB_WIN; did publish for win-x64 run?"

  mkdir -p "$NSIS"

  # Pass absolute paths to NSIS (Linux-style slashes are fine on makensis for Linux)
  "$MAKENSIS" -V4 \
    -DVERSION="$VERSION" \
    -DOUTDIR="$PKG" \
    -DAPP_NAME="$APP_NAME" \
    -DAPP_ID="$APP_ID" \
    -DGUI_DIR="$GUI_PUB_WIN" \
    -DCLI_DIR="$CLI_PUB_WIN" \
    ${ICON_ICO_PATH:+-DICON_ICO="$ICON_ICO_PATH"} \
    "$NSI"

  note "NSIS: $PKG/WPStallman-$VERSION-setup-win-x64.exe"
}


# ---------- Linux .deb (GUI + CLI, lintian friendly) ----------
linux_deb() {
  note "Building Linux .deb (GUI + CLI)"
  local DEB_ROOT="$BUILD/deb"
  local DEB_NAME="wpstallman_${VERSION}_amd64"
  rm -rf "$DEB_ROOT"
  mkdir -p "$DEB_ROOT/DEBIAN" \
           "$DEB_ROOT/usr/lib/$APP_ID" \
           "$DEB_ROOT/usr/share/applications" \
           "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps" \
           "$DEB_ROOT/usr/share/doc/wpstallman"

  # payload
  rsync -a "$GUI_PUB_LIN/." "$DEB_ROOT/usr/lib/$APP_ID/"
  rsync -a "$CLI_PUB_LIN/." "$DEB_ROOT/usr/lib/$APP_ID/"

  # desktop + icon (id = wpstallman)
  create_desktop_entry "$DEB_ROOT" "wpstallman" "$APP_NAME" "/usr/lib/$APP_ID/WPStallman.GUI" "WordPress plugin project manager"

  # prefer pre-staged hicolor icons if present
  if [[ -d "$REPO_ROOT/artifacts/icons/hicolor" ]]; then
    mkdir -p "$DEB_ROOT/usr/share/icons"
    rsync -a "$REPO_ROOT/artifacts/icons/hicolor/" "$DEB_ROOT/usr/share/icons/hicolor/"
  fi

  # Optional: override desktop/icon from repo assets
  [[ -f "$DESKTOP_FILE" ]] && install -m644 "$DESKTOP_FILE" "$DEB_ROOT/usr/share/applications/wpstallman.desktop"
  [[ -f "$ICON_PNG"   ]] && install -m644 "$ICON_PNG"     "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps/wpstallman.png"

  # ---- Debian control (no unknown fields) ----
  cat > "$DEB_ROOT/DEBIAN/control" <<EOF
Package: wpstallman
Version: $VERSION
Section: utils
Priority: optional
Architecture: amd64
Maintainer: ${MAINT_NAME} <${MAINT_EMAIL}>
Homepage: ${HOMEPAGE}
Description: W.P. Stallman — WordPress project manager (GUI & CLI)
 A cross-platform .NET application providing tools to generate and manage
 WordPress plugin/theme scaffolding and assets. Includes a GUI and a CLI.
Depends: libgtk-3-0, libwebkit2gtk-4.0-37 | libwebkit2gtk-4.1-0, libjavascriptcoregtk-4.0-18, libnotify4, libgdk-pixbuf-2.0-0
EOF

  # ---- /usr/share/doc/wpstallman ----
  local DOC="$DEB_ROOT/usr/share/doc/wpstallman"
  mkdir -p "$DOC"
  # prefer repo-maintained DEP-5 file if present
  if   [[ -f "$REPO_ROOT/build/package/debian/copyright" ]]; then
    install -m644 "$REPO_ROOT/build/package/debian/copyright" "$DOC/copyright"
  elif [[ -f "$REPO_ROOT/packaging/debian/copyright" ]]; then
    install -m644 "$REPO_ROOT/packaging/debian/copyright" "$DOC/copyright"
  else
    cat > "$DOC/copyright" <<'EOC'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: WPStallman
Source: https://example.com/wpstallman

Files: *
Copyright: 2025 Patrick Driscoll
License: MIT
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 .
 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.
 .
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
EOC
  fi

  # reproducible-ish changelog (gzip -n kills timestamps)
  if have gzip; then
    printf "wpstallman (%s) unstable; urgency=medium\n\n  * Automated build.\n\n -- %s <%s>  %s\n" \
      "$VERSION" "$MAINT_NAME" "$MAINT_EMAIL" "$(date -R)" \
      | gzip -n -9 > "$DOC/changelog.gz"
  fi

  # clean up empty dirs (lintian info)
  find "$DEB_ROOT/usr/lib/$APP_ID" -type d -empty -delete || true

  # perms (lintian)
  chmod 0755 "$DEB_ROOT/DEBIAN"
  chmod 0644 "$DEB_ROOT/DEBIAN/control" 2>/dev/null || true
  find "$DEB_ROOT/usr" -type d -print0 | xargs -0 chmod 0755
  find "$DEB_ROOT/usr" -type f -print0 | xargs -0 chmod 0644

  # Build the .deb with dpkg-deb (so DEBIAN/ is control, not payload)
  rm -f "$PKG/${DEB_NAME}.deb" 2>/dev/null || true
  dpkg-deb --build "$DEB_ROOT" "$PKG/${DEB_NAME}.deb"
  note "DEB: $PKG/${DEB_NAME}.deb"
}

# ---------- Linux AppImage (includes CLI) ----------
linux_appimage() {
  if ! have "$APPIMAGETOOL"; then warn "appimagetool not found; skipping AppImage."; return; fi
  note "Building AppImage (GUI + CLI)"
  local APPDIR="$BUILD/AppDir"
  rm -rf "$APPDIR"
  mkdir -p "$APPDIR/usr/lib/$APP_ID" "$APPDIR/usr/share/applications" "$APPDIR/usr/share/icons/hicolor/256x256/apps"

  rsync -a "$GUI_PUB_LIN/." "$APPDIR/usr/lib/$APP_ID/"
  rsync -a "$CLI_PUB_LIN/." "$APPDIR/usr/lib/$APP_ID/"

  # AppRun
  if [[ ! -x "$APPDIR/AppRun" ]]; then
    cat > "$APPDIR/AppRun" <<'EOF'
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "$0")")"
export DOTNET_BUNDLE_EXTRACT_BASE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/WPStallman/dotnet_bundle"
exec "$HERE/usr/lib/com.wpstallman.app/WPStallman.GUI" "$@"
EOF
    chmod +x "$APPDIR/AppRun"
  fi

  # Desktop + icon (id = wpstallman)
  create_desktop_entry "$APPDIR" "wpstallman" "$APP_NAME" "usr/lib/$APP_ID/WPStallman.GUI" "WordPress plugin project manager"

  # prefer pre-staged hicolor icons if present
  if [[ -d "$REPO_ROOT/artifacts/icons/hicolor" ]]; then
    mkdir -p "$APPDIR/usr/share/icons"
    rsync -a "$REPO_ROOT/artifacts/icons/hicolor/" "$APPDIR/usr/share/icons/hicolor/"
  fi

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

# ---------- Optional: run lints if scripts exist ----------
run_lints() {
  if [[ "${LINT_AFTER:-0}" == "1" ]]; then
    [[ -x "$REPO_ROOT/tools/dev/lint/lint_deb.sh"       ]] && "$REPO_ROOT/tools/dev/lint/lint_deb.sh"       "$PKG"/wpstallman_*_amd64.deb || true
    [[ -x "$REPO_ROOT/tools/dev/lint/lint_appimage.sh"  ]] && "$REPO_ROOT/tools/dev/lint/lint_appimage.sh"  "$PKG"/WPStallman-*.AppImage || true
  fi
}

# ---------- Run ----------
refresh_icons
build_all
win_nsis
linux_deb
linux_appimage
mac_bundles
run_lints
note "All done. Packages in: $PKG"
