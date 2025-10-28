#!/usr/bin/env bash
set -euo pipefail

# Resolve script directory and step up to repo root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
cd "$REPO_ROOT"

# Location of output zip (Desktop + timestamp)
TS=$(date +"%Y%m%d_%H%M%S")
OUT="$HOME/Desktop/minimal-llm-wpstallman-$TS.zip"

# Ensure Desktop exists
mkdir -p "$HOME/Desktop"

echo "Creating minimal zip from repo root: $REPO_ROOT"
echo "Output: $OUT"

# Archive current HEAD, honoring .gitattributes export-ignore
git archive --format=zip -o "$OUT" HEAD

echo "Done. File written to $OUT"
