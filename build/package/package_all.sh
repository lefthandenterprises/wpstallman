#!/usr/bin/env bash
set -euo pipefail

# =========================
# Repo & project paths
# =========================
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUI_CSPROJ="$ROOT/src/WPStallman.GUI/WPStallman.GUI.csproj"
CLI_CSPROJ="$ROOT/src/WPStallman.CLI/WPStallman.CLI.csproj"

# Granular packagers
NSIS_WRAP="$ROOT/build/package/package_nsis.sh"
PKG_DEB="$ROOT/build/package/package_deb.sh"
PKG_APPIMG="$ROOT/build/package/package_appimage.sh"
PKG_MAC="$ROOT/build/package/package_macos.sh"
PKG_WINZIP="$ROOT/build/package/package_winzip.sh"

# =========================
# App metadata (override via env)
# =========================
: "${VERSION:=1.0.0}"
: "${APP_NAME:=W. P. Stallman}"
: "${APP_ID:=com.wpstallman.app}"

# Icons / license
: "${ICON_ICO:=$ROOT/artifacts/icons/WPS.ico}"            # Windows .ico (multi-res)
: "${ICON_PNG_256:=$ROOT/artifacts/icons/WPS-256.png}"    # PNG used by AppImage/.deb (optional)
: "${LICENSE_FILE:=$ROOT/build/package/LICENSE.txt}"      # MIT text for installers

# RIDs
RID_WIN="win-x64"
RID_LIN="linux-x64"
RID_OSX_X64="osx-x64"
RID_OSX_ARM="osx-arm64"

# Output directory
OUTDIR="$ROOT/artifacts/packages"

note(){ printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }
die(){  printf "\n\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }

# =========================
# Build helpers
# =========================
tfm_for() {
  case "$1" in
    win-*)   echo "net8.0-windows" ;;
    *)       echo "net8.0" ;;
  esac
}

build_all() {
  note "Publishing GUI + CLI (self-contained, single-file)"

  # GUI (RID→TFM mapping)
  dotnet publish "$GUI_CSPROJ" -c Release -r "$RID_WIN"     -p:TargetFramework="$(tfm_for "$RID_WIN")"     -p:SelfContained=true -p:PublishSingleFile=true
  dotnet publish "$GUI_CSPROJ" -c Release -r "$RID_LIN"     -p:TargetFramework="$(tfm_for "$RID_LIN")"     -p:SelfContained=true -p:PublishSingleFile=true
  dotnet publish "$GUI_CSPROJ" -c Release -r "$RID_OSX_X64" -p:TargetFramework="$(tfm_for "$RID_OSX_X64")" -p:SelfContained=true -p:PublishSingleFile=true
  dotnet publish "$GUI_CSPROJ" -c Release -r "$RID_OSX_ARM" -p:TargetFramework="$(tfm_for "$RID_OSX_ARM")" -p:SelfContained=true -p:PublishSingleFile=true

  # CLI (single TFM net8.0 for all RIDs unless you multi-targeted it)
  dotnet publish "$CLI_CSPROJ" -c Release -r "$RID_WIN"     -p:TargetFramework=net8.0 -p:SelfContained=true -p:PublishSingleFile=true
  dotnet publish "$CLI_CSPROJ" -c Release -r "$RID_LIN"     -p:TargetFramework=net8.0 -p:SelfContained=true -p:PublishSingleFile=true
  dotnet publish "$CLI_CSPROJ" -c Release -r "$RID_OSX_X64" -p:TargetFramework=net8.0 -p:SelfContained=true -p:PublishSingleFile=true
  dotnet publish "$CLI_CSPROJ" -c Release -r "$RID_OSX_ARM" -p:TargetFramework=net8.0 -p:SelfContained=true -p:PublishSingleFile=true
}

# =========================
# Build everything
# =========================
build_all

# =========================
# Publish directories
# =========================
GUI_DIR_WIN="$ROOT/src/WPStallman.GUI/bin/Release/net8.0-windows/$RID_WIN/publish"
GUI_DIR_LIN="$ROOT/src/WPStallman.GUI/bin/Release/net8.0/$RID_LIN/publish"
GUI_DIR_OSX_X64="$ROOT/src/WPStallman.GUI/bin/Release/net8.0/$RID_OSX_X64/publish"
GUI_DIR_OSX_ARM="$ROOT/src/WPStallman.GUI/bin/Release/net8.0/$RID_OSX_ARM/publish"

CLI_DIR_WIN="$ROOT/src/WPStallman.CLI/bin/Release/net8.0/$RID_WIN/publish"
CLI_DIR_LIN="$ROOT/src/WPStallman.CLI/bin/Release/net8.0/$RID_LIN/publish"
CLI_DIR_OSX_X64="$ROOT/src/WPStallman.CLI/bin/Release/net8.0/$RID_OSX_X64/publish"
CLI_DIR_OSX_ARM="$ROOT/src/WPStallman.CLI/bin/Release/net8.0/$RID_OSX_ARM/publish"

[ -d "$GUI_DIR_WIN" ] || die "Expected GUI publish not found: $GUI_DIR_WIN"
[ -d "$CLI_DIR_WIN" ] || die "Expected CLI publish not found: $CLI_DIR_WIN"
mkdir -p "$OUTDIR"

# =========================
# Package: Windows NSIS installer
# =========================
if [ -x "$NSIS_WRAP" ]; then
  note "Packaging Windows installer (NSIS)"
  VERSION="$VERSION" \
  APP_NAME="$APP_NAME" \
  APP_ID="$APP_ID" \
  GUI_DIR="$GUI_DIR_WIN" \
  CLI_DIR="$CLI_DIR_WIN" \
  OUTDIR="$OUTDIR" \
  ICON_ICO="$ICON_ICO" \
  LICENSE_FILE="$LICENSE_FILE" \
  "$NSIS_WRAP"
else
  note "Skipping NSIS (wrapper not executable): $NSIS_WRAP"
fi

# =========================
# Package: Windows ZIP (EXE + LICENSE)
# =========================
if [ -x "$PKG_WINZIP" ]; then
  note "Packaging Windows ZIP"
  VERSION="$VERSION" \
  APP_NAME="$APP_NAME" \
  GUI_DIR="$GUI_DIR_WIN" \
  LICENSE_FILE="$LICENSE_FILE" \
  "$PKG_WINZIP"
else
  note "Skipping Windows ZIP (wrapper not executable): $PKG_WINZIP"
fi

# =========================
# Package: Debian/Ubuntu .deb
# =========================
if [ -x "$PKG_DEB" ]; then
  note "Packaging .deb"
  VERSION="$VERSION" \
  APP_NAME="$APP_NAME" \
  APP_ID="$APP_ID" \
  GUI_DIR="$GUI_DIR_LIN" \
  CLI_DIR="$CLI_DIR_LIN" \
  "$PKG_DEB"
else
  note "Skipping .deb (wrapper not executable): $PKG_DEB"
fi

# =========================
# Package: Linux AppImage
# =========================
if [ -x "$PKG_APPIMG" ]; then
  note "Packaging AppImage"
  VERSION="$VERSION" \
  APP_NAME="$APP_NAME" \
  APP_ID="$APP_ID" \
  GUI_DIR="$GUI_DIR_LIN" \
  ICON_PNG="$ICON_PNG_256" \
  "$PKG_APPIMG"
else
  note "Skipping AppImage (wrapper not executable): $PKG_APPIMG"
fi

# =========================
# Package: macOS (.app → zip, dmg if on macOS)
# =========================
if [ -x "$PKG_MAC" ]; then
  note "Packaging macOS"
  # By default, point to the osx-x64 bundle; override APP_BUNDLE if you build arm64 instead
  APP_BUNDLE="$ROOT/src/WPStallman.GUI/bin/Release/net8.0/osx-x64/publish/${APP_NAME}.app" \
  VERSION="$VERSION" \
  APP_NAME="$APP_NAME" \
  "$PKG_MAC"
else
  note "Skipping macOS packaging (wrapper not executable): $PKG_MAC"
fi

note "All done. Outputs in: $OUTDIR"
