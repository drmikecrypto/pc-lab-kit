#!/usr/bin/env bash
# Stage full PCVerse payload for installers (Linux build host)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:?destination directory}"

# shellcheck source=bootstrap-build-tools.sh
source "$ROOT/scripts/bootstrap-build-tools.sh"

cd "$ROOT"

if [[ ! -f vendor/autoload.php ]]; then
  echo "Installing PHP dependencies (bundled Composer)…"
  run_bundled_composer install --no-interaction --prefer-dist --no-dev
fi

resolve_build_php | xargs -I{} {} "$ROOT/bin/migrate.php" >/dev/null 2>&1 || true

rsync -a --delete \
  --exclude='.git' \
  --exclude='.env' \
  --exclude='storage/database/*.sqlite' \
  --exclude='storage/cache' \
  --exclude='public/downloads/*.zip' \
  --exclude='public/downloads/*.tar.gz' \
  --exclude='public/downloads/*.exe' \
  --exclude='public/downloads/*.run' \
  --exclude='pcverse_app/.dart_tool' \
  --exclude='pcverse_app/build' \
  --exclude='installer/PCVerse.Setup/bin' \
  --exclude='installer/PCVerse.Setup/obj' \
  "$ROOT/" "$DEST/"

mkdir -p "$DEST/public/downloads"
touch "$DEST/public/downloads/.gitkeep"

bundle_linux_php_into "$DEST"

chmod +x "$DEST/PCVerse" "$DEST/scripts/"*.sh 2>/dev/null || true
