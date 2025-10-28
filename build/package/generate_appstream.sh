#!/usr/bin/env bash
set -euo pipefail

# generate_appstream.sh
# Creates a modern AppStream metainfo file for AppImage (AppDir) and Debian stage.

# -------- Resolve ROOT --------
ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../.."
cd "$ROOT"

# -------- Load release.meta if present --------
META="${META:-$ROOT/build/package/release.meta}"
if [[ -f "$META" ]]; then
  # shellcheck disable=SC1090
  set -a; source "$META"; set +a
fi

# -------- Inputs from release.meta (with fallbacks) --------
APP_ID="${APP_ID:-${APP_ID_META:-com.wpstallman.app}}"
APP_NAME="${APP_NAME:-${APP_NAME_META:-W. P. Stallman}}"
APPVER="${APP_VERSION_META:-${APPVER:-0.0.0}}"

SHORTDESC="${APP_SHORTDESC:-${APP_SHORTDESC_META:-Document your entire MySQL database in MarkDown format}}"
LONGDESC="${APP_LONGDESC_META:-${APP_LONGDESC:-$SHORTDESC}}"

DEVELOPER="${APP_VENDOR_META:-Left Hand Enterprises, LLC}"
PROJECT_LICENSE="${LICENSE_ID:-${APP_PROJECT_LICENSE_META:-MIT}}"
METADATA_LICENSE="${APPSTREAM_METADATA_LICENSE:-${APP_METADATA_LICENSE_META:-CC0-1.0}}"

HOMEPAGE="${HOMEPAGE_URL:-${APP_HOMEPAGE_META:-}}"
BUGS_URL="${APPSTREAM_URL_ISSUES:-}"
DONATE_URL_META="${APPSTREAM_URL_DONATION:-${DONATE_URL:-}}"

CATEGORIES_RAW="${APPSTREAM_CATEGORIES:-}"
KEYWORDS_RAW="${APPSTREAM_KEYWORDS:-}"

# Optional external content rating (OARS) XML path
OARS_PATH="${APPSTREAM_CONTENT_RATING:-}"

# Optional rich description file
DESC_FILE="${APPSTREAM_DESCRIPTION_FILE:-}"

# Desktop id (must match the file you install under usr/share/applications/)
DESKTOP_ID="${DESKTOP_ID_META:-${APP_ID}.desktop}"

# Release date (ISO-8601). Defaults to today.
RELEASE_DATE="${APP_RELEASE_DATE_META:-$(date +%F)}"

# -------- Targets --------
# AppDir (prefer artifacts path; fall back to legacy build/AppDir)
APPDIR="${APPDIR:-}"
if [[ -z "${APPDIR}" ]]; then
  if [[ -d "$ROOT/artifacts/build/AppDir" ]]; then
    APPDIR="$ROOT/artifacts/build/AppDir"
  else
    APPDIR="$ROOT/build/AppDir"
  fi
fi
APPDIR_META_DIR="$APPDIR/usr/share/metainfo"

# Debian stage (optional)
DEB_STAGE="${DEB_STAGE:-}"
DEB_META_DIR=""
[[ -n "$DEB_STAGE" ]] && DEB_META_DIR="$DEB_STAGE/usr/share/metainfo"

mkdir -p "$APPDIR_META_DIR"
[[ -n "$DEB_META_DIR" ]] && mkdir -p "$DEB_META_DIR"

OUT_NAME="${APP_ID}.metainfo.xml"
APPDIR_OUT="$APPDIR_META_DIR/$OUT_NAME"
DEB_OUT="${DEB_META_DIR:+$DEB_META_DIR/$OUT_NAME}"

# -------- Helpers --------
xml_escape() {
  # Escapes &, <, > for XML text nodes.
  # Usage: xml_escape "raw text"
  local s=${1:-}
  s=${s//&/&amp;}
  s=${s//</&lt;}
  s=${s//> /&gt; }
  s=${s//>/&gt;}
  printf '%s' "$s"
}

# If a description markdown file is provided, read & escape it.
if [[ -n "$DESC_FILE" && -f "$DESC_FILE" ]]; then
  LONGDESC="$(xml_escape "$(cat "$DESC_FILE")")"
else
  LONGDESC="$(xml_escape "$LONGDESC")"
fi
SHORTDESC="$(xml_escape "$SHORTDESC")"
APP_NAME_ESC="$(xml_escape "$APP_NAME")"
DEVELOPER_ESC="$(xml_escape "$DEVELOPER")"

# Categories block (optional)
build_categories_block() {
  local raw="$1"; local out=""
  if [[ -n "$raw" ]]; then
    IFS=',;' read -r -a arr <<< "$raw"
    if [[ "${#arr[@]}" -gt 0 ]]; then
      out+="  <categories>"
      for c in "${arr[@]}"; do
        c="$(echo "$c" | xargs)"
        [[ -n "$c" ]] && out+=$'\n'"    <category>$(xml_escape "$c")</category>"
      done
      out+=$'\n'"  </categories>"
    fi
  fi
  printf '%s' "$out"
}

# Keywords block (optional)
build_keywords_block() {
  local raw="$1"; local out=""
  if [[ -n "$raw" ]]; then
    IFS=',;' read -r -a arr <<< "$raw"
    if [[ "${#arr[@]}" -gt 0 ]]; then
      out+="  <keywords>"
      for k in "${arr[@]}"; do
        k="$(echo "$k" | xargs)"
        [[ -n "$k" ]] && out+=$'\n'"    <keyword>$(xml_escape "$k")</keyword>"
      done
      out+=$'\n'"  </keywords>"
    fi
  fi
  printf '%s' "$out"
}

CATS_BLOCK="$(build_categories_block "$CATEGORIES_RAW")"
KEYS_BLOCK="$(build_keywords_block "$KEYWORDS_RAW")"

# URL block (optional)
URL_BLOCK=""
[[ -n "$HOMEPAGE"   ]] && URL_BLOCK+=$'\n'"  <url type=\"homepage\">$(xml_escape "$HOMEPAGE")</url>"
[[ -n "$BUGS_URL"   ]] && URL_BLOCK+=$'\n'"  <url type=\"bugtracker\">$(xml_escape "$BUGS_URL")</url>"
[[ -n "$DONATE_URL_META" ]] && URL_BLOCK+=$'\n'"  <url type=\"donation\">$(xml_escape "$DONATE_URL_META")</url>"

# Content rating block:
# - If APPSTREAM_CONTENT_RATING="empty"  -> <content_rating type="oars-1.1"/>
# - If APPSTREAM_CONTENT_RATING points to an existing file -> inline that block
CONTENT_RATING_BLOCK=""
if [[ -n "$OARS_PATH" ]]; then
  if [[ "$OARS_PATH" == "empty" ]]; then
    CONTENT_RATING_BLOCK=$'\n  <content_rating type="oars-1.1"/>'
  elif [[ -f "$OARS_PATH" ]]; then
    # Inline the provided OARS XML (should be a <content_rating ...>...</content_rating> block)
    CONTENT_RATING_BLOCK=$'\n'"  $(sed 's/^/  /' "$OARS_PATH")"
  fi
fi


# -------- Emit XML --------
generate_xml() {
  cat <<XML
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>${APP_ID}</id>
  <name>${APP_NAME_ESC}</name>
  <summary>${SHORTDESC}</summary>

  <launchable type="desktop-id">${DESKTOP_ID}</launchable>

  <developer_name>${DEVELOPER_ESC}</developer_name>
  <project_license>${PROJECT_LICENSE}</project_license>
  <metadata_license>${METADATA_LICENSE}</metadata_license>
${URL_BLOCK}

  <description>
    <p>${LONGDESC}</p>
  </description>

  <releases>
    <release version="${APPVER}" date="${RELEASE_DATE}">
      <description>
        <p>${SHORTDESC}</p>
      </description>
    </release>
  </releases>
$( [[ -n "$CATS_BLOCK" ]] && echo "$CATS_BLOCK" )
$( [[ -n "$KEYS_BLOCK" ]] && echo "$KEYS_BLOCK" )${CONTENT_RATING_BLOCK}
</component>
XML
}

generate_xml > "$APPDIR_OUT"
echo "[OK] AppStream written: $APPDIR_OUT"
if [[ -n "$DEB_OUT" ]]; then
  generate_xml > "$DEB_OUT"
  echo "[OK] AppStream written: $DEB_OUT"
fi

# -------- Optional validation --------
if command -v appstreamcli >/dev/null 2>&1; then
  echo "[INFO] Validating AppStream with appstreamcli…"
  appstreamcli validate "$APPDIR_OUT" || true
  if [[ -n "$DEB_OUT" ]]; then
    appstreamcli validate "$DEB_OUT" || true
  fi
else
  echo "[WARN] appstreamcli not installed; skipping validation."
fi

echo "[DONE] AppStream generation complete."
