#!/usr/bin/env bash
set -euo pipefail

note(){ printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[WARN]\033[0m %s\n" "$*" >&2; }
die(){  printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; exit 1; }

ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT"

# Defaults
: "${GUI_CSPROJ:=src/WPStallman.GUI/WPStallman.GUI.csproj}"
: "${TFM_LIN_GUI:=net8.0}"
: "${RID_LIN:=linux-x64}"

GTK40_SRC="${GTK40_SRC:-}"
GTK41_SRC="${GTK41_SRC:-}"

# Where to stage (matches your release layout)
: "${ARTIFACTS_DIR:=artifacts}"
: "${DIST_DIR:=$ARTIFACTS_DIR/dist}"
LINUX_DIR="$DIST_DIR/linux"
STAGE41="$LINUX_DIR/gtk4.1"
STAGE40="$LINUX_DIR/gtk4.0"

# Ensure tree exists even on clean runs
mkdir -p "$STAGE41" "$STAGE40"

positional=()

is_number_token(){ [[ "$1" =~ ^[0-9]+(\.[0-9]+)*$ ]]; }      # e.g. 2.35
is_kv_token(){ [[ "$1" == *=* ]]; }                          # e.g. glibc=2.35

usage() {
  cat <<EOF
Usage: $(basename "$0") [--gtk41 PATH] [--gtk40 PATH]
       $(basename "$0") [PATH_1] [PATH_2]
Stages:
  $STAGE41
  $STAGE40
Env:
  DIST_DIR (default: artifacts/dist)
EOF
}

# Parse args (flags OR bare paths). Ignore numeric/kv stray tokens (e.g. "2.35")
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gtk41) GTK41_SRC="${2:?path required}"; shift 2;;
    --gtk40) GTK40_SRC="${2:?path required}"; shift 2;;
    -h|--help) usage; exit 0;;
    --*) die "Unknown option: $1";;
    *)
      if is_number_token "$1" || is_kv_token "$1"; then
        warn "Ignoring non-path token: $1"
        shift
      else
        positional+=("$1"); shift
      fi
      ;;
  esac
done

# Version (nice to print)
get_msbuild_prop(){ dotnet msbuild "$1" -nologo -getProperty:"$2" 2>/dev/null | tr -d '\r' | tail -n1; }
get_version_from_props(){ local p="$ROOT/Directory.Build.props"; [[ -f "$p" ]] && grep -oP '(?<=<Version>).*?(?=</Version>)' "$p" | head -n1 || echo ""; }
resolve_app_version(){ local v; v="$(get_msbuild_prop "$GUI_CSPROJ" "Version")"; [[ -z "$v" || "$v" == "*Undefined*" ]] && v="$(get_version_from_props)"; echo "$v"; }
APP_VERSION="${APP_VERSION_OVERRIDE:-$(resolve_app_version)}"
[[ -n "$APP_VERSION" ]] && note "Version: $APP_VERSION" || warn "Version unresolved (ok)."

# If bare paths provided, use up to two of them; ignore extras with a warning
if (( ${#positional[@]} > 0 )); then
  # keep only directories
  filtered=()
  for p in "${positional[@]}"; do
    if [[ -d "$p" ]]; then filtered+=("$p"); else warn "Ignoring non-directory token: $p"; fi
  done
  positional=("${filtered[@]}")
  if (( ${#positional[@]} == 1 )); then
    so="${positional[0]}/libPhotino.Native.so"
    if [[ -f "$so" ]] && ldd "$so" 2>/dev/null | grep -q 'libwebkit2gtk-4\.1\.so\.0'; then
      GTK41_SRC="${positional[0]}"
    elif [[ -f "$so" ]] && ldd "$so" 2>/dev/null | grep -q 'libwebkit2gtk-4\.0\.so\.37'; then
      GTK40_SRC="${positional[0]}"
    else
      warn "Could not detect variant from $so; assuming gtk4.1"
      GTK41_SRC="${positional[0]}"
    fi
  elif (( ${#positional[@]} >= 2 )); then
    # detect each; fall back to first=gtk41, second=gtk40
    for p in "${positional[@]:0:2}"; do
      so="$p/libPhotino.Native.so"
      if [[ -f "$so" ]] && ldd "$so" 2>/dev/null | grep -q 'libwebkit2gtk-4\.1\.so\.0'; then GTK41_SRC="$p"; fi
      if [[ -f "$so" ]] && ldd "$so" 2>/dev/null | grep -q 'libwebkit2gtk-4\.0\.so\.37'; then GTK40_SRC="$p"; fi
    done
    [[ -z "${GTK41_SRC:-}" ]] && GTK41_SRC="${positional[0]}"
    [[ -z "${GTK40_SRC:-}" ]] && GTK40_SRC="${positional[1]}"
  fi
fi

# Auto-locate if still missing
[[ -n "${GTK41_SRC:-}" ]] || for c in \
  "$ROOT/src/WPStallman.GUI/bin/Release/${TFM_LIN_GUI}/${RID_LIN}/publish" \
  "$ROOT/src/WPStallman.GUI.GTK41/bin/Release/${TFM_LIN_GUI}/${RID_LIN}/publish" \
  "$ROOT/artifacts/publish-gtk4.1"
do [[ -d "$c" ]] && GTK41_SRC="$c" && break; done

[[ -n "${GTK40_SRC:-}" ]] || for c in \
  "$ROOT/src/WPStallman.GUI.Legacy/bin/Release/${TFM_LIN_GUI}/${RID_LIN}/publish" \
  "$ROOT/src/DrSQLMD.GUI.GTK40/bin/Release/${TFM_LIN_GUI}/${RID_LIN}/publish" \
  "$ROOT/artifacts/publish-gtk4.0"
do [[ -d "$c" ]] && GTK40_SRC="$c" && break; done

copy_stage(){
  local src="$1" dst="$2" label="$3"
  [[ -z "$src" ]] && { warn "Skipping $label — no source provided"; return 1; }
  [[ -d "$src" ]] || { warn "Skipping $label — not found: $src"; return 1; }
  note "Staging $label → $dst"
  mkdir -p "$dst"
  rsync -a --delete "$src/" "$dst/"
}

HAVE41=0; HAVE40=0
[[ -n "${GTK41_SRC:-}" ]] && copy_stage "$GTK41_SRC" "$STAGE41" "gtk4.1" && HAVE41=1 || true
[[ -n "${GTK40_SRC:-}" ]] && copy_stage "$GTK40_SRC" "$STAGE40" "gtk4.0" && HAVE40=1 || true
(( HAVE41==1 || HAVE40==1 )) || die "Nothing staged. Provide --gtk41/--gtk40 or positional path(s)."

# Quick native lib presence check
for d in "$STAGE41" "$STAGE40"; do
  [[ -d "$d" ]] || continue
  [[ -f "$d/libPhotino.Native.so" ]] || warn "No libPhotino.Native.so in $(basename "$d")"
done

note "Done. Staged dirs:"
[[ -d "$STAGE41" ]] && echo "  $STAGE41"
[[ -d "$STAGE40" ]] && echo "  $STAGE40"
