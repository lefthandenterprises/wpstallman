#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/meta_set_vars.sh"

bash "$SCRIPT_DIR/package_zip.sh"
if [[ -x "$SCRIPT_DIR/package_nsis.sh" ]]; then
  bash "$SCRIPT_DIR/package_nsis.sh"
else
  printf "\033[1;33m[WARN]\033[0m %s\n" "package_nsis.sh not found; skipping NSIS"
fi
