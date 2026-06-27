#!/usr/bin/env bash
# Bundle Qt shared libraries next to pcverse on Linux.
set -euo pipefail

BIN_DIR="$1"
QT_DIR="$2"
EXE="$BIN_DIR/pcverse"

if [[ ! -x "$EXE" ]]; then
  echo "pcverse binary not found: $EXE" >&2
  exit 1
fi

LIB_DIR="$BIN_DIR/lib"
PLUGIN_DIR="$BIN_DIR/plugins"
mkdir -p "$LIB_DIR" "$PLUGIN_DIR/platforms"

copy_qt_lib() {
  local name="$1"
  local src="$QT_DIR/lib/${name}.so.6"
  [[ -f "$src" ]] || src="$QT_DIR/lib/${name}.so"
  [[ -f "$src" ]] || return 0
  cp -f "$src" "$LIB_DIR/"
}

for lib in Qt6Core Qt6Gui Qt6Widgets Qt6Network Qt6Concurrent Qt6DBus Qt6Svg Qt6XcbQpa; do
  copy_qt_lib "$lib"
done

if [[ -f "$QT_DIR/plugins/platforms/libqxcb.so" ]]; then
  cp -f "$QT_DIR/plugins/platforms/libqxcb.so" "$PLUGIN_DIR/platforms/"
fi

if command -v patchelf >/dev/null 2>&1; then
  patchelf --set-rpath '$ORIGIN/lib' "$EXE" || true
fi

# XCB / ICU deps from ldd
if command -v ldd >/dev/null 2>&1; then
  ldd "$EXE" | awk '/=>/ {print $3}' | while read -r dep; do
    [[ -n "$dep" && -f "$dep" ]] || continue
    case "$dep" in
      *libQt6*|*libicu*|*libxcb*|*libX*|*libGL*)
        cp -fn "$dep" "$LIB_DIR/" 2>/dev/null || true
        ;;
    esac
  done
fi

echo "Deployed Qt runtime to $BIN_DIR"
