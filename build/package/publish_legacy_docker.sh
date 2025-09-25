#!/usr/bin/env bash
set -euo pipefail

# --- Locate repo root robustly ---
if git_root=$(git rev-parse --show-toplevel 2>/dev/null); then
  ROOT="$git_root"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

DOCKERFILE="${DOCKERFILE:-$ROOT/Dockerfile.legacy}"
IMAGE_NAME="${IMAGE_NAME:-wpstallman-legacy-sdk}"

PROJECT="${PROJECT:-$ROOT/src/WPStallman.GUI.Legacy/WPStallman.GUI.csproj}"
TFM="${TFM:-net8.0}"
RID="${RID:-linux-x64}"
CONF="${CONF:-Release}"

# Container path for the project
PROJECT_IN_CONTAINER="${PROJECT/#$ROOT/\/src}"

echo "ROOT        = $ROOT"
echo "DOCKERFILE  = $DOCKERFILE"
echo "PROJECT     = $PROJECT"
echo "TFM/RID     = $TFM / $RID"
echo "CONFIG      = $CONF"

[[ -f "$PROJECT" ]] || { echo "ERROR: project not found: $PROJECT"; exit 2; }

# --- Build tool image (cached) ---
docker build -f "$DOCKERFILE" -t "$IMAGE_NAME" "$ROOT"

# --- Publish in container ---
docker run --rm \
  -v "$ROOT":/src \
  -w /src \
  "$IMAGE_NAME" \
  bash -lc "
    echo 'Container glibc:' \$(getconf GNU_LIBC_VERSION);
    dotnet restore \"$PROJECT_IN_CONTAINER\";
    dotnet publish \"$PROJECT_IN_CONTAINER\" -c \"$CONF\" -f \"$TFM\" -r \"$RID\";
  "

PUB_DIR="$ROOT/src/WPStallman.GUI.Legacy/bin/$CONF/$TFM/$RID/publish"

# --- Sanity checks ---
[[ -f "$PUB_DIR/WPStallman.GUI" ]] || { echo 'ERROR: Legacy binary missing'; exit 2; }
[[ -f "$PUB_DIR/wwwroot/index.html" ]] || { echo 'ERROR: wwwroot missing in publish'; exit 2; }

echo "Legacy publish ready: $PUB_DIR"

# --- (Optional) Show GLIBC floor symbol detected in binary ---
if command -v strings >/dev/null 2>&1; then
  FLOOR=$(strings -a "$PUB_DIR/WPStallman.GUI" | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -n1 || true)
  echo "Detected GLIBC floor: ${FLOOR:-unknown}"
fi
