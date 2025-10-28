#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd -- "$(dirname "$0")" && pwd)"

APP_CANDIDATES=(
  "$SELF_DIR"
  "$SELF_DIR/usr/lib/com.WPStallman.app"
  "$SELF_DIR/usr/lib/com.wpstallman.app"
)

APPROOT=""
for r in "${APP_CANDIDATES[@]}"; do
  if [[ -d "$r/gtk4.1" || -d "$r/gtk4.0" ]]; then
    APPROOT="$r"; break
  fi
done

# Auto-discover in usr/lib if needed (handles arbitrary casing/paths)
if [[ -z "$APPROOT" && -d "$SELF_DIR/usr/lib" ]]; then
  while IFS= read -r d; do
    if [[ -d "$d/gtk4.1" || -d "$d/gtk4.0" ]]; then
      APPROOT="$d"; break
    fi
  done < <(find "$SELF_DIR/usr/lib" -maxdepth 3 -type d -iname 'com.*wpstallman*.app' -print 2>/dev/null || true)
fi

if [[ -z "$APPROOT" ]]; then
  echo "[ERR] Could not find payload (gtk4.1/ or gtk4.0/) under:"
  printf '  - %s\n' "${APP_CANDIDATES[@]}"
  echo "Tree preview:"; find "$SELF_DIR" -maxdepth 4 -type d -name 'gtk4.*' -print || true
  exit 66
fi

# Build an LD_LIBRARY_PATH that includes likely native lib locations
build_ld_path() {
  local base="$1"
  local -a dirs=(
    "$base"
    "$base/runtimes/linux-x64/native"
    "$base/native"
    "$base/lib"
  )
  local out=""
  for d in "${dirs[@]}"; do
    [[ -d "$d" ]] || continue
    case ":${out}:" in *":$d:"*) ;; *) out="${out:+${out}:}$d" ;; esac
  done
  echo "$out"
}

pick_variant() {
  case "${WPStallman_FORCE_VARIANT:-}" in
    gtk4.1|gtk4.0) echo "$WPStallman_FORCE_VARIANT"; return 0 ;;
  esac

  if { /sbin/ldconfig -p 2>/dev/null || /usr/sbin/ldconfig -p 2>/dev/null || true; } \
        | grep -Eq 'libwebkit2gtk-4\.1\.so' \
     && { /sbin/ldconfig -p 2>/dev/null || /usr/sbin/ldconfig -p 2>/dev/null || true; } \
        | grep -Eq 'libjavascriptcoregtk-4\.1\.so'; then
    echo "gtk4.1"; return 0
  fi

  [[ -d "$APPROOT/gtk4.0" ]] && { echo "gtk4.0"; return 0; }
  [[ -d "$APPROOT/gtk4.1" ]] && { echo "gtk4.1"; return 0; }
  return 1
}

variant="$(pick_variant || true)"
if [[ -z "$variant" ]]; then
  cat <<'MSG'
W. P. Stallman needs WebKitGTK:
Ubuntu 24.04+/Mint 22:  sudo apt install libwebkit2gtk-4.1-0 libjavascriptcoregtk-4.1-0
Ubuntu 22.04/Mint 21 :  sudo apt install libwebkit2gtk-4.0-37 libjavascriptcoregtk-4.0-18
MSG
  exit 127
fi

PAYDIR="$APPROOT/$variant"

# Build LD_LIBRARY_PATH with native subdirs
LD_CANDIDATES="$(build_ld_path "$PAYDIR")"
export LD_LIBRARY_PATH="${LD_CANDIDATES}${LD_LIBRARY_PATH+:${LD_LIBRARY_PATH}}"

# Prefer launcher if staged; else run GUI directly
if [[ -x "$APPROOT/WPStallman.Launcher" ]]; then
  exec "$APPROOT/WPStallman.Launcher" "$@"
fi

if [[ -x "$PAYDIR/WPStallman.GUI" ]]; then
  exec "$PAYDIR/WPStallman.GUI" "$@"
elif [[ -f "$PAYDIR/WPStallman.GUI.dll" ]]; then
  exec dotnet "$PAYDIR/WPStallman.GUI.dll" "$@"
else
  echo "[ERR] No GUI entrypoint in $PAYDIR (expected WPStallman.GUI or WPStallman.GUI.dll)."
  ls -l "$PAYDIR" || true
  exit 67
fi
