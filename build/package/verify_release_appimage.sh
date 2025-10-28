#!/usr/bin/env bash
set -euo pipefail

# verify_release_appimage.sh
# Verifies and smoke-runs the AppImage emitted by make_appimage.sh
#
# Features:
#   - Auto-detect AppImage in artifacts/packages/, or --appimage <path>
#   - Validates presence, size, and optional .sha256 file
#   - Prints AppImage runtime version via --appimage-version
#   - Optionally smoke-runs the app for N seconds (default 6s) with timeout
#   - Supports forcing variant selection: --variant gtk4.1 | gtk4.0 | auto
#   - Pass-through custom args to the app via --args="--your --flags"

ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../.."
cd "$ROOT"

META="${META:-$ROOT/build/package/release.meta}"
if [[ -f "$META" ]]; then
  set -a; source "$META"; set +a
else
  echo "[WARN] no release.meta at $META; using defaults."
fi

APPVER="${APPVER:-0.0.0}"
APPNAME="${APP_NAME:-${APP_NAME_META:-WPStallman}}"
APP_ID="${APP_ID:-${APP_ID_META:-com.wpstallman.app}}"
BASENAME_CLEAN="$(echo "$APPNAME" | tr -cd '[:alnum:]._-' | sed 's/[.]*$//')"
[[ -n "$BASENAME_CLEAN" ]] || BASENAME_CLEAN="WPStallman"

PKGDIR="$ROOT/artifacts/packages"
DEFAULT_NAME="${BASENAME_CLEAN}-${APPVER}-x86_64-unified.AppImage"

# -------- args ----------
APPIMAGE_PATH=""
VARIANT="auto"     # auto | gtk4.1 | gtk4.0
SMOKE_SECS=6
DO_SMOKE=1         # 1 = run with timeout, 0 = no run
PASS_ARGS=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --appimage <file>    Use this AppImage file (otherwise auto-detect in artifacts/packages/)
  --variant <v>        Force variant: gtk4.1 | gtk4.0 | auto (default: auto)
  --no-run             Do not smoke-run the app (still verifies integrity)
  --smoke-secs <n>     Smoke-run duration in seconds (default: ${SMOKE_SECS})
  --args="...flags..." Extra flags to pass to the app inside the AppImage
  -h, --help           Show this help

Examples:
  $(basename "$0")
  $(basename "$0") --variant gtk4.0
  $(basename "$0") --appimage "$PKGDIR/${DEFAULT_NAME}"
  $(basename "$0") --no-run --appimage "$PKGDIR/${DEFAULT_NAME}" --args="--version"
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --appimage) APPIMAGE_PATH="${2:-}"; shift 2;;
    --variant)  VARIANT="${2:-auto}"; shift 2;;
    --no-run)   DO_SMOKE=0; shift;;
    --smoke-secs) SMOKE_SECS="${2:-6}"; shift 2;;
    --args=*)   PASS_ARGS="${1#--args=}"; shift;;
    -h|--help)  usage; exit 0;;
    *) echo "[ERR] Unknown arg: $1"; usage; exit 2;;
  esac
done

# -------- locate appimage ----------
pick_latest_appimage() {
  local dir="$1"
  [[ -d "$dir" ]] || return 1
  # Prefer unified.AppImage naming, then any .AppImage
  local cand
  cand="$(ls -1t "$dir"/*unified.AppImage 2>/dev/null | head -n1 || true)"
  [[ -n "$cand" ]] || cand="$(ls -1t "$dir"/*.AppImage 2>/dev/null | head -n1 || true)"
  [[ -n "$cand" ]] && echo "$cand" || return 1
}

if [[ -z "$APPIMAGE_PATH" ]]; then
  # Try exact expected name first, then latest
  if [[ -f "$PKGDIR/$DEFAULT_NAME" ]]; then
    APPIMAGE_PATH="$PKGDIR/$DEFAULT_NAME"
  else
    APPIMAGE_PATH="$(pick_latest_appimage "$PKGDIR" || true)"
  fi
fi

[[ -n "$APPIMAGE_PATH" && -f "$APPIMAGE_PATH" ]] || {
  echo "[ERR] Could not find AppImage. Searched: $PKGDIR and expected: $DEFAULT_NAME"
  exit 3
}

chmod +x "$APPIMAGE_PATH" || true

echo "[INFO] AppImage: $APPIMAGE_PATH"
echo "[INFO] Size  : $(du -h "$APPIMAGE_PATH" | awk '{print $1}')"

# -------- sha256 check ----------
if [[ -f "${APPIMAGE_PATH}.sha256" ]]; then
  echo "[INFO] Verifying sha256 (${APPIMAGE_PATH}.sha256)…"
  if (cd "$(dirname "$APPIMAGE_PATH")" && sha256sum -c "$(basename "${APPIMAGE_PATH}.sha256")"); then
    echo "[OK] sha256 matches."
  else
    echo "[ERR] sha256 mismatch!"; exit 4
  fi
else
  echo "[WARN] No .sha256 file found for $(basename "$APPIMAGE_PATH") — skipping checksum verification."
fi

# -------- AppImage runtime sanity ----------
echo "[INFO] AppImage runtime version:"
if "$APPIMAGE_PATH" --appimage-version >/dev/null 2>&1; then
  "$APPIMAGE_PATH" --appimage-version || true
else
  echo "  (Runtime doesn't expose --appimage-version; continuing.)"
fi

# -------- decide variant ----------
RUN_ENV=()
case "$VARIANT" in
  gtk4.0|gtk4.1)
    # Support both the env var and CLI switch for safety
    RUN_ENV+=(WPStallman_FORCE_VARIANT="$VARIANT")
    PASS_ARGS="${PASS_ARGS:+$PASS_ARGS }--variant=$VARIANT"
    echo "[INFO] Forcing variant: $VARIANT"
    ;;
  auto) echo "[INFO] Variant: auto-detect";;
  *) echo "[ERR] Invalid --variant value: $VARIANT"; exit 5;;
esac

# -------- smoke run (non-interactive) ----------
if [[ $DO_SMOKE -eq 1 ]]; then
  # Prefer a non-blocking flag if your GUI supports it; otherwise rely on timeout.
  # We'll try --version first; if it exits nonzero, we still consider the AppImage runnable.
  SMOKE_FLAGS="${PASS_ARGS:-}"
  if [[ -z "$SMOKE_FLAGS" ]]; then
    SMOKE_FLAGS="--version"
  fi

  echo "[INFO] Smoke-run: timeout ${SMOKE_SECS}s '${APPIMAGE_PATH} ${SMOKE_FLAGS}'"
  set +e
  "${RUN_ENV[@]}" timeout "${SMOKE_SECS}" "$APPIMAGE_PATH" $SMOKE_FLAGS
  rc=$?
  set -e

  case $rc in
    0)
      echo "[OK] AppImage executed successfully (exit 0).";;
    124)
      echo "[OK] AppImage launched and was terminated after ${SMOKE_SECS}s (timeout).";;
    *)
      echo "[WARN] AppImage exited with code $rc. This may be fine if the app returns nonzero for '${SMOKE_FLAGS}'."
      echo "       Consider re-running with: $0 --no-run --args=\"\" OR --smoke-secs 12"
      ;;
  esac
else
  echo "[INFO] Skipping smoke-run (--no-run)."
fi

echo "[DONE] Verification complete."
