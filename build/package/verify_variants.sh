#!/usr/bin/env bash
set -euo pipefail

# ---------- config ----------
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RID="${RID:-linux-x64}"
VARIANTS=(${VARIANTS:-glibc2.35 glibc2.39})
APP_NAME="${APP_NAME:-W. P. Stallman}"

ok()  { printf "\033[32m✔ %s\033[0m\n" "$*"; }
bad() { printf "\033[31m✗ %s\033[0m\n" "$*"; }
hdr() { printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }

fail=0

check_variant () {
  local variant="$1"
  hdr "Verifying Linux variant: $variant"

  # ---- staged payload (dist) ----
  local STAGED="$ROOT/artifacts/dist/WPStallman.GUI-${RID}-${variant}"
  if [[ ! -d "$STAGED" ]]; then bad "Staged dir missing: $STAGED"; fail=1; return; fi
  ok "Staged dir exists: $STAGED"

  [[ -x "$STAGED/WPStallman.GUI" ]] || { bad "Missing GUI binary in staged dir"; fail=1; return; }
  ok "Binary present: $STAGED/WPStallman.GUI"

  [[ -f "$STAGED/wwwroot/index.html" ]] || { bad "Missing wwwroot/index.html in staged dir"; fail=1; return; }
  ok "wwwroot present"

  if [[ -f "$STAGED/SHA256SUMS" ]]; then
    (cd "$STAGED" && sha256sum -c SHA256SUMS >/dev/null) \
      && ok "SHA256SUMS verified" \
      || { bad "SHA256SUMS failed"; fail=1; }
  else
    bad "No SHA256SUMS in staged dir (non-fatal)"
  fi

  # glibc floor (informational)
  local floor
  floor="$(strings -a "$STAGED/WPStallman.GUI" | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sort -V | tail -n1 || true)"
  [[ -n "$floor" ]] && ok "Detected GLIBC floor symbol in binary: $floor" || ok "GLIBC floor symbol not detected (ok)"

  # ---- packaged outputs (linuxvariants/<variant>) ----
  local OUTBASE="$ROOT/artifacts/packages/linuxvariants/$variant"
  if [[ ! -d "$OUTBASE" ]]; then bad "Output dir missing: $OUTBASE"; fail=1; return; fi
  ok "Output dir exists: $OUTBASE"

  # AppImage
  local ai; ai="$(ls -1 "$OUTBASE"/*.AppImage 2>/dev/null | head -n1 || true)"
  if [[ -n "$ai" ]]; then
    chmod +x "$ai" || true
    ok "AppImage found: $(basename "$ai")"
    # Quick metadata ping (no FUSE needed)
    APPIMAGE_EXTRACT_AND_RUN=1 "$ai" --appimage-version >/dev/null 2>&1 \
      && ok "AppImage self-check passed (--appimage-version)" \
      || bad "AppImage self-check failed (--appimage-version)"
  else
    bad "No AppImage found in $OUTBASE"; fail=1
  fi

  # .deb
  local deb; deb="$(ls -1 "$OUTBASE"/*.deb 2>/dev/null | head -n1 || true)"
  if [[ -n "$deb" ]]; then
    ok "Deb found: $(basename "$deb")"
    dpkg-deb -I "$deb" >/dev/null && ok "Deb metadata readable" || { bad "dpkg-deb -I failed"; fail=1; }
  else
    bad "No .deb found in $OUTBASE"; fail=1
  fi
}

# ----- run checks for all variants -----
for v in "${VARIANTS[@]}"; do
  check_variant "$v"
done

# ----- Windows installer (optional) -----
hdr "Checking Windows artifacts"
WIN_PUBLISH="$ROOT/src/WPStallman.GUI/bin/Release/net8.0-windows/win-x64/publish"
WIN_EXE="$(ls -1 "$ROOT"/artifacts/packages/*.exe 2>/dev/null | head -n1 || true)"

[[ -d "$WIN_PUBLISH" ]] && ok "Windows publish present" || bad "Windows publish missing (optional)"
[[ -n "$WIN_EXE" ]] && ok "NSIS installer present: $(basename "$WIN_EXE")" || bad "NSIS installer missing (optional)"

# ----- summary -----
echo
if [[ "$fail" -eq 0 ]]; then
  hdr "All checks passed ✅"
else
  hdr "Some checks failed ❌  (see messages above)"
  exit 1
fi
