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
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT"

: "${APP_ID:=com.wpstallman.app}"
: "${APP_NAME:="W. P. Stallman"}"
: "${MAIN_BIN:=WPStallman.GUI}"

# AppStream / publisher metadata (override with env if you like)
: "${APP_SUMMARY:=Packaging tools for WordPress modules}"
: "${APP_HOMEPAGE:=https://lefthandenterprises.com/projects/wpstallman}"
: "${APP_DEVELOPER:=Patrick Driscoll}"
: "${APP_LICENSE:=MIT}"


# Optional suffix to label the build (e.g., -unified, -nightly, etc.)
: "${APP_SUFFIX:="-unified"}"

# Projects / publish defaults (you can override via env)
: "${GUI_CSPROJ:=src/WPStallman.GUI/WPStallman.GUI.csproj}"
: "${TFM_LIN_GUI:=net8.0}"
: "${RID_LIN:=linux-x64}"

# Try to auto-locate payloads if not provided:
# GTK 4.1 payload (24.04+ baseline)
: "${PUBLISH_DIR_GTK41:=}"
if [[ -z "${PUBLISH_DIR_GTK41}" ]]; then
  for cand in \
    "$ROOT/src/WPStallman.GUI/bin/Release/${TFM_LIN_GUI}/${RID_LIN}/publish" \
    "$ROOT/artifacts/publish-gtk4.1" \
    "$ROOT/src/WPStallman.GUI.GTK41/bin/Release/${TFM_LIN_GUI}/${RID_LIN}/publish"
  do [[ -d "$cand" ]] && PUBLISH_DIR_GTK41="$cand" && break; done
fi

# GTK 4.0 payload (22.04 baseline)
: "${PUBLISH_DIR_GTK40:=}"
if [[ -z "${PUBLISH_DIR_GTK40}" ]]; then
  for cand in \
    "$ROOT/artifacts/publish-gtk4.0" \
    "$ROOT/src/WPStallman.GUI.GTK40/bin/Release/${TFM_LIN_GUI}/${RID_LIN}/publish"
  do [[ -d "$cand" ]] && PUBLISH_DIR_GTK40="$cand" && break; done
fi

# You need at least one payload; ideally both.
[[ -d "${PUBLISH_DIR_GTK41:-/nonexistent}" || -d "${PUBLISH_DIR_GTK40:-/nonexistent}" ]] \
  || die "No payloads found. Set PUBLISH_DIR_GTK41 and/or PUBLISH_DIR_GTK40."

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
mkdir -p "$BUILDDIR" "$OUTDIR"

APPDIR="$BUILDDIR/AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib/$APP_ID" "$APPDIR/usr/share/applications"

# ───────────────────────────────
# Stage payloads
# ───────────────────────────────
stage_payload() {
  local src="$1" subdir="$2"
  [[ -d "$src" ]] || return 1
  note "Staging $subdir payload from: $src"
  mkdir -p "$APPDIR/usr/lib/$APP_ID/$subdir"
  rsync -a --delete "$src/" "$APPDIR/usr/lib/$APP_ID/$subdir/"
  # Ensure native lib is present
  if [[ ! -f "$APPDIR/usr/lib/$APP_ID/$subdir/libPhotino.Native.so" ]]; then
    warn "[$subdir] libPhotino.Native.so not found in publish; GUI may fail if host lacks WebKitGTK."
  fi
  return 0
}

HAVE_41=0
HAVE_40=0
if [[ -n "${PUBLISH_DIR_GTK41:-}" && -d "$PUBLISH_DIR_GTK41" ]]; then
  stage_payload "$PUBLISH_DIR_GTK41" "gtk4.1" && HAVE_41=1
fi
if [[ -n "${PUBLISH_DIR_GTK40:-}" && -d "$PUBLISH_DIR_GTK40" ]]; then
  stage_payload "$PUBLISH_DIR_GTK40" "gtk4.0" && HAVE_40=1
fi
(( HAVE_41 == 1 || HAVE_40 == 1 )) || die "Staging failed; no payload copied."

# ───────────────────────────────
# Choose an icon and copy to AppDir root
# ───────────────────────────────
pick_icon() {
  local base="$1"
  local candidates=(
    "$base/wwwroot/img/WPS-256.png"
    "$base/wwwroot/img/WPS.png"
    "$base/wwwroot/img/wpst-256.png"
  )
  for c in "${candidates[@]}"; do [[ -f "$c" ]] && echo "$c" && return 0; done
  return 1
}
ICON_SRC=""
if (( HAVE_41 )); then
  ICON_SRC="$(pick_icon "$APPDIR/usr/lib/$APP_ID/gtk4.1")" || true
fi
if [[ -z "$ICON_SRC" && $HAVE_40 -eq 1 ]]; then
  ICON_SRC="$(pick_icon "$APPDIR/usr/lib/$APP_ID/gtk4.0")" || true
fi
if [[ -n "$ICON_SRC" ]]; then
  cp -f "$ICON_SRC" "$APPDIR/${APP_ID}.png"
else
  warn "Icon not found in payloads; AppImage will use a generic icon."
fi

# ───────────────────────────────
# Create AppRun (runtime selector)
# ───────────────────────────────
cat > "$APPDIR/AppRun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
APPROOT="$HERE/usr/lib/com.wpstallman.app"

gtk41_dir="$APPROOT/gtk4.1"
gtk40_dir="$APPROOT/gtk4.0"
target_dir=""

version_ge() { # compare dotted versions (e.g., 2.39 >= 2.38)
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

glibc_ver="$(ldd --version 2>/dev/null | awk 'NR==1{print $NF}')"
have_gtk41_libs="no"
if ldconfig -p 2>/dev/null | grep -q 'libwebkit2gtk-4\.1\.so\.0'; then
  have_gtk41_libs="yes"
elif [[ -e /lib/x86_64-linux-gnu/libwebkit2gtk-4.1.so.0 || -e /usr/lib/x86_64-linux-gnu/libwebkit2gtk-4.1.so.0 ]]; then
  have_gtk41_libs="yes"
fi

# Prefer gtk4.1 when host glibc >= 2.38 and libs exist; else fall back
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

# Create symlink for Exec target
ln -sf "./AppRun" "$APPDIR/usr/bin/${APP_ID}"

# ───────────────────────────────
# Desktop file (includes AppImage version)
# ───────────────────────────────
cat > "$APPDIR/${APP_ID}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Comment=WPStallman
Exec=${APP_ID}
Icon=${APP_ID}
Categories=Utility;
StartupWMClass=WPStallman.GUI
X-AppImage-Version=${APP_VERSION}
EOF

# Identity
APP_ID="com.wpstallman.app"
APP_NAME="W.P. Stallman"
APP_VERSION="1.0.0"

# publisher/licensing (what we decided)
APP_DEVELOPER="Left Hand Enterprises, LLC"
APP_LICENSE="MIT"           # software license
METADATA_LICENSE="CC0-1.0"  # license for the AppStream XML

# optional URLs
APP_URL_BUGS="https://github.com/lefthandenterprises/wpstallman/issues"
APP_URL_HELP=""


# Source helper from the script’s dir (robust to cwd)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${SCRIPT_DIR}/build/package/appstream_helpers.sh"

# Write metainfo into AppDir + (optionally) copy .desktop
write_appstream "$APPDIR"
validate_desktop_and_metainfo "$APPDIR"   # optional but helpful

# Optional validation (best-effort; won’t fail the build)
if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "$APPDIR/${APP_ID}.desktop" || warn "desktop-file-validate warnings"
fi
if command -v appstreamcli >/dev/null 2>&1; then
  appstreamcli validate --no-net "$APPDIR/usr/share/metainfo/${APP_ID}.metainfo.xml" \
    || warn "appstreamcli validation warnings"
fi


# ───────────────────────────────
# Diagnostics (print ldd for each payload if present)
# ───────────────────────────────
print_ldd() {
  local sub="$1"
  local so="$APPDIR/usr/lib/$APP_ID/$sub/libPhotino.Native.so"
  if [[ -f "$so" ]]; then
    note "ldd on Photino native ($sub payload):"
    ldd "$so" | sed 's/^/  /' || true
  else
    warn "No libPhotino.Native.so found under $sub payload."
  fi
}
(( HAVE_41 )) && print_ldd "gtk4.1"
(( HAVE_40 )) && print_ldd "gtk4.0"

# ───────────────────────────────
# Build the AppImage
# ───────────────────────────────
OUTFILE="$OUTDIR/WPStallman-${APP_VERSION}-x86_64${APP_SUFFIX}.AppImage"
note "Building AppImage → $OUTFILE"

export APPIMAGE_EXTRACT_AND_RUN=${APPIMAGE_EXTRACT_AND_RUN:-1}
command -v appimagetool >/dev/null 2>&1 || die "appimagetool is not in PATH."

appimagetool "$APPDIR" "$OUTFILE"
chmod +x "$OUTFILE"

note "AppImage built: $OUTFILE"
