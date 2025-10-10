#!/usr/bin/env bash
set -euo pipefail

# ───────────────────────────────
# Pretty logging
# ───────────────────────────────
note() { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*" >&2; }
die()  { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; exit 1; }

# ───────────────────────────────
# Repo layout (adjust if needed)
# ───────────────────────────────
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT"

: "${GUI_CSPROJ:=src/WPStallman.GUI/WPStallman.GUI.csproj}"
: "${CLI_CSPROJ:=src/WPStallman.CLI/WPStallman.CLI.csproj}"

# Output directories
: "${ARTIFACTS_DIR:=artifacts}"
: "${OUTDIR_PACKAGES:=$ARTIFACTS_DIR/packages}"

mkdir -p "$OUTDIR_PACKAGES"

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

# Optional suffix to tag artifacts (e.g., -gtk4.0 or -gtk4.1)
: "${APP_SUFFIX:=}"

# ───────────────────────────────
# Target frameworks & RIDs
# ───────────────────────────────
: "${TFM_LIN_GUI:=net8.0}"
: "${TFM_WIN_GUI:=net8.0-windows}"
: "${TFM_LIN_CLI:=net8.0}"
: "${TFM_WIN_CLI:=net8.0}"

: "${RID_LIN:=linux-x64}"
: "${RID_WIN:=win-x64}"

# ───────────────────────────────
# Build / publish
# ───────────────────────────────
note "Restoring solution"
dotnet restore

note "Publishing GUI + CLI"
# Windows GUI (single-file) — enable Windows targeting pack on non-Windows hosts
dotnet publish "$GUI_CSPROJ" -c Release -r "$RID_WIN" -f "$TFM_WIN_GUI" \
  -p:SelfContained=true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true \
  -p:EnableWindowsTargeting=true

# Linux GUI (non–single-file so libPhotino.Native.so is present)
dotnet publish "$GUI_CSPROJ" -c Release -r "$RID_LIN" -f "$TFM_LIN_GUI" \
  -p:SelfContained=true -p:PublishSingleFile=false -p:IncludeNativeLibrariesForSelfExtract=false

# CLI (Windows)
if [[ -f "$CLI_CSPROJ" ]]; then
  dotnet publish "$CLI_CSPROJ" -c Release -r "$RID_WIN" -f "$TFM_WIN_CLI" \
    -p:SelfContained=true -p:PublishSingleFile=true -p:EnableWindowsTargeting=true || warn "Windows CLI publish skipped/failed"
  # CLI (Linux)
  dotnet publish "$CLI_CSPROJ" -c Release -r "$RID_LIN" -f "$TFM_LIN_CLI" \
    -p:SelfContained=true -p:PublishSingleFile=true || warn "Linux CLI publish skipped/failed"
else
  warn "CLI project not found at $CLI_CSPROJ — skipping CLI publishes"
fi

# ───────────────────────────────
# Locate publish outputs (Linux GUI)
# ───────────────────────────────
PUB_LIN_GUI="$ROOT/src/WPStallman.GUI/bin/Release/${TFM_LIN_GUI}/${RID_LIN}/publish"
[[ -d "$PUB_LIN_GUI" ]] || die "Linux GUI publish folder not found: $PUB_LIN_GUI"

# Ensure Photino native is present in publish (best-effort — your appimage/deb scripts will re-check)
if [[ ! -f "$PUB_LIN_GUI/libPhotino.Native.so" && -f "$ROOT/src/WPStallman.GUI/bin/Release/${TFM_LIN_GUI}/${RID_LIN}/libPhotino.Native.so" ]]; then
  note "Copying libPhotino.Native.so into publish/"
  cp -f "$ROOT/src/WPStallman.GUI/bin/Release/${TFM_LIN_GUI}/${RID_LIN}/libPhotino.Native.so" "$PUB_LIN_GUI/"
fi

# ───────────────────────────────
# Build AppImage + .deb
# ───────────────────────────────
# Pass version & suffix through to sub-scripts; they should already pick up APP_VERSION
export OUTDIR_PACKAGES APP_SUFFIX

if [[ -x "$ROOT/build/package/package_appimage.sh" ]]; then
  note "Building AppImage…"
  "$ROOT/build/package/package_appimage.sh"
  note "AppImage done."
else
  warn "Missing or non-executable: build/package/package_appimage.sh — skipping"
fi

if [[ -x "$ROOT/build/package/package_deb.sh" ]]; then
  note "Building .deb…"
  "$ROOT/build/package/package_deb.sh"
  note ".deb done."
else
  warn "Missing or non-executable: build/package/package_deb.sh — skipping"
fi

# ───────────────────────────────
# Final artifact names (use version + optional suffix)
# (These should match what your sub-scripts produce)
# ───────────────────────────────
note "Artifacts in: $OUTDIR_PACKAGES"
ls -lh "$OUTDIR_PACKAGES" || true

# Suggested canonical names (for reference):
#   WPStallman-${APP_VERSION}-x86_64${APP_SUFFIX}.AppImage
#   wpstallman_${APP_VERSION}_amd64${APP_SUFFIX}.deb

note "Done."
