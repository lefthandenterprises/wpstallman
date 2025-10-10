#!/usr/bin/env bash
set -euo pipefail

# ───────────────────────────────
# Pretty logging
# ───────────────────────────────
note() { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*" >&2; }
die()  { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; exit 1; }

# ───────────────────────────────
# Repo layout & inputs (adjust if needed)
# ───────────────────────────────
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT"

: "${GUI_CSPROJ:=src/WPStallman.GUI/WPStallman.GUI.csproj}"
: "${TFM_LIN_GUI:=net8.0}"
: "${RID_LIN:=linux-x64}"

PUB_LIN_GUI="$ROOT/src/WPStallman.GUI/bin/Release/${TFM_LIN_GUI}/${RID_LIN}/publish"
[[ -d "$PUB_LIN_GUI" ]] || die "Linux GUI publish folder not found: $PUB_LIN_GUI (run package_all.sh first)"

# App identity
: "${APP_ID:=com.wpstallman.app}"
: "${APP_NAME:="W. P. Stallman"}"
: "${MAIN_BIN:=WPStallman.GUI}"

# Output paths
: "${ARTIFACTS_DIR:=artifacts}"
: "${BUILDDIR:=$ARTIFACTS_DIR/build}"
: "${OUTDIR:=$ARTIFACTS_DIR/packages}"
DEB_ROOT="$BUILDDIR/deb"
mkdir -p "$BUILDDIR" "$OUTDIR"
rm -rf "$DEB_ROOT"
mkdir -p "$DEB_ROOT"

# Optional suffix to label baseline (e.g., -gtk4.0 / -gtk4.1)
: "${APP_SUFFIX:=}"

# ───────────────────────────────
# Version resolver (Directory.Build.props / MSBuild)
# ───────────────────────────────
get_msbuild_prop() {
  local proj="$1" prop="$2"
  dotnet msbuild "$proj" -nologo -getProperty:"$prop" 2>/dev/null | tr -d '\r' | tail -n1
}
get_version_from_props() {
  local props="$ROOT/Directory.Build.props"
  [[ -f "$props" ]] || { echo ""; return; }
  grep -oP '(?<=<Version>).*?(?=</Version>)' "$props" | head -n1
}
resolve_app_version() {
  local v=""
  v="$(get_msbuild_prop "$GUI_CSPROJ" "Version")"
  if [[ -z "$v" || "$v" == "*Undefined*" ]]; then
    v="$(get_version_from_props)"
  fi
  echo "$v"
}
APP_VERSION="${APP_VERSION_OVERRIDE:-$(resolve_app_version)}"
[[ -n "$APP_VERSION" ]] || die "Could not resolve Version from MSBuild or Directory.Build.props"
export APP_VERSION
note "Version: $APP_VERSION"

# ───────────────────────────────
# Default runtime dependencies (24.04+ GTK 4.1 baseline)
# Override via:  DEB_DEPENDS="..." build/package/package_deb.sh
# ───────────────────────────────
: "${DEB_DEPENDS:=libc6 (>= 2.38), libstdc++6 (>= 13), libgtk-3-0, libnotify4, libgdk-pixbuf-2.0-0, libnss3, libjavascriptcoregtk-4.1-0, libwebkit2gtk-4.1-0}"

# For a Mint/22.04 (GTK 4.0) build, you could run:
#   DEB_DEPENDS="libgtk-3-0, libnotify4, libgdk-pixbuf-2.0-0, libnss3, libjavascriptcoregtk-4.0-18, libwebkit2gtk-4.0-37" \
#   APP_SUFFIX="-gtk4.0" build/package/package_deb.sh

# ───────────────────────────────
# Layout the package filesystem
# ───────────────────────────────
install -d "$DEB_ROOT/DEBIAN"
install -d "$DEB_ROOT/usr/bin"
install -d "$DEB_ROOT/usr/lib/$APP_ID"
install -d "$DEB_ROOT/usr/share/applications"
install -d "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps"

# Stage payload
note "Staging publish → $DEB_ROOT/usr/lib/$APP_ID"
rsync -a --delete "$PUB_LIN_GUI/" "$DEB_ROOT/usr/lib/$APP_ID/"

# Ensure native lib is present (non–single-file expected)
if [[ ! -f "$DEB_ROOT/usr/lib/$APP_ID/libPhotino.Native.so" ]]; then
  warn "Missing libPhotino.Native.so in publish; attempting to copy from bin/Release…"
  if [[ -f "$ROOT/src/WPStallman.GUI/bin/Release/${TFM_LIN_GUI}/${RID_LIN}/libPhotino.Native.so" ]]; then
    cp -f "$ROOT/src/WPStallman.GUI/bin/Release/${TFM_LIN_GUI}/${RID_LIN}/libPhotino.Native.so" "$DEB_ROOT/usr/lib/$APP_ID/"
    note "Copied libPhotino.Native.so from bin/Release."
  else
    warn "Still no libPhotino.Native.so; the package may fail at runtime on a clean system."
  fi
fi

# Launcher shim in /usr/bin
cat > "$DEB_ROOT/usr/bin/wpstallman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
APPDIR="/usr/lib/com.wpstallman.app"
export LD_LIBRARY_PATH="$APPDIR:${LD_LIBRARY_PATH:-}"
exec "$APPDIR/WPStallman.GUI" "${@:-}"
EOF
chmod +x "$DEB_ROOT/usr/bin/wpstallman"

# Copy icon (prefer 256px)
ICON_SRC="$DEB_ROOT/usr/lib/$APP_ID/wwwroot/img/WPS-256.png"
if [[ ! -f "$ICON_SRC" ]]; then
  for alt in "$DEB_ROOT/usr/lib/$APP_ID/wwwroot/img/WPS.png" \
             "$DEB_ROOT/usr/lib/$APP_ID/wwwroot/img/wpst-256.png"; do
    [[ -f "$alt" ]] && ICON_SRC="$alt" && break
  done
fi
if [[ -f "$ICON_SRC" ]]; then
  cp -f "$ICON_SRC" "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps/${APP_ID}.png"
else
  warn "Icon not found in wwwroot/img; desktop entry will use a generic icon."
fi

# Desktop entry
cat > "$DEB_ROOT/usr/share/applications/${APP_ID}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Comment=WPStallman
Exec=wpstallman
Icon=${APP_ID}
Categories=Utility;
StartupWMClass=WPStallman.GUI
EOF

# ───────────────────────────────
# Control metadata
# ───────────────────────────────
CONTROL_FILE="$DEB_ROOT/DEBIAN/control"
cat > "$CONTROL_FILE" <<EOF
Package: wpstallman
Version: ${APP_VERSION}
Section: utils
Priority: optional
Architecture: amd64
Maintainer: WPStallman Team <noreply@example.com>
Depends: ${DEB_DEPENDS}
Description: W. P. Stallman – desktop app (Photino.NET)
 A cross-platform desktop app using Photino.NET.
EOF

# Optional: postinst to refresh icon cache / desktop database
cat > "$DEB_ROOT/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if command -v update-icon-caches >/dev/null 2>&1; then update-icon-caches /usr/share/icons/hicolor || true; fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then gtk-update-icon-cache -f /usr/share/icons/hicolor || true; fi
if command -v update-desktop-database >/dev/null 2>&1; then update-desktop-database -q /usr/share/applications || true; fi
exit 0
EOF
chmod 0755 "$DEB_ROOT/DEBIAN/postinst"

# ───────────────────────────────
# Diagnostics: show native deps
# ───────────────────────────────
if [[ -f "$DEB_ROOT/usr/lib/$APP_ID/libPhotino.Native.so" ]]; then
  note "ldd on Photino native (.deb payload):"
  ldd "$DEB_ROOT/usr/lib/$APP_ID/libPhotino.Native.so" | sed 's/^/  /' || true
  # Only warn on GTK baseline mismatch; don't fail builds on host glibc checks.
  if ldd "$DEB_ROOT/usr/lib/$APP_ID/libPhotino.Native.so" | grep -q 'libwebkit2gtk-4\.0'; then
    warn "Photino.Native links to WebKitGTK 4.0; your Depends currently target GTK 4.1."
    warn "Set DEB_DEPENDS to 4.0 libs and add APP_SUFFIX='-gtk4.0' if this is a 22.04 build."
  fi
fi

# ───────────────────────────────
# Build the .deb
# ───────────────────────────────
DEB_FILE="$OUTDIR/wpstallman_${APP_VERSION}_amd64${APP_SUFFIX}.deb"
note "Building .deb → $DEB_FILE"
fakeroot dpkg-deb --build "$DEB_ROOT" "$DEB_FILE"
note ".deb built: $DEB_FILE"
