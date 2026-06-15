#!/usr/bin/env bash
# Build pcverse-lab-linux-mac.tar.gz for /download/pcverse-lab-linux-mac.tar.gz
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT/public/downloads"
OUT="$OUT_DIR/pcverse-lab-linux-mac.tar.gz"

mkdir -p "$OUT_DIR"
cd "$ROOT"

echo "Building $OUT ..."

tar czf "$OUT" \
  --exclude='./vendor' \
  --exclude='./.git' \
  --exclude='./.env' \
  --exclude='./storage/database/*.sqlite' \
  --exclude='./storage/cache' \
  --exclude='./public/downloads/pcverse-probe-windows.zip' \
  --exclude='./public/downloads/pcverse-lab-windows.zip' \
  --exclude='./public/downloads/pcverse-lab-linux-mac.tar.gz' \
  --exclude='./pcverse_app/.dart_tool' \
  --exclude='./pcverse_app/build' \
  .

echo "Done: $OUT ($(du -h "$OUT" | cut -f1))"
