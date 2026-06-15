#!/usr/bin/env bash
# Build PCVerse-Setup-Linux-x64.run — single-file Linux installer
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT/public/downloads"
OUT="$OUT_DIR/PCVerse-Setup-Linux-x64.run"
STAGE="$(mktemp -d)"
PAYLOAD="$STAGE/payload"
HEADER="$STAGE/header.sh"

cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

mkdir -p "$OUT_DIR" "$PAYLOAD"

echo "Staging Linux payload…"
bash "$ROOT/scripts/bootstrap-build-tools.sh" >/dev/null 2>&1 || true
bash "$ROOT/scripts/stage-payload-unix.sh" "$PAYLOAD"

cp "$ROOT/installer/linux/setup-ui.sh" "$PAYLOAD/setup-ui.sh"
chmod +x "$PAYLOAD/setup-ui.sh"

cat > "$HEADER" <<'HEADER_EOF'
#!/usr/bin/env bash
set -euo pipefail
ARCHIVE_LINE=__ARCHIVE_LINE__
TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
tail -n +$ARCHIVE_LINE "$0" | tar xz -C "$TMP"
bash "$TMP/setup-ui.sh"
exit 0
HEADER_EOF

# Placeholder line number; replace after we know archive offset
ARCHIVE_LINE=9999
sed -i "s/__ARCHIVE_LINE__/$ARCHIVE_LINE/" "$HEADER" 2>/dev/null || sed -i '' "s/__ARCHIVE_LINE__/$ARCHIVE_LINE/" "$HEADER"

TAR="$STAGE/payload.tar.gz"
tar czf "$TAR" -C "$PAYLOAD" .

# Compute line where tar starts (header lines + 1)
HEADER_LINES=$(wc -l < "$HEADER" | tr -d ' ')
ARCHIVE_LINE=$((HEADER_LINES + 1))
sed -i "s/ARCHIVE_LINE=9999/ARCHIVE_LINE=$ARCHIVE_LINE/" "$HEADER" 2>/dev/null || sed -i '' "s/ARCHIVE_LINE=9999/ARCHIVE_LINE=$ARCHIVE_LINE/" "$HEADER"

cat "$HEADER" "$TAR" > "$OUT"
chmod +x "$OUT"

echo "Built $OUT ($(du -h "$OUT" | cut -f1))"
