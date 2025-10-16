#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# Load release metadata (dotenv) from build/package/release.meta
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

# Required metadata for this packer
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
require_vars APP_ID APP_NAME PUBLISHER_NAME PUBLISHER_EMAIL HOMEPAGE_URL DEB_PACKAGE DEB_SECTION DEB_PRIORITY DEB_ARCH

# ───────────────────────────────
# Compatibility shim for inputs
# ───────────────────────────────
: "${PUBLISH_DIR_GTK41:=${GTK41_SRC:-}}"
: "${PUBLISH_DIR_GTK40:=${GTK40_SRC:-}}"
: "${PUBLISH_DIR_LAUNCHER:=${LAUNCHER_SRC:-}}"
: "${APP_VERSION:=${APP_VERSION:-${VERSION:-}}}"

APP_VERSION_RAW="${APP_VERSION}"
APP_VERSION_DEB="${APP_VERSION_RAW#v}"
APP_VERSION_DEB="${APP_VERSION_DEB#V}"


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

if [[ "${DEBUG_DEB:-0}" == "1" ]]; then
  echo "[DBG] APP_VERSION=${APP_VERSION}"
  echo "[DBG] PUBLISH_DIR_GTK41=${PUBLISH_DIR_GTK41}"
  echo "[DBG] PUBLISH_DIR_GTK40=${PUBLISH_DIR_GTK40}"
  echo "[DBG] PUBLISH_DIR_LAUNCHER=${PUBLISH_DIR_LAUNCHER}"
fi

# --- defaults for paths / identity (safe for `set -u`) ---
: "${APP_SUFFIX:=}"                       # e.g., "-unified" or ""
# normalize: if non-empty and missing leading '-', add it
if [[ -n "$APP_SUFFIX" && "$APP_SUFFIX" != -* ]]; then
  APP_SUFFIX="-$APP_SUFFIX"
fi

: "${APP_ID:=com.wpstallman.app}"
: "${APP_NAME:=W. P. Stallman}"

: "${ARTIFACTS_DIR:=${PROJECT_ROOT}/artifacts}"
: "${BUILDDIR:=${ARTIFACTS_DIR}/build}"
: "${OUTDIR:=${ARTIFACTS_DIR}/packages}"
: "${DEB_ROOT:=${PROJECT_ROOT}/build/debroot}"
mkdir -p "$ARTIFACTS_DIR" "$BUILDDIR" "$OUTDIR" "$DEB_ROOT"

# dependency vars (don’t rely on debhelper substvars)
: "${DEB_DEPENDS:=libgtk-3-0, libnotify4, libgdk-pixbuf-2.0-0, libnss3, libjavascriptcoregtk-4.1-0 | libjavascriptcoregtk-4.0-18, libwebkit2gtk-4.1-0 | libwebkit2gtk-4.0-37}"
: "${MISC_DEPENDS:=}"
: "${SHLIBS_DEPENDS:=}"


# If you’re not using debhelper’s substvars, make these no-ops so
# “Depends:” lines don’t explode under `set -u`.
: "${DEB_DEPENDS:=libgtk-3-0, libnotify4, libgdk-pixbuf-2.0-0, libnss3, libjavascriptcoregtk-4.1-0 | libjavascriptcoregtk-4.0-18, libwebkit2gtk-4.1-0 | libwebkit2gtk-4.0-37}"
: "${MISC_DEPENDS:=}"
: "${SHLIBS_DEPENDS:=}"


# ───────────────────────────────
# Helpers
# ───────────────────────────────
note() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }

# Accept both possible Photino native names
has_photino_native() {
  local d="$1"
  [[ -f "$d/libPhotino.Native.so" || -f "$d/Photino.Native.so" ]]
}

# Stage one payload into deb root
DEB_ROOT="${DEB_ROOT:-"${PROJECT_ROOT}/build/debroot"}"
APP_LIB_ROOT="$DEB_ROOT/usr/lib/$APP_ID"

stage_payload() {
  local src="$1" dest_sub="$2"
  [[ -d "$src" ]] || return 1

  local dest="$APP_LIB_ROOT/$dest_sub"
  note "Staging $dest_sub from: $src"
  install -d "$dest"
  rsync -a --delete "$src/" "$dest/"

  # find Photino .so and ldd it (either filename)
  local so=""
  if [[ -f "$dest/libPhotino.Native.so" ]]; then
    so="$dest/libPhotino.Native.so"
  elif [[ -f "$dest/Photino.Native.so" ]]; then
    so="$dest/Photino.Native.so"
  fi
  if [[ -n "$so" ]]; then
    note "ldd on Photino native ($dest_sub): $(basename "$so")"
    ldd "$so" | sed 's/^/  /' || true
  else
    warn "[$dest_sub] No Photino native .so found (looked for libPhotino.Native.so or Photino.Native.so)."
  fi
}

# ───────────────────────────────
# Start fresh deb root and stage
# ───────────────────────────────
rm -rf "$DEB_ROOT"
install -d "$DEB_ROOT/DEBIAN" "$DEB_ROOT/usr/bin" "$APP_LIB_ROOT/gtk4.1" "$APP_LIB_ROOT/gtk4.0"

# Stage payloads
[[ -n "${PUBLISH_DIR_GTK41:-}" ]]   && stage_payload "${PUBLISH_DIR_GTK41}" "gtk4.1"
[[ -n "${PUBLISH_DIR_GTK40:-}" ]]   && stage_payload "${PUBLISH_DIR_GTK40}" "gtk4.0"
if [[ -n "${PUBLISH_DIR_LAUNCHER:-}" ]]; then
  # launcher goes to /usr/bin
  if [[ -x "${PUBLISH_DIR_LAUNCHER}/WPStallman.Launcher" ]]; then
    install -m 0755 "${PUBLISH_DIR_LAUNCHER}/WPStallman.Launcher" "$DEB_ROOT/usr/bin/WPStallman"
  else
    warn "Launcher binary not found in ${PUBLISH_DIR_LAUNCHER}"
  fi
fi

# ── compute Installed-Size (KiB) excluding DEBIAN ──
calc_installed_size_kib() {
  # Portable way (works even if 'du --exclude' isn't available)
  # Sums apparent sizes of all staged files except the DEBIAN control dir.
  ( cd "$DEB_ROOT" \
    && find . -path ./DEBIAN -prune -o -type f -print0 \
    | du -c -k --files0-from=- 2>/dev/null \
    | awk '/total$/ {print $1}' )
}

INSTALLED_SIZE_KIB="$(calc_installed_size_kib)"
: "${INSTALLED_SIZE_KIB:=0}"   # fallback safety


# ───────────────────────────────
# Control metadata (from release.meta)
# ───────────────────────────────
# curated deps for both WebKitGTK baselines (from metadata)
: "${DEB_DEPENDS:=libgtk-3-0, libnotify4, libgdk-pixbuf-2.0-0, libnss3, libasound2, \
libjavascriptcoregtk-4.1-0 | libjavascriptcoregtk-4.0-18, \
libwebkit2gtk-4.1-0 | libwebkit2gtk-4.0-37}"

# If you also compute shlibs via dpkg-shlibdeps, put the value (not the key=val) here.
shlibs="${shlibs:-}"

CONTROL_FILE="$DEB_ROOT/DEBIAN/control"
cat > "$CONTROL_FILE" <<EOF
Package: ${DEB_PACKAGE}
Version: ${APP_VERSION_DEB}
Section: ${DEB_SECTION}
Priority: ${DEB_PRIORITY}
Architecture: ${DEB_ARCH}
Maintainer: ${PUBLISHER_NAME} <${PUBLISHER_EMAIL}>
Installed-Size: ${INSTALLED_SIZE_KIB}
Homepage: ${HOMEPAGE_URL}
Depends: ${shlibs:+${shlibs}, }${DEB_DEPENDS}
Description: ${APP_SHORTDESC}
$( [[ -f "${DEB_LONGDESC_FILE:-}" ]] && sed 's/^/ /' "${DEB_LONGDESC_FILE}" )
EOF


# Optional postinst to refresh caches
cat > "$DEB_ROOT/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if command -v gtk-update-icon-cache >/dev/null 2>&1; then gtk-update-icon-cache -f /usr/share/icons/hicolor || true; fi
if command -v update-desktop-database >/dev/null 2>&1; then update-desktop-database -q /usr/share/applications || true; fi
exit 0
EOF
chmod 0755 "$DEB_ROOT/DEBIAN/postinst"

# ───────────────────────────────
# Build the .deb
# ───────────────────────────────
# ── normalize perms inside the staging tree ──
# dirs 0755, executables 0755, regular files 0644
find "$DEB_ROOT" -type d  -exec chmod 0755 {} +
find "$DEB_ROOT" -type f  -name "*.sh" -exec chmod 0755 {} +
find "$DEB_ROOT/usr/bin" -type f -exec chmod 0755 {} + 2>/dev/null || true
find "$DEB_ROOT" -type f ! -perm -111 -exec chmod 0644 {} +

# control files: 0644 (scripts 0755 if you add any)
find "$DEB_ROOT/DEBIAN" -type f -exec chmod 0644 {} +
for s in postinst prerm postrm preinst; do
  [[ -f "$DEB_ROOT/DEBIAN/$s" ]] && chmod 0755 "$DEB_ROOT/DEBIAN/$s"
done

# ── build with fakeroot so metadata looks “rooty” without sudo ──
OUT_DEB="$OUTDIR/wpstallman_${APP_VERSION}_${DEB_ARCH}.deb"
mkdir -p "$OUTDIR"
fakeroot dpkg-deb --build "$DEB_ROOT" "$OUT_DEB"

# ensure the resulting file is readable by non-root
chmod 0644 "$OUT_DEB"
# (optional) if any step used sudo earlier, take ownership back:
chown "$USER:$USER" "$OUT_DEB" || true

note "Built .deb: $OUT_DEB"
