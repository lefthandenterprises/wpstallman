#!/usr/bin/env bash
set -euo pipefail

note(){ printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[WARN]\033[0m %s\n" "$*" >&2; }
die(){  printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; exit 1; }

ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT"

# Match stage_variants layout
: "${ARTIFACTS_DIR:=artifacts}"
: "${DIST_DIR:=$ARTIFACTS_DIR/dist}"
LINUX_DIR="$DIST_DIR/linux"
STAGE41="${STAGE41:-$LINUX_DIR/gtk4.1}"
STAGE40="${STAGE40:-$LINUX_DIR/gtk4.0}"

mkdir -p "$LINUX_DIR" # keep it tidy on clean runs

# Version (nice to print)
: "${GUI_CSPROJ:=src/WPStallman.GUI/WPStallman.GUI.csproj}"
get_msbuild_prop(){ dotnet msbuild "$1" -nologo -getProperty:"$2" 2>/dev/null | tr -d '\r' | tail -n1; }
get_version_from_props(){ local p="$ROOT/Directory.Build.props"; [[ -f "$p" ]] && grep -oP '(?<=<Version>).*?(?=</Version>)' "$p" | head -n1 || echo ""; }
resolve_app_version(){ local v; v="$(get_msbuild_prop "$GUI_CSPROJ" "Version")"; [[ -z "$v" || "$v" == "*Undefined*" ]] && v="$(get_version_from_props)"; echo "$v"; }
APP_VERSION="${APP_VERSION_OVERRIDE:-$(resolve_app_version)}"
[[ -n "$APP_VERSION" ]] && note "Version: $APP_VERSION" || warn "Version unresolved (OK)."

check_payload(){
  local dir="$1" label="$2"
  printf "\n\033[1m== %s ==\033[0m\n" "$label"
  if [[ ! -d "$dir" ]]; then
    warn "Missing dir: $dir"
    return
  fi
  local so="$dir/libPhotino.Native.so"
  if [[ ! -f "$so" ]]; then
    warn "No libPhotino.Native.so in $dir"
    return
  fi

  note "ldd on libPhotino.Native.so:"
  (ldd "$so" || true) | sed 's/^/  /'

  local need_glibc
  need_glibc="$(strings "$so" | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -n1 || true)"
  [[ -n "$need_glibc" ]] && note "Detected GLIBC floor: $need_glibc" || warn "Could not detect GLIBC floor."

  local has_gtk41="no" has_gtk40="no"
  ldd "$so" 2>/dev/null | grep -q 'libwebkit2gtk-4\.1\.so\.0' && has_gtk41="yes"
  ldd "$so" 2>/dev/null | grep -q 'libwebkit2gtk-4\.0\.so\.37' && has_gtk40="yes"

  if [[ "$has_gtk41" == "yes" ]]; then
    echo "→ WebKitGTK: 4.1 (Ubuntu 24.04+). Suggested .deb Depends:"
    echo "   libc6 (>= 2.38), libstdc++6 (>= 13), libgtk-3-0, libnotify4, libgdk-pixbuf-2.0-0, libnss3, libjavascriptcoregtk-4.1-0, libwebkit2gtk-4.1-0"
  elif [[ "$has_gtk40" == "yes" ]]; then
    echo "→ WebKitGTK: 4.0 (22.04). Suggested .deb Depends:"
    echo "   libgtk-3-0, libnotify4, libgdk-pixbuf-2.0-0, libnss3, libjavascriptcoregtk-4.0-18, libwebkit2gtk-4.0-37"
  else
    warn "Could not determine WebKitGTK soname from ldd."
  fi
}

note "Verifying staged Linux variants in $LINUX_DIR …"
check_payload "$STAGE41" "gtk4.1 payload ($STAGE41)"
check_payload "$STAGE40" "gtk4.0 payload ($STAGE40)"

echo
note "Verification complete."
