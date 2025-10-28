#!/usr/bin/env bash
# appstream_helpers.sh — legacy-compatible for AppStream 0.15.x

: "${APP_ID:?Set APP_ID (e.g., com.wpstallman.app)}"
: "${APP_NAME:?Set APP_NAME (e.g., W. P. Stallman)}"
: "${APP_VERSION:=1.0.0}"
: "${APP_RELEASE_DATE:=$(date +%F)}"   # e.g., 2025-10-14


# Publisher & licensing
: "${APP_DEVELOPER:=Left Hand Enterprises, LLC}"   # shown to users
: "${APP_LICENSE:=MIT}"                            # software license
: "${METADATA_LICENSE:=CC0-1.0}"                   # license for this metadata XML

# Product info
: "${APP_SUMMARY:=Packaging tools for WordPress modules}"
: "${APP_DESCRIPTION:=W. P. Stallman packages WordPress modules into AppImage, .deb, and Windows installers and generates release manifests.}"
: "${APP_HOMEPAGE:=https://lefthandenterprises.com/#/projects/wpstallman}"

# Optional extra URLs (leave blank if unused)
: "${APP_URL_HELP:=}"
: "${APP_URL_BUGS:=}"

# ...same header and variables...
# ---- compute release date once (expands in heredoc) ----

write_appstream() {
  local appdir="${1:?usage: write_appstream <APPDIR>}"
  mkdir -p "$appdir/usr/share/metainfo" "$appdir/usr/share/applications"

  # also place .desktop in the conventional path if you keep it at AppDir root
  if compgen -G "$appdir/*.desktop" >/dev/null; then
    cp -f "$appdir"/*.desktop "$appdir/usr/share/applications/" 2>/dev/null || true
  fi

  local meta="$appdir/usr/share/metainfo/${APP_ID}.metainfo.xml"

  # prepare optional URL lines to avoid empty <url> tags
  local url_help_line="" url_bugs_line=""
  [[ -n "$APP_URL_HELP" ]] && url_help_line="  <url type=\"help\">${APP_URL_HELP}</url>"
  [[ -n "$APP_URL_BUGS" ]] && url_bugs_line="  <url type=\"bugtracker\">${APP_URL_BUGS}</url>"

  cat > "$meta" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>${APP_ID}</id>
  <name>${APP_NAME}</name>
  <summary>${APP_SUMMARY}</summary>
  <description>
    <p>${APP_DESCRIPTION}</p>
  </description>

  <!-- pre-1.0 compatible -->
  <developer_name>${APP_DEVELOPER}</developer_name>

  <project_license>${APP_LICENSE}</project_license>
  <metadata_license>${METADATA_LICENSE}</metadata_license>

  <url type="homepage">${APP_HOMEPAGE}</url>
${url_help_line}
${url_bugs_line}

  <releases>
    <release version="${APP_VERSION}" date="${APP_RELEASE_DATE}"/>
  </releases>

  <content_rating type="oars-1.1">
    <content_attribute id="violence">none</content_attribute>
    <content_attribute id="drugs">none</content_attribute>
    <content_attribute id="sexual-content">none</content_attribute>
    <content_attribute id="language">none</content_attribute>
    <content_attribute id="social-info">none</content_attribute>
    <content_attribute id="money-purchases">none</content_attribute>
    <content_attribute id="data-sharing">none</content_attribute>
    <content_attribute id="human-interaction">none</content_attribute>
  </content_rating>
</component>
EOF
}

validate_desktop_and_metainfo() {
  local appdir="${1:?usage: validate_desktop_and_metainfo <APPDIR>}"
  if command -v desktop-file-validate >/dev/null 2>&1; then
    if compgen -G "$appdir/usr/share/applications/*.desktop" >/dev/null; then
      desktop-file-validate "$appdir/usr/share/applications/"*.desktop || true
    elif compgen -G "$appdir/*.desktop" >/dev/null; then
      desktop-file-validate "$appdir/"*.desktop || true
    fi
  fi
  if command -v appstreamcli >/dev/null 2>&1; then
    if compgen -G "$appdir/usr/share/metainfo/*.metainfo.xml" >/dev/null; then
      appstreamcli validate --no-net "$appdir/usr/share/metainfo/"*.metainfo.xml || true
    fi
  fi
}

# ---- allow running the helper directly for ad-hoc use ----
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "$1" in
    --write)    write_appstream   "${APPDIR:?set APPDIR}";;
    --validate) validate_desktop_and_metainfo "${APPDIR:?set APPDIR}";;
    *)
      echo "Usage:" >&2
      echo "  APPDIR=/path APP_ID=com.wpstallman.app APP_NAME='W. P. Stallman' APP_VERSION=1.0.0 \\" >&2
      echo "    APP_HOMEPAGE=https://... APP_DEVELOPER='Left Hand Enterprises, LLC' \\" >&2
      echo "    $0 --write|--validate" >&2
      exit 2
      ;;
  esac
fi
