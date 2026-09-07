#!/usr/bin/env bash
# Stage portable PC Lab Kit payload (Linux build host) into DEST.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:?destination directory}"

# shellcheck source=bootstrap-build-tools.sh
source "$ROOT/scripts/bootstrap-build-tools.sh"

cd "$ROOT"

ensure_build_tools >/dev/null

if [[ ! -f vendor/autoload.php ]]; then
  echo "Installing PHP dependencies (bundled Composer)..."
  run_bundled_composer install --no-interaction --prefer-dist --no-dev --optimize-autoloader
else
  run_bundled_composer install --no-interaction --prefer-dist --no-dev --optimize-autoloader
fi

mkdir -p "$DEST"
rsync -a \
  --exclude='desktop/' \
  --exclude='.git/' \
  --exclude='.cursor/' \
  --exclude='.env' \
  --exclude='build-cache/' \
  --exclude='graphify-out/' \
  --exclude='node_modules/' \
  --exclude='storage/cache/' \
  --exclude='storage/database/*.sqlite' \
  --exclude='storage/settings/local.json' \
  --exclude='public/downloads/*.zip' \
  --exclude='public/downloads/*.tar.gz' \
  --exclude='public/downloads/*.exe' \
  --exclude='public/downloads/*.run' \
  --exclude='agent/pclab_probe/PcLabHwMon/bin/' \
  --exclude='agent/pclab_probe/PcLabHwMon/obj/' \
  --exclude='agent/pclab_probe/PcLabHwMon.exe' \
  "$ROOT/" "$DEST/"

mkdir -p \
  "$DEST/storage/cache/benchmark" \
  "$DEST/storage/settings" \
  "$DEST/storage/database" \
  "$DEST/public/downloads"
touch "$DEST/public/downloads/.gitkeep"

cp -f "$DEST/.env.example" "$DEST/.env"

bundle_linux_php_into "$DEST"

chmod +x "$DEST/PcLabKit" "$DEST/scripts/"*.sh 2>/dev/null || true
