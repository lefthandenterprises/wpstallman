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
: "${TFM_WIN_CLI:=net8.0}"
: "${RID_WIN:=win-x64}"
: "${WIN_SELF_CONTAINED:=true}"
: "${WIN_SINGLE_FILE:=true}"

# Identity (from meta, with fallbacks)
: "${APP_NAME:=W.P. Stallman}"
: "${APP_ID:=com.wpstallman.app}"
: "${PUBLISHER_NAME:=Left Hand Enterprises, LLC}"
: "${HOMEPAGE_URL:=https://lefthandenterprises.com/projects/wpstallman}"
: "${NSIS_COMPANY_NAME:=${PUBLISHER_NAME}}"
: "${NSIS_PRODUCT_NAME:=${APP_NAME}}"
: "${NSIS_URL:=${HOMEPAGE_URL}}"
: "${NSIS_GUID:={FAD6F1E7-1C1F-4E16-9F5B-8C6A0C13A2A1}}"

: "${NSIS_ICON_FILE:=${PROJECT_ROOT}/WPStallman.Assets/logo/WPS.ico}"
: "${NSIS_UNICON_FILE:=${NSIS_ICON_FILE}}"



# Paths
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${PROJECT_ROOT}/artifacts}"
OUTDIR="${OUTDIR:-${ARTIFACTS_DIR}/packages}"
BUILDDIR="${BUILDDIR:-${ARTIFACTS_DIR}/build/nsis}"
STAGE="${BUILDDIR}/stage"
mkdir -p "$OUTDIR" "$BUILDDIR"

note(){ printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[WARN]\033[0m %s\n" "$*" >&2; }
die(){  printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; exit 1; }

# Resolve version
resolve_version(){ local p="$PROJECT_ROOT/Directory.Build.props"; [[ -f "$p" ]] && grep -oP '(?<=<Version>).*?(?=</Version>)' "$p" | head -n1 || true; }
APP_VERSION="${APP_VERSION:-$(resolve_version)}"; [[ -n "$APP_VERSION" ]] || die "APP_VERSION not found."
note "Version: $APP_VERSION"

# NSIS script
NSI="${NSI:-${PROJECT_ROOT}/build/package/installer.nsi}"
[[ -f "$NSI" ]] || die "Missing NSIS script: $NSI"
command -v makensis >/dev/null 2>&1 || die "makensis not found (sudo apt install nsis)."

# Absolutize project paths
case "$GUI_CSPROJ_WIN" in /*) GUI_PROJ="$GUI_CSPROJ_WIN";; *) GUI_PROJ="$PROJECT_ROOT/$GUI_CSPROJ_WIN";; esac
[[ -f "$GUI_PROJ" ]] || die "Missing Windows GUI project: $GUI_PROJ"
case "${CLI_CSPROJ_WIN:-}" in "") ;; /*) CLI_PROJ="$CLI_CSPROJ_WIN";; *) CLI_PROJ="$PROJECT_ROOT/$CLI_CSPROJ_WIN";; esac
[[ -n "${CLI_PROJ:-}" && ! -f "$CLI_PROJ" ]] && { warn "CLI project not found at $CLI_PROJ; continuing without CLI."; CLI_PROJ=""; }

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
    warn "CLI publish failed; installer will not contain CLI."
  fi
fi

# Stage for NSIS
rm -rf "$STAGE"; mkdir -p "$STAGE"
rsync -a --delete "$GUI_PUB/" "$STAGE/"

if [[ -n "$CLI_PUB" && -d "$CLI_PUB" ]]; then
  mkdir -p "$STAGE/cli"
  rsync -a --delete "$CLI_PUB/" "$STAGE/cli/"
fi

# LICENSE (optional)
if [[ -f "${PROJECT_ROOT}/LICENSE" ]]; then
  cp -a "${PROJECT_ROOT}/LICENSE" "${STAGE}/LICENSE.txt"
elif [[ -f "${PROJECT_ROOT}/LICENSE.txt" ]]; then
  cp -a "${PROJECT_ROOT}/LICENSE.txt" "${STAGE}/LICENSE.txt"
fi

# Inject NSIS meta
META_INC="${BUILDDIR}/nsis-meta.nsi"
cat > "${META_INC}" <<EOF
!define COMPANY_NAME "${NSIS_COMPANY_NAME}"
!define PRODUCT_NAME "${NSIS_PRODUCT_NAME}"
!define PUBLISHER_URL "${NSIS_URL}"
!define PRODUCT_GUID "${NSIS_GUID}"
!define PRODUCT_VERSION "${APP_VERSION}"
!define APP_ID "${APP_ID}"
EOF

# 4-part numeric for VIProductVersion
VI_VERSION="$(echo "$APP_VERSION" | sed 's/[^0-9.].*$//' | awk -F. '{printf "%d.%d.%d.%d", $1,$2,$3, ($4==""?0:$4)}')"
[[ -n "$VI_VERSION" ]] || VI_VERSION="1.0.0.0"

OUT_EXE="${OUTDIR}/WPStallman-${APP_VERSION}-setup-win-x64.exe"
note "Building NSIS → $OUT_EXE"

NSIS_ICON_FILE="${PROJECT_ROOT}/src/WPStallman.Assets/logo/WPS.ico"
NSIS_UNICON_FILE="${PROJECT_ROOT}/src/WPStallman.Assets/logo/WPS.ico"

makensis -V4 -NOCD \
  -DINCLUDE_META="${META_INC}" \
  -DAPP_STAGE="${STAGE}" \
  -DOUT_EXE="${OUT_EXE}" \
  -DVI_VERSION="${VI_VERSION}" \
  -DICON_FILE="${NSIS_ICON_FILE}" \
  -DUNICON_FILE="${NSIS_UNICON_FILE}" \
  "$NSI" > "${BUILDDIR}/makensis.log"


note "NSIS built: ${OUT_EXE}"
