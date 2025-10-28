#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# generate_package_credits.sh
#
# - Scans solution for NuGet packages (project files, packages.config, props/targets)
# - Fetches license/project URL from NuGet
# - Detects common frontend libs by filename and <script src="..."> *without regex*
#   (KnockoutJS, Bootstrap, Sammy.js, JSZip, jQuery) and extracts versions when possible
# - Writes package_credits.html (KO via CDN with defer; KO code runs at DOMContentLoaded)
# - No separate Web Link column (name already links)
# -----------------------------------------------------------------------------

ROOT_DIR="$(pwd)"
OUT_HTML="${ROOT_DIR}/package_credits.html"

for cmd in curl grep sed awk tr sort cut head find; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Error: '$cmd' required."; exit 1; }
done

# ---------- helpers ----------
json_escape() {
  echo -n "$1" \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\r/\\r/g' -e 's/\n/\\n/g' -e 's/\t/\\t/g'
}
max_version() { printf "%s\n%s\n" "$1" "$2" | sort -V | tail -n1; }
extract_tag_text() {
  local xml="$1" tag="$2"
  echo "$xml" | tr '\n' ' ' | sed -n "s:.*<${tag}>\\([^<][^<]*\\)</${tag}>.*:\\1:p" | head -n1
}
extract_license_expression() {
  local xml="$1"
  echo "$xml" | tr '\n' ' ' | grep -o '<license[^>]*type="expression"[^>]*>[^<]*' 2>/dev/null | sed 's/.*>//' | head -n1
}
fetch_metadata() {
  local id="$1" version="$2"
  local lower_id nuspec_url nuspec license_display license_link project_url
  lower_id="$(echo "$id" | tr '[:upper:]' '[:lower:]')"
  nuspec_url="https://api.nuget.org/v3-flatcontainer/${lower_id}/${version}/${lower_id}.nuspec"
  nuspec="$(curl -sL --fail "$nuspec_url" || true)"
  license_display="(Unknown)"; license_link=""; project_url=""
  if [[ -n "$nuspec" ]]; then
    local lic_expr lic_url proj_url
    lic_expr="$(extract_license_expression "$nuspec")"
    lic_url="$(extract_tag_text "$nuspec" "licenseUrl")"
    proj_url="$(extract_tag_text "$nuspec" "projectUrl")"
    if [[ -n "$lic_expr" ]]; then
      license_display="$lic_expr"; license_link="https://spdx.org/licenses/${lic_expr}.html"
    elif [[ -n "$lic_url" ]]; then
      license_display="$lic_url"; license_link="$lic_url"
    fi
    [[ -n "$proj_url" ]] && project_url="$proj_url"
  fi
  [[ -z "$project_url" ]] && project_url="https://www.nuget.org/packages/${id}/${version}"
  echo -e "${license_display}\t${license_link}\t${project_url}"
}

# ---------- central versions ----------
declare -A CENTRAL_VERSIONS
while IFS= read -r props; do
  while IFS= read -r line; do
    name="$(echo "$line" | grep -o 'Include="[^"]*"' | cut -d'"' -f2 || true)"
    ver="$(echo "$line"  | grep -o 'Version="[^"]*"' | cut -d'"' -f2 || true)"
    [[ -n "$name" && -n "$ver" ]] && CENTRAL_VERSIONS["$name"]="$ver"
  done < <(grep -o '<PackageVersion[^>]*/>' "$props" || true)
done < <(find "$ROOT_DIR" -type f -name "Directory.Packages.props")

# ---------- collect NuGet packages ----------
declare -A PACKAGES

mapfile -t PR_FILES < <(
  find "$ROOT_DIR" -type f \
    \( -name "*.csproj" -o -name "*.fsproj" -o -name "*.vbproj" \
       -o -name "Directory.Build.props" -o -name "Directory.Build.targets" \
       -o -name "*.props" -o -name "*.targets" \) \
    ! -name "Directory.Packages.props"
)

for proj in "${PR_FILES[@]}"; do
  # Inline PackageReference
  while IFS= read -r line; do
    name="$(echo "$line" | grep -o 'Include="[^"]*"' | cut -d'"' -f2 || true)"
    ver="$(echo "$line"  | grep -o 'Version="[^"]*"' | cut -d'"' -f2 || true)"
    if [[ -n "$name" ]]; then
      [[ -z "$ver" ]] && ver="${CENTRAL_VERSIONS[$name]:-}"
      if [[ -n "$ver" ]]; then
        [[ -n "${PACKAGES[$name]:-}" ]] && PACKAGES["$name"]="$(max_version "${PACKAGES[$name]}" "$ver")" || PACKAGES["$name"]="$ver"
      fi
    fi
  done < <(grep -o '<PackageReference[^>]*/>' "$proj" || true)

  # Nested PackageReference
  collapsed="$(tr '\n' ' ' < "$proj" | sed 's/  \+/ /g')"
  while IFS= read -r block; do
    name="$(echo "$block" | grep -o 'Include="[^"]*"' | cut -d'"' -f2 || true)"
    ver="$(echo "$block"  | grep -o '<Version>[^<]*' | sed 's/.*>//' | head -n1 || true)"
    if [[ -n "$name" ]]; then
      [[ -z "$ver" ]] && ver="${CENTRAL_VERSIONS[$name]:-}"
      if [[ -n "$ver" ]]; then
        [[ -n "${PACKAGES[$name]:-}" ]] && PACKAGES["$name"]="$(max_version "${PACKAGES[$name]}" "$ver")" || PACKAGES["$name"]="$ver"
      fi
    fi
  done < <(echo "$collapsed" | grep -o '<PackageReference[^>]*>.*</PackageReference>' || true)

  # GlobalPackageReference
  while IFS= read -r line; do
    name="$(echo "$line" | grep -o 'Include="[^"]*"' | cut -d'"' -f2 || true)"
    ver="$(echo "$line"  | grep -o 'Version="[^"]*"' | cut -d'"' -f2 || true)"
    if [[ -n "$name" && -n "$ver" ]]; then
      [[ -n "${PACKAGES[$name]:-}" ]] && PACKAGES["$name"]="$(max_version "${PACKAGES[$name]}" "$ver")" || PACKAGES["$name"]="$ver"
    fi
  done < <(grep -o '<GlobalPackageReference[^>]*/>' "$proj" || true)
done

# packages.config
while IFS= read -r pkgcfg; do
  while IFS= read -r line; do
    name="$(echo "$line" | grep -o 'id="[^"]*"' | cut -d'"' -f2 || true)"
    ver="$(echo "$line"  | grep -o 'version="[^"]*"' | cut -d'"' -f2 || true)"
    if [[ -n "$name" && -n "$ver" ]]; then
      [[ -n "${PACKAGES[$name]:-}" ]] && PACKAGES["$name"]="$(max_version "${PACKAGES[$name]}" "$ver")" || PACKAGES["$name"]="$ver"
    fi
  done < <(grep -o '<package[^>]*/>' "$pkgcfg" || true)
done < <(find "$ROOT_DIR" -type f -name "packages.config")

# ---------- JSON from NuGet ----------
JSON_ITEMS=""
mapfile -t NAMES < <(printf "%s\n" "${!PACKAGES[@]}" | sort -f)
declare -A INCLUDED_NAMES
for name in "${NAMES[@]}"; do INCLUDED_NAMES["$name"]=1; done

for name in "${NAMES[@]}"; do
  version="${PACKAGES[$name]}"
  meta="$(fetch_metadata "$name" "$version")"
  license_display="$(echo "$meta" | awk -F'\t' '{print $1}')"
  license_link="$(echo "$meta" | awk -F'\t' '{print $2}')"
  project_url="$(echo "$meta" | awk -F'\t' '{print $3}')"
  obj="{\"name\":\"$(json_escape "$name")\",\"version\":\"$(json_escape "$version")\",\"license\":\"$(json_escape "$license_display")\",\"licenseLink\":\"$(json_escape "$license_link")\",\"link\":\"$(json_escape "$project_url")\"}"
  [[ -z "$JSON_ITEMS" ]] && JSON_ITEMS="$obj" || JSON_ITEMS="$JSON_ITEMS,$obj"
done

# ---------- Frontend library detectors (NO REGEX) ----------
# name|license|licenseLink|projectLink|fileSubstr|srcSubstr
# - fileSubstr: case-insensitive substring that should appear in a *.js path
# - srcSubstr : case-insensitive substring that should appear in <script src="...">
DETECTORS='
KnockoutJS|MIT|https://spdx.org/licenses/MIT.html|https://knockoutjs.com/|knockout|knockout
Bootstrap|MIT|https://spdx.org/licenses/MIT.html|https://getbootstrap.com/|bootstrap|bootstrap
Sammy.js|MIT|https://spdx.org/licenses/MIT.html|https://github.com/quirkey/sammy|sammy|sammy
JSZip|MIT|https://spdx.org/licenses/MIT.html|https://github.com/Stuk/jszip|jszip|jszip
jQuery|MIT|https://spdx.org/licenses/MIT.html|https://jquery.com/|jquery|jquery
'

# HTML-like files to scan for script tags
readarray -t HTML_FILES < <(find "$ROOT_DIR" -type f \( -iname "*.html" -o -iname "*.cshtml" -o -iname "*.razor" -o -iname "*.aspx" -o -iname "*.md" \) || true)

# Extract version from a path/URL (3.5.1 in -3.5.1.min.js or /3.5.1/)
extract_version_from_path() {
  local s="$1"
  echo "$s" | sed -nE 's/.*[-_\/]v?([0-9]+\.[0-9]+(\.[0-9]+)?)([^0-9].*)?/\1/p' | head -n1
}
# Extract version by scanning file contents for "v3.5.1"
extract_version_from_file() {
  local f="$1"
  grep -a -m1 -i -E 'v[0-9]+\.[0-9]+(\.[0-9]+)?' "$f" 2>/dev/null \
    | sed -nE 's/.*v([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/p' | head -n1
}

add_detected() {
  local name="$1" version="$2" license="$3" liclink="$4" link="$5"
  [[ -n "${INCLUDED_NAMES[$name]:-}" ]] && return 0
  INCLUDED_NAMES["$name"]=1
  local obj="{\"name\":\"$(json_escape "$name")\",\"version\":\"$(json_escape "$version")\",\"license\":\"$(json_escape "$license")\",\"licenseLink\":\"$(json_escape "$liclink")\",\"link\":\"$(json_escape "$link")\"}"
  [[ -z "$JSON_ITEMS" ]] && JSON_ITEMS="$obj" || JSON_ITEMS="$JSON_ITEMS,$obj"
}

# 1) Scan JS files by filename substring (case-insensitive)
while IFS='|' read -r D_NAME D_LIC D_LICLINK D_LINK D_FILE_SUB D_SRC_SUB; do
  [[ -z "${D_NAME// /}" ]] && continue

  found=""
  version=""

  while IFS= read -r f; do
    # Skip common bulky dirs
    case "$f" in
      */.git/*|*/node_modules/*|*/bin/*|*/obj/*) continue ;;
    esac
    # Must be a .js file
    [[ "${f,,}" != *.js ]] && continue
    # Match substring
    if [[ "${f,,}" == *"${D_FILE_SUB,,}"* ]]; then
      found="$f"
      version="$(extract_version_from_path "$f")"
      [[ -z "$version" ]] && version="$(extract_version_from_file "$f")"
      break
    fi
  done < <(find "$ROOT_DIR" -type f -iname "*.js" 2>/dev/null || true)

  # 2) Scan HTML-like for <script src="..."> containing substring
  if [[ -z "$found" && ${#HTML_FILES[@]} -gt 0 ]]; then
    for hf in "${HTML_FILES[@]}"; do
      # quick grep to avoid cat overhead
      if grep -I -i -m1 '<script' "$hf" >/dev/null 2>&1; then
        # pull first src
        src_line="$(grep -I -i -m1 'src=['"'"'"][^"'"'"']*'"$D_SRC_SUB"'[^"'"'"']*' "$hf" 2>/dev/null || true)"
        if [[ -n "$src_line" ]]; then
          url="$(echo "$src_line" | sed -nE 's/.*src=["'"'"' ]*([^"'"'"' >]+).*/\1/p' | head -n1)"
          if [[ -n "$url" ]]; then
            found="$hf"
            version="$(extract_version_from_path "$url")"
            break
          fi
        fi
      fi
    done
  fi

  if [[ -n "$found" ]]; then
    add_detected "$D_NAME" "${version:-}" "$D_LIC" "$D_LICLINK" "$D_LINK"
  fi
done <<< "$DETECTORS"

# ---------- write HTML ----------
cat > "$OUT_HTML" <<'HTML_HEAD'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<title>Package Credits</title>
<link rel="preconnect" href="https://cdn.jsdelivr.net" crossorigin>
<style>
  :root { color-scheme: light dark; }
  body { font-family: system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, 'Helvetica Neue', Arial, 'Noto Sans', 'Apple Color Emoji', 'Segoe UI Emoji', sans-serif; margin: 2rem; }
  h1 { margin-top: 0; }
  .muted { opacity: 0.75; font-size: 0.9rem; }
  table { border-collapse: collapse; width: 100%; margin-top: 1rem; }
  th, td { border-bottom: 1px solid #ccc; padding: 0.5rem 0.75rem; text-align: left; vertical-align: top; }
  th { position: sticky; top: 0; background: inherit; }
  a { text-decoration: none; }
  a:hover { text-decoration: underline; }
  input[type="search"] { padding: 0.4rem 0.6rem; width: 320px; max-width: 100%; }
  .nowrap { white-space: nowrap; }
</style>
<!-- KnockoutJS (CDN) loaded deferred -->
<script src="https://cdn.jsdelivr.net/npm/knockout@3.5.1/build/output/knockout-latest.js" defer></script>
HTML_HEAD

cat >> "$OUT_HTML" <<HTML_VM
<script>
  // Inline data (generated + detected)
  var initialPackages = [
    $JSON_ITEMS
  ];

  // Sort by name (case-insensitive)
  initialPackages.sort(function (a, b) {
    return (a.name || "").localeCompare(b.name || "", undefined, { sensitivity: "base" });
  });  

  function PackageVM(items) {
    var self = this;
    self.query = ko.observable("");
    self.packages = ko.observableArray(items || []);
    self.filtered = ko.computed(function () {
      var q = (self.query() || "").toLowerCase().trim();
      if (!q) return self.packages();
      return ko.utils.arrayFilter(self.packages(), function (p) {
        return (p.name && p.name.toLowerCase().indexOf(q) >= 0)
            || (p.version && p.version.toLowerCase().indexOf(q) >= 0)
            || (p.license && p.license.toLowerCase().indexOf(q) >= 0);
      });
    });
  }

  document.addEventListener('DOMContentLoaded', function () {
    var viewModel = new PackageVM(initialPackages);
    ko.applyBindings(viewModel);
  });
</script>
HTML_VM

cat >> "$OUT_HTML" <<'HTML_BODY'
</head>
<body>
  <h1>Package Credits</h1>
  <div class="muted">This page lists NuGet packages and detected frontend libraries found in this repository.</div>

  <div style="margin-top:1rem;">
    <input type="search" placeholder="Filter by name, version, or license…" data-bind="textInput: query" />
    <span class="muted" data-bind="text: filtered().length + ' of ' + packages().length + ' shown'"></span>
  </div>

  <table>
    <thead>
      <tr>
        <th>Package</th>
        <th class="nowrap">Version</th>
        <th>License</th>
      </tr>
    </thead>
    <tbody data-bind="foreach: filtered">
      <tr>
        <td>
          <a data-bind="attr: { href: link, target: '_blank', rel: 'noopener noreferrer' }, text: name"></a>
        </td>
        <td class="nowrap" data-bind="text: version || '—'"></td>
        <td>
          <span data-bind="if: licenseLink">
            <a data-bind="attr: { href: licenseLink, target: '_blank', rel: 'noopener noreferrer' }, text: license"></a>
          </span>
          <span data-bind="ifnot: licenseLink" data-bind="text: license || '(Unknown)'"></span>
        </td>
      </tr>
    </tbody>
  </table>

  <p class="muted" style="margin-top:1rem;">
    Tip: edit the detector table inside the script (name|license|licenseLink|projectLink|fileSubstr|srcSubstr) to add more libraries.
  </p>
</body>
</html>
HTML_BODY

echo "Wrote: ${OUT_HTML}"
echo "Packages discovered (NuGet only): ${#PACKAGES[@]}"
