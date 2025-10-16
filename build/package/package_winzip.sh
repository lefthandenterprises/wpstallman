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

# Pretty logging
note() { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*" >&2; }
die()  { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; exit 1; }

# ──────────────────────────────────────────────────────────────
# Inputs from release_all.sh (Windows publishes)
# ──────────────────────────────────────────────────────────────
: "${WIN_MODERN_SRC:=}"    # e.g., src/WPStallman.GUI.Modern/bin/Release/net8.0-windows/win-x64/publish
: "${WIN_LEGACY_SRC:=}"    # e.g., src/WPStallman.GUI.Legacy/bin/Release/net8.0-windows/win-x64/publish
: "${WIN_LAUNCHER_SRC:=}"  # e.g., src/WPStallman.Launcher/bin/Release/net8.0-windows/win-x64/publish

# Version: prefer env (release_all sets APP_VERSION); fall back to props
resolve_version_from_props() {
  local props="${PROJECT_ROOT}/Directory.Build.props"
  [[ -f "$props" ]] || { echo ""; return; }
  grep -oP '(?<=<Version>).*?(?=</Version>)' "$props" | head -n1
}
APP_VERSION="${APP_VERSION:-$(resolve_version_from_props)}"
[[ -n "${APP_VERSION}" ]] || die "APP_VERSION is not set and could not be resolved."

# Metadata defaults
: "${APP_NAME:=W.P. Stallman}"
: "${APP_ID:=com.wpstallman.app}"
: "${WINZIP_BASENAME:=WPStallman-Windows}"
: "${HOMEPAGE_URL:=https://example.com}"
: "${PUBLISHER_NAME:=Left Hand Enterprises, LLC}"

# Layout & outputs
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${PROJECT_ROOT}/artifacts}"
OUTDIR="${OUTDIR:-${ARTIFACTS_DIR}/packages}"
WORKDIR="${WORKDIR:-${ARTIFACTS_DIR}/build/winzip}"
STAGE_ROOT="${WORKDIR}/${WINZIP_BASENAME}-${APP_VERSION}"
mkdir -p "${OUTDIR}" "${WORKDIR}"

note "Version: ${APP_VERSION}"
note "Staging to: ${STAGE_ROOT}"

# ──────────────────────────────────────────────────────────────
# Guard: at least one payload is required
# ──────────────────────────────────────────────────────────────
if [[ -z "${WIN_MODERN_SRC}" && -z "${WIN_LEGACY_SRC}" && -z "${WIN_LAUNCHER_SRC}" ]]; then
  die "No Windows payloads provided. Set WIN_MODERN_SRC and/or WIN_LEGACY_SRC and WIN_LAUNCHER_SRC."
fi
[[ -n "${WIN_MODERN_SRC}"   && -d "${WIN_MODERN_SRC}"   ]] || [[ -z "${WIN_MODERN_SRC}"   ]] || die "WIN_MODERN_SRC not found: ${WIN_MODERN_SRC}"
[[ -n "${WIN_LEGACY_SRC}"   && -d "${WIN_LEGACY_SRC}"   ]] || [[ -z "${WIN_LEGACY_SRC}"   ]] || die "WIN_LEGACY_SRC not found: ${WIN_LEGACY_SRC}"
[[ -n "${WIN_LAUNCHER_SRC}" && -d "${WIN_LAUNCHER_SRC}" ]] || [[ -z "${WIN_LAUNCHER_SRC}" ]] || die "WIN_LAUNCHER_SRC not found: ${WIN_LAUNCHER_SRC}"

# Clean stage
rm -rf "${STAGE_ROOT}"
mkdir -p "${STAGE_ROOT}"

# ──────────────────────────────────────────────────────────────
# Stage launcher (root)
# ──────────────────────────────────────────────────────────────
if [[ -n "${WIN_LAUNCHER_SRC}" ]]; then
  # Prefer WPStallman.Launcher.exe; fall back to any *.exe
  launcher_exe=""
  if compgen -G "${WIN_LAUNCHER_SRC}/WPStallman.Launcher.exe" > /dev/null; then
    launcher_exe="${WIN_LAUNCHER_SRC}/WPStallman.Launcher.exe"
  else
    launcher_exe="$(find "${WIN_LAUNCHER_SRC}" -maxdepth 1 -type f -iname '*.exe' | head -n1 || true)"
  fi

  if [[ -n "${launcher_exe}" ]]; then
    note "Copying launcher: $(basename "${launcher_exe}")"
    install -m 0644 "${launcher_exe}" "${STAGE_ROOT}/WPStallman.Launcher.exe"
    # include any native DLLs next to the launcher if present
    shopt -s nullglob
    for n in "${WIN_LAUNCHER_SRC}"/*.dll; do
      cp -a "$n" "${STAGE_ROOT}/"
    done
    shopt -u nullglob
  else
    warn "No launcher .exe found in ${WIN_LAUNCHER_SRC}; ZIP will not include a launcher."
  fi
else
  warn "WIN_LAUNCHER_SRC not set; ZIP will not include a launcher."
fi

# ──────────────────────────────────────────────────────────────
# Stage payloads (Modern/Legacy)
# ──────────────────────────────────────────────────────────────
if [[ -n "${WIN_MODERN_SRC}" ]]; then
  note "Staging Modern → gtk4.1/"
  mkdir -p "${STAGE_ROOT}/gtk4.1"
  rsync -a --delete "${WIN_MODERN_SRC}/" "${STAGE_ROOT}/gtk4.1/"
fi

if [[ -n "${WIN_LEGACY_SRC}" ]]; then
  note "Staging Legacy → gtk4.0/"
  mkdir -p "${STAGE_ROOT}/gtk4.0"
  rsync -a --delete "${WIN_LEGACY_SRC}/" "${STAGE_ROOT}/gtk4.0/"
fi

# ──────────────────────────────────────────────────────────────
# Ancillary files: LICENSE, README
# ──────────────────────────────────────────────────────────────
# Try to include a LICENSE if present in repo
if [[ -f "${PROJECT_ROOT}/LICENSE" ]]; then
  cp -a "${PROJECT_ROOT}/LICENSE" "${STAGE_ROOT}/LICENSE.txt"
elif [[ -f "${PROJECT_ROOT}/LICENSE.txt" ]]; then
  cp -a "${PROJECT_ROOT}/LICENSE.txt" "${STAGE_ROOT}/LICENSE.txt"
fi

# Generate a small README with metadata
cat > "${STAGE_ROOT}/README.txt" <<EOF
${APP_NAME} (${APP_VERSION}) — Windows portable ZIP
Publisher: ${PUBLISHER_NAME}
Homepage : ${HOMEPAGE_URL}

Contents
--------
- WPStallman.Launcher.exe  -> entry point
- gtk4.1\\                  -> Modern UI payload (if present)
- gtk4.0\\                  -> Legacy UI payload (if present)

Notes
-----
- Requires Microsoft Edge WebView2 Runtime on Windows.
- Run WPStallman.Launcher.exe to start the app.
EOF

# ──────────────────────────────────────────────────────────────
# Create ZIP
# ──────────────────────────────────────────────────────────────
OUT_ZIP="${OUTDIR}/${WINZIP_BASENAME}-${APP_VERSION}.zip"
rm -f "${OUT_ZIP}"

(
  cd "${WORKDIR}"
  if command -v zip >/dev/null 2>&1; then
    note "Zipping with zip → ${OUT_ZIP}"
    zip -r -q "${OUT_ZIP}" "$(basename "${STAGE_ROOT}")"
  elif command -v 7z >/dev/null 2>&1; then
    note "Zipping with 7z  → ${OUT_ZIP}"
    7z a -tzip -r -bd "${OUT_ZIP}" "$(basename "${STAGE_ROOT}")" >/dev/null
  else
    die "Neither 'zip' nor '7z' is available to create ${OUT_ZIP}"
  fi
)

note "ZIP created: ${OUT_ZIP}"
