#!/usr/bin/env bash
set -euo pipefail

# ---------- repo root ----------
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

SCRIPTS="$ROOT/build/package"


note() { printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }
die()  { printf "\n\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }

# ---------- config ----------
RID_LIN="${RID_LIN:-linux-x64}"
TFM_LIN="${TFM_LIN:-net8.0}"
CONF="${CONF:-Release}"
LEG_LABEL="${LEG_LABEL:-2.35}"
MOD_LABEL="${MOD_LABEL:-2.39}"

GUI_MOD_PUB="$ROOT/src/WPStallman.GUI.Modern/bin/$CONF/$TFM_LIN/$RID_LIN/publish"
GUI_LEG_PUB="$ROOT/src/WPStallman.GUI.Legacy/bin/$CONF/$TFM_LIN/$RID_LIN/publish"

# Windows publish locations (cross-published on Linux)
RID_WIN="${RID_WIN:-win-x64}"
TFM_WIN="${TFM_WIN:-net8.0-windows}"
GUI_WIN_PUB="$ROOT/src/WPStallman.GUI/bin/$CONF/$TFM_WIN/$RID_WIN/publish"
CLI_WIN_PUB="$ROOT/src/WPStallman.CLI/bin/$CONF/net8.0/$RID_WIN/publish"

# ---------- Linux (modern/legacy) builds & staging ----------
note "Building Linux Modern (glibc $MOD_LABEL) in Docker…"
bash build/package/publish_modern_docker.sh

note "Building Linux Legacy (glibc $LEG_LABEL) in Docker…"
bash build/package/publish_legacy_docker.sh

note "Staging Linux variants to artifacts/dist/…"
bash build/package/stage_variants.sh \
  "$GUI_LEG_PUB" "$GUI_MOD_PUB" \
  "$ROOT/artifacts/dist" "$LEG_LABEL" "$MOD_LABEL" "$RID_LIN"

# ---------- Linux packaging ----------
note "Packaging Linux (Modern)…"
VARIANT="glibc$MOD_LABEL" "$SCRIPTS/package_appimage.sh"
VARIANT="glibc$MOD_LABEL" "$SCRIPTS/package_deb.sh"

note "Packaging Linux (Legacy)…"
VARIANT="glibc$LEG_LABEL" "$SCRIPTS/package_appimage.sh"
VARIANT="glibc$LEG_LABEL" "$SCRIPTS/package_deb.sh"


# Build launcher publish for linux-x64
note "Publishing Launcher (linux-x64)…"
dotnet publish src/WPStallman.Launcher/WPStallman.Launcher.csproj \
  -c Release -f net8.0 -r linux-x64 \
  -p:SelfContained=true \
  -p:PublishSingleFile=true \
  -p:IncludeNativeLibrariesForSelfExtract=true \
  -p:PublishTrimmed=false


# Unified AppImage containing launcher + both variants
note "Packaging Unified AppImage (launcher + legacy + modern)…"
LAUNCHER_DIR="src/WPStallman.Launcher/bin/Release/net8.0/linux-x64/publish" \
build/package/package_appimage_unified.sh

note "Packaging Unified .deb (launcher + legacy + modern)…"
LAUNCHER_DIR="src/WPStallman.Launcher/bin/Release/net8.0/linux-x64/publish" \
build/package/package_deb_unified.sh

# ---------- Windows cross-publish ----------
note "Cross-publishing Windows GUI…"
dotnet publish src/WPStallman.GUI/WPStallman.GUI.csproj \
  -c "$CONF" -f "$TFM_WIN" -r "$RID_WIN" -p:EnableWindowsTargeting=true

note "Cross-publishing Windows CLI…"
dotnet publish src/WPStallman.CLI/WPStallman.CLI.csproj \
  -c "$CONF" -f net8.0 -r "$RID_WIN" -p:EnableWindowsTargeting=true

# sanity checks
[[ -f "$GUI_WIN_PUB/WPStallman.GUI.exe" ]] || die "Windows GUI publish missing: $GUI_WIN_PUB"
[[ -f "$CLI_WIN_PUB/WPStallman.CLI.exe" ]] || die "Windows CLI publish missing: $CLI_WIN_PUB"
[[ -f "$GUI_WIN_PUB/wwwroot/index.html" ]] || die "wwwroot missing in Windows GUI publish"

# ---------- Windows packaging (NSIS + zip) ----------
# deps: nsis (makensis), 7-zip (if your zip script uses it)
if ! command -v makensis >/dev/null 2>&1; then
  note "NSIS 'makensis' not found. Install it (e.g., sudo apt install nsis) then re-run."
  exit 3
fi

note "Packaging Windows (NSIS)…"
GUI_DIR="$GUI_WIN_PUB" CLI_DIR="$CLI_WIN_PUB" "$SCRIPTS/package_nsis.sh"


# If you have a zip packer:
if [[ -x "$SCRIPTS/package_winzip.sh" ]]; then
  note "Packaging Windows (ZIP)…"
  GUI_DIR="$GUI_WIN_PUB" CLI_DIR="$CLI_WIN_PUB" "$SCRIPTS/package_winzip.sh"
fi

note "All done."
