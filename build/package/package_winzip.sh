#!/usr/bin/env bash
set -euo pipefail

# ───────────────────────────────
# Pretty logging
# ───────────────────────────────
note() { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*" >&2; }
die()  { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; exit 1; }

# ───────────────────────────────
# Repo layout & inputs (adjust if needed)
# ───────────────────────────────
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT"

: "${GUI_CSPROJ:=src/WPStallman.GUI/WPStallman.GUI.csproj}"
: "${CLI_CSPROJ:=src/WPStallman.CLI/WPStallman.CLI.csproj}"

# Windows targets
: "${TFM_WIN_GUI:=net8.0-windows}"
: "${TFM_WIN_CLI:=net8.0}"
: "${RID_WIN:=win-x64}"

# Output dirs
: "${ARTIFACTS_DIR:=artifacts}"
: "${BUILDDIR:=$ARTIFACTS_DIR/build/winzip}"
: "${OUTDIR:=$ARTIFACTS_DIR/packages}"
mkdir -p "$BUILDDIR" "$OUTDIR"

# Optional suffix for filename (e.g., -portable, -beta)
: "${APP_SUFFIX:=}"

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

# ───────────────────────────────
# Build / publish (Windows, single-file GUI; CLI optional)
# ───────────────────────────────
note "Restoring…"
dotnet restore

note "Publishing Windows GUI → $TFM_WIN_GUI / $RID_WIN"
dotnet publish "$GUI_CSPROJ" -c Release -r "$RID_WIN" -f "$TFM_WIN_GUI" \
  -p:SelfContained=true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true \
  -p:EnableWindowsTargeting=true

GUI_PUB="$ROOT/src/$(basename "${GUI_CSPROJ%/*.csproj}")/bin/Release/${TFM_WIN_GUI}/${RID_WIN}/publish"
[[ -d "$GUI_PUB" ]] || die "Windows GUI publish folder not found: $GUI_PUB"

CLI_PUB=""
if [[ -f "$CLI_CSPROJ" ]]; then
  note "Publishing Windows CLI → $TFM_WIN_CLI / $RID_WIN"
  if dotnet publish "$CLI_CSPROJ" -c Release -r "$RID_WIN" -f "$TFM_WIN_CLI" \
       -p:SelfContained=true -p:PublishSingleFile=true -p:EnableWindowsTargeting=true; then
    CLI_PUB="$ROOT/src/$(basename "${CLI_CSPROJ%/*.csproj}")/bin/Release/${TFM_WIN_CLI}/${RID_WIN}/publish"
  else
    warn "Windows CLI publish failed or project missing; continuing without CLI."
  fi
fi

# ───────────────────────────────
# Stage files for zipping
# ───────────────────────────────
STAGE="$BUILDDIR/WPStallman-${APP_VERSION}-win-x64"
rm -rf "$STAGE"
mkdir -p "$STAGE"

note "Staging GUI payload…"
rsync -a "$GUI_PUB/" "$STAGE/"

if [[ -n "$CLI_PUB" && -d "$CLI_PUB" ]]; then
  note "Adding CLI payload…"
  mkdir -p "$STAGE/cli"
  rsync -a "$CLI_PUB/" "$STAGE/cli/"
fi

# Optional readme
cat > "$STAGE/README.txt" <<EOF
W. P. Stallman (Windows Portable)
Version: ${APP_VERSION}

Contents:
- GUI:   WPStallman.GUI.exe (self-contained, portable)
- CLI:   (optional) in .\cli\

Notes:
- Requires Windows 10/11 x64.
- Extract and run WPStallman.GUI.exe
EOF

# ───────────────────────────────
# Zip it
# ───────────────────────────────
ZIP_FILE="$OUTDIR/WPStallman-${APP_VERSION}-win-x64${APP_SUFFIX}.zip"
rm -f "$ZIP_FILE"

note "Creating zip → $ZIP_FILE"
if command -v 7z >/dev/null 2>&1; then
  (cd "$BUILDDIR" && 7z a -tzip -mx=9 "$ZIP_FILE" "$(basename "$STAGE")" >/dev/null)
elif command -v zip >/dev/null 2>&1; then
  (cd "$BUILDDIR" && zip -r -9 "$ZIP_FILE" "$(basename "$STAGE")" >/dev/null)
else
  die "Neither 7z nor zip found. Install p7zip-full or zip."
fi

note "Windows zip built: $ZIP_FILE"
