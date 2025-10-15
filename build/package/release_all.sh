#!/usr/bin/env bash
set -euo pipefail

# ===============================
# W.P. Stallman - Unified Release
# Linux builds can run in Docker (default); Windows builds on host.
# ===============================

# --- config ---
USE_DOCKER="${USE_DOCKER:-1}"

# Containers (adjust if you like)
DOCKER_IMAGE_NOBLE="${DOCKER_IMAGE_NOBLE:-mcr.microsoft.com/dotnet/sdk:8.0-noble}"
DOCKER_IMAGE_JAMMY="${DOCKER_IMAGE_JAMMY:-mcr.microsoft.com/dotnet/sdk:8.0-jammy}"
# Which variant uses which image
DOCKER_IMG_MODERN="${DOCKER_IMG_MODERN:-$DOCKER_IMAGE_NOBLE}"  # WebKitGTK 4.1 era
DOCKER_IMG_LEGACY="${DOCKER_IMG_LEGACY:-$DOCKER_IMAGE_JAMMY}"  # WebKitGTK 4.0 era
DOCKER_IMG_LAUNCHER="${DOCKER_IMG_LAUNCHER:-$DOCKER_IMAGE_NOBLE}"

# --- resolve repository root robustly ---
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
if git -C "${SCRIPT_DIR}" rev-parse --show-toplevel >/dev/null 2>&1; then
  PROJECT_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel)"
fi

SRC_DIR="${PROJECT_ROOT}/src"
BUILD_DIR="${PROJECT_ROOT}/build"
PKG_DIR="${BUILD_DIR}/package"

echo "PROJECT_ROOT: ${PROJECT_ROOT}"

# ---- projects (auto-resolve .csproj paths; safe with set -e) ----
req() { [[ -f "$1" ]] || { echo "[ERROR] Missing: $1" >&2; exit 1; }; }

MODERN_DIR="${SRC_DIR}/WPStallman.GUI.Modern"
LEGACY_DIR="${SRC_DIR}/WPStallman.GUI.Legacy"
LAUNCHER_DIR="${SRC_DIR}/WPStallman.Launcher"

PROJ_MODERN="$(find "$MODERN_DIR"    -maxdepth 1 -type f -name '*.csproj' -print -quit)"
PROJ_LEGACY="$(find "$LEGACY_DIR"    -maxdepth 1 -type f -name '*.csproj' -print -quit)"
PROJ_LAUNCHER="$(find "$LAUNCHER_DIR" -maxdepth 1 -type f -name '*.csproj' -print -quit)"

req "${PROJ_MODERN}"; req "${PROJ_LEGACY}"; req "${PROJ_LAUNCHER}"

echo "Resolved projects:"
echo "  Modern   -> ${PROJ_MODERN}"
echo "  Legacy   -> ${PROJ_LEGACY}"
echo "  Launcher -> ${PROJ_LAUNCHER}"
echo

# ---- frameworks & RIDs ----
TFM_LINUX="net8.0"
RID_LINUX="linux-x64"
TFM_WIN="net8.0-windows"
RID_WIN="win-x64"

# ---- publish output dirs (per project folder) ----
PUB_LINUX_MODERN="${MODERN_DIR}/bin/Release/${TFM_LINUX}/${RID_LINUX}/publish"
PUB_LINUX_LEGACY="${LEGACY_DIR}/bin/Release/${TFM_LINUX}/${RID_LINUX}/publish"
PUB_LINUX_LAUNCHER="${LAUNCHER_DIR}/bin/Release/${TFM_LINUX}/${RID_LINUX}/publish"

PUB_WIN_MODERN="${MODERN_DIR}/bin/Release/${TFM_WIN}/${RID_WIN}/publish"
PUB_WIN_LEGACY="${LEGACY_DIR}/bin/Release/${TFM_WIN}/${RID_WIN}/publish"
PUB_WIN_LAUNCHER="${LAUNCHER_DIR}/bin/Release/${TFM_WIN}/${RID_WIN}/publish"

# ---- package scripts ----
PKG_APPIMAGE="${PKG_DIR}/package_appimage_unified.sh"
PKG_DEB="${PKG_DIR}/package_deb_unified.sh"
PKG_NSIS="${PKG_DIR}/package_nsis.sh"
PKG_WINZIP="${PKG_DIR}/package_winzip.sh"

# ---- version resolution ----
VERSION="${VERSION:-}"
if [[ -z "${VERSION}" ]] && [[ -f "${PROJECT_ROOT}/VERSION.txt" ]]; then
  VERSION="$(tr -d ' \t\n\r' < "${PROJECT_ROOT}/VERSION.txt")"
fi
if [[ -z "${VERSION}" ]]; then
  if git -C "${PROJECT_ROOT}" describe --tags --abbrev=0 >/dev/null 2>&1; then
    VERSION="$(git -C "${PROJECT_ROOT}" describe --tags --abbrev=0)"
  else
    VERSION="0.0.0-dev"
  fi
fi
echo "Version: ${VERSION}"
echo

# ---- helpers ----
dotnet_flags_linux=(
  -c Release -f "${TFM_LINUX}" -r "${RID_LINUX}"
  --self-contained true
  -p:PublishSingleFile=false
  -p:PublishTrimmed=false
  -p:DebugType=None
  -p:StripSymbols=true
)
dotnet_flags_win=(
  -c Release -f "${TFM_WIN}" -r "${RID_WIN}"
  --self-contained true
  -p:PublishSingleFile=false
  -p:PublishTrimmed=false
)

check_exists() { [[ -e "$1" ]] || { echo "[ERROR] Missing $2 at: $1" >&2; exit 1; }; }

print_sonames_hint() {
  local so="$1"
  if command -v ldd >/dev/null 2>&1 && [[ -f "$so" ]]; then
    echo "   · $(basename "$so") links:"
    ldd "$so" | grep -E 'webkit|javascriptcore' || true
  fi
}

docker_publish() {
  local image="$1"; shift
  local proj_abs="$1"; shift
  local -a pub_flags=( "$@" )

  local work_in="/work"                               # mount point in container
  local proj_in="${proj_abs/#$PROJECT_ROOT/$work_in}" # project path in container

  # make a fake HOME inside the mounted repo so it's writable by your UID
  local home_host="${PROJECT_ROOT}/.dockersdk_home"
  mkdir -p "${home_host}/.nuget/packages"

  echo "-- docker publish: ${proj_abs}"
  docker run --rm \
    -u "$(id -u):$(id -g)" \
    -e HOME="${work_in}/.dockersdk_home" \
    -e DOTNET_CLI_HOME="${work_in}/.dockersdk_home" \
    -e NUGET_PACKAGES="${work_in}/.dockersdk_home/.nuget/packages" \
    -e XDG_CACHE_HOME="${work_in}/.dockersdk_home/.cache" \
    -e DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 \
    -e DOTNET_NOLOGO=1 \
    -v "${PROJECT_ROOT}:${work_in}" \
    -w "${work_in}" \
    "${image}" \
    bash -lc "mkdir -p '${work_in}/.dockersdk_home/.nuget/packages' '${work_in}/.dockersdk_home/.cache' && dotnet publish '${proj_in}' ${pub_flags[*]}"
}



host_publish() {
  local proj="$1"; shift
  local -a pub_flags=( "$@" )
  echo "-- host publish: ${proj}"
  dotnet publish "${proj}" "${pub_flags[@]}"
}

publish_linux() {
  local proj="$1" image="$2"
  if [[ "${USE_DOCKER}" == "1" ]]; then
    docker_publish "${image}" "${proj}" "${dotnet_flags_linux[@]}"
  else
    host_publish "${proj}" "${dotnet_flags_linux[@]}"
  fi
}

publish_windows() {
  local proj="$1"
  host_publish "${proj}" "${dotnet_flags_win[@]}"
}

# -------- Linux: build Modern + Legacy + Launcher (Docker by default) --------
echo "==> Publishing Linux payloads (Modern, Legacy, Launcher)…"
dotnet nuget locals all --clear || true

publish_linux "${PROJ_MODERN}"   "${DOCKER_IMG_MODERN}"
publish_linux "${PROJ_LEGACY}"   "${DOCKER_IMG_LEGACY}"
publish_linux "${PROJ_LAUNCHER}" "${DOCKER_IMG_LAUNCHER}"

check_exists "${PUB_LINUX_MODERN}"   "Modern publish dir"
check_exists "${PUB_LINUX_LEGACY}"   "Legacy publish dir"
check_exists "${PUB_LINUX_LAUNCHER}" "Launcher publish dir"

echo "   Linux Modern output:  ${PUB_LINUX_MODERN}"
print_sonames_hint "${PUB_LINUX_MODERN}/Photino.Native.so"
echo "   Linux Legacy output:  ${PUB_LINUX_LEGACY}"
print_sonames_hint "${PUB_LINUX_LEGACY}/Photino.Native.so"
echo "   Linux Launcher output:${PUB_LINUX_LAUNCHER}"
echo

# -------- AppImage (unified) --------
if [[ -x "${PKG_APPIMAGE}" ]]; then
  echo "==> Packaging AppImage (unified)…"
  export GTK41_SRC="${PUB_LINUX_MODERN}"
  export GTK40_SRC="${PUB_LINUX_LEGACY}"
  export LAUNCHER_SRC="${PUB_LINUX_LAUNCHER}"
  export APP_VERSION="${VERSION}"
  bash "${PKG_APPIMAGE}"
  echo "✔ AppImage packaging done."
  echo
else
  echo "[WARN] AppImage packer not found/executable at ${PKG_APPIMAGE} – skipping."
fi

# -------- .deb (unified) --------
if [[ -x "${PKG_DEB:-/nonexistent}" ]]; then
  echo "==> Packaging .deb (unified)…"
  export GTK41_SRC="${PUB_LINUX_MODERN}"
  export GTK40_SRC="${PUB_LINUX_LEGACY}"
  export LAUNCHER_SRC="${PUB_LINUX_LAUNCHER}"
  export APP_VERSION="${VERSION}"
  bash "${PKG_DEB}"
  echo "✔ .deb packaging done."
  echo
else
  echo "[INFO] Debian packer script not present (${PKG_DEB}); skip."
fi

# -------- Windows: build Modern + Legacy + Launcher on host --------
if [[ "${BUILD_WINDOWS:-1}" == "1" ]]; then
  echo "==> Publishing Windows payloads (Modern, Legacy, Launcher)…"
  publish_windows "${PROJ_MODERN}"
  publish_windows "${PROJ_LEGACY}"
  publish_windows "${PROJ_LAUNCHER}"

  check_exists "${PUB_WIN_MODERN}"   "Windows Modern publish dir"
  check_exists "${PUB_WIN_LEGACY}"   "Windows Legacy publish dir"
  check_exists "${PUB_WIN_LAUNCHER}" "Windows Launcher publish dir"

  # NSIS installer (unified)
  if [[ -x "${PKG_NSIS:-/nonexistent}" ]]; then
    echo "==> Packaging NSIS (unified)…"
    export WIN_MODERN_SRC="${PUB_WIN_MODERN}"
    export WIN_LEGACY_SRC="${PUB_WIN_LEGACY}"
    export WIN_LAUNCHER_SRC="${PUB_WIN_LAUNCHER}"
    export APP_VERSION="${VERSION}"
    bash "${PKG_NSIS}"
    echo "✔ NSIS packaging done."
    echo
  else
    echo "[INFO] NSIS packer script not present (${PKG_NSIS}); skip."
  fi

  # Windows ZIP (unified)
  if [[ -x "${PKG_WINZIP:-/nonexistent}" ]]; then
    echo "==> Packaging Windows ZIP (unified)…"
    export WIN_MODERN_SRC="${PUB_WIN_MODERN}"
    export WIN_LEGACY_SRC="${PUB_WIN_LEGACY}"
    export WIN_LAUNCHER_SRC="${PUB_WIN_LAUNCHER}"
    export APP_VERSION="${VERSION}"
    bash "${PKG_WINZIP}"
    echo "✔ Windows ZIP packaging done."
    echo
  else
    echo "[INFO] Windows ZIP packer not present (${PKG_WINZIP}); skip."
  fi
fi

echo "==> All done."
