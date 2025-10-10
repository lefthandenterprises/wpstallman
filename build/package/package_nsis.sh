#!/usr/bin/env bash
set -euo pipefail

# ───────────────────────────────
# Pretty logging
# ───────────────────────────────
note(){ printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[WARN]\033[0m %s\n" "$*" >&2; }
die(){  printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; exit 1; }

ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT"

: "${GUI_CSPROJ:=src/WPStallman.GUI/WPStallman.GUI.csproj}"
: "${TFM_WIN_GUI:=net8.0-windows}"
: "${RID_WIN:=win-x64}"

# Identity
: "${APP_NAME:="W. P. Stallman"}"
: "${APP_ID:=com.wpstallman.app}"
: "${COMPANY_NAME:=WPStallman}"

# Output dirs
: "${ARTIFACTS_DIR:=artifacts}"
: "${BUILDDIR:=$ARTIFACTS_DIR/build/nsis}"
: "${OUTDIR:=$ARTIFACTS_DIR/packages}"
mkdir -p "$BUILDDIR" "$OUTDIR"

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
note "Version: $APP_VERSION"

# VIProductVersion must be 4-part numeric; derive from APP_VERSION
VI_VERSION="$(echo "$APP_VERSION" | sed 's/[^0-9.].*$//' | awk -F. '{printf "%d.%d.%d.%d", $1,$2,$3, ($4==""?0:$4)}' )"
[[ -n "$VI_VERSION" ]] || VI_VERSION="1.0.0.0"

# ───────────────────────────────
# Ensure makensis
# ───────────────────────────────
if ! command -v makensis >/dev/null 2>&1; then
  die "makensis not found. Install NSIS (e.g., on Ubuntu: sudo apt install nsis)."
fi

# ───────────────────────────────
# Publish Windows payload (single-file)
# ───────────────────────────────
note "Publishing Windows GUI → $TFM_WIN_GUI / $RID_WIN"
dotnet publish "$GUI_CSPROJ" -c Release -r "$RID_WIN" -f "$TFM_WIN_GUI" \
  -p:SelfContained=true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true \
  -p:EnableWindowsTargeting=true

GUI_PUB="$ROOT/src/$(basename "${GUI_CSPROJ%/*.csproj}")/bin/Release/${TFM_WIN_GUI}/${RID_WIN}/publish"
[[ -d "$GUI_PUB" ]] || die "Windows GUI publish folder not found: $GUI_PUB"

# Stage files for installer (you can add CLI or extras here if desired)
STAGE="$BUILDDIR/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
rsync -a "$GUI_PUB/" "$STAGE/"

# ───────────────────────────────
# Run NSIS
# ───────────────────────────────
NSI="$ROOT/build/package/installer.nsi"   # (your corrected path)
[[ -f "$NSI" ]] || die "Missing NSIS script: $NSI"

OUT_EXE="$OUTDIR/WPStallman-${APP_VERSION}-setup-win-x64.exe"
note "Building NSIS → $OUT_EXE"

makensis -V4 -NOCD \
  -DAPP_NAME="$APP_NAME" \
  -DAPP_ID="$APP_ID" \
  -DCOMPANY_NAME="$COMPANY_NAME" \
  -DAPP_VERSION="$APP_VERSION" \
  -DVI_VERSION="$VI_VERSION" \
  -DAPP_STAGE="$STAGE" \
  -DOUT_EXE="$OUT_EXE" \
  "$NSI" > "$BUILDDIR/makensis.log"

note "NSIS built: $OUT_EXE"

