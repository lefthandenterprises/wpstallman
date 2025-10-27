#!/usr/bin/env bash
set -euo pipefail

note(){ printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[WARN]\033[0m %s\n" "$*" >&2; }
die(){  printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; exit 1; }

# Resolve repo root and move there
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || realpath "$(dirname "$0")/../..")}"
cd "$ROOT"

command -v zip >/dev/null 2>&1 || die "'zip' utility not found. On Debian/Ubuntu: sudo apt-get install zip"
command -v realpath >/dev/null 2>&1 || warn "'realpath' not found; using relative paths where needed."

META_FILE="${META_FILE:-$ROOT/build/package/release.meta}"
if [[ -f "$META_FILE" ]]; then set -a; # export all
  # shellcheck source=/dev/null
  source "$META_FILE"
  set +a
else
  warn "No release.meta at $META_FILE; using defaults."
fi

# Default project paths (can be overridden in release.meta)
: "${GUI_CSPROJ_WIN:=src/WPStallman.GUI.Windows/WPStallman.GUI.Windows.csproj}"
: "${CLI_CSPROJ_WIN:=src/WPStallman.CLI/WPStallman.CLI.csproj}"

# Windows publish settings
: "${TFM_WIN_GUI:=net8.0-windows}"
: "${TFM_WIN_CLI:=net8.0}"
: "${RID_WIN:=win-x64}"
: "${WIN_SELF_CONTAINED:=true}"
: "${WIN_SINGLE_FILE:=true}"

# Version (prefer release.meta APP_VERSION; else Directory.Build.props <Version>)
APP_VERSION="${APP_VERSION:-$(grep -m1 -oP '(?<=<Version>)[^<]+' "$ROOT/Directory.Build.props" 2>/dev/null || echo 0.0.0)}"

# Output and staging directories (make both absolute for safety)
OUTDIR_REL="${OUTDIR:-artifacts/packages/zip}"
STAGE_REL="${STAGE:-artifacts/tmp/zip-stage}"

if command -v realpath >/dev/null 2>&1; then
  OUTDIR="$(realpath -m "$OUTDIR_REL")"
  STAGE="$(realpath -m "$STAGE_REL")"
else
  OUTDIR="$OUTDIR_REL"
  STAGE="$STAGE_REL"
fi

mkdir -p "$OUTDIR" "$STAGE"

publish_one(){
  local csproj="$1"
  local subdir="$2"
  [[ -f "$csproj" ]] || die "Missing project: $csproj"
  dotnet publish "$csproj" -c Release -r "$RID_WIN" -f "${3:-$TFM_WIN_GUI}" \
    -p:SelfContained="${4:-$WIN_SELF_CONTAINED}" -p:PublishSingleFile="${5:-$WIN_SINGLE_FILE}" \
    -p:DebugType=None -p:DebugSymbols=false -p:IncludeNativeLibrariesForSelfExtract=true \
    -o "$STAGE/$subdir"
}

note "Publishing Windows GUI → $GUI_CSPROJ_WIN"
publish_one "$GUI_CSPROJ_WIN" "gui" "$TFM_WIN_GUI" "$WIN_SELF_CONTAINED" "$WIN_SINGLE_FILE"

if [[ -f "$CLI_CSPROJ_WIN" ]]; then
  note "Publishing Windows CLI → $CLI_CSPROJ_WIN"
  publish_one "$CLI_CSPROJ_WIN" "cli" "$TFM_WIN_CLI" "$WIN_SELF_CONTAINED" "$WIN_SINGLE_FILE"
else
  warn "CLI project not found at $CLI_CSPROJ_WIN (skipping)."
fi

# Compose the ZIP name and ensure its parent exists
BASENAME="${WINZIP_BASENAME:-WPStallman-Windows}"
ZIP="${OUTDIR}/${BASENAME}-${APP_VERSION}.zip"
mkdir -p "$(dirname "$ZIP")"

# Diagnostics before zipping
note "Repo ROOT     : $ROOT"
note "Staging (abs) : $STAGE"
note "Out dir (abs) : $OUTDIR"
note "ZIP (abs)     : $ZIP"
note "pwd           : $(pwd)"

# Confirm write permissions
touch "$ZIP" 2>/dev/null || die "Cannot create file at $ZIP (permission issue?)."
rm -f "$ZIP"

note "Staging directory tree:"
if command -v tree >/dev/null 2>&1; then
  tree -a "$STAGE" || true
else
  # Fallback to recursive ls
  find "$STAGE" -printf "%y %p\n" | sed 's/^/  /'
fi

# Perform the zip from inside the staging directory with an absolute ZIP path
note "Creating ZIP → $ZIP"
(
  cd "$STAGE"
  set -x
  zip -r -v -T "$ZIP" .
  set +x
)

note "ZIP created: $ZIP"

# Optional listing
note "ZIP contents (short):"
unzip -l "$ZIP" | sed 's/^/  /'