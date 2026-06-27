#!/usr/bin/env bash
# Build PCVerse native Qt desktop (Linux)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v cmake >/dev/null 2>&1; then
  echo "cmake not found - install: sudo apt install cmake build-essential patchelf" >&2
  exit 1
fi
if ! command -v g++ >/dev/null 2>&1; then
  echo "g++ not found - install: sudo apt install build-essential" >&2
  exit 1
fi
missing_pkgs=()
for pkg in libgl1-mesa-dev libxkbcommon-dev libxcb-cursor-dev libx11-xcb-dev libxcb-xinerama0-dev; do
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    missing_pkgs+=("$pkg")
  fi
done
if ((${#missing_pkgs[@]} > 0)); then
  echo "Missing Qt/X11 build packages: ${missing_pkgs[*]}" >&2
  echo "Install: sudo apt install ${missing_pkgs[*]}" >&2
  exit 1
fi

bash "$ROOT/scripts/bootstrap-qt.sh"
QT_DIR=""
if [[ -f "$ROOT/build-cache/qt/.qt6_root_linux" ]]; then
  QT_DIR="$(tr -d '\r\n' < "$ROOT/build-cache/qt/.qt6_root_linux")"
fi
if [[ -z "$QT_DIR" || ! -f "$QT_DIR/lib/cmake/Qt6/Qt6Config.cmake" ]]; then
  echo "Qt not found - run scripts/bootstrap-qt.sh" >&2
  exit 1
fi

if [[ -f "$ROOT/vendor/autoload.php" ]]; then
  php "$ROOT/scripts/export-tool-catalog.php"
fi

NATIVE="$ROOT/native"
BUILD_DIR="$NATIVE/build-linux"
cd "$NATIVE"
rm -rf "$BUILD_DIR"
cmake -B build-linux -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$QT_DIR"
cmake --build build-linux --parallel "$(nproc 2>/dev/null || echo 4)"

BIN="$NATIVE/build-linux/apps/pcverse/pcverse"
[[ -x "$BIN" ]] || { echo "Build failed - pcverse not found" >&2; exit 1; }

bash "$ROOT/scripts/deploy-qt-linux.sh" "$(dirname "$BIN")" "$QT_DIR"

echo ""
echo "Run: $BIN"
echo "Run from the git clone so optional probe scripts can be found."
