#!/usr/bin/env bash
# Interactive PCVerse installer UI (called from self-extracting .run)
set -euo pipefail

PAYLOAD_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_DIR="${HOME}/PCVerse"

pick_folder() {
  if command -v zenity >/dev/null 2>&1; then
    zenity --file-selection --directory --title="PCVerse — choose install folder" --filename="${DEFAULT_DIR}/" 2>/dev/null || true
    return
  fi
  if command -v kdialog >/dev/null 2>&1; then
    kdialog --getexistingdirectory "$HOME" --title "PCVerse — choose install folder" 2>/dev/null || true
    return
  fi
  echo "$DEFAULT_DIR"
}

ask_checkbox() {
  local prompt="$1"
  local default="${2:-true}"
  if command -v zenity >/dev/null 2>&1; then
    if [[ "$default" == "true" ]]; then
      zenity --question --title="PCVerse Setup" --text="$prompt" --default-cancel 2>/dev/null && echo yes || echo no
    else
      zenity --question --title="PCVerse Setup" --text="$prompt" --default-cancel 2>/dev/null && echo yes || echo no
    fi
    return
  fi
  if [[ "$default" == "true" ]]; then
    echo yes
  else
    echo no
  fi
}

show_info() {
  local msg="$1"
  if command -v zenity >/dev/null 2>&1; then
    zenity --info --title="PCVerse Setup" --text="$msg" --width=420 2>/dev/null || echo "$msg"
  else
    echo "$msg"
  fi
}

show_error() {
  local msg="$1"
  if command -v zenity >/dev/null 2>&1; then
    zenity --error --title="PCVerse Setup" --text="$msg" --width=420 2>/dev/null || echo "ERROR: $msg" >&2
  else
    echo "ERROR: $msg" >&2
  fi
}

resolve_php() {
  if [[ -x "$TARGET/runtime/php/bin/php" ]]; then
    echo "$TARGET/runtime/php/bin/php"
    return 0
  fi
  if command -v php >/dev/null 2>&1; then
    if php -r 'exit(version_compare(PHP_VERSION,"8.2.0",">=")?0:1);' 2>/dev/null; then
      command -v php
      return 0
    fi
  fi
  return 1
}

ensure_php() {
  if resolve_php >/dev/null; then
    return 0
  fi

  show_error "PCVerse PHP runtime is missing from this installer.

Re-download PCVerse-Setup-Linux-x64.run or install PHP 8.2+ (sqlite, curl, mbstring, json)."
  exit 1
}

TARGET="$(pick_folder)"
[[ -z "${TARGET}" ]] && exit 0
mkdir -p "$TARGET"

SHORTCUT="$(ask_checkbox "Create a desktop shortcut?" true)"
LAUNCH="$(ask_checkbox "Launch PCVerse when setup finishes?" true)"

if command -v zenity >/dev/null 2>&1; then
  (
    echo "10"; echo "# Extracting files…"
    rsync -a --delete "$PAYLOAD_DIR/" "$TARGET/" 2>/dev/null || cp -a "$PAYLOAD_DIR/." "$TARGET/"
    echo "60"; echo "# Configuring…"
    ensure_php
    [[ -f "$TARGET/.env.example" && ! -f "$TARGET/.env" ]] && cp "$TARGET/.env.example" "$TARGET/.env"
    mkdir -p "$TARGET/storage/cache/benchmark" "$TARGET/storage/settings" "$TARGET/storage/database" "$TARGET/public/downloads"
    chmod +x "$TARGET/PCVerse" "$TARGET/scripts/"*.sh 2>/dev/null || true
    php "$(resolve_php)" "$TARGET/bin/migrate.php" 2>/dev/null || true
    echo "85"; echo "# Creating shortcut…"
    if [[ "$SHORTCUT" == "yes" ]]; then
      DESKTOP="${XDG_DESKTOP_DIR:-$HOME/Desktop}"
      [[ -d "$DESKTOP" ]] || DESKTOP="$HOME"
      cat > "$DESKTOP/PCVerse.desktop" <<EOF
[Desktop Entry]
Name=PCVerse
Comment=Local PC diagnostic lab
Exec=$TARGET/PCVerse
Path=$TARGET
Terminal=true
Type=Application
Categories=Utility;
EOF
      chmod +x "$DESKTOP/PCVerse.desktop"
      command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$DESKTOP" 2>/dev/null || true
    fi
    echo "100"; echo "# Done"
  ) | zenity --progress --title="PCVerse Setup" --percentage=0 --auto-close --no-cancel 2>/dev/null || true
else
  echo "Installing to $TARGET …"
  rsync -a --delete "$PAYLOAD_DIR/" "$TARGET/" 2>/dev/null || cp -a "$PAYLOAD_DIR/." "$TARGET/"
  ensure_php
  [[ -f "$TARGET/.env.example" && ! -f "$TARGET/.env" ]] && cp "$TARGET/.env.example" "$TARGET/.env"
  mkdir -p "$TARGET/storage/cache/benchmark" "$TARGET/storage/settings" "$TARGET/storage/database" "$TARGET/public/downloads"
  chmod +x "$TARGET/PCVerse" "$TARGET/scripts/"*.sh 2>/dev/null || true
  php "$(resolve_php)" "$TARGET/bin/migrate.php" 2>/dev/null || true
  if [[ "$SHORTCUT" == "yes" ]]; then
    DESKTOP="${XDG_DESKTOP_DIR:-$HOME/Desktop}"
    [[ -d "$DESKTOP" ]] || DESKTOP="$HOME"
    cat > "$DESKTOP/PCVerse.desktop" <<EOF
[Desktop Entry]
Name=PCVerse
Comment=Local PC diagnostic lab
Exec=$TARGET/PCVerse
Path=$TARGET
Terminal=true
Type=Application
Categories=Utility;
EOF
    chmod +x "$DESKTOP/PCVerse.desktop"
  fi
fi

show_info "PCVerse is installed.

Open the lab at http://127.0.0.1:8080/diagnostic

Use the desktop shortcut or run:
  $TARGET/PCVerse"

if [[ "$LAUNCH" == "yes" ]]; then
  nohup "$TARGET/PCVerse" >/dev/null 2>&1 &
fi
