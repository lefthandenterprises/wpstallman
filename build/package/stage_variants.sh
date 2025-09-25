#!/usr/bin/env bash
set -euo pipefail

# Args:
#   1: LEGACY publish dir
#   2: MODERN publish dir
#   3: OUT root (artifacts/dist)
#   4: LEGACY glibc label (e.g., 2.35)
#   5: MODERN glibc label (e.g., 2.39)
#   6: RID (e.g., linux-x64)
LEG_PUB="${1:-}"
MOD_PUB="${2:-}"
OUT_ROOT="${3:-artifacts/dist}"
LEG_LABEL="${4:-2.35}"
MOD_LABEL="${5:-2.39}"
RID="${6:-linux-x64}"

die(){ echo "ERROR: $*" >&2; exit 2; }

[[ -n "$LEG_PUB" && -n "$MOD_PUB" ]] || die "Usage: $0 <LEG_PUB> <MOD_PUB> [OUT_ROOT] [LEG_LABEL] [MOD_LABEL] [RID]"
[[ -d "$LEG_PUB" ]] || die "Legacy publish dir not found: $LEG_PUB"
[[ -d "$MOD_PUB" ]] || die "Modern publish dir not found: $MOD_PUB"
[[ -f "$LEG_PUB/WPStallman.GUI" ]] || die "Legacy binary missing in $LEG_PUB"
[[ -f "$MOD_PUB/WPStallman.GUI" ]] || die "Modern binary missing in $MOD_PUB"
[[ -f "$LEG_PUB/wwwroot/index.html" ]] || die "Legacy wwwroot missing: $LEG_PUB/wwwroot/index.html"
[[ -f "$MOD_PUB/wwwroot/index.html" ]] || die "Modern wwwroot missing: $MOD_PUB/wwwroot/index.html"

mkdir -p "$OUT_ROOT"

stage_one() {
  local src="$1" label="$2"
  local dest="$OUT_ROOT/WPStallman.GUI-${RID}-glibc${label}"
  echo "Staging: $src  ->  $dest"
  rm -rf "$dest"
  mkdir -p "$dest"
  rsync -a --delete "$src/" "$dest/"
  (cd "$dest" && find . -type f -print0 | xargs -0 sha256sum > SHA256SUMS)
  echo "OK: $dest"
}

stage_one "$LEG_PUB" "$LEG_LABEL"
stage_one "$MOD_PUB" "$MOD_LABEL"

# point 'current' at modern by default
ln -snf "$(realpath "$OUT_ROOT/WPStallman.GUI-${RID}-glibc${MOD_LABEL}")" \
        "$OUT_ROOT/WPStallman.GUI-${RID}-current"

echo "current -> $(readlink -f "$OUT_ROOT/WPStallman.GUI-${RID}-current")"
