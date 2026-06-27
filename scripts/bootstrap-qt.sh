#!/usr/bin/env bash
# Download Qt 6 into build-cache for native desktop builds (Linux).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$ROOT/config/build-deps.json"
VERSION="$(python3 -c "import json; print(json.load(open('$CONFIG'))['qt_version'])")"
ARCH="$(python3 -c "import json; print(json.load(open('$CONFIG'))['qt_linux_arch'])")"
OUT_ROOT="$ROOT/build-cache/qt"
VERSION_ROOT="$OUT_ROOT/$VERSION"

resolve_qt_dir() {
  local marker="lib/cmake/Qt6/Qt6Config.cmake"
  for child in "$VERSION_ROOT/linux_gcc_64" "$VERSION_ROOT/gcc_64" "$VERSION_ROOT"/*; do
    [[ -d "$child" ]] || continue
    [[ "$child" == *msvc* ]] && continue
    [[ -f "$child/$marker" ]] || continue
    if [[ -f "$child/lib/libQt6Core.so.6" || -f "$child/lib/libQt6Core.so" ]]; then
      echo "$child"
      return 0
    fi
  done
  return 1
}

if QT_DIR="$(resolve_qt_dir)"; then
  echo "Qt $VERSION already in build-cache ($QT_DIR)"
  echo "$QT_DIR" > "$OUT_ROOT/.qt6_root_linux"
  echo "export QT6_ROOT='$QT_DIR'"
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 required for aqtinstall" >&2
  exit 1
fi

AQT_VENV="$ROOT/build-cache/aqt-venv"
AQT=""

install_aqt_tool() {
  local user_aqt
  user_aqt="$(python3 -m site --user-base 2>/dev/null)/bin/aqt"
  if [[ -x "$user_aqt" ]]; then
    AQT="$user_aqt"
    return 0
  fi
  if command -v aqt >/dev/null 2>&1; then
    AQT="$(command -v aqt)"
    return 0
  fi
  if [[ -x "$AQT_VENV/bin/aqt" ]]; then
    AQT="$AQT_VENV/bin/aqt"
    return 0
  fi
  rm -rf "$AQT_VENV"
  if python3 -m venv "$AQT_VENV" 2>/dev/null && [[ -x "$AQT_VENV/bin/pip" ]]; then
    "$AQT_VENV/bin/pip" install --quiet --upgrade pip aqtinstall
    AQT="$AQT_VENV/bin/aqt"
    return 0
  fi
  rm -rf "$AQT_VENV"
  if command -v pipx >/dev/null 2>&1; then
    pipx install aqtinstall >/dev/null 2>&1 || pipx upgrade aqtinstall >/dev/null 2>&1 || true
    if command -v aqt >/dev/null 2>&1; then
      AQT="$(command -v aqt)"
      return 0
    fi
  fi
  python3 -m pip install --user --quiet --upgrade aqtinstall 2>/dev/null || \
    python3 -m pip install --break-system-packages --quiet --upgrade aqtinstall 2>/dev/null || true
  user_aqt="$(python3 -m site --user-base 2>/dev/null)/bin/aqt"
  if [[ -x "$user_aqt" ]]; then
    AQT="$user_aqt"
    return 0
  fi
  if command -v aqt >/dev/null 2>&1; then
    AQT="$(command -v aqt)"
    return 0
  fi
  echo "Could not install aqtinstall." >&2
  echo "Install one of:" >&2
  echo "  sudo apt install python3-venv   # then re-run" >&2
  echo "  sudo apt install pipx && pipx install aqtinstall" >&2
  return 1
}

echo "Preparing aqtinstall..."
install_aqt_tool

mkdir -p "$OUT_ROOT"
echo "Downloading Qt $VERSION ($ARCH) - first run may take several minutes..."
"$AQT" install-qt linux desktop "$VERSION" "$ARCH" -O "$OUT_ROOT"

if ! QT_DIR="$(resolve_qt_dir)"; then
  echo "Qt install failed - no Qt6Config.cmake under $VERSION_ROOT" >&2
  exit 1
fi

echo "OK: $QT_DIR"
echo "$QT_DIR" > "$OUT_ROOT/.qt6_root_linux"
echo "Build desktop: cd native && cmake -B build -DCMAKE_PREFIX_PATH=$QT_DIR"
