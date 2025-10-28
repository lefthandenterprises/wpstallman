#!/usr/bin/env bash
# build/package/package_folder_mock.sh
# Safe staging of the W. P. Stallman "package folder" + robust runner emission.
# Non-destructive by default. Only gtk subdirs are cleaned if --clean-subdirs is given.

set -euo pipefail

GTK41_DIR=""
GTK40_DIR=""
LAUNCHER_PATH=""
OUT_DIR="."
CLEAN_SUBDIRS="0"
ALLOW_ANY_OUTDIR="${ALLOW_ANY_OUTDIR:-0}"   # set to 1 to allow outdirs that don't include build/package

usage() {
  cat <<USG
Usage: $(basename "$0") [--gtk41 DIR] [--gtk40 DIR] [--launcher FILE] [--out DIR] [--clean-subdirs]

  --gtk41 DIR        Path to gtk4.1 publish directory (optional; reuses staged if omitted)
  --gtk40 DIR        Path to gtk4.0 publish directory (optional)
  --launcher FILE    Path to WPStallman.Launcher (optional)
  --out DIR          Staging root (default: . ; usually build/package)
  --clean-subdirs    Remove ONLY usr/lib/com.wpstallman.app/gtk4.1 and gtk4.0 before copying

Safety:
  • Refuses suspicious OUT_DIR (/, \$HOME, repo root).
  • By default OUT_DIR must contain 'build/package' (override with ALLOW_ANY_OUTDIR=1).

Examples:
  $(basename "$0") --gtk41 "../../src/WPStallman.GUI.Modern/bin/Release/net8.0/linux-x64/publish-gtk41" --out "."
USG
}

# ---- args ----
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gtk41) GTK41_DIR="${2:-}"; shift 2 ;;
    --gtk40) GTK40_DIR="${2:-}"; shift 2 ;;
    --launcher) LAUNCHER_PATH="${2:-}"; shift 2 ;;
    --out) OUT_DIR="${2:-}"; shift 2 ;;
    --clean-subdirs) CLEAN_SUBDIRS="1"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[ERR] Unknown arg: $1"; usage; exit 2 ;;
  esac
done

# ---- resolve paths ----
SCRIPT_DIR="$(cd -- "$(dirname "$0")" && pwd)"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

# ---- safety checks for OUT_DIR ----
danger() { echo "[ERR] $1"; exit 2; }
is_same() { [ "$(cd "$1" && pwd)" = "$2" ]; }

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd 2>/dev/null || echo "")"
[ -z "$OUT_DIR" ] && danger "OUT_DIR resolved to empty path."
[ "$OUT_DIR" = "/" ] && danger "Refusing to stage to root '/'."
[ "$OUT_DIR" = "$HOME" ] && danger "Refusing to stage to \$HOME."

if [[ "$ALLOW_ANY_OUTDIR" != "1" ]]; then
  [[ "$OUT_DIR" == *"build/package"* ]] || danger "OUT_DIR must contain 'build/package' (got: $OUT_DIR). Set ALLOW_ANY_OUTDIR=1 to override."
fi

if [[ -n "$REPO_ROOT" ]] && is_same "$OUT_DIR" "$REPO_ROOT"; then
  danger "OUT_DIR equals repository root; refusing."
fi

echo "==> OUT_DIR: $OUT_DIR"
APPROOT="$OUT_DIR/usr/lib/com.wpstallman.app"
mkdir -p "$APPROOT"

# ---- optional cleaning of *only* our subdirs ----
if [[ "$CLEAN_SUBDIRS" = "1" ]]; then
  echo "==> Cleaning subdirs under $APPROOT (gtk4.1, gtk4.0 only)"
  rm -rf "$APPROOT/gtk4.1" "$APPROOT/gtk4.0"
else
  echo "[INFO] --clean-subdirs NOT set; preserving any existing staged content."
fi

# ---- stage gtk4.1 ----
if [[ -n "$GTK41_DIR" ]]; then
  [[ -d "$GTK41_DIR" ]] || { echo "[ERR] --gtk41 not a directory: $GTK41_DIR"; exit 2; }
  echo "==> Copy gtk4.1 from: $GTK41_DIR"
  mkdir -p "$APPROOT/gtk4.1"
  cp -a "$GTK41_DIR/." "$APPROOT/gtk4.1/"
else
  if [[ -d "$APPROOT/gtk4.1" ]]; then
    echo "[INFO] Reusing existing staged gtk4.1 in $APPROOT/gtk4.1"
  else
    echo "[WARN] No --gtk41 and none staged; gtk4.1 will be absent."
  fi
fi

# ---- stage gtk4.0 ----
if [[ -n "$GTK40_DIR" ]]; then
  [[ -d "$GTK40_DIR" ]] || { echo "[ERR] --gtk40 not a directory: $GTK40_DIR"; exit 2; }
  echo "==> Copy gtk4.0 from: $GTK40_DIR"
  mkdir -p "$APPROOT/gtk4.0"
  cp -a "$GTK40_DIR/." "$APPROOT/gtk4.0/"
else
  if [[ -d "$APPROOT/gtk4.0" ]]; then
    echo "[INFO] Reusing existing staged gtk4.0 in $APPROOT/gtk4.0"
  else
    echo "[INFO] No --gtk40 provided."
  fi
fi

# ---- optional: launcher ----
if [[ -n "${LAUNCHER_PATH}" ]]; then
  if [[ -d "$LAUNCHER_PATH" ]]; then
    echo "==> Copy launcher directory: $LAUNCHER_PATH"
    cp -a "$LAUNCHER_PATH/." "$APPROOT/"
  elif [[ -f "$LAUNCHER_PATH" ]]; then
    echo "==> Copy launcher file: $LAUNCHER_PATH"
    cp -a "$LAUNCHER_PATH" "$APPROOT/WPStallman.Launcher"
    chmod +x "$APPROOT/WPStallman.Launcher" || true
    # If framework-dependent, grab the companions from the same folder
    LDIR="$(dirname "$LAUNCHER_PATH")"
    for f in WPStallman.Launcher.dll WPStallman.Launcher.deps.json WPStallman.Launcher.runtimeconfig.json; do
      [[ -f "$LDIR/$f" ]] && cp -a "$LDIR/$f" "$APPROOT/$f"
    done
  else
    echo "[ERR] --launcher is neither a dir nor a file: $LAUNCHER_PATH"; exit 2
  fi
else
  echo "[INFO] No launcher passed; runner will execute GUI directly."
fi


# ---- case-compat symlink ----
( cd "$OUT_DIR/usr/lib" && ln -sf com.wpstallman.app com.WPStallman.app )

# ---- normalize/hoist Photino native so name (Photino.Native.so -> libPhotino.Native.so) ----
normalize_photino_so() {
  local vdir="$1"  # e.g., "$APPROOT/gtk4.1"
  local src=""
  # Look in common places, accept either filename
  for cand in \
    "$vdir/runtimes/linux-x64/native/libPhotino.Native.so" \
    "$vdir/runtimes/linux-x64/native/Photino.Native.so" \
    "$vdir/libPhotino.Native.so" \
    "$vdir/Photino.Native.so"
  do
    if [[ -f "$cand" ]]; then src="$cand"; break; fi
  done
  if [[ -n "$src" ]]; then
    local dest="$vdir/libPhotino.Native.so"
    if [[ "$src" != "$dest" ]]; then
      echo "==> Normalizing $(basename "$src") -> $(basename "$dest") in $(basename "$vdir")"
      cp -a "$src" "$dest"
    fi
  else
    echo "[WARN] Photino native .so not found in $vdir (will rely on LD_LIBRARY_PATH if present)"
  fi
}
normalize_photino_so "$APPROOT/gtk4.1"
normalize_photino_so "$APPROOT/gtk4.0"

# ---- emit robust runner ----
cat > "$OUT_DIR/run-drs-folder.sh" << 'SH'
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
SH
chmod +x "$OUT_DIR/run-drs-folder.sh"

echo "==> Staged tree (top 3 levels):"
( cd "$OUT_DIR" && find . -maxdepth 3 -type d -print | sed 's|^\./||' )
echo "==> Done. Run with:  bash $OUT_DIR/run-drs-folder.sh"
