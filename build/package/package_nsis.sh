#!/usr/bin/env bash
set -euo pipefail

# --- Repo root (go up 2 dirs from build/package) ---
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# --- Inputs (edit as needed) ---
VERSION="${VERSION:-1.0.0}"
APP_NAME="${APP_NAME:-W. P. Stallman}"
APP_ID="${APP_ID:-com.wpstallman.app}"

GUI_DIR="${GUI_DIR:-$ROOT/src/WPStallman.GUI/bin/Release/net8.0-windows/win-x64/publish}"
CLI_DIR="${CLI_DIR:-$ROOT/src/WPStallman.CLI/bin/Release/net8.0/win-x64/publish}"
OUTDIR="${OUTDIR:-$ROOT/artifacts/packages}"
ICON_ICO="${ICON_ICO:-$ROOT/artifacts/icons/WPS.ico}"
NSI="${NSI:-$ROOT/build/package/installer.nsi}"
LICENSE_FILE="${LICENSE_FILE:-$ROOT/build/package/LICENSE.txt}"
[ -f "$LICENSE_FILE" ] || die "LICENSE_FILE not found: $LICENSE_FILE"


note() { printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }
die()  { printf "\n\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }

# --- Sanity checks ---
command -v makensis >/dev/null || die "makensis not found. Install the 'nsis' package."
[ -f "$LICENSE_FILE" ] || die "LICENSE_FILE not found: $LICENSE_FILE"
[ -d "$GUI_DIR" ] || die "GUI_DIR not found: $GUI_DIR"
[ -d "$CLI_DIR" ] || die "CLI_DIR not found: $CLI_DIR"
[ -f "$NSI" ]     || die "NSIS script not found: $NSI"
mkdir -p "$OUTDIR"

# Icon: must exist and be a real Windows .ico
[ -f "$ICON_ICO" ] || die "ICON_ICO not found: $ICON_ICO"
if command -v file >/dev/null 2>&1; then
  if ! file "$ICON_ICO" | grep -qi "MS Windows icon"; then
    die "ICON_ICO is not a valid Windows .ico: $ICON_ICO"
  fi
fi


# --- Show summary ---
note "Packaging NSIS installer"
echo "  Version : $VERSION"
echo "  AppName : $APP_NAME"
echo "  AppID   : $APP_ID"
echo "  GUI_DIR : $GUI_DIR"
echo "  CLI_DIR : $CLI_DIR"
echo "  OUTDIR  : $OUTDIR"
echo "  ICON_ICO: $ICON_ICO"
echo "  Script  : $NSI"
echo "  License : $LICENSE_FILE"

# --- Run makensis ---
set -x
makensis -V4 \
  -DVERSION="$VERSION" \
  -DOUTDIR="$OUTDIR" \
  -DAPP_NAME="$APP_NAME" \
  -DAPP_ID="$APP_ID" \
  -DGUI_DIR="$GUI_DIR" \
  -DCLI_DIR="$CLI_DIR" \
  -DICON_ICO="$ICON_ICO" \
  -DLICENSE_FILE="$LICENSE_FILE" \
  "$NSI"
set +x


note "Done. Output -> $OUTDIR"
