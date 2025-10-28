#!/usr/bin/env bash
set -euo pipefail

# package_deb_unified.sh
# Unified Debian packager for W. P. Stallman
# - Uses build/package/release.meta (falls back to ./release.meta)
# - Stages under build/debroot and builds a .deb in artifacts/packages/deb
# - Layout: /usr/lib/<APP_ID>/{gtk4.1,gtk4.0}, /usr/bin/<pkg>, .desktop, icon, AppStream, docs
# - Fixes common lintian issues (maintainer, depends, perms, docs, optional manpage)

# -------- Resolve ROOT --------
ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../.."
cd "$ROOT"

# -------- Load metadata --------
META="${META:-$ROOT/build/package/release.meta}"
[[ -f "$META" ]] || META="$ROOT/release.meta"
if [[ -f "$META" ]]; then
  # shellcheck disable=SC1090
  set -a; source "$META"; set +a
else
  echo "[ERR] release.meta not found (looked in build/package/ and repo root)."; exit 2
fi

# -------- Inputs / Defaults from meta --------
APPVER="${APPVER:-${APP_VERSION_META:-0.0.0}}"
APP_ID="${APP_ID:-${APP_ID_META:-com.wpstallman.app}}"         # reverse-DNS id
APP_NAME_DISP="${APP_NAME:-${APP_NAME_META:-W. P. Stallman}}" # display name (can have spaces)
PKG_NAME="${DEB_PACKAGE:-${APP_NAME_SHORT:-wpstallman}}"        # Debian package name (lowercase)
PKG_NAME="${PKG_NAME,,}"

DEB_SECTION="${DEB_SECTION:-utils}"
DEB_PRIORITY="${DEB_PRIORITY:-optional}"
DEB_ARCH="${DEB_ARCH:-amd64}"

# Maintainer (prefer explicit; else compose Name <email>)
if [[ -n "${DEB_MAINTAINER_META:-}" ]]; then
  DEB_MAINTAINER="$DEB_MAINTAINER_META"

  # Try to derive vendor name/email from DEB_MAINTAINER_META for docs
  VENDOR_NAME="${DEB_MAINTAINER_META%%<*}"
  VENDOR_NAME="$(echo "${VENDOR_NAME:-}" | sed 's/[[:space:]]*$//')"   # trim
  VENDOR_MAIL="${DEB_MAINTAINER_META##*<}"
  VENDOR_MAIL="${VENDOR_MAIL%>*}"
else
  VENDOR_NAME="${APP_VENDOR_META:-${PUBLISHER_NAME:-Left Hand Enterprises, LLC}}"
  VENDOR_MAIL="${APP_VENDOR_EMAIL:-${PUBLISHER_EMAIL:-support@lefthandenterprises.com}}"
  DEB_MAINTAINER="${VENDOR_NAME} <${VENDOR_MAIL}>"
fi

# FINAL SAFETY NETS (avoid set -u explosions later)
VENDOR_NAME="${VENDOR_NAME:-${APP_VENDOR_META:-${PUBLISHER_NAME:-Left Hand Enterprises, LLC}}}"
VENDOR_MAIL="${VENDOR_MAIL:-${APP_VENDOR_EMAIL:-${PUBLISHER_EMAIL:-support@lefthandenterprises.com}}}"


# Summary/Description (short line; no trailing period recommended)
SHORTDESC="${APP_SHORTDESC:-Document your entire MySQL database in Markdown format}"
SHORTDESC="$(echo "$SHORTDESC" | sed 's/[[:space:]]\+$//')"

# Depends (exact string from meta, otherwise a safe baseline)
DEPS_RAW="${DEB_DEPENDS:-}"
if [[ -z "$DEPS_RAW" ]]; then
  DEPS_RAW="libgtk-3-0, libnotify4, libgdk-pixbuf-2.0-0, libnss3, \
 libjavascriptcoregtk-4.1-0 | libjavascriptcoregtk-4.0-18, \
 libwebkit2gtk-4.1-0 | libwebkit2gtk-4.0-37, libasound2"
fi
# Normalize spaces/commas for cleaner control field
DEPS="$(echo "$DEPS_RAW" | sed 's/[[:space:]]\+/ /g; s/ ,/,/g')"

# Payload inputs (already published binaries)
PUBLISH_DIR_GTK41="${PUBLISH_DIR_GTK41:-$ROOT/artifacts/modern-gtk41/publish-gtk41}"
PUBLISH_DIR_GTK40="${PUBLISH_DIR_GTK40:-$ROOT/artifacts/legacy-gtk40/publish-gtk40}"
[[ -d "$PUBLISH_DIR_GTK41" ]] || { echo "[ERR] No payload at $PUBLISH_DIR_GTK41"; exit 1; }
[[ -d "$PUBLISH_DIR_GTK40" ]] || { echo "[ERR] No payload at $PUBLISH_DIR_GTK40"; exit 1; }

# -------- Output locations --------
OUT_DIR="$ROOT/artifacts/packages/deb"
APPDIR="$ROOT/build/debroot"
PAYROOT_REL="/usr/lib/${APP_ID}"
PAYROOT="$APPDIR${PAYROOT_REL}"

rm -rf "$APPDIR"
mkdir -p "$OUT_DIR" "$APPDIR/DEBIAN" "$PAYROOT"

# -------- Stage payloads --------
cp -a "$PUBLISH_DIR_GTK41" "$PAYROOT/gtk4.1"
cp -a "$PUBLISH_DIR_GTK40" "$PAYROOT/gtk4.0"

# Normalize Photino native name in both variants (best-effort; ignore if missing)
normalize_photino() {
  local vdir="$1" src=""
  for cand in \
    "$vdir/runtimes/linux-x64/native/libPhotino.Native.so" \
    "$vdir/runtimes/linux-x64/native/Photino.Native.so" \
    "$vdir/libPhotino.Native.so" \
    "$vdir/Photino.Native.so"
  do [[ -f "$cand" ]] && { src="$cand"; break; }; done
  [[ -n "$src" ]] && cp -a "$src" "$vdir/libPhotino.Native.so" || true
}
normalize_photino "$PAYROOT/gtk4.1"
normalize_photino "$PAYROOT/gtk4.0"

# -------- Launcher in /usr/bin --------
mkdir -p "$APPDIR/usr/bin"
cat > "$APPDIR/usr/bin/${PKG_NAME}" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
APPROOT="/usr/lib/com.wpstallman.app"

# Prefer gtk4.1 on hosts that have it and glibc>=2.38
has41(){ { /sbin/ldconfig -p 2>/dev/null || /usr/sbin/ldconfig -p 2>/dev/null || true; } | grep -q 'libwebkit2gtk-4\.1\.so'; }
glibc(){ local r v; r="$(getconf GNU_LIBC_VERSION 2>/dev/null || true)"; v="${r##* }"; [[ -n "$v" ]] && echo "$v" || echo "0.0"; }
ge238(){ awk 'BEGIN{split("'"$(glibc)"'",h,"."); if ((h[1]>2)|| (h[1]==2 && h[2]>=38)) exit 0; exit 1;}'; }

pick=""
if has41 && ge238; then
  pick="gtk4.1"
elif [[ -d "$APPROOT/gtk4.0" ]]; then
  pick="gtk4.0"
else
  pick="gtk4.1"
fi

export DOTNET_BUNDLE_EXTRACT_BASE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/WPStallman/dotnet_bundle"

buildld(){ local b="$1" o=""; for d in "$b" "$b/runtimes/linux-x64/native" "$b/native" "$b/lib"; do [[ -d "$d" ]] && case ":$o:" in *":$d:"*) ;; *) o="${o:+$o:}$d";; esac; done; echo "$o"; }
export LD_LIBRARY_PATH="$(buildld "$APPROOT/$pick")${LD_LIBRARY_PATH+:${LD_LIBRARY_PATH}}"

if [[ -x "$APPROOT/WPStallman.Launcher" ]]; then exec "$APPROOT/WPStallman.Launcher" "$@"; fi
if [[ -x "$APPROOT/$pick/WPStallman.GUI" ]]; then exec "$APPROOT/$pick/WPStallman.GUI" "$@"; fi
if [[ -f "$APPROOT/$pick/WPStallman.GUI.dll" ]]; then exec dotnet "$APPROOT/$pick/WPStallman.GUI.dll" "$@"; fi
echo "WPStallman could not find a GUI entry under $APPROOT/$pick" >&2; exit 67
SH
chmod 0755 "$APPDIR/usr/bin/${PKG_NAME}"

# -------- .desktop --------
mkdir -p "$APPDIR/usr/share/applications"
DESKTOP_ID="${APP_ID}.desktop"
cat > "$APPDIR/usr/share/applications/${DESKTOP_ID}" <<EOF
[Desktop Entry]
Name=${APP_NAME_DISP}
Comment=${SHORTDESC}
Exec=${PKG_NAME} %F
Icon=${APP_ID}
Terminal=false
Type=Application
Categories=Development;Database;
EOF

# -------- Icons (256x256 minimum) --------
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"
ICON_SRC=""
for cand in \
  "$PAYROOT/gtk4.1/wwwroot/img/app-icon-256.png" \
  "$PAYROOT/gtk4.0/wwwroot/img/app-icon-256.png" \
  "$ROOT/${APP_ICON_SRC:-}"
do
  [[ -f "$cand" ]] && { ICON_SRC="$cand"; break; }
done
if [[ -n "$ICON_SRC" ]]; then
  # If ImageMagick present, ensure 256x256; else copy as-is
  if command -v identify >/dev/null 2>&1; then
    sz="$(identify -format '%wx%h' "$ICON_SRC" 2>/dev/null || echo '')"
    if [[ "$sz" != "256x256" ]]; then
      convert "$ICON_SRC" -resize 256x256 "$APPDIR/usr/share/icons/hicolor/256x256/apps/${APP_ID}.png"
    else
      cp -a "$ICON_SRC" "$APPDIR/usr/share/icons/hicolor/256x256/apps/${APP_ID}.png"
    fi
  else
    cp -a "$ICON_SRC" "$APPDIR/usr/share/icons/hicolor/256x256/apps/${APP_ID}.png"
  fi
else
  echo "[WARN] No icon source found; Icon=${APP_ID}"
fi

# -------- AppStream (if already generated in AppDir stage) --------
if [[ -f "$ROOT/artifacts/build/AppDir/usr/share/metainfo/${APP_ID}.metainfo.xml" ]]; then
  mkdir -p "$APPDIR/usr/share/metainfo"
  cp -a "$ROOT/artifacts/build/AppDir/usr/share/metainfo/${APP_ID}.metainfo.xml" \
        "$APPDIR/usr/share/metainfo/${APP_ID}.metainfo.xml"
fi

# -------- Basic docs (copyright + changelog) --------
DOCDIR="$APPDIR/usr/share/doc/$PKG_NAME"
mkdir -p "$DOCDIR"

cat > "$DOCDIR/copyright" <<EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: ${APP_NAME_DISP}
Upstream-Contact: ${VENDOR_MAIL}
Source: ${HOMEPAGE_URL:-https://lefthandenterprises.com/#/projects/dr-sql-md}

Files: *
Copyright: $(date +%Y) ${VENDOR_NAME}
License: ${LICENSE_ID:-MIT}
 This software is licensed under the ${LICENSE_ID:-MIT} license.
EOF

# create plain text first
cat > "$DOCDIR/changelog.Debian" <<EOF
${PKG_NAME} (${APPVER}) stable; urgency=medium

  * Initial packaging of unified GTK 4.1/4.0 build.

 -- ${DEB_MAINTAINER}  $(date -R)
EOF

# gzip in-place (overwrites if exists)
gzip -n --best -f "$DOCDIR/changelog.Debian"


# -------- (Optional) Tiny manpage to silence binary-without-manpage --------
MANDIR="$APPDIR/usr/share/man/man1"
mkdir -p "$MANDIR"
cat > "$MANDIR/${PKG_NAME}.1" <<'EOF'
.TH DRSQ LMD 1 "User Commands"
.SH NAME
wpstallman \- document MySQL/MariaDB schemas to Markdown
.SH SYNOPSIS
.B wpstallman
.RI [ options ]
.SH DESCRIPTION
Launches the Dr. SQL, M.D. GUI.
EOF
gzip -f "$MANDIR/${PKG_NAME}.1"

# -------- Permissions tidy (common lintian nits) --------
# Executables
find "$APPDIR/usr" -type f -path "*/gtk4.*/*" -name "WPStallman.GUI" -exec chmod 0755 {} +
find "$APPDIR/usr/bin" -type f -exec chmod 0755 {} +
# .so libraries should not be executable
find "$APPDIR/usr" -type f -name "*.so" -exec chmod 0644 {} +
# Common non-ELF types: ensure no exec bit
find "$APPDIR/usr" -type f \( -name "*.dll" -o -name "*.pdb" -o -name "*.xml" -o -name "*.json" -o -name "*.md" -o -name "*.txt" \) -exec chmod 0644 {} + || true
# Dirs readable
find "$APPDIR/usr" -type d -exec chmod 0755 {} +

# -------- Control file (omit Installed-Size; let dpkg compute) --------
cat > "$APPDIR/DEBIAN/control" <<EOF
Package: ${PKG_NAME}
Version: ${APPVER}
Section: ${DEB_SECTION}
Priority: ${DEB_PRIORITY}
Architecture: ${DEB_ARCH}
Maintainer: ${DEB_MAINTAINER}
Depends: ${DEPS}
Description: ${SHORTDESC}
 ${APP_NAME_DISP} generates clean, navigable Markdown docs for MySQL/MariaDB schemas, tables, views, routines, triggers, and relationships.
EOF
chmod 0644 "$APPDIR/DEBIAN/control"

# -------- Build .deb --------
OUT_DEB="$OUT_DIR/${PKG_NAME}_${APPVER}_${DEB_ARCH}.deb"
dpkg-deb --build --root-owner-group "$APPDIR" "$OUT_DEB"
echo "[OK] Created .deb at $OUT_DEB"
