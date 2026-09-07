#!/usr/bin/env bash
# Build pc-lab-kit-linux-x64.tar.gz — portable lab with bundled PHP.
# End users: tar xzf, ./PcLabKit
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT/public/downloads"
OUT="$OUT_DIR/pc-lab-kit-linux-x64.tar.gz"
STAGE="$(mktemp -d)"
PAYLOAD="$STAGE/pc-lab-kit"

cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

mkdir -p "$OUT_DIR" "$PAYLOAD"

echo "Staging Linux app payload..."
bash "$ROOT/scripts/stage-app-payload.sh" "$PAYLOAD"

echo "Packing $OUT ..."
tar czf "$OUT" -C "$STAGE" pc-lab-kit

echo "Built $OUT ($(du -h "$OUT" | cut -f1))"
