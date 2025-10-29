#!/usr/bin/env bash
set -euo pipefail

# ---------- locate repo root ----------
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"

# ---------- meta ----------
META="${META:-$ROOT/build/package/release.meta}"
if [[ -f "$META" ]]; then set -a; source "$META"; set +a; fi

APP_NAME="${APP_NAME:-WP Stallman}"
APP_NAME_SHORT="${APP_NAME_SHORT:-wpstallman}"
APP_VERSION="${APP_VERSION:-${APPVER:-$(grep -m1 -oP '(?<=<Version>)[^<]+' "$ROOT/Directory.Build.props" 2>/dev/null || echo 0.0.0)}}"

# derived
BASENAME_CLEAN="$(echo "$APP_NAME" | tr -cd '[:alnum:]')"   # "WPStallman"
[[ -n "$BASENAME_CLEAN" ]] || BASENAME_CLEAN="WPStallman"

# ---------- projects & output ----------
GUI_WIN_CSPROJ="${GUI_WIN_CSPROJ:-$ROOT/src/WPStallman.GUI.Windows/WPStallman.GUI.csproj}"
CLI_CSPROJ="${CLI_CSPROJ:-$ROOT/src/WPStallman.CLI/WPStallman.CLI.csproj}"

TFM="net8.0-windows"
RID="win-x64"
CONF="Release"

OUT_ROOT="$ROOT/artifacts/windows/$RID"
OUT_PUBLISH="$OUT_ROOT/publish"
ZIP_DIR="$ROOT/artifacts/packages/zip"
ZIP_PKG="$ZIP_DIR/${BASENAME_CLEAN}-Windows-${APP_VERSION}.zip"

echo "[INFO] Root            : $ROOT"
echo "[INFO] Windows GUI     : $GUI_WIN_CSPROJ"
[[ -f "$CLI_CSPROJ" ]] && echo "[INFO] Windows CLI     : $CLI_CSPROJ" || echo "[INFO] Windows CLI     : (not found; skipping)"
echo "[INFO] Publish TFM/RID : $TFM / $RID"
echo "[INFO] Publish out     : $OUT_PUBLISH"
echo "[INFO] ZIP target      : $ZIP_PKG"
echo

# ---------- sanitize permissions (fix Docker root-owned leftovers) ----------
if find "$ROOT/src" -xdev -type d \( -name bin -o -name obj -o -name publish \) -exec stat -c '%U %n' {} + | grep -q '^root '; then
  echo "[WARN] root-owned build directories detected; fixing ownership (sudo may prompt)…"
  sudo chown -R "$USER:$USER" "$ROOT/src"
fi

# ---------- clean output ----------
rm -rf "$OUT_PUBLISH"
mkdir -p "$OUT_PUBLISH" "$ZIP_DIR"

# Optional deep clean of project bin/obj if you still hit weirdness:
# find "$ROOT/src" -type d \( -name bin -o -name obj \) -prune -exec rm -rf {} +

# ---------- publish GUI (and CLI) ----------
export DISABLE_SOURCELINK=1   # disables SourceLink in Directory.Build.props (conditional)

echo "[INFO] Restoring & publishing Windows GUI…"
dotnet restore "$GUI_WIN_CSPROJ"
dotnet publish "$GUI_WIN_CSPROJ" \
  -c "$CONF" -f "$TFM" -r "$RID" \
  -p:SelfContained=true \
  -p:PublishSingleFile=false \
  -p:IncludeNativeLibrariesForSelfExtract=true \
  -o "$OUT_PUBLISH/gui"

if [[ -f "$CLI_CSPROJ" ]]; then
  echo
  echo "[INFO] Restoring & publishing Windows CLI…"
  dotnet restore "$CLI_CSPROJ"
  dotnet publish "$CLI_CSPROJ" \
    -c "$CONF" -f "net8.0" -r "$RID" \
    -p:SelfContained=true \
    -p:PublishSingleFile=false \
    -o "$OUT_PUBLISH/cli"
fi

# ---------- verify publish ----------
echo
echo "[INFO] Verifying publish outputs…"
GUI_EXE="$(find "$OUT_PUBLISH/gui" -maxdepth 1 -type f -iname '*.exe' | head -n 1 || true)"
if [[ -z "$GUI_EXE" ]]; then
  echo "[ERR ] Windows GUI publish output missing at $OUT_PUBLISH/gui"
  echo "      (Looked for *.exe; ensure project builds for $TFM/$RID and outputs into that folder.)"
  exit 2
fi
echo "[OK ] GUI exe: $(basename "$GUI_EXE")"

if [[ -d "$OUT_PUBLISH/cli" ]]; then
  CLI_EXE="$(find "$OUT_PUBLISH/cli" -maxdepth 1 -type f -iname '*.exe' | head -n 1 || true)"
  [[ -n "$CLI_EXE" ]] && echo "[OK ] CLI exe: $(basename "$CLI_EXE")"
fi

# ---------- zip packaging ----------
echo
echo "[INFO] Creating ZIP → $ZIP_PKG"
# zip the *contents* as a single top-level folder 'wpstallman'
pushd "$OUT_PUBLISH" >/dev/null
  # make a friendly top-level folder inside the zip
  STAGE_DIR=".zipstage.${APP_NAME_SHORT}"
  rm -rf "$STAGE_DIR"
  mkdir -p "$STAGE_DIR"
  # gui -> wpstallman/gui, cli -> wpstallman/cli
  mkdir -p "$STAGE_DIR/$APP_NAME_SHORT"
  if [[ -d gui ]]; then cp -a gui "$STAGE_DIR/$APP_NAME_SHORT/"; fi
  if [[ -d cli ]]; then cp -a cli "$STAGE_DIR/$APP_NAME_SHORT/"; fi
  # zip it
  (cd "$STAGE_DIR" && zip -r -9 "$ZIP_PKG" "$APP_NAME_SHORT" >/dev/null)
  rm -rf "$STAGE_DIR"
popd >/dev/null

echo "[OK ] ZIP created: $ZIP_PKG"
echo

# ---------- optional NSIS ----------
NSI="${NSI:-$ROOT/build/package/installer.nsi}"
if [[ -f "$NSI" ]]; then
  echo "[INFO] Building NSIS installer…"
  APPDIR_WIN="$OUT_PUBLISH/gui"
  OUT_EXE="$ROOT/artifacts/packages/nsis/${BASENAME_CLEAN}-${APP_VERSION}-Setup.exe"
  mkdir -p "$(dirname "$OUT_EXE")"

  makensis -V4 -NOCD \
    -DAPP_NAME="$APP_NAME" \
    -DAPP_VERSION="$APP_VERSION" \
    -DAPP_STAGE="Release" \
    -DOUT_EXE="$OUT_EXE" \
    -DSOURCE_DIR="$APPDIR_WIN" \
    -DICON_FILE="$ROOT/src/WPStallman.Assets/logo/app.ico" \
    "$NSI"

  echo "[OK ] NSIS → $OUT_EXE"
else
  echo "[INFO] NSIS script not found at $NSI; skipping installer."
fi

