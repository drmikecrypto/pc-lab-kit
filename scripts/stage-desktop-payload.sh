#!/usr/bin/env bash
# Stage PHP lab (+ bundled PHP) into desktop/src-tauri/resources/lab for Tauri.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/desktop/src-tauri/resources/lab"

# shellcheck source=bootstrap-build-tools.sh
source "$ROOT/scripts/bootstrap-build-tools.sh"

ensure_build_tools >/dev/null

echo "Staging desktop lab payload..."
rm -rf "$DEST"
mkdir -p "$DEST"

# Reuse unix stage helper into DEST
bash "$ROOT/scripts/stage-app-payload.sh" "$DEST"

# Exclude desktop tree if recursively copied (stage-app-payload uses rsync of ROOT)
rm -rf "$DEST/desktop" "$DEST/build-cache" "$DEST/graphify-out" "$DEST/.cursor" || true

echo "Staged lab at $DEST"
