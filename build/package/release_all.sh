#!/usr/bin/env bash
set -euo pipefail

# ===============================
# W.P. Stallman — release_all.sh
# ===============================
# Linux builds run in Docker by default; Windows builds run on host.
# Linux packaging (AppImage, .deb) is independent from Windows.

# --- load release metadata (dotenv) ---
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

# ---- knobs ----
USE_DOCKER="${USE_DOCKER:-1}"               # 1 = build Linux in Docker, 0 = host
BUILD_WINDOWS="${BUILD_WINDOWS:-1}"         # 1 = also build Windows artifacts
BUILD_WINDOWS_NSIS="${BUILD_WINDOWS_NSIS:-1}"
BUILD_WINDOWS_ZIP="${BUILD_WINDOWS_ZIP:-1}"
STRICT_WINDOWS="${STRICT_WINDOWS:-0}"       # 1 = Windows failures abort script

# Containers (tune if needed)
DOCKER_IMAGE_NOBLE="${DOCKER_IMAGE_NOBLE:-mcr.microsoft.com/dotnet/sdk:8.0-noble}"
DOCKER_IMAGE_JAMMY="${DOCKER_IMAGE_JAMMY:-mcr.microsoft.com/dotnet/sdk:8.0-jammy}"
DOCKER_IMG_MODERN="${DOCKER_IMG_MODERN:-$DOCKER_IMAGE_NOBLE}"    # WebKitGTK 4.1 era
DOCKER_IMG_LEGACY="${DOCKER_IMG_LEGACY:-$DOCKER_IMAGE_JAMMY}"    # WebKitGTK 4.0 era
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

# ---- flags for dotnet publish ----
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

# ---- helpers ----
# returns 0 if the .csproj supports the given TFM (e.g., net8.0-windows)
supports_tfm() {
  local csproj="$1" tfm="$2"
  # Try to read TargetFrameworks/TargetFramework quickly
  local tfms
  tfms="$(grep -Eo '<TargetFrameworks?>[^<]+' "$csproj" 2>/dev/null | sed -E 's/.*>(.*)$/\1/' | tr ';' '\n' | tr -d '[:space:]' || true)"
  [[ -n "$tfms" ]] && grep -qx "$tfm" <<<"$tfms"
}

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

  local work_in="/work"
  local proj_in="${proj_abs/#$PROJECT_ROOT/$work_in}"

  # writable fake HOME inside repo mount
  local home_host="${PROJECT_ROOT}/.dockersdk_home"
  mkdir -p "${home_host}/.nuget/packages" "${home_host}/.cache"

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

# ---- Linux-only packaging (never touches Windows) ----
package_linux() {
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

  # ---- AppImage (unified) ----
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

  # ---- .deb (unified) ----
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
}

# ---- Optional Windows packaging (won't block Linux unless STRICT_WINDOWS=1) ----
package_windows() {
  echo "==> Publishing Windows payloads (Modern, Legacy, Launcher)…"

  local build_modern=0 build_legacy=0 build_launcher=0

  if supports_tfm "${PROJ_MODERN}" "net8.0-windows";   then build_modern=1; else echo "[INFO] Modern does not target net8.0-windows — skipping."; fi
  if supports_tfm "${PROJ_LEGACY}" "net8.0-windows";   then build_legacy=1; else echo "[INFO] Legacy does not target net8.0-windows — skipping."; fi
  if supports_tfm "${PROJ_LAUNCHER}" "net8.0-windows"; then build_launcher=1; else echo "[INFO] Launcher does not target net8.0-windows — skipping."; fi

  if (( build_modern == 0 && build_legacy == 0 && build_launcher == 0 )); then
    echo "[WARN] No projects target net8.0-windows; skipping all Windows packaging."
    return 0
  fi

  # Publish only the projects that support the Windows TFM
  if (( build_modern  )); then publish_windows "${PROJ_MODERN}";  fi
  if (( build_legacy  )); then publish_windows "${PROJ_LEGACY}";  fi
  if (( build_launcher)); then publish_windows "${PROJ_LAUNCHER}"; fi

  # Validate only what we built
  if (( build_modern ));   then check_exists "${PUB_WIN_MODERN}"   "Windows Modern publish dir";   fi
  if (( build_legacy ));   then check_exists "${PUB_WIN_LEGACY}"   "Windows Legacy publish dir";   fi
  if (( build_launcher )); then check_exists "${PUB_WIN_LAUNCHER}" "Windows Launcher publish dir"; fi

  # Export only the built sources for packaging
  if (( build_modern ));   then export WIN_MODERN_SRC="${PUB_WIN_MODERN}";   else unset WIN_MODERN_SRC;   fi
  if (( build_legacy ));   then export WIN_LEGACY_SRC="${PUB_WIN_LEGACY}";   else unset WIN_LEGACY_SRC;   fi
  if (( build_launcher )); then export WIN_LAUNCHER_SRC="${PUB_WIN_LAUNCHER}"; else unset WIN_LAUNCHER_SRC; fi
  export APP_VERSION="${VERSION}"

  # NSIS (requires at least one payload present)
  if [[ "${BUILD_WINDOWS_NSIS}" == "1" && -x "${PKG_NSIS:-/nonexistent}" ]]; then
    if [[ -n "${WIN_MODERN_SRC:-}" || -n "${WIN_LEGACY_SRC:-}" || -n "${WIN_LAUNCHER_SRC:-}" ]]; then
      echo "==> Packaging NSIS (unified)…"
      bash "${PKG_NSIS}"
      echo "✔ NSIS packaging done."
      echo
    else
      echo "[INFO] No Windows payloads to feed NSIS; skipping."
    fi
  else
    echo "[INFO] NSIS packer disabled or not present (${PKG_NSIS}); skip."
  fi

  # Windows ZIP (same condition)
  if [[ "${BUILD_WINDOWS_ZIP}" == "1" && -x "${PKG_WINZIP:-/nonexistent}" ]]; then
    if [[ -n "${WIN_MODERN_SRC:-}" || -n "${WIN_LEGACY_SRC:-}" || -n "${WIN_LAUNCHER_SRC:-}" ]]; then
      echo "==> Packaging Windows ZIP (unified)…"
      bash "${PKG_WINZIP}"
      echo "✔ Windows ZIP packaging done."
      echo
    else
      echo "[INFO] No Windows payloads to zip; skipping."
    fi
  else
    echo "[INFO] Windows ZIP packer disabled or not present (${PKG_WINZIP}); skip."
  fi
}

# ---- drive the flow ----
package_linux

if [[ "${BUILD_WINDOWS}" == "1" ]]; then
  if [[ "${STRICT_WINDOWS}" == "1" ]]; then
    package_windows
  else
    set +e
    package_windows
    win_rc=$?
    set -e
    if (( win_rc != 0 )); then
      echo "[WARN] Windows packaging failed (rc=$win_rc) but STRICT_WINDOWS=0 so continuing."
    fi
  fi
fi

echo "==> All done."
