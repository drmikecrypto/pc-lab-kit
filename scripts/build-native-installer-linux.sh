#!/usr/bin/env bash
# Build PCVerse-Native-Setup-Linux-x64.run - native desktop, no PHP/browser
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT/public/downloads"
OUT="$OUT_DIR/PCVerse-Native-Setup-Linux-x64.run"
STAGE="$(mktemp -d)"
PAYLOAD="$STAGE/payload"
HEADER="$STAGE/header.sh"

cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

mkdir -p "$OUT_DIR" "$PAYLOAD/bin"

echo "Building native desktop..."
bash "$ROOT/scripts/build-native-desktop.sh"

BIN_SRC="$ROOT/native/build-linux/apps/pcverse"
cp -a "$BIN_SRC/pcverse" "$PAYLOAD/bin/"
[[ -d "$BIN_SRC/lib" ]] && cp -a "$BIN_SRC/lib" "$PAYLOAD/bin/"
[[ -d "$BIN_SRC/plugins" ]] && cp -a "$BIN_SRC/plugins" "$PAYLOAD/bin/"

mkdir -p "$PAYLOAD/native/assets"
if [[ -f "$ROOT/native/assets/tool_catalog.json" ]]; then
  cp "$ROOT/native/assets/tool_catalog.json" "$PAYLOAD/native/assets/"
fi

cat > "$PAYLOAD/PCVerse" <<'LAUNCHER'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
export LD_LIBRARY_PATH="$ROOT/bin/lib:${LD_LIBRARY_PATH:-}"
exec "$ROOT/bin/pcverse" "$@"
LAUNCHER
chmod +x "$PAYLOAD/PCVerse" "$PAYLOAD/bin/pcverse"

cp "$ROOT/installer/linux/setup-native-ui.sh" "$PAYLOAD/setup-ui.sh"
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

ARCHIVE_LINE=9999
sed -i "s/__ARCHIVE_LINE__/$ARCHIVE_LINE/" "$HEADER" 2>/dev/null || sed -i '' "s/__ARCHIVE_LINE__/$ARCHIVE_LINE/" "$HEADER"

TAR="$STAGE/payload.tar.gz"
tar czf "$TAR" -C "$PAYLOAD" .

HEADER_LINES=$(wc -l < "$HEADER" | tr -d ' ')
ARCHIVE_LINE=$((HEADER_LINES + 1))
sed -i "s/ARCHIVE_LINE=9999/ARCHIVE_LINE=$ARCHIVE_LINE/" "$HEADER" 2>/dev/null || sed -i '' "s/ARCHIVE_LINE=9999/ARCHIVE_LINE=$ARCHIVE_LINE/" "$HEADER"

cat "$HEADER" "$TAR" > "$OUT"
chmod +x "$OUT"

echo "Built $OUT ($(du -h "$OUT" | cut -f1))"
