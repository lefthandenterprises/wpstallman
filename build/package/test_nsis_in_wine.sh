#!/usr/bin/env bash
set -euo pipefail

INSTALLER="${1:-artifacts/packages/WPStallman-*-setup-win-x64.exe}"
WINEPREFIX="${WINEPREFIX:-$PWD/.wine-wpst-smoke}"
WINEARCH="${WINEARCH:-win64}"

# Fresh sandboxed Windows prefix
rm -rf "$WINEPREFIX"
WINEARCH="$WINEARCH" WINEPREFIX="$WINEPREFIX" wineboot -i

# Resolve UNIX path to the installer (handle globs)
INSTALLER_PATH=$(ls -1 $INSTALLER | head -n1)
[ -f "$INSTALLER_PATH" ] || { echo "Installer not found: $INSTALLER" >&2; exit 1; }

# Silent install to Program Files\WPStallman
DEST_WIN='C:\Program Files\WPStallman'
WINEARCH="$WINEARCH" WINEPREFIX="$WINEPREFIX" wine "$INSTALLER_PATH" /S /D="$DEST_WIN"

# Verify files landed
INSTALL_DIR="$WINEPREFIX/drive_c/Program Files/WPStallman"
test -d "$INSTALL_DIR" || { echo "Install dir missing"; exit 1; }
test -f "$INSTALL_DIR/WPStallman.GUI.exe" || { echo "GUI exe missing"; exit 1; }
test -f "$INSTALL_DIR/cli/WPStallman.CLI.exe" || echo "WARNING: CLI exe not found (expected at cli/)"

# Exercise CLI (don’t fail build if it exits nonzero)
if [ -f "$INSTALL_DIR/cli/WPStallman.CLI.exe" ]; then
  WINEARCH="$WINEARCH" WINEPREFIX="$WINEPREFIX" wine "$INSTALL_DIR/cli/WPStallman.CLI.exe" --help >/tmp/wpst_cli.out 2>&1 || true
  head -n 20 /tmp/wpst_cli.out || true
fi

# Check uninstall registration (optional)
WINEARCH="$WINEARCH" WINEPREFIX="$WINEPREFIX" wine reg query \
  "HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall" /s | grep -i "WPStallman" || true

# Uninstall silently
if [ -f "$INSTALL_DIR/Uninstall.exe" ]; then
  WINEARCH="$WINEARCH" WINEPREFIX="$WINEPREFIX" wine "$INSTALL_DIR/Uninstall.exe" /S || true
fi

# Assert uninstall cleaned up
if [ -d "$INSTALL_DIR" ]; then
  echo "WARNING: Uninstall did not remove $INSTALL_DIR"
  exit 1
fi

echo "NSIS smoke test OK in Wine."
