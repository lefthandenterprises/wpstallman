#!/usr/bin/env bash
set -euo pipefail

# ---------- helpers ----------
note(){ printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }
warn(){ printf "\033[1;33mWARNING:\033[0m %s\n" "$*"; }
die(){  printf "\n\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }

# ---------- repo root ----------
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ---------- variant-aware output roots ----------
# Variant comes from env (release_all.sh sets VARIANT=glibc2.39 / glibc2.35)
VARIANT="${VARIANT:-glibc2.39}"     # or 'current'
RID="${RID:-linux-x64}"

# Staged input (produced by your stage script or orchestrator)
GUI_DIR="${GUI_DIR:-$ROOT/artifacts/dist/WPStallman.GUI-${RID}-${VARIANT}}"
CLI_DIR="${CLI_DIR:-$ROOT/src/WPStallman.CLI/bin/Release/net8.0/${RID}/publish}"

# App identity
APP_NAME="${APP_NAME:-W. P. Stallman}"
APP_ID="${APP_ID:-com.wpstallman.app}"         # used for paths and .desktop Icon
MAIN_BIN="${MAIN_BIN:-WPStallman.GUI}"         # main executable name in publish dir
VERSION="${VERSION:-1.0.0}"
ARCH="${ARCH:-$(uname -m)}"

# Icons (prefer the one shipped in the payload)
ICON_PNG="${ICON_PNG:-$GUI_DIR/wwwroot/img/WPS-256.png}"

# Build/output folders
BUILD="${BUILD:-$ROOT/artifacts/build}"        # keep build cache in a common place
APPDIR="${APPDIR:-$BUILD/AppDir}"

# Variant-aware output directory for artifacts
LINUXVAR_DIR="${LINUXVAR_DIR:-$ROOT/artifacts/packages/linuxvariants/$VARIANT}"
OUTDIR="${OUTDIR:-$LINUXVAR_DIR}"
mkdir -p "$OUTDIR"

# Output filename (needs OUTDIR defined first)
_SAFE_APP_NAME="$(printf '%s' "$APP_NAME" | tr ' /' '__')"
OUT_APPIMAGE="${OUT_APPIMAGE:-$OUTDIR/${_SAFE_APP_NAME}-${VERSION}-${ARCH}.AppImage}"

# Require Photino native to be present as a loose file?
# 0 = best-effort (warn if missing), 1 = hard requirement
REQUIRE_PHOTINO_NATIVE="${REQUIRE_PHOTINO_NATIVE:-0}"


mkdir -p "$OUTDIR"

# ---------- sanity checks on inputs ----------
[ -d "$GUI_DIR" ] || die "GUI_DIR not found: $GUI_DIR"
[ -x "$GUI_DIR/$MAIN_BIN" ] || die "GUI binary not found: $GUI_DIR/$MAIN_BIN"
[ -f "$GUI_DIR/wwwroot/index.html" ] || die "Missing wwwroot: $GUI_DIR/wwwroot/index.html"

# ---------- clean AppDir structure ----------
rm -rf "$APPDIR"
mkdir -p \
  "$APPDIR/usr/lib/$APP_ID" \
  "$APPDIR/usr/share/applications" \
  "$APPDIR/usr/share/icons/hicolor/64x64/apps" \
  "$APPDIR/usr/share/icons/hicolor/128x128/apps" \
  "$APPDIR/usr/share/icons/hicolor/256x256/apps"

# ---------- stage payload ----------
note "Staging payload into AppDir"
rsync -a "$GUI_DIR/." "$APPDIR/usr/lib/$APP_ID/"
# CLI optional
if [ -d "$CLI_DIR" ]; then
  rsync -a "$CLI_DIR/." "$APPDIR/usr/lib/$APP_ID/" || true
fi

# ---------- ensure Photino native present in AppDir ----------
ensure_photino_native() {
  local dest="$APPDIR/usr/lib/$APP_ID"
  # if present, make sure both names exist for good measure
  if [[ -f "$dest/libPhotino.Native.so" || -f "$dest/Photino.Native.so" ]]; then
    [[ -f "$dest/libPhotino.Native.so" && ! -e "$dest/Photino.Native.so" ]] && ln -sf libPhotino.Native.so "$dest/Photino.Native.so"
    [[ -f "$dest/Photino.Native.so"    && ! -e "$dest/libPhotino.Native.so" ]] && ln -sf Photino.Native.so "$dest/libPhotino.Native.so"
    return 0
  fi

  note "Locating Photino native for AppImage…"
  local cand=""

  # 1) Common publish sibling (…/net8.0/linux-x64)
  for name in libPhotino.Native.so Photino.Native.so; do
    [[ -z "$cand" && -f "$GUI_DIR/../$name" ]] && cand="$GUI_DIR/../$name"
  done

  # 2) Under runtimes in publish root
  [[ -z "$cand" ]] && cand="$(find "$GUI_DIR/.." -maxdepth 8 -path '*/runtimes/linux-x64/native/*photino.native*.so' -type f -print -quit 2>/dev/null || true)"

  # 3) NuGet cache fallback
  if [[ -z "$cand" ]]; then
    local NUPKG="${NUGET_PACKAGES:-$HOME/.nuget/packages}"
    cand="$(find "$NUPKG/photino.native" -path '*/runtimes/linux-x64/native/*photino.native*.so' -type f 2>/dev/null | sort -V | tail -n1 || true)"
  fi

  [[ -z "$cand" ]] && return 1

  note "  candidate: $cand"
  cp -f "$cand" "$dest/libPhotino.Native.so"
  ln -sf libPhotino.Native.so "$dest/Photino.Native.so"
  return 0
}

[[ -x "$APPDIR/usr/lib/$APP_ID/$MAIN_BIN" ]] || die "Missing $MAIN_BIN inside AppDir"
# old:
# ensure_photino_native || die "Missing Photino native in AppDir and NuGet cache fallback failed."

# new:
if ! ensure_photino_native; then
  if [[ "$REQUIRE_PHOTINO_NATIVE" == "1" ]]; then
    die "Missing Photino native in AppDir and NuGet cache fallback failed."
  else
    warn "Photino native not found to pre-copy; relying on single-file runtime extraction."
  fi
fi


# ---------- .desktop entry ----------
DESKTOP="$APPDIR/$APP_ID.desktop"
cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Comment=WordPress plugin project manager
Exec=usr/lib/${APP_ID}/${MAIN_BIN} %U
Icon=${APP_ID}
Categories=Development;
Terminal=false
StartupWMClass=WPStallman.GUI
EOF
note "Desktop written: $DESKTOP"

# ---------- icons ----------
ICON_SRC=""
if [[ -f "$ICON_PNG" ]]; then
  ICON_SRC="$ICON_PNG"
elif [[ -f "$APPDIR/usr/lib/$APP_ID/wwwroot/img/WPS-256.png" ]]; then
  ICON_SRC="$APPDIR/usr/lib/$APP_ID/wwwroot/img/WPS-256.png"
elif [[ -f "$APPDIR/usr/lib/$APP_ID/wwwroot/img/WPS-512.png" ]]; then
  ICON_SRC="$APPDIR/usr/lib/$APP_ID/wwwroot/img/WPS-512.png"
fi

if [[ -n "$ICON_SRC" ]]; then
  install -m644 "$ICON_SRC" "$APPDIR/usr/share/icons/hicolor/64x64/apps/${APP_ID}.png"
  install -m644 "$ICON_SRC" "$APPDIR/usr/share/icons/hicolor/128x128/apps/${APP_ID}.png"
  install -m644 "$ICON_SRC" "$APPDIR/usr/share/icons/hicolor/256x256/apps/${APP_ID}.png"
  # Root-level icon for very old appimagetool expectations
  cp -f "$ICON_SRC" "$APPDIR/${APP_ID}.png" 2>/dev/null || true
else
  warn "No icon source found; desktop may show a generic icon."
fi

# ---------- AppRun launcher ----------
cat > "$APPDIR/AppRun" <<'EOF'
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "$0")")"
export DOTNET_BUNDLE_EXTRACT_BASE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/WPStallman/dotnet_bundle"
export LD_LIBRARY_PATH="$HERE/usr/lib/com.wpstallman.app:${LD_LIBRARY_PATH}"
exec "$HERE/usr/lib/com.wpstallman.app/WPStallman.GUI" "$@"
EOF
chmod +x "$APPDIR/AppRun"

# ---------- appimagetool bootstrap (portable) ----------
APPTOOLS_DIR="${APPTOOLS_DIR:-$ROOT/build/tools}"
APPIMAGETOOL="${APPIMAGETOOL:-appimagetool}"

if ! command -v "$APPIMAGETOOL" >/dev/null 2>&1; then
  mkdir -p "$APPTOOLS_DIR"
  APPIMAGETOOL="$APPTOOLS_DIR/appimagetool-x86_64.AppImage"
  if [[ ! -x "$APPIMAGETOOL" ]]; then
    note "Bootstrapping appimagetool -> $APPIMAGETOOL"
    curl -fsSL -o "$APPIMAGETOOL" \
      https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
    chmod +x "$APPIMAGETOOL"
  fi
fi

# ---------- build AppImage (no FUSE needed) ----------
note "Building AppImage -> $OUT_APPIMAGE"
APPIMAGE_EXTRACT_AND_RUN=1 "$APPIMAGETOOL" "$APPDIR" "$OUT_APPIMAGE"

note "Wrote $OUT_APPIMAGE"

# ---------- optional: copy debug runner next to AppImage ----------
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
DEBUG_RUNNER_SRC="$SCRIPT_DIR/run-wpst-debug.sh"
if [[ -f "$DEBUG_RUNNER_SRC" ]]; then
  cp -f "$DEBUG_RUNNER_SRC" "$OUTDIR/run-wpst-debug.sh"
  chmod +x "$OUTDIR/run-wpst-debug.sh"
  note "Debug runner: $OUTDIR/run-wpst-debug.sh"
fi
