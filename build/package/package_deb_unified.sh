#!/usr/bin/env bash
set -euo pipefail

# ───────────────────────────────
# Pretty logging
# ───────────────────────────────
note() { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*" >&2; }
die()  { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; exit 1; }

# ───────────────────────────────
# Repo layout & identity
# ───────────────────────────────
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT"

: "${APP_ID:=com.wpstallman.app}"
: "${APP_NAME:="W. P. Stallman"}"
: "${MAIN_BIN:=WPStallman.GUI}"

# Default projects / outputs (override via env if needed)
: "${GUI_CSPROJ:=src/WPStallman.GUI/WPStallman.GUI.csproj}"
: "${TFM_LIN_GUI:=net8.0}"
: "${RID_LIN:=linux-x64}"

# Try to auto-locate payloads if not provided
: "${PUBLISH_DIR_GTK41:=}"
if [[ -z "${PUBLISH_DIR_GTK41}" ]]; then
  for cand in \
    "$ROOT/src/WPStallman.GUI/bin/Release/${TFM_LIN_GUI}/${RID_LIN}/publish" \
    "$ROOT/artifacts/publish-gtk4.1" \
    "$ROOT/src/WPStallman.GUI.GTK41/bin/Release/${TFM_LIN_GUI}/${RID_LIN}/publish"
  do [[ -d "$cand" ]] && PUBLISH_DIR_GTK41="$cand" && break; done
fi

: "${PUBLISH_DIR_GTK40:=}"
if [[ -z "${PUBLISH_DIR_GTK40}" ]]; then
  for cand in \
    "$ROOT/artifacts/publish-gtk4.0" \
    "$ROOT/src/WPStallman.GUI.GTK40/bin/Release/${TFM_LIN_GUI}/${RID_LIN}/publish"
  do [[ -d "$cand" ]] && PUBLISH_DIR_GTK40="$cand" && break; done
fi

if [[ ! -d "${PUBLISH_DIR_GTK41:-/nonexistent}" && ! -d "${PUBLISH_DIR_GTK40:-/nonexistent}" ]]; then
  die "No payloads found. Set PUBLISH_DIR_GTK41 and/or PUBLISH_DIR_GTK40."
fi

# Optional suffix for filename (default -unified)
: "${APP_SUFFIX:="-unified"}"

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
# Output dirs
# ───────────────────────────────
: "${ARTIFACTS_DIR:=artifacts}"
: "${BUILDDIR:=$ARTIFACTS_DIR/build}"
: "${OUTDIR:=$ARTIFACTS_DIR/packages}"
DEB_ROOT="$BUILDDIR/deb-unified"
rm -rf "$DEB_ROOT"
install -d "$DEB_ROOT/DEBIAN" \
           "$DEB_ROOT/usr/bin" \
           "$DEB_ROOT/usr/lib/$APP_ID" \
           "$DEB_ROOT/usr/share/applications" \
           "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps"

# ───────────────────────────────
# Stage payloads under /usr/lib/<APP_ID>/{gtk4.1,gtk4.0}
# ───────────────────────────────
stage_payload() {
  local src="$1" dest_sub="$2"
  [[ -d "$src" ]] || return 1
  local dest="$DEB_ROOT/usr/lib/$APP_ID/$dest_sub"
  note "Staging $dest_sub from: $src"
  install -d "$dest"
  rsync -a --delete "$src/" "$dest/"
  # Sanity: show lib deps if present
  if [[ -f "$dest/libPhotino.Native.so" ]]; then
    note "ldd on Photino native ($dest_sub payload):"
    ldd "$dest/libPhotino.Native.so" | sed 's/^/  /' || true
  else
    warn "[$dest_sub] No libPhotino.Native.so found; GUI may fail on clean systems."
  fi
  return 0
}

HAVE_41=0
HAVE_40=0
[[ -d "${PUBLISH_DIR_GTK41:-/nonexistent}" ]] && stage_payload "$PUBLISH_DIR_GTK41" "gtk4.1" && HAVE_41=1
[[ -d "${PUBLISH_DIR_GTK40:-/nonexistent}" ]] && stage_payload "$PUBLISH_DIR_GTK40" "gtk4.0" && HAVE_40=1
(( HAVE_41 == 1 || HAVE_40 == 1 )) || die "No payload could be staged."

# ───────────────────────────────
# Launcher shim (runtime selector)
# ───────────────────────────────
cat > "$DEB_ROOT/usr/bin/wpstallman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
APPROOT="/usr/lib/com.wpstallman.app"
GTK41="$APPROOT/gtk4.1"
GTK40="$APPROOT/gtk4.0"

version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }

glibc_ver="$(ldd --version 2>/dev/null | awk 'NR==1{print $NF}')"
have_gtk41="no"
if ldconfig -p 2>/dev/null | grep -q 'libwebkit2gtk-4\.1\.so\.0'; then
  have_gtk41="yes"
elif [[ -e /lib/x86_64-linux-gnu/libwebkit2gtk-4.1.so.0 || -e /usr/lib/x86_64-linux-gnu/libwebkit2gtk-4.1.so.0 ]]; then
  have_gtk41="yes"
fi

target="$GTK40"
if [[ -d "$GTK41" ]] && [[ "$have_gtk41" == "yes" ]] && version_ge "${glibc_ver:-0}" "2.38"; then
  target="$GTK41"
elif [[ -d "$GTK40" ]]; then
  target="$GTK40"
elif [[ -d "$GTK41" ]]; then
  target="$GTK41"
else
  echo "No suitable GUI payload found." >&2
  exit 1
fi

export LD_LIBRARY_PATH="$target:${LD_LIBRARY_PATH:-}"
exec "$target/WPStallman.GUI" "${@:-}"
EOF
chmod +x "$DEB_ROOT/usr/bin/wpstallman"

# ───────────────────────────────
# Icon (pick from whichever payload has it)
# ───────────────────────────────
pick_icon() {
  local base="$1"
  local c
  for c in \
    "$base/wwwroot/img/WPS-256.png" \
    "$base/wwwroot/img/WPS.png" \
    "$base/wwwroot/img/wpst-256.png"
  do [[ -f "$c" ]] && { echo "$c"; return 0; }; done
  return 1
}
ICON_SRC=""
(( HAVE_41 )) && ICON_SRC="$(pick_icon "$DEB_ROOT/usr/lib/$APP_ID/gtk4.1")" || true
[[ -z "$ICON_SRC" && $HAVE_40 -eq 1 ]] && ICON_SRC="$(pick_icon "$DEB_ROOT/usr/lib/$APP_ID/gtk4.0")" || true
if [[ -n "$ICON_SRC" ]]; then
  cp -f "$ICON_SRC" "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps/${APP_ID}.png"
else
  warn "Icon not found in payloads; desktop entry will use a generic icon."
fi

# ───────────────────────────────
# Desktop entry
# ───────────────────────────────
cat > "$DEB_ROOT/usr/share/applications/${APP_ID}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Comment=WPStallman
Exec=wpstallman
Icon=${APP_ID}
Categories=Utility;
StartupWMClass=WPStallman.GUI
EOF

# ───────────────────────────────
# Control metadata (loose, works for both baselines)
# ───────────────────────────────
# Default to "either-or" GTK deps so the unified package installs broadly.
: "${DEB_DEPENDS:=libgtk-3-0, libnotify4, libgdk-pixbuf-2.0-0, libnss3, libjavascriptcoregtk-4.1-0 | libjavascriptcoregtk-4.0-18, libwebkit2gtk-4.1-0 | libwebkit2gtk-4.0-37}"

CONTROL_FILE="$DEB_ROOT/DEBIAN/control"
cat > "$CONTROL_FILE" <<EOF
Package: wpstallman
Version: ${APP_VERSION}
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Patrick Driscoll <patrick@lefthandenterprises.com>
Depends: ${DEB_DEPENDS}
Description: W. P. Stallman – desktop app (Photino.NET; unified gtk4.0/gtk4.1)
 Ships both gtk4.0 and gtk4.1 payloads and selects the right one at runtime.
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
OUTDIR="${OUTDIR:-$ARTIFACTS_DIR/packages}"
mkdir -p "$OUTDIR"
DEB_FILE="$OUTDIR/wpstallman_${APP_VERSION}_amd64${APP_SUFFIX}.deb"

note "Building .deb → $DEB_FILE"
fakeroot dpkg-deb --build "$DEB_ROOT" "$DEB_FILE"
note ".deb built: $DEB_FILE"
