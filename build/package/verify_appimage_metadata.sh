#!/usr/bin/env bash
set -euo pipefail

# verify_appimage_metadata.sh (with report output + ELF-safe binary checks)

# ---------- helpers ----------
script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$script_dir/../.." && pwd)"

REPORT_DIR="$ROOT/build/package"
REPORT_FILE="$REPORT_DIR/verify_appimage_metadata_report.txt"
mkdir -p "$REPORT_DIR"
: > "$REPORT_FILE"   # clear each run

teeout(){ tee -a "$REPORT_FILE"; }
note(){ printf "\e[1;34m[INFO]\e[0m %s\n" "$1" | teeout; }
warn(){ printf "\e[1;33m[WARN]\e[0m %s\n" "$1" | teeout; }
err(){  printf "\e[1;31m[ERR ]\e[0m %s\n" "$1" | teeout; }
hr(){   printf -- "------------------------------------------------------------\n" | teeout; }
say(){  printf "%s\n" "$1" | teeout; }
have(){ command -v "$1" >/dev/null 2>&1; }
run(){ printf "$ %s\n" "$*" | teeout; { "$@" 2>&1 || true; } | teeout; }

# ---------- inputs ----------
APPIMAGE_PATH="${1:-}"
META_FILE="${META:-$ROOT/build/package/release.meta}"

# try to locate newest AppImage if not provided
if [[ -z "${APPIMAGE_PATH:-}" ]]; then
  mapfile -d '' cand < <(find "$ROOT/artifacts" -maxdepth 3 -type f -iname '*.appimage' -print0 2>/dev/null || true)
  if [[ "${#cand[@]}" -eq 0 ]]; then
    err "No .AppImage found under $ROOT/artifacts. Pass a path explicitly."
    exit 2
  fi
  IFS=$'\n' read -r -d '' -a sorted < <(printf '%s\0' "${cand[@]}" | xargs -0 ls -t 2>/dev/null && printf '\0')
  APPIMAGE_PATH="${sorted[0]}"
fi
[[ -f "$APPIMAGE_PATH" ]] || { err "AppImage not found: $APPIMAGE_PATH"; exit 2; }

# ---------- expected metadata (optional) ----------
declare -A EXP=()
if [[ -f "$META_FILE" ]]; then
  note "Loading expected metadata from: $META_FILE"
  # shellcheck disable=SC1090
  set -a; source "$META_FILE"; set +a
  EXP[APP_NAME]="${APP_NAME_META:-${APP_NAME:-}}"
  EXP[APP_ID]="${APP_ID_META:-${APP_ID:-}}"
  EXP[SHORT_DESC]="${APP_SHORTDESC_META:-${APP_SHORTDESC:-}}"
  EXP[VERSION]="${APP_VERSION_META:-${APPVER:-}}"
else
  warn "No release.meta at $META_FILE (skipping expected-vs-actual unless fields discovered)."
fi

# ---------- tooling presence ----------
if ! have sha256sum; then warn "sha256sum not found (hash step skipped)"; fi
if ! have appstreamcli; then warn "appstreamcli not found (AppStream validation skipped)"; fi
if ! have desktop-file-validate; then warn "desktop-file-validate not found (.desktop validation skipped)"; fi
if ! have readelf; then warn "readelf not found (ELF inspection reduced)"; fi
if ! have ldd; then warn "ldd not found (ELF dependency check skipped)"; fi
if ! have file; then warn "'file' not found (file-type detection reduced)"; fi
if ! have unsquashfs; then warn "unsquashfs not found (fallback relies on --appimage-extract)"; fi
if ! have identify; then warn "ImageMagick 'identify' not found (icon size detection limited)"; fi

# ---------- BASIC INFO ----------
hr
note "BASIC INFO"
sz=$(stat -c '%s' "$APPIMAGE_PATH" 2>/dev/null || stat -f '%z' "$APPIMAGE_PATH")
mt=$(stat -c '%y' "$APPIMAGE_PATH" 2>/dev/null || stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$APPIMAGE_PATH")
say "Root:      $ROOT"
say "Report:    $REPORT_FILE"
say "File:      $APPIMAGE_PATH"
say "Size:      ${sz} bytes"
say "Modified:  ${mt}"
if have sha256sum; then
  printf "SHA256:    " | teeout
  sha256sum "$APPIMAGE_PATH" | awk '{print $1}' | teeout
fi
say ""

# ---------- runtime flags ----------
hr
note "APPIMAGE RUNTIME FLAGS (if supported)"
for flag in --appimage-version --appimage-offset --appimage-type --appimage-signature --appimage-checksign; do
  if "$APPIMAGE_PATH" "$flag" >/dev/null 2>&1; then
    printf "%-20s" "$flag" | teeout
    "$APPIMAGE_PATH" "$flag" 2>&1 | teeout
  fi
done
say ""

# ---------- extract squashfs ----------
work="$(mktemp -d)"
cleanup(){ rm -rf "$work" || true; }
trap cleanup EXIT

note "Extracting squashfs payload..."
if "$APPIMAGE_PATH" --appimage-extract >/dev/null 2>&1; then
  mv -f squashfs-root "$work/squashfs-root"
elif have unsquashfs; then
  run unsquashfs -d "$work/squashfs-root" "$APPIMAGE_PATH"
else
  err "Could not extract AppImage (need --appimage-extract or unsquashfs)."
  exit 3
fi
rootd="$work/squashfs-root"

# ---------- .desktop entries ----------
hr
note ".DESKTOP ENTRIES"
mapfile -d '' desktop_files < <(find "$rootd" -type f -name '*.desktop' -print0)
if [[ "${#desktop_files[@]}" -eq 0 ]]; then
  warn "No .desktop files found in AppImage."
else
  for d in "${desktop_files[@]}"; do
    say "File: ${d#"$rootd/"}"
    say "----"
    awk -F= '
      BEGIN{IGNORECASE=1}
      /^\[/ { sect=$0 }
      /^Name=|^Comment=|^Exec=|^TryExec=|^Icon=|^Categories=|^Type=|^Terminal=|^StartupWMClass=|^X-AppImage-BuildId=|^X-AppImage-Name=|^X-AppImage-Version=/ {
        print $1": " $2
      }' "$d" | teeout
    say ""
    if have desktop-file-validate; then
      say "Validation:"
      { desktop-file-validate "$d" 2>&1 && echo "  OK"; } | sed 's/^/  /' | teeout
      say ""
    fi
  done
fi

# ---------- AppStream ----------
hr
note "APPSTREAM (appdata/metainfo)"
mapfile -d '' appstream_files < <(find "$rootd" -type f \( -name '*.metainfo.xml' -o -name '*.appdata.xml' \) -print0)
if [[ "${#appstream_files[@]}" -eq 0 ]]; then
  warn "No AppStream files found (usr/share/metainfo/*.metainfo.xml | *.appdata.xml)."
else
  for a in "${appstream_files[@]}"; do
    say "File: ${a#"$rootd/"}"
    say "----"
    grep -Eo '<(id|name|summary|developer_name|project_license)>([^<]+)</\1>' "$a" \
      | sed -E 's#<([^>]+)>([^<]+)</\1>#\1: \2#g' | teeout
    latest_ver=$(grep -Eo '<release[^>]*version="[^"]+"' "$a" | head -n1 | sed -E 's/.*version="([^"]+)".*/\1/')
    latest_date=$(grep -Eo '<release[^>]*date="[^"]+"' "$a" | head -n1 | sed -E 's/.*date="([^"]+)".*/\1/')
    [[ -n "${latest_ver:-}${latest_date:-}" ]] && say "latest release: ${latest_ver:-?} (${latest_date:-?})"
    say ""
    if have appstreamcli; then
      say "Validation:"
      { appstreamcli validate "$a" 2>&1 && echo "  OK"; } | sed 's/^/  /' | teeout
      say ""
    fi
  done
fi

# ---------- icons ----------
hr
note "ICON ASSETS (paths and sizes)"
mapfile -d '' icon_files < <(find "$rootd" -type f \( -iname '*.png' -o -iname '*.svg' -o -iname '*.svgz' -o -iname '*.ico' \) -print0)
if [[ "${#icon_files[@]}" -eq 0 ]]; then
  warn "No icon files found."
else
  printf "%-8s  %-8s  %s\n" "TYPE" "SIZE" "PATH" | teeout
  for i in "${icon_files[@]}"; do
    ext="${i##*.}"; typ="${ext,,}"
    size="?"
    case "$typ" in
      png|ico) size="$(identify -format '%wx%h' "$i" 2>/dev/null || echo '?')" ;;
      svg|svgz) size="vector" ;;
    esac
    rel="${i#"$rootd/"}"
    printf "%-8s  %-8s  %s\n" "$typ" "$size" "$rel" | teeout
  done
fi
say ""

# ---------- binaries & deps (ELF-safe) ----------
hr
note "PRIMARY BINARIES & DEP CHECKS"
cands=()
[[ -x "$rootd/AppRun" ]] && cands+=("$rootd/AppRun")
[[ -x "$rootd/usr/bin/AppRun" ]] && cands+=("$rootd/usr/bin/AppRun")
while IFS= read -r -d '' f; do cands+=("$f"); done < <(find "$rootd/usr/bin" -maxdepth 1 -type f -perm -111 -print0 2>/dev/null || true)

if [[ "${#cands[@]}" -eq 0 ]]; then
  warn "No obvious entrypoint binaries found (AppRun or usr/bin/*)."
else
  for b in "${cands[@]}"; do
    say "Binary: ${b#"$rootd/"}"

    # type detection
    is_elf=0
    if have file; then
      fsum="$(file "$b" 2>&1)"
      echo "  $fsum" | teeout
      echo "$fsum" | grep -q 'ELF' && is_elf=1 || is_elf=0
    else
      is_elf=1
    fi

    if [[ "$is_elf" -eq 1 ]]; then
      # GLIBC symbols (non-fatal)
      if have readelf; then
        need="$( (readelf -V "$b" 2>/dev/null || true) | grep -Eo 'GLIBC_([0-9]+\.)+[0-9]+' | sort -u | tr '\n' ' ' )"
        [[ -n "${need:-}" ]] && say "  Requires: $need"
      fi
      # ldd summary (non-fatal)
      if have ldd; then
        say "  ldd summary:"
        ( ldd "$b" 2>&1 || true ) | sed 's/^/    /' | teeout
      fi
    else
      say "  (non-ELF executable; skipping readelf/ldd)"
    fi
    say ""
  done
fi

# ---------- EXPECTED vs ACTUAL ----------
if [[ -n "${EXP[APP_NAME]:-}${EXP[APP_ID]:-}${EXP[SHORT_DESC]:-}${EXP[VERSION]:-}" ]]; then
  hr
  note "EXPECTED vs ACTUAL (best-effort quick check)"
  ACT_NAME=""; ACT_COMMENT=""; ACT_ID=""; ACT_VERSION=""
  # first .desktop
  mapfile -t _dtmp < <(printf "%s\n" "${desktop_files[@]}")
  if [[ "${#_dtmp[@]}" -gt 0 ]]; then
    d="${_dtmp[0]}"
    ACT_NAME="$(grep -E '^Name=' "$d" | head -n1 | cut -d= -f2- || true)"
    ACT_COMMENT="$(grep -E '^Comment=' "$d" | head -n1 | cut -d= -f2- || true)"
  fi
  # first appstream
  mapfile -t _atmp < <(printf "%s\n" "${appstream_files[@]:-}")
  if [[ "${#_atmp[@]}" -gt 0 ]]; then
    a="${_atmp[0]}"
    ACT_ID="$(grep -Eo '<id>[^<]+'</ "$a" | head -n1 | sed -E 's#<id>([^<]+)#\1#' || true)"
    ACT_VERSION="$(grep -Eo '<release[^>]*version="[^"]+"' "$a" | head -n1 | sed -E 's/.*version="([^"]+)".*/\1/' || true)"
  fi

  printf "%-12s | %-36s | %-36s\n" "Field" "Expected" "Actual" | teeout
  printf "%-12s-+-%-36s-+-%-36s\n" "------------" "------------------------------------" "------------------------------------" | teeout
  printf "%-12s | %-36s | %-36s\n" "APP_NAME"   "${EXP[APP_NAME]:-}"   "${ACT_NAME:-}" | teeout
  printf "%-12s | %-36s | %-36s\n" "APP_ID"     "${EXP[APP_ID]:-}"     "${ACT_ID:-}" | teeout
  printf "%-12s | %-36s | %-36s\n" "SHORT_DESC" "${EXP[SHORT_DESC]:-}" "${ACT_COMMENT:-}" | teeout
  printf "%-12s | %-36s | %-36s\n" "VERSION"    "${EXP[VERSION]:-}"    "${ACT_VERSION:-}" | teeout
  say ""
fi

# ---------- DONE ----------
hr
note "DONE."
say "Full report written to: $REPORT_FILE"
