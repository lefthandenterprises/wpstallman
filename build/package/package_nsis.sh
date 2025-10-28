#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

APPVER="${APPVER:-0.0.0}"
APP_NAME_META="${APP_NAME_META:-WPStallman}"

EXE_NAME="${EXE_NAME:-WPStallman.GUI.exe}"
GUI_PROJ="${GUI_PROJ:-$ROOT/src/WPStallman.GUI.Windows/WPStallman.GUI.csproj}"
SOURCE_DIR="${SOURCE_DIR:-$ROOT/src/WPStallman.GUI.Windows/bin/Release/net8.0-windows/win-x64/publish}"
OUT_DIR="${OUT_DIR:-$ROOT/artifacts/packages}"
OUT_EXE="${OUT_EXE:-$OUT_DIR/${APP_NAME_META}-Setup-${APPVER}.exe}"
ICON_FILE="${ICON_FILE:-$ROOT/src/WPStallman.GUI.Windows/appicon/DRS.ico}"
UNICON_FILE="${UNICON_FILE:-$ROOT/src/WPStallman.GUI.Windows/appicon/DRS.ico}"
NSI="${NSI:-$ROOT/build/package/installer.nsi}"

mkdir -p "$OUT_DIR"

echo "== Packaging NSIS Installer (Windows) =="
echo "[INFO] ROOT       : $ROOT"
echo "[INFO] APPVER     : $APPVER"
echo "[INFO] PROJECT    : $GUI_PROJ"
echo "[INFO] SOURCE_DIR : $SOURCE_DIR"
echo "[INFO] OUT_EXE    : $OUT_EXE"
echo "[INFO] NSI        : $NSI"
echo

# --- Always rebuild cleanly ---
echo "[INFO] Rebuilding Windows GUI from scratch..."
dotnet clean "$GUI_PROJ" -c Release
dotnet restore "$GUI_PROJ" -r win-x64

dotnet publish "$GUI_PROJ" \
  -c Release \
  -r win-x64 \
  -f net8.0-windows10.0.17763.0 \
  --self-contained true \
  -p:PublishSingleFile=true \
  -p:InvariantGlobalization=true



echo "[OK] Publish complete."

# Sanity check
if [[ ! -f "$SOURCE_DIR/$EXE_NAME" ]]; then
  echo "[ERR] Build failed — $EXE_NAME not found at $SOURCE_DIR"
  echo "[HINT] Try checking actual publish output folder structure."
  exit 2
fi

# --- Optional icon flags ---
ICON_DEF=()
[[ -f "$ICON_FILE"   ]] && ICON_DEF+=("-DICON_FILE=$ICON_FILE")
[[ -f "$UNICON_FILE" ]] && ICON_DEF+=("-DUNICON_FILE=$UNICON_FILE")

echo "[INFO] Running makensis..."
makensis -V4 -NOCD \
  -DAPPVER="$APPVER" \
  -DSOURCE_DIR="$SOURCE_DIR" \
  -DEXE_NAME="$EXE_NAME" \
  -DOUT_EXE="$OUT_EXE" \
  "${ICON_DEF[@]}" \
  "$NSI"

echo "[OK] NSIS built: $OUT_EXE"
