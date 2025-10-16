#!/usr/bin/env bash
set -euo pipefail

# ── Load metadata (dotenv) ────────────────────────────────────
PROJECT_ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || realpath "$(dirname "$0")/../..")}"
META_FILE="${META_FILE:-${PROJECT_ROOT}/build/package/release.meta}"
if [[ -f "$META_FILE" ]]; then set -a; source "$META_FILE"; set +a; else echo "[WARN] No metadata at ${META_FILE}; using defaults."; fi

# Projects (Windows GUI mandatory; CLI optional)
: "${GUI_CSPROJ_WIN:=src/WPStallman.GUI.Windows/WPStallman.GUI.Windows.csproj}"
: "${CLI_CSPROJ_WIN:=src/WPStallman.CLI/WPStallman.CLI.csproj}"

# Windows publish settings
: "${TFM_WIN_GUI:=net8.0-windows}"
: "${TFM_WIN_CLI:=net8.0}"          # CLI is cross-plat; publishing for win-x64
: "${RID_WIN:=win-x64}"
: "${WIN_SELF_CONTAINED:=true}"
: "${WIN_SINGLE_FILE:=true}"

# Output
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${PROJECT_ROOT}/artifacts}"
OUTDIR="${OUTDIR:-${ARTIFACTS_DIR}/packages}"
BUILDDIR="${BUILDDIR:-${ARTIFACTS_DIR}/build/winzip}"
STAGE="${BUILDDIR}/stage"
mkdir -p "$OUTDIR" "$BUILDDIR"

note(){ printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[WARN]\033[0m %s\n" "$*" >&2; }
die(){  printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; exit 1; }

# Resolve version
resolve_version(){ local p="$PROJECT_ROOT/Directory.Build.props"; [[ -f "$p" ]] && grep -oP '(?<=<Version>).*?(?=</Version>)' "$p" | head -n1 || true; }
APP_VERSION="${APP_VERSION:-$(resolve_version)}"; [[ -n "$APP_VERSION" ]] || die "APP_VERSION not found."

# Absolutize project paths
case "$GUI_CSPROJ_WIN" in /*) GUI_PROJ="$GUI_CSPROJ_WIN";; *) GUI_PROJ="$PROJECT_ROOT/$GUI_CSPROJ_WIN";; esac
[[ -f "$GUI_PROJ" ]] || die "Missing Windows GUI project: $GUI_PROJ"
case "${CLI_CSPROJ_WIN:-}" in "") ;; /*) CLI_PROJ="$CLI_CSPROJ_WIN";; *) CLI_PROJ="$PROJECT_ROOT/$CLI_CSPROJ_WIN";; esac
[[ -n "${CLI_PROJ:-}" && ! -f "$CLI_PROJ" ]] && { warn "CLI project not found at $CLI_PROJ; continuing without CLI."; CLI_PROJ=""; }

note "Version: $APP_VERSION"

# Publish GUI
note "Publishing GUI → $TFM_WIN_GUI / $RID_WIN"
dotnet publish "$GUI_PROJ" -c Release -r "$RID_WIN" -f "$TFM_WIN_GUI" \
  -p:SelfContained=$WIN_SELF_CONTAINED -p:PublishSingleFile=$WIN_SINGLE_FILE \
  -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableWindowsTargeting=true

GUI_PUB="$(dirname "$GUI_PROJ")/bin/Release/${TFM_WIN_GUI}/${RID_WIN}/publish"
[[ -d "$GUI_PUB" ]] || die "GUI publish folder missing: $GUI_PUB"

# Publish CLI (optional)
CLI_PUB=""
if [[ -n "${CLI_PROJ:-}" ]]; then
  note "Publishing CLI → $TFM_WIN_CLI / $RID_WIN"
  if dotnet publish "$CLI_PROJ" -c Release -r "$RID_WIN" -f "$TFM_WIN_CLI" \
       -p:SelfContained=$WIN_SELF_CONTAINED -p:PublishSingleFile=$WIN_SINGLE_FILE \
       -p:EnableWindowsTargeting=true; then
    CLI_PUB="$(dirname "$CLI_PROJ")/bin/Release/${TFM_WIN_CLI}/${RID_WIN}/publish"
  else
    warn "CLI publish failed; ZIP will not contain CLI."
  fi
fi

# Stage
rm -rf "$STAGE"; mkdir -p "$STAGE"
rsync -a --delete "$GUI_PUB/" "$STAGE/"

if [[ -n "$CLI_PUB" && -d "$CLI_PUB" ]]; then
  mkdir -p "$STAGE/cli"
  rsync -a --delete "$CLI_PUB/" "$STAGE/cli/"
fi

# Zip
BASENAME="${WINZIP_BASENAME:-WPStallman-Windows}"
ZIP="${OUTDIR}/${BASENAME}-${APP_VERSION}.zip"
( cd "$STAGE" && zip -r -q "$ZIP" . )
note "Windows ZIP built: $ZIP"
