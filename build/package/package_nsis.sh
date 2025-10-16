#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# Load release metadata (dotenv)
# ──────────────────────────────────────────────────────────────
PROJECT_ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || realpath "$(dirname "$0")/../..")}"
META_FILE="${META_FILE:-${PROJECT_ROOT}/build/package/release.meta}"
if [[ -f "$META_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$META_FILE"
  set +a
else
  echo "[WARN] No metadata file at ${META_FILE}; using script defaults."
fi

# ──────────────────────────────────────────────────────────────
# Pretty logging + guards
# ──────────────────────────────────────────────────────────────
note(){ printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[WARN]\033[0m %s\n" "$*" >&2; }
die(){  printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; exit 1; }

require_vars() {
  local missing=0
  for v in "$@"; do
    if [[ -z "${!v:-}" ]]; then
      echo "[ERR ] Missing required metadata: $v" >&2
      missing=1
    fi
  done
  (( missing == 0 )) || exit 1
}

# ──────────────────────────────────────────────────────────────
# Inputs from release_all.sh
# ──────────────────────────────────────────────────────────────
: "${WIN_MODERN_SRC:=}"     # src/WPStallman.GUI.Modern/bin/.../publish (optional)
: "${WIN_LEGACY_SRC:=}"     # src/WPStallman.GUI.Legacy/bin/.../publish (optional)
: "${WIN_LAUNCHER_SRC:=}"   # src/WPStallman.Launcher/bin/.../publish (recommended)

# Read version (prefer env from release_all)
resolve_version_from_props() {
  local props="${PROJECT_ROOT}/Directory.Build.props"
  [[ -f "$props" ]] || { echo ""; return; }
  grep -oP '(?<=<Version>).*?(?=</Version>)' "$props" | head -n1
}
APP_VERSION="${APP_VERSION:-$(resolve_version_from_props)}"
[[ -n "${APP_VERSION}" ]] || die "APP_VERSION is not set and could not be resolved."

# Company/product defaults from release.meta
: "${APP_NAME:=W.P. Stallman}"
: "${APP_ID:=com.wpstallman.app}"
: "${PUBLISHER_NAME:=Left Hand Enterprises, LLC}"
: "${HOMEPAGE_URL:=https://example.com}"
: "${NSIS_COMPANY_NAME:=${PUBLISHER_NAME}}"
: "${NSIS_PRODUCT_NAME:=${APP_NAME}}"
: "${NSIS_URL:=${HOMEPAGE_URL}}"
: "${NSIS_GUID:={FAD6F1E7-1C1F-4E16-9F5B-8C6A0C13A2A1}}"

# Paths
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${PROJECT_ROOT}/artifacts}"
OUTDIR="${OUTDIR:-${ARTIFACTS_DIR}/packages}"
BUILDDIR="${BUILDDIR:-${ARTIFACTS_DIR}/build/nsis}"
STAGE="${BUILDDIR}/stage"
mkdir -p "${OUTDIR}" "${BUILDDIR}"

# NSIS script
NSI="${NSI:-${PROJECT_ROOT}/build/package/installer.nsi}"
[[ -f "$NSI" ]] || die "Missing NSIS script: $NSI"

# Ensure makensis
command -v makensis >/dev/null 2>&1 || die "makensis not found. Install NSIS (ex: sudo apt install nsis)."

note "Version: ${APP_VERSION}"

# ──────────────────────────────────────────────────────────────
# Validate inputs
# ──────────────────────────────────────────────────────────────
if [[ -z "${WIN_MODERN_SRC}" && -z "${WIN_LEGACY_SRC}" && -z "${WIN_LAUNCHER_SRC}" ]]; then
  die "No Windows payloads provided. Set WIN_MODERN_SRC and/or WIN_LEGACY_SRC and WIN_LAUNCHER_SRC."
fi
[[ -z "${WIN_MODERN_SRC}"   || -d "${WIN_MODERN_SRC}"   ]] || die "WIN_MODERN_SRC not found: ${WIN_MODERN_SRC}"
[[ -z "${WIN_LEGACY_SRC}"   || -d "${WIN_LEGACY_SRC}"   ]] || die "WIN_LEGACY_SRC not found: ${WIN_LEGACY_SRC}"
[[ -z "${WIN_LAUNCHER_SRC}" || -d "${WIN_LAUNCHER_SRC}" ]] || die "WIN_LAUNCHER_SRC not found: ${WIN_LAUNCHER_SRC}"

# ──────────────────────────────────────────────────────────────
# Stage files for installer
# Layout:
#   stage/
#     WPStallman.Launcher.exe   (if provided)
#     gtk4.1/                   (Modern payload)
#     gtk4.0/                   (Legacy payload)
#     LICENSE.txt (optional)
# ──────────────────────────────────────────────────────────────
rm -rf "${STAGE}"
mkdir -p "${STAGE}"

# Launcher
if [[ -n "${WIN_LAUNCHER_SRC}" ]]; then
  launcher_exe=""
  if compgen -G "${WIN_LAUNCHER_SRC}/WPStallman.Launcher.exe" > /dev/null; then
    launcher_exe="${WIN_LAUNCHER_SRC}/WPStallman.Launcher.exe"
  else
    launcher_exe="$(find "${WIN_LAUNCHER_SRC}" -maxdepth 1 -type f -iname '*.exe' | head -n1 || true)"
  fi
  if [[ -n "${launcher_exe}" ]]; then
    note "Including launcher: $(basename "${launcher_exe}")"
    install -m 0644 "${launcher_exe}" "${STAGE}/WPStallman.Launcher.exe"
    shopt -s nullglob
    for n in "${WIN_LAUNCHER_SRC}"/*.dll; do cp -a "$n" "${STAGE}/"; done
    shopt -u nullglob
  else
    warn "No .exe found in WIN_LAUNCHER_SRC; installer will not include a launcher."
  fi
fi

# Modern payload
if [[ -n "${WIN_MODERN_SRC}" ]]; then
  note "Staging Modern payload → gtk4.1/"
  mkdir -p "${STAGE}/gtk4.1"
  rsync -a --delete "${WIN_MODERN_SRC}/" "${STAGE}/gtk4.1/"
fi

# Legacy payload
if [[ -n "${WIN_LEGACY_SRC}" ]]; then
  note "Staging Legacy payload → gtk4.0/"
  mkdir -p "${STAGE}/gtk4.0"
  rsync -a --delete "${WIN_LEGACY_SRC}/" "${STAGE}/gtk4.0/"
fi

# LICENSE (optional)
if [[ -f "${PROJECT_ROOT}/LICENSE" ]]; then
  cp -a "${PROJECT_ROOT}/LICENSE" "${STAGE}/LICENSE.txt"
elif [[ -f "${PROJECT_ROOT}/LICENSE.txt" ]]; then
  cp -a "${PROJECT_ROOT}/LICENSE.txt" "${STAGE}/LICENSE.txt"
fi

# ──────────────────────────────────────────────────────────────
# Generate NSIS meta include (keeps installer.nsi clean)
# ──────────────────────────────────────────────────────────────
META_INC="${BUILDDIR}/nsis-meta.nsi"
cat > "${META_INC}" <<EOF
!define COMPANY_NAME "${NSIS_COMPANY_NAME}"
!define PRODUCT_NAME "${NSIS_PRODUCT_NAME}"
!define PUBLISHER_URL "${NSIS_URL}"
!define PRODUCT_GUID "${NSIS_GUID}"
!define PRODUCT_VERSION "${APP_VERSION}"
!define APP_ID "${APP_ID}"
EOF

# Also compute VIProductVersion (must be 4-part numeric)
VI_VERSION="$(echo "$APP_VERSION" | sed 's/[^0-9.].*$//' | awk -F. '{printf "%d.%d.%d.%d", $1,$2,$3, ($4==""?0:$4)}')"
[[ -n "$VI_VERSION" ]] || VI_VERSION="1.0.0.0"

# ──────────────────────────────────────────────────────────────
# Run NSIS
# ──────────────────────────────────────────────────────────────
OUT_EXE="${OUTDIR}/WPStallman-${APP_VERSION}-setup-win-x64.exe"
note "Building NSIS → $OUT_EXE"

makensis -V4 -NOCD \
  -DINCLUDE_META="${META_INC}" \
  -DAPP_STAGE="${STAGE}" \
  -DOUT_EXE="${OUT_EXE}" \
  -DVI_VERSION="${VI_VERSION}" \
  "${NSI}" > "${BUILDDIR}/makensis.log"

note "NSIS built: ${OUT_EXE}"
