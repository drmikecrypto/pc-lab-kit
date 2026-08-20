#!/usr/bin/env bash
# Build PcLabKit-Linux-x64.AppImage (Tauri).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESKTOP="$ROOT/desktop"
OUT_DIR="$ROOT/public/downloads"
OUT="$OUT_DIR/PcLabKit-Linux-x64.AppImage"

echo "=== Stage lab payload ==="
chmod +x "$ROOT/scripts/"*.sh
bash "$ROOT/scripts/stage-desktop-payload.sh"

STAGED_PUBLIC="$ROOT/desktop/src-tauri/resources/lab/public/index.php"
if [[ ! -f "$STAGED_PUBLIC" ]]; then
  echo "Lab payload incomplete after staging (missing $STAGED_PUBLIC)" >&2
  exit 1
fi

echo "=== npm install (desktop) ==="
cd "$DESKTOP"
if [[ ! -d node_modules ]]; then
  npm install
else
  npm install --prefer-offline
fi

echo "=== tauri build (AppImage) ==="
npm run tauri -- build --bundles appimage

BUNDLE_DIR="$DESKTOP/src-tauri/target/release/bundle/appimage"
BUILT="$(ls -1t "$BUNDLE_DIR"/*.AppImage 2>/dev/null | head -n1 || true)"
if [[ -z "$BUILT" || ! -f "$BUILT" ]]; then
  echo "AppImage not found under $BUNDLE_DIR" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
cp -f "$BUILT" "$OUT"
chmod +x "$OUT"
echo "Built $OUT ($(du -h "$OUT" | cut -f1))"
