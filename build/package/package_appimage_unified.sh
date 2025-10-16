#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# Load shared metadata (dotenv)
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
# Compatibility shim (new vars from release_all, legacy fallbacks)
# ──────────────────────────────────────────────────────────────
: "${PUBLISH_DIR_GTK41:=${GTK41_SRC:-}}"
: "${PUBLISH_DIR_GTK40:=${GTK40_SRC:-}}"
: "${PUBLISH_DIR_LAUNCHER:=${LAUNCHER_SRC:-}}"
: "${APP_VERSION:=${APP_VERSION:-${VERSION:-}}}"

if [[ -z "${PUBLISH_DIR_GTK41}" && -z "${PUBLISH_DIR_GTK40}" ]]; then
  echo "[ERR ] No payloads found. Set PUBLISH_DIR_GTK41 and/or PUBLISH_DIR_GTK40." >&2
  exit 1
fi

for _v in PUBLISH_DIR_GTK41 PUBLISH_DIR_GTK40 PUBLISH_DIR_LAUNCHER; do
  _p="${!_v:-}"
  if [[ -n "${_p}" && ! -d "${_p}" ]]; then
    echo "[ERR ] ${_v} path does not exist: ${_p}" >&2
    exit 1
  fi
done

if [[ "${DEBUG_APPIMAGE:-0}" == "1" ]]; then
  echo "[DBG] APP_VERSION=${APP_VERSION}"
  echo "[DBG] PUBLISH_DIR_GTK41=${PUBLISH_DIR_GTK41}"
  echo "[DBG] PUBLISH_DIR_GTK40=${PUBLISH_DIR_GTK40}"
  echo "[DBG] PUBLISH_DIR_LAUNCHER=${PUBLISH_DIR_LAUNCHER}"
fi

# ──────────────────────────────────────────────────────────────
# Pretty logging
# ──────────────────────────────────────────────────────────────
note() { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*" >&2; }
die()  { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; exit 1; }

# ──────────────────────────────────────────────────────────────
# Identity (from release.meta; provide sane defaults)
# ──────────────────────────────────────────────────────────────
: "${APP_ID:=com.wpstallman.app}"
: "${APP_NAME:=W.P. Stallman}"
: "${APP_SUMMARY:=Packaging tools for WordPress modules}"
: "${APP_HOMEPAGE:=https://lefthandenterprises.com/projects/wpstallman}"
: "${APP_DEVELOPER:=Left Hand Enterprises, LLC}"
: "${APP_LICENSE:=MIT}"
: "${METADATA_LICENSE:=CC0-1.0}"     # license for the AppStream XML
: "${APP_SUFFIX:=-unified}"

# Try to resolve version if still not set
if [[ -z "${APP_VERSION:-}" ]]; then
  get_msbuild_prop() { dotnet msbuild "$1" -nologo -getProperty:"$2" 2>/dev/null | tr -d '\r' | tail -n1; }
  get_version_from_props() {
    local props="${PROJECT_ROOT}/Directory.Build.props"
    [[ -f "$props" ]] && grep -oP '(?<=<Version>).*?(?=</Version>)' "$props" | head -n1 || true
  }
  APP_VERSION="$(get_msbuild_prop "${PROJECT_ROOT}/src/WPStallman.GUI/WPStallman.GUI.csproj" "Version" || true)"
  [[ -n "$APP_VERSION" && "$APP_VERSION" != "*Undefined*" ]] || APP_VERSION="$(get_version_from_props)"
  [[ -n "$APP_VERSION" ]] || die "Could not resolve Version from MSBuild or Directory.Build.props"
fi
export APP_VERSION
note "Version: $APP_VERSION"

# ──────────────────────────────────────────────────────────────
# Resolve helper path (once) and source it
# ──────────────────────────────────────────────────────────────
# Physical dir of this script (resolves symlinks)
__src="${BASH_SOURCE[0]}"
while [ -h "$__src" ]; do
  __dir="$(cd -P "$(dirname "$__src")" && pwd)"
  __src="$(readlink "$__src")"
  [[ "$__src" != /* ]] && __src="$__dir/$__src"
done
SCRIPT_DIR="$(cd -P "$(dirname "$__src")" && pwd)"

REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel 2>/dev/null || echo "")"

HELPER_CANDIDATES=(
  "${APPSTREAM_HELPERS_PATH:-}"
  "${SCRIPT_DIR}/appstream_helpers.sh"
  "${SCRIPT_DIR}/../appstream_helpers.sh"
  "${SCRIPT_DIR}/../../appstream_helpers.sh"
  "${REPO_ROOT:+${REPO_ROOT}/build/package/appstream_helpers.sh}"
)

APPSTREAM_HELPERS=""
for cand in "${HELPER_CANDIDATES[@]}"; do
  if [[ -n "$cand" && -f "$cand" ]]; then APPSTREAM_HELPERS="$cand"; break; fi
done

if [[ "${DEBUG_HELPERS:-0}" = "1" ]]; then
  echo "[DBG] PWD=$(pwd)"
  echo "[DBG] SCRIPT_DIR=$SCRIPT_DIR"
  echo "[DBG] REPO_ROOT=$REPO_ROOT"
  printf '[DBG] Candidates:\n'; printf '  - %s\n' "${HELPER_CANDIDATES[@]}"
  echo "[DBG] Selected: $APPSTREAM_HELPERS"
fi

[[ -n "$APPSTREAM_HELPERS" ]] || die "appstream_helpers.sh not found. Set APPSTREAM_HELPERS_PATH to an absolute path."
# shellcheck disable=SC1090
source "$APPSTREAM_HELPERS"

# Make sure helpers see the right metadata (env → used by write_appstream)
export APP_ID APP_NAME APP_VERSION APP_SUMMARY APP_HOMEPAGE APP_DEVELOPER APP_LICENSE METADATA_LICENSE

# ──────────────────────────────────────────────────────────────
# Layout / staging
# ──────────────────────────────────────────────────────────────
ROOT="${PROJECT_ROOT}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${ROOT}/artifacts}"
BUILDDIR="${BUILDDIR:-${ARTIFACTS_DIR}/build}"
OUTDIR="${OUTDIR:-${ARTIFACTS_DIR}/packages}"
mkdir -p "$BUILDDIR" "$OUTDIR"

APPDIR="$BUILDDIR/AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib/$APP_ID" "$APPDIR/usr/share/applications"

# Copy the AppImage debug runner into packages (once)
DEBUG_RUNNER_SRC="$ROOT/build/package/run-wpst-debug.sh"
DEBUG_RUNNER_DST="$OUTDIR/run-wpst-debug.sh"
if [[ -f "$DEBUG_RUNNER_SRC" ]]; then
  if [[ ! -f "$DEBUG_RUNNER_DST" ]]; then
    install -Dm755 "$DEBUG_RUNNER_SRC" "$DEBUG_RUNNER_DST"
    note "Placed debug runner at: $DEBUG_RUNNER_DST"
  else
    note "Debug runner already present: $DEBUG_RUNNER_DST"
  fi
else
  warn "Debug runner not found at: $DEBUG_RUNNER_SRC"
fi


stage_payload() {
  local src="$1" subdir="$2"
  [[ -d "$src" ]] || return 1
  note "Staging $subdir from: $src"
  local dest="$APPDIR/usr/lib/$APP_ID/$subdir"
  mkdir -p "$dest"
  rsync -a --delete "$src/" "$dest/"
  # Check either so name
  local so=""
  if [[ -f "$dest/libPhotino.Native.so" ]]; then so="$dest/libPhotino.Native.so"; fi
  if [[ -z "$so" && -f "$dest/Photino.Native.so" ]]; then so="$dest/Photino.Native.so"; fi
  if [[ -n "$so" ]]; then
    note "ldd on $(basename "$so") ($subdir):"
    ldd "$so" | sed 's/^/  /' || true
  else
    warn "[$subdir] No Photino native .so found; GUI may fail on clean systems."
  fi
}

HAVE_41=0; HAVE_40=0
[[ -n "${PUBLISH_DIR_GTK41:-}" && -d "$PUBLISH_DIR_GTK41" ]] && { stage_payload "$PUBLISH_DIR_GTK41" "gtk4.1" && HAVE_41=1; }
[[ -n "${PUBLISH_DIR_GTK40:-}" && -d "$PUBLISH_DIR_GTK40" ]] && { stage_payload "$PUBLISH_DIR_GTK40" "gtk4.0" && HAVE_40=1; }
(( HAVE_41 || HAVE_40 )) || die "Staging failed; no payload copied."

# ──────────────────────────────────────────────────────────────
# Icon selection
# ──────────────────────────────────────────────────────────────
pick_icon() {
  local base="$1"
  local candidates=(
    "$base/wwwroot/img/WPS-256.png"
    "$base/wwwroot/img/WPS-512.png"
    "$base/wwwroot/img/WPS.png"
  )
  for c in "${candidates[@]}"; do [[ -f "$c" ]] && echo "$c" && return 0; done
  return 1
}
ICON_SRC=""
(( HAVE_41 )) && ICON_SRC="$(pick_icon "$APPDIR/usr/lib/$APP_ID/gtk4.1")" || true
[[ -z "$ICON_SRC" && $HAVE_40 -eq 1 ]] && ICON_SRC="$(pick_icon "$APPDIR/usr/lib/$APP_ID/gtk4.0")" || true
[[ -n "$ICON_SRC" ]] && cp -f "$ICON_SRC" "$APPDIR/${APP_ID}.png" || warn "Icon not found; using generic."

# ──────────────────────────────────────────────────────────────
# AppRun (selector prefers gtk4.1 on glibc ≥ 2.38)
# ──────────────────────────────────────────────────────────────
cat > "$APPDIR/AppRun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
APPROOT="$HERE/usr/lib/com.wpstallman.app"

gtk41_dir="$APPROOT/gtk4.1"
gtk40_dir="$APPROOT/gtk4.0"
target_dir=""

version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }

glibc_ver="$(ldd --version 2>/dev/null | awk 'NR==1{print $NF}')"
have_gtk41_libs="no"
if ldconfig -p 2>/dev/null | grep -q 'libwebkit2gtk-4\.1\.so\.0'; then
  have_gtk41_libs="yes"
elif [[ -e /lib/x86_64-linux-gnu/libwebkit2gtk-4.1.so.0 || -e /usr/lib/x86_64-linux-gnu/libwebkit2gtk-4.1.so.0 ]]; then
  have_gtk41_libs="yes"
fi

if [[ -d "$gtk41_dir" ]] && [[ "$have_gtk41_libs" == "yes" ]] && version_ge "${glibc_ver:-0}" "2.38"; then
  target_dir="$gtk41_dir"
elif [[ -d "$gtk40_dir" ]]; then
  target_dir="$gtk40_dir"
elif [[ -d "$gtk41_dir" ]]; then
  target_dir="$gtk41_dir"
fi

if [[ -z "$target_dir" ]]; then
  echo "No suitable GUI payload found." >&2
  exit 1
fi

export LD_LIBRARY_PATH="$target_dir:${LD_LIBRARY_PATH:-}"
exec "$target_dir/WPStallman.GUI" "${@:-}"
EOF
chmod +x "$APPDIR/AppRun"
ln -sf "./AppRun" "$APPDIR/usr/bin/${APP_ID}"

# ──────────────────────────────────────────────────────────────
# Desktop entry
# ──────────────────────────────────────────────────────────────
cat > "$APPDIR/${APP_ID}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Comment=${APP_SUMMARY}
Exec=${APP_ID}
Icon=${APP_ID}
Categories=Utility;
StartupWMClass=WPStallman.GUI
X-AppImage-Version=${APP_VERSION}
EOF

# ──────────────────────────────────────────────────────────────
# AppStream metadata (helpers write + validate)
# ──────────────────────────────────────────────────────────────
write_appstream "$APPDIR"
validate_desktop_and_metainfo "$APPDIR" || true

# Extra validation if tools exist
command -v desktop-file-validate >/dev/null 2>&1 && desktop-file-validate "$APPDIR/${APP_ID}.desktop" || true
command -v appstreamcli >/dev/null 2>&1 && appstreamcli validate --no-net "$APPDIR/usr/share/metainfo/${APP_ID}.metainfo.xml" || true

# ──────────────────────────────────────────────────────────────
# Build AppImage
# ──────────────────────────────────────────────────────────────
OUTFILE="${OUTDIR}/WPStallman-${APP_VERSION}-x86_64${APP_SUFFIX}.AppImage"
note "Building AppImage → $OUTFILE"
export APPIMAGE_EXTRACT_AND_RUN=${APPIMAGE_EXTRACT_AND_RUN:-1}
command -v appimagetool >/dev/null 2>&1 || die "appimagetool is not in PATH."
appimagetool "$APPDIR" "$OUTFILE"
chmod +x "$OUTFILE"
note "AppImage built: $OUTFILE"
