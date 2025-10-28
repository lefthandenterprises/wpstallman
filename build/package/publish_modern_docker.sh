#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Optional: force cache-busting when FLUSH_DOCKER_CACHE=1
if [[ "${FLUSH_DOCKER_CACHE:-0}" -eq 1 ]]; then
  echo "[INFO] FLUSH_DOCKER_CACHE=1 → pruning BuildKit cache and removing local SDK image"
  docker buildx prune --all --force || true
  # Remove the specific SDK image tag for this lane
  docker rmi -f "${IMAGE_NAME:-wpstallman-modern-sdk}" 2>/dev/null || true
fi


# shellcheck source=/dev/null
source "$SCRIPT_DIR/meta_set_vars.sh"

DOCKERFILE="${DOCKERFILE:-$DOCKERFILE_MODERN}"
IMAGE_NAME="${IMAGE_NAME:-wpstallman-modern-sdk}"
PROJECT="${PROJECT:-$ROOT/src/WPStallman.GUI.Modern/WPStallman.GUI.csproj}"
PROJECT_IN_CONTAINER="${PROJECT/#$ROOT/\/src}"
TFM="${TFM:-net8.0}"
RID="${RID:-linux-x64}"
CONF="${CONF:-Release}"

echo "ROOT        = $ROOT"
echo "DOCKERFILE  = $DOCKERFILE"
echo "PROJECT     = $PROJECT"
echo "TFM/RID     = $TFM / $RID"
echo "CONFIG      = $CONF"

[[ -f "$PROJECT" ]] || { echo "ERROR: project not found on host: $PROJECT"; exit 2; }

docker build -f "$DOCKERFILE" -t "$IMAGE_NAME" "$ROOT"

docker run --rm \
  -e DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 \
  -e DOTNET_CLI_TELEMETRY_OPTOUT=1 \
  -e NUGET_PACKAGES=/root/.nuget/packages \
  -v "$HOME/.nuget/packages":/root/.nuget/packages \
  -v "$ROOT":/src \
  -w /src \
  "$IMAGE_NAME" \
  bash -lc "
    echo 'Container glibc:' \$(getconf GNU_LIBC_VERSION);
    dotnet restore \"$PROJECT_IN_CONTAINER\" -r \"$RID\";
    dotnet publish \"$PROJECT_IN_CONTAINER\" -c \"$CONF\" -f \"$TFM\" -r \"$RID\" --no-restore;
  "

PUB_DIR="$ROOT/src/WPStallman.GUI.Modern/bin/$CONF/$TFM/$RID/publish"
[[ -f "$PUB_DIR/WPStallman.GUI" ]] || { echo 'ERROR: Modern binary missing'; exit 2; }
[[ -f "$PUB_DIR/wwwroot/index.html" ]] || { echo 'ERROR: wwwroot missing in publish'; exit 2; }

echo "Modern publish ready: $PUB_DIR"

# ---- NEW: backfill expected artifacts path for downstream packagers ----
OUT_DIR="$ROOT/artifacts/modern-gtk41/publish-gtk41"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
cp -a "$PUB_DIR/." "$OUT_DIR/"
echo "[OK] Modern payload synced to $OUT_DIR"

if command -v strings >/dev/null 2>&1; then
  FLOOR=$(strings -a "$PUB_DIR/WPStallman.GUI" | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -n1 || true)
  echo "Detected GLIBC floor: ${FLOOR:-unknown}"
fi
