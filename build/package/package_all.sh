#!/usr/bin/env bash
set -euo pipefail

# =========================
# Repo & project paths
# =========================
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUI_CSPROJ="$ROOT/src/WPStallman.GUI/WPStallman.GUI.csproj"
CLI_CSPROJ="$ROOT/src/WPStallman.CLI/WPStallman.CLI.csproj"

# Granular packagers
PKG_DEB="$ROOT/build/package/package_deb.sh"
PKG_APPIMG="$ROOT/build/package/package_appimage.sh"

# =========================
# App metadata (override via env)
# =========================
: "${VERSION:=1.0.0}"
: "${APP_NAME:=W. P. Stallman}"
: "${APP_ID:=com.wpstallman.app}"

# ----- Variant selection -----
# Examples:
#   VARIANT=glibc2.39 ./package_all.sh
#   VARIANT=glibc2.35 ./package_all.sh
#   VARIANT=current   ./package_all.sh   (uses the symlink)
VARIANT="${VARIANT:-glibc2.39}"          # default = Modern
RID_LIN="${RID_LIN:-linux-x64}"

# Staged GUI dir (can be overridden by GUI_DIR_LIN if you want to bypass staging)
GUI_DIR_LIN="${GUI_DIR_LIN:-$ROOT/artifacts/dist/WPStallman.GUI-${RID_LIN}-${VARIANT}}"



# RIDs / TFMs
RID_WIN="win-x64"
RID_LIN="linux-x64"
: "${TFM_WIN_GUI:=net8.0-windows}"
: "${TFM_LIN_GUI:=net8.0}"
: "${TFM_WIN_CLI:=net8.0}"
: "${TFM_LIN_CLI:=net8.0}"

# Icons (optional)
: "${ICON_PNG_256:=$GUI_DIR_LIN/wwwroot/img/WPS-256.png}"

# Output directory
OUTDIR="$ROOT/artifacts/packages"

note(){ printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }
warn(){ printf "\033[1;33mWARNING:\033[0m %s\n" "$*"; }
die(){  printf "\n\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }

# =========================
# Helpers
# =========================
ensure_photino_so_in_publish() {
  local pub="$1"
  local have_any=0
  [[ -f "$pub/libPhotino.Native.so"     ]] && have_any=1
  [[ -f "$pub/Photino.Native.so"        ]] && have_any=1
  if [[ $have_any -eq 1 ]]; then
    note "Photino native already in publish (one of the names is present)."
    # ensure we have both names (real+symlink) for maximum compatibility
    [[ -f "$pub/libPhotino.Native.so"  && ! -e "$pub/Photino.Native.so" ]] && ln -sf libPhotino.Native.so "$pub/Photino.Native.so"
    [[ -f "$pub/Photino.Native.so"     && ! -e "$pub/libPhotino.Native.so" ]] && ln -sf Photino.Native.so "$pub/libPhotino.Native.so"
    return 0
  fi

  note "Searching for Photino native…"
  local parent cand=""
  parent="$(cd "$pub/.." && pwd)"
  # A) exactly where you found it
  for name in libPhotino.Native.so Photino.Native.so; do
    [[ -z "$cand" && -f "$parent/$name" ]] && cand="$parent/$name"
  done
  # B) inside publish tree
  [[ -z "$cand" ]] && cand="$(find "$pub" -maxdepth 6 -type f -iname '*photino.native*.so' -print -quit 2>/dev/null || true)"
  # C) sibling runtimes
  [[ -z "$cand" ]] && cand="$(find "$parent" -maxdepth 8 -path '*/runtimes/linux-x64/native/*photino.native*.so' -type f -print -quit 2>/dev/null || true)"
  # D) NuGet cache
  if [[ -z "$cand" ]]; then
    local NUPKG="${NUGET_PACKAGES:-$HOME/.nuget/packages}"
    cand="$(find "$NUPKG/photino.native" -path '*/runtimes/linux-x64/native/*photino.native*.so' -type f 2>/dev/null | sort -V | tail -n1 || true)"
  fi

  if [[ -n "$cand" ]]; then
    note "  candidate: $cand"
    cp -f "$cand" "$pub/libPhotino.Native.so"
    ln -sf libPhotino.Native.so "$pub/Photino.Native.so"
    note "Installed Photino native (lib + symlink) in publish/"
    return 0
  fi

  note "DEBUG: couldn’t find it; listing $parent"
  ls -la "$parent" || true
  return 1
}


# =========================
# Build
# =========================
build_all() {
  note "Publishing GUI + CLI (net8.0); Linux GUI is non–single-file"
  # --- GUI ---
  dotnet publish "$GUI_CSPROJ" -c Release -r "$RID_WIN" -f "$TFM_WIN_GUI" \
    -p:SelfContained=true -p:PublishSingleFile=true

  dotnet publish "$GUI_CSPROJ" -c Release -r "$RID_LIN" -f "$TFM_LIN_GUI" \
    -p:SelfContained=true -p:PublishSingleFile=false -p:IncludeNativeLibrariesForSelfExtract=false

  # --- CLI ---
  dotnet publish "$CLI_CSPROJ" -c Release -r "$RID_WIN" -f "$TFM_WIN_CLI" \
    -p:SelfContained=true -p:PublishSingleFile=true

  dotnet publish "$CLI_CSPROJ" -c Release -r "$RID_LIN" -f "$TFM_LIN_CLI" \
    -p:SelfContained=true -p:PublishSingleFile=true
}

# Resolve publish dirs
GUI_DIR_LIN="$ROOT/src/WPStallman.GUI/bin/Release/${TFM_LIN_GUI}/${RID_LIN}/publish"
CLI_DIR_LIN="$ROOT/src/WPStallman.CLI/bin/Release/${TFM_LIN_CLI}/${RID_LIN}/publish"

build_all

# Sanity + self-heal for Photino native
[[ -x "$GUI_DIR_LIN/WPStallman.GUI" ]] || die "Missing GUI binary at $GUI_DIR_LIN/WPStallman.GUI"
[[ -f "$GUI_DIR_LIN/wwwroot/index.html" ]] || die "Missing wwwroot in $GUI_DIR_LIN/wwwroot/index.html"


if ! ensure_photino_so_in_publish "$GUI_DIR_LIN"; then
  die "Missing libPhotino.Native.so in $GUI_DIR_LIN and not found in NuGet cache. Ensure Photino.Native is referenced and publish is non–single-file."
fi

# Ensure shared wwwroot was copied into publish
[[ -f "$GUI_DIR_LIN/wwwroot/index.html" ]] || die "Missing wwwroot in publish: $GUI_DIR_LIN/wwwroot/index.html"


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
  ICON_PNG="$ICON_PNG_256" \
  "$PKG_DEB"
else
  warn "Skipping .deb (wrapper not executable): $PKG_DEB"
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
  CLI_DIR="$CLI_DIR_LIN" \
  ICON_PNG="$ICON_PNG_256" \
  "$PKG_APPIMG"
else
  warn "Skipping AppImage (wrapper not executable): $PKG_APPIMG"
fi

note "All done. Outputs in: $OUTDIR"
