#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../.."
cd "$ROOT"

# Defaults; overridable by release.meta
APP_NAME_META="${APP_NAME_META:-W.P. Stallman}"
APP_ID_META="${APP_ID_META:-com.wpstallman.app}"
APP_NAME_SHORT="${APP_NAME_SHORT:-wpstallman}"
APP_SHORTDESC_META="${APP_SHORTDESC_META:-WordPress scaffolding &amp; packaging toolkit}"
APP_DESC_META="${APP_DESC_META:-W.P. Stallman is a toolkit designed for WordPress developers to easily scaffold, package, and deploy WordPress plugins and projects.}"
HOMEPAGE_URL="${HOMEPAGE_URL:-https://lefthandenterprises.com/#/projects/wpstallman}"

META="${META:-$ROOT/build/package/release.meta}"
if [[ -f "$META" ]]; then set -a; source "$META"; set +a; fi

APPVER="${APPVER:-${APP_VERSION:-$(grep -m1 -oP '(?<=<Version>)[^<]+' "$ROOT/Directory.Build.props" 2>/dev/null || echo 1.0.0)}}"
APPNAME="${APP_NAME:-$APP_NAME_META}"
APP_ID="${APP_ID:-$APP_ID_META}"
BASENAME_CLEAN="$(echo "${APP_NAME_SHORT:-$APPNAME}" | tr -cd '[:alnum:]._-' | sed 's/[.]*$//')"
[[ -n "$BASENAME_CLEAN" ]] || BASENAME_CLEAN="wpstallman"

MOD="${MOD:-$ROOT/artifacts/modern-gtk41/publish-gtk41}"
LEG="${LEG:-$ROOT/artifacts/legacy-gtk40/publish-gtk40}"
OUT="$ROOT/artifacts/packages"
APPDIR="$ROOT/build/AppDir"

[[ -d "$MOD" ]] || { echo "[ERR] missing $MOD"; exit 2; }
[[ -d "$LEG" ]] || { echo "[ERR] missing $LEG"; exit 2; }

rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/lib/$APP_ID" "$OUT"

# payloads
cp -a "$MOD" "$APPDIR/usr/lib/$APP_ID/gtk4.1"
cp -a "$LEG" "$APPDIR/usr/lib/$APP_ID/gtk4.0"

# icons: brand with APP_NAME_SHORT, plus fallback app.png for appimagetool
ICON_SRC="$ROOT/src/WPStallman.Assets/logo/app-icon-256.png"
if [[ -f "$ICON_SRC" ]]; then
  cp -a "$ICON_SRC" "$APPDIR/${APP_NAME_SHORT}.png"
  cp -a "$ICON_SRC" "$APPDIR/app.png"
else
  echo "[WARN] icon not found at $ICON_SRC"
fi

# normalize Photino Native
normalize_photino() {
  local vdir="$1" src=""
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

# AppRun
cat > "$APPDIR/AppRun" << 'SH'
#!/usr/bin/env bash
set -euo pipefail
APPDIR="$(cd -- "$(dirname "$0")" && pwd)"
APPROOT=""; for d in "$APPDIR"/usr/lib/*; do [[ -d "$d/gtk4.1" || -d "$d/gtk4.0" ]] && { APPROOT="$d"; break; }; done
log(){ printf '[AppRun] %s\n' "$*"; }

FORCED="${WPSTALLMAN_FORCE_VARIANT:-}"
for arg in "$@"; do case "$arg" in --variant=gtk4.0|--gtk4.0) FORCED="gtk4.0";; --variant=gtk4.1|--gtk4.1) FORCED="gtk4.1";; esac; done
if [[ -n "${FORCED:-}" && -d "$APPROOT/$FORCED" ]]; then PICK="$FORCED"; log "Forced variant: $FORCED"; fi

has41(){ { /sbin/ldconfig -p 2>/dev/null || /usr/sbin/ldconfig -p 2>/dev/null || true; } | grep -q 'libwebkit2gtk-4\.1\.so'; }
glibc(){ local r v; r="$(getconf GNU_LIBC_VERSION 2>/dev/null || true)"; v="${r##* }"; echo "${v:-0.0}"; }
ge238(){ awk 'BEGIN{split("'"$(glibc)"'",h,"."); if ((h[1]>2)|| (h[1]==2 && h[2]>=38)) exit 0; exit 1;}'; }
buildld(){ local b="$1" o=""; for d in "$b" "$b/runtimes/linux-x64/native" "$b/native" "$b/lib"; do [[ -d "$d" ]] && case ":$o:" in *":$d:"*) ;; *) o="${o:+$o:}$d";; esac; done; echo "$o"; }

if [[ -z "${PICK:-}" ]]; then H="$(glibc)"; H41=0; has41 && H41=1; GE=1; ge238 || GE=0; log "Host glibc: $H ; has 4.1: $H41 ; ge>=2.38: $GE"
  if [[ $H41 -eq 1 && $GE -eq 1 ]]; then PICK=gtk4.1
  elif [[ -d "$APPROOT/gtk4.0" ]]; then PICK=gtk4.0
  elif [[ -d "$APPROOT/gtk4.1" ]]; then PICK=gtk4.1
  else echo "[ERR] no payloads"; exit 67; fi
fi

PAYDIR="$APPROOT/$PICK"
export DOTNET_BUNDLE_EXTRACT_BASE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/WPStallman/dotnet_bundle"
export LD_LIBRARY_PATH="$(buildld "$PAYDIR")${LD_LIBRARY_PATH+:${LD_LIBRARY_PATH}}"
log "Variant picked: $PICK"

if [[ -x "$PAYDIR/WPStallman.GUI" ]]; then exec "$PAYDIR/WPStallman.GUI" "$@"
elif [[ -f "$PAYDIR/WPStallman.GUI.dll" ]]; then exec dotnet "$PAYDIR/WPStallman.GUI.dll" "$@"
else echo "[ERR] no GUI entry in $PAYDIR"; ls -l "$PAYDIR"; exit 67; fi
SH
chmod +x "$APPDIR/AppRun"

# ---------------------------
# Desktop entry (APP_ID-based)
# ---------------------------
DESKTOP_BASENAME="${APP_ID}.desktop"
DESKTOP_ROOT="$APPDIR/$DESKTOP_BASENAME"
cat > "$DESKTOP_ROOT" <<EOF
[Desktop Entry]
Name=${APP_NAME}
Comment=${APP_SHORTDESC_META}
Exec=AppRun
Icon=${APP_NAME_SHORT}
Type=Application
Categories=Development;
Terminal=false
# NOTE: do NOT add ContentRating here; non-standard keys must be prefixed X-,
# and AppStream ratings belong in the AppStream XML (OARS), not the .desktop.
EOF


# Ensure hi-color icon too
if [[ -f "$ICON_SRC" ]]; then
  mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"
  cp -a "$ICON_SRC" "$APPDIR/usr/share/icons/hicolor/256x256/apps/${APP_NAME_SHORT}.png"
fi

# ----------------------------------------
# AppStream metadata (AppData / metainfo)
# ----------------------------------------
mkdir -p "$APPDIR/usr/share/metainfo"
APPDATA_PATH="$APPDIR/usr/share/metainfo/${APP_ID}.appdata.xml"
cat > "$APPDATA_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop">
  <!-- id MUST match the .desktop basename -->
  <id>${APP_ID}.desktop</id>
  <name>${APP_NAME}</name>
  <summary>${APP_SHORTDESC_META}</summary>
  <description>
    <p>${APP_DESC_META}</p>
  </description>
  <metadata_license>CC0-1.0</metadata_license>
  <project_license>${LICENSE_ID:-MIT}</project_license>
  <url type="homepage">${HOMEPAGE_URL%#*}</url>
  <provides>
    <id>${APP_ID}</id>
  </provides>
  <releases>
    <release version="${APPVER}" date="$(date +%Y-%m-%d)"/>
  </releases>
  <!-- OARS content rating (note the underscore in 'content_rating') -->
  <content_rating type="oars-1.1">
    <content_attribute id="violence-cartoon">none</content_attribute>
    <content_attribute id="violence-fantasy">none</content_attribute>
    <content_attribute id="violence-realistic">none</content_attribute>
    <content_attribute id="violence-bloodshed">none</content_attribute>
    <content_attribute id="drugs-alcohol">none</content_attribute>
    <content_attribute id="drugs-narcotics">none</content_attribute>
    <content_attribute id="sex-nudity">none</content_attribute>
    <content_attribute id="sex-themes">none</content_attribute>
    <content_attribute id="language-profanity">none</content_attribute>
    <content_attribute id="social-chat">none</content_attribute>
  </content_rating>
</component>
EOF

echo "[INFO] AppStream metadata generated at: $APPDATA_PATH"


# Echo the path of the generated metadata for verification
echo "[INFO] AppStream metadata generated at: $APPDATA_PATH"

# Build AppImage
AIT="$ROOT/tools/appimagetool-x86_64.AppImage"
[[ -x "$AIT" ]] || { mkdir -p "$ROOT/tools"; curl -L -o "$AIT" https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage; chmod +x "$AIT"; }
OUTFILE="$OUT/${BASENAME_CLEAN}-${APPVER}${APP_VER_SUFFIX:-}-x86_64-unified.AppImage"
"$AIT" "$APPDIR" "$OUTFILE"
( cd "$OUT" && sha256sum "$(basename "$OUTFILE")" > "$(basename "$OUTFILE").sha256" )
echo "[OK] AppImage -> $OUTFILE"
