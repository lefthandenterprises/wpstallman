#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

: "${VERSION:=1.0.0}"
: "${APP_NAME:=W. P. Stallman}"

# Expected .app bundle path from your publish step or bundle target
APP_BUNDLE="${APP_BUNDLE:-$ROOT/src/WPStallman.GUI/bin/Release/net8.0/osx-x64/publish/${APP_NAME}.app}"
OUTDIR="$ROOT/artifacts/packages"
mkdir -p "$OUTDIR"

note(){ printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }
die(){  printf "\n\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }

[ -d "$APP_BUNDLE" ] || die ".app bundle not found: $APP_BUNDLE"

ZIP="$OUTDIR/${APP_NAME// /_}-${VERSION}-macos.zip"
note "Zipping .app bundle -> $ZIP"
(cd "$(dirname "$APP_BUNDLE")" && zip -qry "$ZIP" "$(basename "$APP_BUNDLE")")
note "Wrote $ZIP"

# Optional: DMG if on macOS (hdiutil) or if create-dmg exists
if [[ "$OSTYPE" == darwin* ]]; then
  DMG="$OUTDIR/${APP_NAME// /_}-${VERSION}.dmg"
  if command -v create-dmg >/dev/null; then
    note "Creating DMG with create-dmg -> $DMG"
    rm -f "$DMG"
    create-dmg --volname "${APP_NAME}" --app-drop-link 600 185 --window-size 800 400 "$DMG" "$APP_BUNDLE"
    note "Wrote $DMG"
  else
    note "Creating DMG with hdiutil -> $DMG"
    rm -f "$DMG"
    hdiutil create -volname "${APP_NAME}" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG"
    note "Wrote $DMG"
  fi
else
  note "Not on macOS; skipped DMG creation (ZIP created)."
fi
