#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck source=bootstrap-build-tools.sh
source "$ROOT/scripts/bootstrap-build-tools.sh"

echo "PCVerse — install"
ensure_build_tools

if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "Created .env"
fi

if [[ ! -f vendor/autoload.php ]]; then
  echo "Installing PHP dependencies (bundled Composer)…"
  run_bundled_composer install --no-interaction --prefer-dist
fi

PHP="$(resolve_build_php)"
"$PHP" bin/migrate.php
mkdir -p storage/cache/benchmark storage/settings storage/database public/downloads

if [[ ! -x runtime/php/bin/php ]]; then
  bundle_linux_php_into "$ROOT"
fi

echo ""
echo "Ready. Start with: ./scripts/start.sh"
echo "Open http://127.0.0.1:8080/diagnostic"
