#!/usr/bin/env bash
# Interactive PCVerse native installer UI (called from self-extracting .run)
set -euo pipefail

PAYLOAD_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_DIR="${HOME}/PCVerse"

pick_folder() {
  if command -v zenity >/dev/null 2>&1; then
    zenity --file-selection --directory --title="PCVerse - choose install folder" --filename="${DEFAULT_DIR}/" 2>/dev/null || true
    return
  fi
  if command -v kdialog >/dev/null 2>&1; then
    kdialog --getexistingdirectory "$HOME" --title "PCVerse - choose install folder" 2>/dev/null || true
    return
  fi
  echo "$DEFAULT_DIR"
}

ask_checkbox() {
  local prompt="$1"
  local default="${2:-true}"
  if command -v zenity >/dev/null 2>&1; then
    zenity --question --title="PCVerse Setup" --text="$prompt" --default-cancel 2>/dev/null && echo yes || echo no
    return
  fi
  [[ "$default" == "true" ]] && echo yes || echo no
}

show_info() {
  local msg="$1"
  if command -v zenity >/dev/null 2>&1; then
    zenity --info --title="PCVerse Setup" --text="$msg" --width=420 2>/dev/null || echo "$msg"
  else
    echo "$msg"
  fi
}

TARGET="$(pick_folder)"
[[ -z "${TARGET}" ]] && exit 0
mkdir -p "$TARGET"

SHORTCUT="$(ask_checkbox "Create a desktop shortcut?" true)"
LAUNCH="$(ask_checkbox "Launch PCVerse when setup finishes?" true)"

install_files() {
  rsync -a --delete "$PAYLOAD_DIR/" "$TARGET/" 2>/dev/null || cp -a "$PAYLOAD_DIR/." "$TARGET/"
  chmod +x "$TARGET/PCVerse" "$TARGET/bin/pcverse" 2>/dev/null || true
}

if command -v zenity >/dev/null 2>&1; then
  (
    echo "10"; echo "# Extracting files..."
    install_files
    echo "100"; echo "# Done"
  ) | zenity --progress --title="PCVerse Setup" --percentage=0 --auto-close --no-cancel 2>/dev/null || install_files
else
  echo "Installing to $TARGET ..."
  install_files
fi

if [[ "$SHORTCUT" == "yes" ]]; then
  DESKTOP="${XDG_DESKTOP_DIR:-$HOME/Desktop}"
  [[ -d "$DESKTOP" ]] || DESKTOP="$HOME"
  cat > "$DESKTOP/PCVerse.desktop" <<EOF
[Desktop Entry]
Name=PCVerse
Comment=Native PC diagnostic lab
Exec=$TARGET/PCVerse
Path=$TARGET
Terminal=false
Type=Application
Categories=Utility;
EOF
  chmod +x "$DESKTOP/PCVerse.desktop"
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$DESKTOP" 2>/dev/null || true
fi

show_info "PCVerse is installed.

Double-click the desktop shortcut or run:
  $TARGET/PCVerse"

if [[ "$LAUNCH" == "yes" ]]; then
  nohup "$TARGET/PCVerse" >/dev/null 2>&1 &
fi
