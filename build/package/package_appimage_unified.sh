#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../.."
cd "$ROOT"

# --- meta ---
META="${META:-$ROOT/release.meta}"
if [[ -f "$META" ]]; then
  set -a; source "$META"; set +a
fi

# Use release meta or fallback
APPVER="${APPVER:-0.0.0}"
APPNAME="${APP_NAME:-W. P. Stallman}"
APP_ID="${APP_ID:-com.wpstallman.app}"

# Clean basename for output filename only (not for desktop/icon IDs!)
BASENAME_CLEAN="$(echo "$APPNAME" | tr -cd '[:alnum:]._-' | sed 's/[.]*$//')"
[[ -n "$BASENAME_CLEAN" ]] || BASENAME_CLEAN="WPStallman"

MOD="$ROOT/artifacts/modern-gtk41/publish-gtk41"
LEG="$ROOT/artifacts/legacy-gtk40/publish-gtk40"
OUT="$ROOT/artifacts/packages"
# Prefer artifacts/build/AppDir if present; else use build/AppDir
APPDIR="${APPDIR:-}"
if [[ -z "${APPDIR}" ]]; then
  if [[ -d "$ROOT/artifacts/build/AppDir" ]]; then
    APPDIR="$ROOT/artifacts/build/AppDir"
  else
    APPDIR="$ROOT/build/AppDir"
  fi
fi

[[ -d "$MOD" ]] || { echo "[ERR] missing $MOD"; exit 2; }
[[ -d "$LEG" ]] || { echo "[ERR] missing $LEG"; exit 2; }

rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/lib/$APP_ID" "$OUT"

# 1) Copy payloads
cp -a "$MOD" "$APPDIR/usr/lib/$APP_ID/gtk4.1"
cp -a "$LEG" "$APPDIR/usr/lib/$APP_ID/gtk4.0"

# 2) Normalize Photino native name + hoist
normalize_photino() {
  local vdir="$1"; local src=""
  for cand in \
    "$vdir/runtimes/linux-x64/native/libPhotino.Native.so" \
    "$vdir/runtimes/linux-x64/native/Photino.Native.so" \
    "$vdir/libPhotino.Native.so" \
    "$vdir/Photino.Native.so"
  do [[ -f "$cand" ]] && { src="$cand"; break; }; done
  [[ -n "$src" ]] && cp -a "$src" "$vdir/libPhotino.Native.so" || echo "[WARN] no Photino native in $vdir"
}
normalize_photino "$APPDIR/usr/lib/$APP_ID/gtk4.1"
normalize_photino "$APPDIR/usr/lib/$APP_ID/gtk4.0"

# 3) AppRun (verbose, glibc gate, CLI/env overrides)
cat > "$APPDIR/AppRun" << 'SH'
#!/usr/bin/env bash
set -euo pipefail
APPDIR="$(cd -- "$(dirname "$0")" && pwd)"
APPROOT=""
for d in "$APPDIR"/usr/lib/*; do [[ -d "$d/gtk4.1" || -d "$d/gtk4.0" ]] && { APPROOT="$d"; break; }; done
log(){ printf '[AppRun] %s\n' "$*"; }

# Accept env and CLI overrides
FORCED="${WPStallman_FORCE_VARIANT:-}"
for arg in "$@"; do case "$arg" in --variant=gtk4.0|--gtk4.0) FORCED="gtk4.0";; --variant=gtk4.1|--gtk4.1) FORCED="gtk4.1";; esac; done
if [[ -n "$FORCED" ]]; then if [[ -d "$APPROOT/$FORCED" ]]; then PICK="$FORCED"; log "Forced variant: $FORCED"; else log "Forced '$FORCED' missing at $APPROOT/$FORCED"; FORCED=""; fi; fi

has41(){ { /sbin/ldconfig -p 2>/dev/null || /usr/sbin/ldconfig -p 2>/dev/null || true; } | grep -q 'libwebkit2gtk-4\.1\.so'; }
glibc(){ local r v; r="$(getconf GNU_LIBC_VERSION 2>/dev/null || true)"; v="${r##* }"; [[ -n "$v" ]] && echo "$v" || echo "0.0"; }
ge238(){ awk 'BEGIN{split("'"$(glibc)"'",h,"."); if ((h[1]>2)|| (h[1]==2 && h[2]>=38)) exit 0; exit 1;}'; }
buildld(){ local b="$1" o=""; for d in "$b" "$b/runtimes/linux-x64/native" "$b/native" "$b/lib"; do [[ -d "$d" ]] && case ":$o:" in *":$d:"*) ;; *) o="${o:+$o:}$d";; esac; done; echo "$o"; }
if [[ -z "${PICK:-}" ]]; then H="$(glibc)"; H41=0; has41 && H41=1; GE=1; ge238 || GE=0; log "Host glibc: $H ; has 4.1: $H41 ; glibc>=2.38: $GE"
  if [[ $H41 -eq 1 && $GE -eq 1 ]]; then PICK=gtk4.1; elif [[ -d "$APPROOT/gtk4.0" ]] && [[ $GE -eq 0 || $H41 -eq 0 ]]; then PICK=gtk4.0; elif [[ -d "$APPROOT/gtk4.1" ]]; then PICK=gtk4.1; else PICK=""; fi; fi
[[ -n "$PICK" ]] || { cat <<'MSG'
W. P. Stallman needs WebKitGTK:
Ubuntu 24.04+/Mint 22:  sudo apt install libwebkit2gtk-4.1-0 libjavascriptcoregtk-4.1-0
Ubuntu 22.04/Mint 21 :  sudo apt install libwebkit2gtk-4.0-37 libjavascriptcoregtk-4.0-18
MSG
  exit 127; }
PAYDIR="$APPROOT/$PICK"; export DOTNET_BUNDLE_EXTRACT_BASE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/WPStallman/dotnet_bundle"
export LD_LIBRARY_PATH="$(buildld "$PAYDIR")${LD_LIBRARY_PATH+:${LD_LIBRARY_PATH}}"
log "Variant picked: $PICK"; log "LD_LIBRARY_PATH:"; printf '  %s\n' $(echo "$LD_LIBRARY_PATH" | tr ':' ' ')
if [[ -x "$APPROOT/WPStallman.Launcher" ]]; then exec "$APPROOT/WPStallman.Launcher" "$@"; fi
if [[ -x "$PAYDIR/WPStallman.GUI" ]]; then exec "$PAYDIR/WPStallman.GUI" "$@"; elif [[ -f "$PAYDIR/WPStallman.GUI.dll" ]]; then exec dotnet "$PAYDIR/WPStallman.GUI.dll" "$@"; else echo "[ERR] no GUI entry in $PAYDIR"; ls -l "$PAYDIR"; exit 67; fi
SH
chmod +x "$APPDIR/AppRun"

# 4) Desktop + icon (root-level .desktop required)
DESKTOP_ID="${APP_ID}.desktop"                  # <-- stable desktop id
DESKTOP_ROOT="$APPDIR/$DESKTOP_ID"

# Use full APP_ID for Icon= (matches hicolor install and AppStream)
ICON_BASENAME="${APP_ID}"

mkdir -p "$APPDIR/usr/share/applications" "$APPDIR/usr/share/icons/hicolor/256x256/apps"

cat > "$DESKTOP_ROOT" <<EOF
[Desktop Entry]
Name=${APPNAME}
Comment=${APP_SHORTDESC:-Document your entire MySQL database in Markdown format}
Exec=AppRun
Icon=${ICON_BASENAME}
Type=Application
Categories=Development;Database;
Terminal=false
EOF

# Try to source a 256px icon from the payloads; fallback to APP_ICON_SRC
ICON_SRC=""
for cand in \
  "$APPDIR/usr/lib/$APP_ID/gtk4.1/wwwroot/img/WPS-256.png" \
  "$APPDIR/usr/lib/$APP_ID/gtk4.0/wwwroot/img/WPS-256.png" \
  "$ROOT/${APP_ICON_SRC:-}"
do
  [[ -f "$cand" ]] && { ICON_SRC="$cand"; break; }
done

if [[ -n "$ICON_SRC" ]]; then
  # ensure 256x256 if ImageMagick is available
  if command -v identify >/dev/null 2>&1; then
    sz="$(identify -format '%wx%h' "$ICON_SRC" 2>/dev/null || echo '')"
    if [[ "$sz" != "256x256" ]]; then
      convert "$ICON_SRC" -resize 256x256 "$APPDIR/${ICON_BASENAME}.png"
    else
      cp -a "$ICON_SRC" "$APPDIR/${ICON_BASENAME}.png"
    fi
  else
    cp -a "$ICON_SRC" "$APPDIR/${ICON_BASENAME}.png"
  fi
  cp -a "$APPDIR/${ICON_BASENAME}.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/${ICON_BASENAME}.png"
else
  echo "[WARN] No icon found for AppDir; Icon=${ICON_BASENAME}"
fi

cp -a "$DESKTOP_ROOT" "$APPDIR/usr/share/applications/$DESKTOP_ID"

# 5) AppStream: generate and install into AppDir/usr/share/metainfo
export APPDIR   # let the generator know where to write
GEN="$ROOT/build/package/generate_appstream.sh"
if [[ -x "$GEN" ]]; then
  echo "[INFO] Generating AppStream metadata..."
  "$GEN"
  META_FILE="$APPDIR/usr/share/metainfo/${APP_ID}.metainfo.xml"
  if [[ -f "$META_FILE" ]]; then
    echo "[OK] AppStream present: $META_FILE"
  else
    echo "[ERR] AppStream generation ran but file missing: $META_FILE"; exit 3
  fi
else
  echo "[ERR] Missing generator: $GEN"
  echo "      Create it (or make it executable) and rerun."
  exit 3
fi

# 6) appimagetool & pack
AIT="$ROOT/tools/appimagetool-x86_64.AppImage"
if [[ ! -x "$AIT" ]]; then
  mkdir -p "$ROOT/tools"
  curl -L -o "$AIT" https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
  chmod +x "$AIT"
fi
OUTFILE="$OUT/${BASENAME_CLEAN}-${APPVER}-x86_64-unified.AppImage"
"$AIT" "$APPDIR" "$OUTFILE"
( cd "$OUT" && sha256sum "$(basename "$OUTFILE")" > "$(basename "$OUTFILE").sha256" )
echo "[OK] AppImage -> $OUTFILE"
