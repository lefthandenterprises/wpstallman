#!/usr/bin/env bash
set -euo pipefail

# verify_deb_metadata.sh (with report output)
# Audits a .deb and writes a full report to build/package/verify_deb_metadata_report.txt
# while still showing everything in the console.

# ---------------- helpers ----------------
script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$script_dir/../.." && pwd)"

REPORT_DIR="$ROOT/build/package"
REPORT_FILE="$REPORT_DIR/verify_deb_metadata_report.txt"
mkdir -p "$REPORT_DIR"
: > "$REPORT_FILE"   # clear each run

teeout(){ tee -a "$REPORT_FILE"; }
note(){ printf "\e[1;34m[INFO]\e[0m %s\n" "$1" | teeout; }
warn(){ printf "\e[1;33m[WARN]\e[0m %s\n" "$1" | teeout; }
err(){  printf "\e[1;31m[ERR ]\e[0m %s\n" "$1" | teeout; }
hr(){   printf -- "------------------------------------------------------------\n" | teeout; }
say(){  printf "%s\n" "$1" | teeout; }

have(){ command -v "$1" >/dev/null 2>&1; }

# Run a command and tee stdout/stderr to report
run(){
  # Show the command (prefixed with $)
  printf "$ %s\n" "$*" | teeout
  # shellcheck disable=SC2068
  { "$@" 2>&1 || true; } | teeout
}

# ---------------- resolve inputs ----------------
DEB_PATH="${1:-}"
META_FILE="${META:-$ROOT/build/package/release.meta}"

# Try to locate a .deb under artifacts if not provided
if [[ -z "${DEB_PATH:-}" ]]; then
  mapfile -d '' cand < <(find "$ROOT/artifacts" -type f -iname '*.deb' -print0 2>/dev/null || true)
  if [[ "${#cand[@]}" -eq 0 ]]; then
    err "No .deb found under $ROOT/artifacts. Pass a path explicitly."
    exit 2
  fi
  # newest by mtime
  IFS=$'\n' read -r -d '' -a sorted < <(printf '%s\0' "${cand[@]}" | xargs -0 ls -t 2>/dev/null && printf '\0')
  DEB_PATH="${sorted[0]}"
fi
[[ -f "$DEB_PATH" ]] || { err "File not found: $DEB_PATH"; exit 2; }

# ---------------- tools ----------------
for t in dpkg-deb ar tar awk sed grep; do
  have "$t" || { err "Missing required tool: $t"; exit 3; }
done
if ! have desktop-file-validate; then warn "desktop-file-validate not found (.desktop validation skipped)"; fi
if ! have appstreamcli; then warn "appstreamcli not found (AppStream validation skipped)"; fi
if ! have lintian; then warn "lintian not found (Debian policy checks skipped)"; fi
if ! have readelf; then warn "readelf not found (GLIBC symbol inspection skipped)"; fi
if ! have ldd; then warn "ldd not found (binary dependency listing skipped)"; fi
if ! have sha256sum; then warn "sha256sum not found (hash step skipped)"; fi
if ! have file; then warn "file not found (ELF type summary skipped)"; fi
if ! have zcat; then warn "zcat not found (reading changelog.gz might be skipped)"; fi
if ! have identify; then warn "ImageMagick 'identify' not found (icon size detection limited)"; fi

# ---------------- load expectations (optional) ----------------
declare -A EXP=()
if [[ -f "$META_FILE" ]]; then
  note "Loading expected metadata from: $META_FILE"
  # shellcheck disable=SC1090
  set -a; source "$META_FILE"; set +a
  EXP[PACKAGE]="${DEB_PACKAGE_META:-${APP_ID_META:-}}"
  EXP[VERSION]="${APP_VERSION_META:-${VERSION:-}}"
  EXP[MAINTAINER]="${DEB_MAINTAINER_META:-}"
  EXP[ARCH]="${DEB_ARCH_META:-}"
  EXP[DESCRIPTION]="${APP_SHORTDESC_META:-}"
else
  warn "No release.meta at $META_FILE (skipping expected-vs-actual unless fields discovered)."
fi

# ---------------- BASIC INFO ----------------
hr
note "BASIC INFO"
sz=$(stat -c '%s' "$DEB_PATH" 2>/dev/null || stat -f '%z' "$DEB_PATH")
mt=$(stat -c '%y' "$DEB_PATH" 2>/dev/null || stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$DEB_PATH")
say "Root:      $ROOT"
say "Report:    $REPORT_FILE"
say "File:      $DEB_PATH"
say "Size:      ${sz} bytes"
say "Modified:  ${mt}"
if have sha256sum; then
  printf "SHA256:    " | teeout
  sha256sum "$DEB_PATH" | awk '{print $1}' | teeout
fi
say ""

# ---------------- dpkg-deb -I ----------------
hr
note "dpkg-deb headers (dpkg-deb -I)"
run dpkg-deb -I "$DEB_PATH"
say ""

# ---------------- extract ----------------
work="$(mktemp -d)"
cleanup(){ rm -rf "$work" || true; }
trap cleanup EXIT

note "Extracting control and data…"
run mkdir -p "$work/ctrl" "$work/root"
run dpkg-deb -e "$DEB_PATH" "$work/ctrl"
run dpkg-deb -x "$DEB_PATH" "$work/root"

CONTROL="$work/ctrl/control"
if [[ ! -f "$CONTROL" ]]; then
  err "DEBIAN/control not found inside .deb"
  exit 4
fi

# ---------------- CONTROL FIELDS ----------------
hr
note "CONTROL FIELDS (DEBIAN/control)"
declare -A ACT=()
parse_field(){
  local key="$1"
  awk -v k="$key" '
    BEGIN{IGNORECASE=1}
    $0 ~ "^"k":[[:space:]]"{
      sub("^"k":[[:space:]]*","",$0);
      print $0;
      infield=1; next
    }
    infield && $0 ~ "^[[:space:]]"{
      sub("^[[:space:]]+","",$0);
      print $0; next
    }
    {infield=0}
  ' "$CONTROL" | sed ':a;N;$!ba;s/\n/ /g'
}

for f in Package Version Architecture Maintainer Depends Recommends Suggests Section Priority Description; do
  v="$(parse_field "$f" || true)"
  ACT["$f"]="$v"
  printf "%-13s: %s\n" "$f" "${v:-}" | teeout
done
say ""

DESC_SHORT="$(awk '
  BEGIN{desc=0}
  /^Description:/ { $1=""; sub(/^ /,"",$0); print $0; desc=1; next }
  desc==1 { exit }' "$CONTROL")"
  
# --- Expected values from release.meta ---
META="${META:-$ROOT/build/package/release.meta}"
if [[ -f "$META" ]]; then
  # shellcheck disable=SC1090,SC1091
  set -a; source "$META"; set +a
else
  echo "[WARN] No release.meta found at $META"
fi

EXP_PACKAGE="${DEB_PACKAGE:-${APP_NAME_SHORT:-}}"
EXP_VERSION="${APPVER:-${APP_VERSION_META:-}}"
EXP_ARCH="${DEB_ARCH:-amd64}"
EXP_SECTION="${DEB_SECTION:-utils}"
EXP_PRIORITY="${DEB_PRIORITY:-optional}"
# Maintainer can be a single string or composed from name+email
if [[ -n "${DEB_MAINTAINER_META:-}" ]]; then
  EXP_MAINTAINER="$DEB_MAINTAINER_META"
else
  # Compose "Name <email>" when available
  if [[ -n "${APP_VENDOR_META:-}" && -n "${APP_VENDOR_EMAIL:-}" ]]; then
    EXP_MAINTAINER="${APP_VENDOR_META} <${APP_VENDOR_EMAIL}>"
  else
    EXP_MAINTAINER="${APP_VENDOR_META:-${PUBLISHER_NAME:-}}"
    [[ -n "${APP_VENDOR_EMAIL:-${PUBLISHER_EMAIL:-}}" ]] && EXP_MAINTAINER="${EXP_MAINTAINER} <${APP_VENDOR_EMAIL:-${PUBLISHER_EMAIL}}>"
  fi
fi
# Dependencies from meta (keep exact spacing+commas to compare string-for-string)
EXP_DEPENDS="$(echo "${DEB_DEPENDS:-}" | sed 's/[[:space:]]\+/ /g' | sed 's/ ,/,/g')"

# --- Expected values from release.meta ---
META="${META:-$ROOT/build/package/release.meta}"
if [[ -f "$META" ]]; then
  # shellcheck disable=SC1090,SC1091
  set -a; source "$META"; set +a
else
  warn "No release.meta found at $META"
fi

# Expected values from meta (with sane fallbacks)
EXP_PACKAGE="${DEB_PACKAGE:-${APP_NAME_SHORT:-}}"
EXP_VERSION="${APPVER:-${APP_VERSION_META:-}}"
EXP_ARCH="${DEB_ARCH:-amd64}"
EXP_SECTION="${DEB_SECTION:-utils}"
EXP_PRIORITY="${DEB_PRIORITY:-optional}"

# Maintainer: explicit string wins; otherwise compose Name <email>
if [[ -n "${DEB_MAINTAINER_META:-}" ]]; then
  EXP_MAINTAINER="$DEB_MAINTAINER_META"
else
  EXP_MAINTAINER="${APP_VENDOR_META:-${PUBLISHER_NAME:-}}"
  if [[ -n "${APP_VENDOR_EMAIL:-${PUBLISHER_EMAIL:-}}" ]]; then
    EXP_MAINTAINER="${EXP_MAINTAINER} <${APP_VENDOR_EMAIL:-${PUBLISHER_EMAIL}}>"
  fi
fi

# Depends normalization (collapse whitespace; avoid " ,")
EXP_DEPENDS="$(echo "${DEB_DEPENDS:-}" | sed 's/[[:space:]]\+/ /g; s/ ,/,/g')"

# Pull ACT fields out of the associative array (safe with set -u)
ACT_PACKAGE="${ACT[Package]:-}"
ACT_VERSION="${ACT[Version]:-}"
ACT_ARCH="${ACT[Architecture]:-}"
ACT_SECTION="${ACT[Section]:-}"
ACT_PRIORITY="${ACT[Priority]:-}"
ACT_MAINTAINER="${ACT[Maintainer]:-}"
ACT_DEPENDS_RAW="${ACT[Depends]:-}"
ACT_DEPENDS="$(echo "${ACT_DEPENDS_RAW}" | sed 's/[[:space:]]\+/ /g; s/ ,/,/g')"

# --- Expected vs Actual table ---
hr
note "EXPECTED vs ACTUAL (DEBIAN control)"

cmp_row() {
  local label="$1" exp="$2" act="$3"
  local status="OK"
  if [[ -z "$exp" || -z "$act" || "$exp" != "$act" ]]; then
    status="MISMATCH"
  fi
  printf "%-12s Expected: %s\n" "$label" "${exp:-<empty>}" | teeout
  printf "%-12s Actual:   %s\n" ""        "${act:-<empty>}" | teeout
  printf "%-12s %s\n\n" "" "$status" | teeout
}

cmp_row "Package"    "$EXP_PACKAGE"    "$ACT_PACKAGE"
cmp_row "Version"    "$EXP_VERSION"    "$ACT_VERSION"
cmp_row "Arch"       "$EXP_ARCH"       "$ACT_ARCH"
cmp_row "Section"    "$EXP_SECTION"    "$ACT_SECTION"
cmp_row "Priority"   "$EXP_PRIORITY"   "$ACT_PRIORITY"
cmp_row "Maintainer" "$EXP_MAINTAINER" "$ACT_MAINTAINER"
cmp_row "Depends"    "$EXP_DEPENDS"    "$ACT_DEPENDS"

# ---------------- LINTIAN ----------------
hr
note "LINTIAN (policy checks)"
if have lintian; then
  run lintian "$DEB_PATH"
else
  warn "lintian not installed."
fi
say ""

# ---------------- .DESKTOP ----------------
hr
note ".DESKTOP ENTRIES (usr/share/applications)"
mapfile -d '' desk < <(find "$work/root/usr/share/applications" -type f -name '*.desktop' -print0 2>/dev/null || true)
if [[ "${#desk[@]}" -eq 0 ]]; then
  warn "No .desktop found under usr/share/applications"
else
  for d in "${desk[@]}"; do
    rel="${d#"$work/root/"}"
    say "File: $rel"
    awk -F= '
      BEGIN{IGNORECASE=1}
      /^\[/ { sect=$0 }
      /^Name=|^Comment=|^Exec=|^TryExec=|^Icon=|^Categories=|^Type=|^Terminal=|^StartupWMClass=/ {print $1": " $2}
    ' "$d" | teeout
    if have desktop-file-validate; then
      say "Validation:"
      { desktop-file-validate "$d" 2>&1 && echo "  OK"; } | sed 's/^/  /' | teeout
    fi
    say ""
  done
fi

# ---------------- APPSTREAM ----------------
hr
note "APPSTREAM (usr/share/metainfo | appdata)"
mapfile -d '' meta < <(find "$work/root/usr/share" -type f \( -name '*.metainfo.xml' -o -name '*.appdata.xml' \) -print0 2>/dev/null || true)
if [[ "${#meta[@]}" -eq 0 ]]; then
  warn "No AppStream metadata found."
else
  for a in "${meta[@]}"; do
    rel="${a#"$work/root/"}"
    say "File: $rel"
    grep -Eo '<(id|name|summary|developer_name|project_license)>([^<]+)</\1>' "$a" \
      | sed -E 's#<([^>]+)>([^<]+)</\1>#\1: \2#g' | teeout
    latest_ver=$(grep -Eo '<release[^>]*version="[^"]+"' "$a" | head -n1 | sed -E 's/.*version="([^"]+)".*/\1/')
    latest_date=$(grep -Eo '<release[^>]*date="[^"]+"' "$a" | head -n1 | sed -E 's/.*date="([^"]+)".*/\1/')
    [[ -n "${latest_ver:-}${latest_date:-}" ]] && say "latest release: ${latest_ver:-?} (${latest_date:-?})"
    if have appstreamcli; then
      say "Validation:"
      { appstreamcli validate "$a" 2>&1 && echo "  OK"; } | sed 's/^/  /' | teeout
    fi
    say ""
  done
fi

# ---------------- ICONS ----------------
hr
note "ICONS (usr/share/icons|pixmaps)"
mapfile -d '' icons < <(find "$work/root/usr/share" \( -path '*/icons/*' -o -path '*/pixmaps/*' \) -type f \( -iname '*.png' -o -iname '*.svg' -o -iname '*.ico' \) -print0 2>/dev/null || true)
if [[ "${#icons[@]}" -eq 0 ]]; then
  warn "No icon assets found."
else
  printf "%-8s  %-8s  %s\n" "TYPE" "SIZE" "PATH" | teeout
  for i in "${icons[@]}"; do
    ext="${i##*.}"; typ="${ext,,}"
    size="?"
    case "$typ" in
      png|ico) size="$(identify -format '%wx%h' "$i" 2>/dev/null || echo '?')" ;;
      svg)     size="vector" ;;
    esac
    rel="${i#"$work/root/"}"
    printf "%-8s  %-8s  %s\n" "$typ" "$size" "$rel" | teeout
  done
fi
say ""

# ---------------- DOCS ----------------
hr
note "DOCS (usr/share/doc/<package>)"
pkg="${ACT[Package]:-}"
docdir="$work/root/usr/share/doc/${pkg:-}"
if [[ -d "$docdir" ]]; then
  run ls -la "$docdir"
  if [[ -f "$docdir/copyright" ]]; then
    say ""
    say "copyright head:"
    head -n 25 "$docdir/copyright" | teeout
  fi
  if [[ -f "$docdir/changelog.Debian.gz" ]]; then
    say ""
    say "changelog head:"
    zcat "$docdir/changelog.Debian.gz" | head -n 25 | teeout
  fi
else
  warn "Doc dir not found: usr/share/doc/${pkg:-<unknown>}"
fi
say ""

# ---------------- FILE LIST ----------------
hr
note "PAYLOAD FILES (dpkg-deb -c)"
run dpkg-deb -c "$DEB_PATH"
say ""

# ---------------- BINARIES ----------------
hr
note "BINARIES & DEP CHECKS"
mapfile -d '' bins < <(find "$work/root" -type f -perm -111 -print0 2>/dev/null || true)
if [[ "${#bins[@]}" -eq 0 ]]; then
  warn "No executable files found in payload."
else
  for b in "${bins[@]}"; do
    rel="${b#"$work/root/"}"
    say "Binary: $rel"

    # Summarize file type
    is_elf=0
    if have file; then
      fsum="$(file "$b" 2>&1 | sed 's/^/  /')"
      echo "$fsum" | teeout
      echo "$fsum" | grep -q 'ELF' && is_elf=1 || is_elf=0
    else
      # If 'file' is missing, assume ELF to keep older behavior
      is_elf=1
    fi

    if [[ "$is_elf" -eq 1 ]]; then
      # GLIBC symbols (tolerate failures)
      if have readelf; then
        need="$( (readelf -V "$b" 2>/dev/null || true) \
                 | grep -Eo 'GLIBC_([0-9]+\.)+[0-9]+' | sort -u | tr '\n' ' ' )"
        [[ -n "${need:-}" ]] && say "  Requires: $need"
      fi

      # ldd summary (tolerate failures)
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


# ---------------- DONE ----------------
hr
note "DONE."
say "Full report written to: $REPORT_FILE"
