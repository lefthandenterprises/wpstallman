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

# Output dirs/files
: "${ARTIFACTS_DIR:=artifacts}"
: "${BUILDDIR:=$ARTIFACTS_DIR/build}"
: "${OUTDIR:=$ARTIFACTS_DIR/packages}"
mkdir -p "$BUILDDIR" "$OUTDIR"

# AppImage identity
: "${APP_ID:=com.wpstallman.app}"
: "${APP_NAME:="W. P. Stallman"}"
: "${MAIN_BIN:=WPStallman.GUI}"

# Optional suffix to label baselines (e.g., -gtk4.0 / -gtk4.1)
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
# Prepare AppDir
# ───────────────────────────────
APPDIR="$BUILDDIR/AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib/$APP_ID" "$APPDIR/usr/share/applications"

# Stage payload (publish folder → usr/lib/<APP_ID>)
note "Staging publish → $APPDIR/usr/lib/$APP_ID"
rsync -a --delete "$PUB_LIN_GUI/" "$APPDIR/usr/lib/$APP_ID/"

# Ensure native lib is present (Photino requires it when non–single-file)
if [[ ! -f "$APPDIR/usr/lib/$APP_ID/libPhotino.Native.so" ]]; then
  warn "Missing libPhotino.Native.so in publish; attempting to locate next to publish…"
  if [[ -f "$ROOT/src/WPStallman.GUI/bin/Release/${TFM_LIN_GUI}/${RID_LIN}/libPhotino.Native.so" ]]; then
    cp -f "$ROOT/src/WPStallman.GUI/bin/Release/${TFM_LIN_GUI}/${RID_LIN}/libPhotino.Native.so" "$APPDIR/usr/lib/$APP_ID/"
    note "Copied libPhotino.Native.so from bin/Release."
  else
    warn "Still no libPhotino.Native.so; the AppImage may fail on systems lacking the right WebKitGTK."
  fi
fi

# Copy icon (prefer the 256px app icon from wwwroot/img)
ICON_SRC="$APPDIR/usr/lib/$APP_ID/wwwroot/img/WPS-256.png"
if [[ ! -f "$ICON_SRC" ]]; then
  # Try a couple alternative names
  for alt in "$APPDIR/usr/lib/$APP_ID/wwwroot/img/WPS.png" \
             "$APPDIR/usr/lib/$APP_ID/wwwroot/img/wpst-256.png"; do
    [[ -f "$alt" ]] && ICON_SRC="$alt" && break
  done
fi
if [[ -f "$ICON_SRC" ]]; then
  cp -f "$ICON_SRC" "$APPDIR/${APP_ID}.png"
else
  warn "App icon not found at wwwroot/img; the AppImage will have a generic icon."
fi

# AppRun (sets LD_LIBRARY_PATH and executes the app)
cat > "$APPDIR/AppRun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
APPDIR_LIB="$HERE/usr/lib/com.wpstallman.app"
export LD_LIBRARY_PATH="$APPDIR_LIB:${LD_LIBRARY_PATH:-}"
exec "$APPDIR_LIB/WPStallman.GUI" "${@:-}"
EOF
chmod +x "$APPDIR/AppRun"

# Desktop file
cat > "$APPDIR/${APP_ID}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Comment=WPStallman
Exec=${APP_ID}
Icon=${APP_ID}
Categories=Utility;
StartupWMClass=WPStallman.GUI
X-AppImage-Version=${APP_VERSION}
EOF

# Symlink launcher name expected by .desktop
ln -sf "./AppRun" "$APPDIR/usr/bin/${APP_ID}"

# ───────────────────────────────
# Sanity: show native deps (warn if GTK SONAME is 4.0 when you expect 4.1)
# ───────────────────────────────
if [[ -f "$APPDIR/usr/lib/$APP_ID/libPhotino.Native.so" ]]; then
  note "ldd on Photino native (AppImage payload):"
  ldd "$APPDIR/usr/lib/$APP_ID/libPhotino.Native.so" | sed 's/^/  /' || true
  if ldd "$APPDIR/usr/lib/$APP_ID/libPhotino.Native.so" | grep -q 'libwebkit2gtk-4\.0'; then
    warn "Photino native links to WebKitGTK 4.0. On Ubuntu 24.04+, prefer GTK 4.1 builds."
  fi
fi

# ───────────────────────────────
# Build AppImage
# ───────────────────────────────
OUTFILE="$OUTDIR/WPStallman-${APP_VERSION}-x86_64${APP_SUFFIX}.AppImage"
note "Building AppImage → $OUTFILE"

# Hint for environments without FUSE
export APPIMAGE_EXTRACT_AND_RUN=${APPIMAGE_EXTRACT_AND_RUN:-1}

if ! command -v appimagetool >/dev/null 2>&1; then
  die "appimagetool is not in PATH. Install it or place it at /usr/local/bin/appimagetool."
fi

appimagetool "$APPDIR" "$OUTFILE"
chmod +x "$OUTFILE"
note "AppImage built: $OUTFILE"
