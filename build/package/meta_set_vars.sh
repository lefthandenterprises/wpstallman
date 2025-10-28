#!/usr/bin/env bash
set -euo pipefail

# -------- paths --------
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# -------- meta file (optional) --------
META="${META:-$ROOT/build/package/release.meta}"
if [[ -f "$META" ]]; then
  # shellcheck source=/dev/null
  set -a; source "$META"; set +a
fi

# -------- defaults (safe for `set -u`) --------
APP_NAME="${APP_NAME:-WP Stallman}"
APP_NAME_SHORT="${APP_NAME_SHORT:-wpstallman}"
APP_ID="${APP_ID:-com.wpstallman.app}"
APP_SHORTDESC="${APP_SHORTDESC:-WordPress scaffolding &amp; packaging toolkit}"
HOMEPAGE_URL="${HOMEPAGE_URL:-https://lefthandenterprises.com/#/projects/wpstallman}"

# Resolve APP_VERSION from Directory.Build.props if not provided
if [[ -z "${APP_VERSION:-}" ]]; then
  if [[ -f "$ROOT/Directory.Build.props" ]]; then
    APP_VERSION="$(grep -m1 -oP '(?<=<Version>)[^<]+' "$ROOT/Directory.Build.props" || true)"
  fi
  APP_VERSION="${APP_VERSION:-1.0.0}"
fi
APP_VER_SUFFIX="${APP_VER_SUFFIX:-}"

# .NET build lane defaults
TFM="${TFM:-net8.0}"
RID="${RID:-linux-x64}"
CONF="${CONF:-Release}"

# Dockerfile hints (used by callers that pass them through)
DOCKERFILE_MODERN="${DOCKERFILE_MODERN:-$ROOT/Dockerfile.modern}"
DOCKERFILE_LEGACY="${DOCKERFILE_LEGACY:-$ROOT/Dockerfile.legacy}"

# -------- icon discovery (robust) --------
# respect APP_ICON_SRC if set; otherwise try common candidates under Assets/logo
if [[ -z "${APP_ICON_SRC:-}" ]]; then
  for cand in \
    "$ROOT/src/WPStallman.Assets/logo/app-icon-256.png" \
    "$ROOT/src/WPStallman.Assets/logo/app-icon-128.png" \
    "$ROOT/src/WPStallman.Assets/logo/app-icon-64.png"  \
    "$ROOT/src/WPStallman.Assets/logo/app.ico" \
    "$ROOT/src/WPStallman.Assets/logo/app.icns"
  do
    [[ -f "$cand" ]] && { APP_ICON_SRC="$cand"; break; }
  done
fi
APP_ICON_SRC="${APP_ICON_SRC:-}"  # may still be empty; callers should handle gracefully

# -------- export for callers --------
export ROOT META \
  APP_NAME APP_NAME_SHORT APP_ID APP_SHORTDESC HOMEPAGE_URL \
  APP_VERSION APP_VER_SUFFIX \
  TFM RID CONF \
  DOCKERFILE_MODERN DOCKERFILE_LEGACY \
  APP_ICON_SRC

# -------- debug header --------
printf '[META] APP_NAME=%s\n'        "$APP_NAME"
printf '[META] APP_NAME_SHORT=%s\n'  "$APP_NAME_SHORT"
printf '[META] APP_ID=%s\n'          "$APP_ID"
printf '[META] APP_VERSION=%s\n'     "$APP_VERSION"
printf '[META] APP_VER_SUFFIX=%s\n'  "${APP_VER_SUFFIX}"
printf '[META] TFM/RID/CONF=%s/%s/%s\n' "$TFM" "$RID" "$CONF"
printf '[META] APP_ICON_SRC=%s\n'    "${APP_ICON_SRC:-<none>}"
