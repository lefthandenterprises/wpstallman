#!/usr/bin/env bash
set -euo pipefail

# Reclaims ownership of repo artifacts that might have been created as root,
# so subsequent builds can delete/overwrite them without permission errors.

# ------- config / args -------
YES=0
FIX_EXEC=0
TARGETS=()  # if empty, we’ll use sensible defaults

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] [paths...]

Options:
  -y, --yes        Run without interactive prompt.
  -x, --fix-exec   Ensure packaging scripts are executable.
  -h, --help       Show this help.

If no paths are provided, the script will operate on:
  artifacts/  build/  src/**/bin  src/**/obj

Examples:
  $(basename "$0") -y
  $(basename "$0") -y -x artifacts build
EOF
}

# parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) YES=0; YES=1; shift ;;
    -x|--fix-exec) FIX_EXEC=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) TARGETS+=("$1"); shift ;;
  esac
done

# ------- repo root detection & safety -------
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if [[ ! -d .git ]]; then
  echo "ERROR: This script must be run from within the git repo (no .git at $ROOT)." >&2
  exit 2
fi

ME_USER="${SUDO_USER:-$USER}"           # if invoked via sudo, use the invoking user
ME_GROUP="$(id -gn "$ME_USER")"

note() { printf "\033[1;36m==> %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33mWARNING:\033[0m %s\n" "$*"; }
die()  { printf "\n\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 2; }

# ------- default target set -------
if [[ ${#TARGETS[@]} -eq 0 ]]; then
  # common build outputs
  mapfile -t TARGETS < <(
    echo "artifacts"
    echo "build"
    # find all bin/ and obj/ dirs under src
    find src -type d \( -name bin -o -name obj \) 2>/dev/null
  )
fi

# de-duplicate & keep existing
uniq_existing=()
declare -A seen
for p in "${TARGETS[@]}"; do
  [[ -e "$p" ]] || continue
  [[ -n "${seen[$p]:-}" ]] && continue
  uniq_existing+=("$p")
  seen[$p]=1
done
TARGETS=("${uniq_existing[@]}")

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  warn "No target paths found. Nothing to do."
  exit 0
fi

echo "Root   : $ROOT"
echo "User   : $ME_USER"
echo "Group  : $ME_GROUP"
echo "Paths  :"
for t in "${TARGETS[@]}"; do echo "  - $t"; done

if [[ $YES -ne 1 ]]; then
  read -r -p "Take ownership of the paths above? [y/N] " ans
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]] || { echo "Aborted."; exit 1; }
fi

# ------- chown step (use sudo only if required) -------
need_sudo=0
for t in "${TARGETS[@]}"; do
  if [[ ! -w "$t" ]]; then need_sudo=1; break; fi
done

CHOWN="chown"
if [[ $need_sudo -eq 1 && $(id -u) -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    CHOWN="sudo chown"
  else
    warn "Some paths may require root to change ownership, but sudo is not available."
  fi
fi

for t in "${TARGETS[@]}"; do
  note "Fixing ownership: $t"
  $CHOWN -R "$ME_USER:$ME_GROUP" "$t" || warn "Could not chown $t (continuing)"
done

# ------- optional: ensure scripts are executable -------
if [[ $FIX_EXEC -eq 1 ]]; then
  note "Ensuring packaging scripts are executable"
  find build/package -maxdepth 1 -type f -name '*.sh' -exec chmod +x {} +
fi

note "Done."
