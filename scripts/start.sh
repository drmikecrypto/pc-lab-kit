#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -f vendor/autoload.php ]]; then
  echo "Run ./scripts/install.sh first."
  exit 1
fi

PORT="${1:-8080}"
PHP_BIN="php"
if [[ -x "$ROOT/runtime/php/bin/php" ]]; then
  PHP_BIN="$ROOT/runtime/php/bin/php"
fi

echo "PCVerse lab → http://127.0.0.1:${PORT}/diagnostic"
echo "Press Ctrl+C to stop."
exec "$PHP_BIN" -S "127.0.0.1:${PORT}" -t public
