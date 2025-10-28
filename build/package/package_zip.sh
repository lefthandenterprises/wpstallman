#!/usr/bin/env bash
set -euo pipefail

note(){ printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[WARN]\033[0m %s\n" "$*" >&2; }
die(){  printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/meta_set_vars.sh"

APPVER="${APPVER:-$APP_VERSION}"
APP_NAME_SHORT="${APP_NAME_SHORT:-wpstallman}"

ZIP_DIR="$ROOT/artifacts/packages/zip"
STAGE="$ROOT/artifacts/tmp/zip-stage"
GUI_PROJ="${GUI_PROJ:-$ROOT/src/WPStallman.GUI.Windows/WPStallman.GUI.csproj}"
CLI_PROJ="${CLI_PROJ:-$ROOT/src/WPStallman.CLI/WPStallman.CLI.csproj}"

WIN_RID="${WIN_RID:-win-x64}"
WIN_TFM="${WIN_TFM:-net8.0-windows}"
CONF="${CONF:-Release}"

mkdir -p "$ZIP_DIR" "$STAGE"
rm -rf "$STAGE"/*

# --- Publish GUI ---
note "Publishing Windows GUI → $GUI_PROJ"
dotnet restore "$GUI_PROJ"
dotnet publish "$GUI_PROJ" -c "$CONF" -f "$WIN_TFM" -r "$WIN_RID" --self-contained true

GUI_PUB="$ROOT/src/WPStallman.GUI.Windows/bin/$CONF/$WIN_TFM/$WIN_RID/publish"
[[ -f "$GUI_PUB/WPStallman.GUI.Windows.exe" || -f "$GUI_PUB/WPStallman.GUI.Windows.dll" ]] \
  || die "Windows GUI publish output missing at $GUI_PUB"

mkdir -p "$STAGE/gui"
cp -a "$GUI_PUB/." "$STAGE/gui/"

# --- (Optional) Publish CLI if present ---
if [[ -f "$CLI_PROJ" ]]; then
  note "Publishing Windows CLI → $CLI_PROJ"
  dotnet restore "$CLI_PROJ"
  dotnet publish "$CLI_PROJ" -c "$CONF" -f net8.0 -r "$WIN_RID" --self-contained true
  CLI_PUB="$ROOT/src/WPStallman.CLI/bin/$CONF/net8.0/$WIN_RID/publish"
  if [[ -d "$CLI_PUB" ]]; then
    mkdir -p "$STAGE/cli"
    cp -a "$CLI_PUB/." "$STAGE/cli/"
  else
    warn "CLI publish directory not found; skipping CLI in ZIP"
  fi
else
  warn "CLI project not found at $CLI_PROJ; skipping CLI"
fi

# --- Add assets/icons (optional, harmless if missing) ---
if [[ -d "$ROOT/src/WPStallman.Assets/logo" ]]; then
  mkdir -p "$STAGE/assets/logo"
  cp -a "$ROOT/src/WPStallman.Assets/logo/." "$STAGE/assets/logo/" || true
fi

# --- Create ZIP ---
OUT_ZIP="$ZIP_DIR/${APP_NAME_SHORT}-Windows-${APPVER}.zip"
note "Creating ZIP → $OUT_ZIP"
( cd "$STAGE" && zip -r "$OUT_ZIP" . ) || die "zip failed creating $OUT_ZIP"
note "[OK] Created Windows ZIP at $OUT_ZIP"
