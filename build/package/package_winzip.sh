#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

: "${VERSION:=1.0.0}"
: "${APP_NAME:=W. P. Stallman}"

GUI_DIR="${GUI_DIR:-$ROOT/src/WPStallman.GUI/bin/Release/net8.0-windows/win-x64/publish}"
LICENSE_FILE="${LICENSE_FILE:-$ROOT/build/package/LICENSE.txt}"
OUTDIR="$ROOT/artifacts/packages"
mkdir -p "$OUTDIR"

note(){ printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }
die(){  printf "\n\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }

command -v zip >/dev/null || die "zip not found (sudo apt-get install zip)."
[ -d "$GUI_DIR" ] || die "GUI_DIR not found: $GUI_DIR"
[ -f "$LICENSE_FILE" ] || die "LICENSE_FILE not found: $LICENSE_FILE"
[ -f "$GUI_DIR/wwwroot/index.html" ] || die "Missing wwwroot in publish: $GUI_DIR/wwwroot/index.html"


# Find the main EXE name (default: WPStallman.GUI.exe)
EXE="${EXE:-$GUI_DIR/WPStallman.GUI.exe}"
[ -f "$EXE" ] || die "GUI exe not found: $EXE"

ZIP="$OUTDIR/${APP_NAME// /_}-${VERSION}-windows.zip"
note "Creating Windows ZIP -> $ZIP"
TMPDIR="$(mktemp -d)"
mkdir -p "$TMPDIR/${APP_NAME}"

# Include the entire publish folder (so dependencies are present)
cp -a "$GUI_DIR/." "$TMPDIR/${APP_NAME}/"
cp -a "$LICENSE_FILE" "$TMPDIR/${APP_NAME}/LICENSE.txt"

( cd "$TMPDIR" && zip -qry "$ZIP" "${APP_NAME}" )
rm -rf "$TMPDIR"
note "Wrote $ZIP"
