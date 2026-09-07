#!/usr/bin/env bash
# Ensures build-cache has Composer PHAR and bundles portable PHP for Linux payloads.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="$ROOT/build-cache"
CONFIG="$ROOT/config/build-deps.json"

ensure_cache() {
  mkdir -p "$CACHE"
}

ensure_composer_phar() {
  ensure_cache
  local phar="$CACHE/composer.phar"
  if [[ -f "$phar" ]]; then
    echo "$phar"
    return 0
  fi
  local url="https://getcomposer.org/download/latest-stable/composer.phar"
  if [[ -f "$CONFIG" ]] && command -v php >/dev/null 2>&1; then
    url="$(php -r 'echo json_decode(file_get_contents($argv[1]), true)["composer_url"] ?? "https://getcomposer.org/download/latest-stable/composer.phar";' "$CONFIG")"
  fi
  echo "Downloading latest Composer…" >&2
  curl -fsSL "$url" -o "$phar"
  chmod +x "$phar"
  echo "$phar"
}

resolve_build_php() {
  if command -v php >/dev/null 2>&1; then
    php -r 'exit(version_compare(PHP_VERSION,"8.2.0",">=")?0:1);' 2>/dev/null && { command -v php; return 0; }
  fi
  if [[ -x "$CACHE/php-linux/bin/php" ]]; then
    echo "$CACHE/php-linux/bin/php"
    return 0
  fi
  echo "PHP 8.2+ required to bootstrap build tools on Linux." >&2
  exit 1
}

run_bundled_composer() {
  local php composer
  php="$(resolve_build_php)"
  composer="$(ensure_composer_phar)"
  "$php" "$composer" "$@"
}

# Copy system PHP + shared libs into DEST/runtime/php (portable on same glibc family).
bundle_linux_php_into() {
  local dest="${1:?destination root}"
  local php_bin php_dir out_bin out_lib
  php_bin="$(command -v php)"
  php_dir="$(dirname "$(readlink -f "$php_bin")")"
  out_bin="$dest/runtime/php/bin"
  out_lib="$dest/runtime/php/lib"
  mkdir -p "$out_bin" "$out_lib"

  cp -L "$php_bin" "$out_bin/php.real"
  chmod +x "$out_bin/php.real"

  if command -v ldd >/dev/null 2>&1; then
    ldd "$out_bin/php.real" 2>/dev/null | awk '/=>/ {print $3}' | while read -r lib; do
      [[ -n "$lib" && -f "$lib" ]] || continue
      cp -L "$lib" "$out_lib/" 2>/dev/null || true
    done
    cat > "$out_bin/php" <<WRAP
#!/usr/bin/env bash
DIR="\$(cd "\$(dirname "\$0")" && pwd)"
export LD_LIBRARY_PATH="\$DIR/../lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
exec "\$DIR/php.real" "\$@"
WRAP
    chmod +x "$out_bin/php"
  else
    mv "$out_bin/php.real" "$out_bin/php"
  fi

  echo "Bundled PHP into $dest/runtime/php" >&2
}

ensure_build_tools() {
  ensure_composer_phar >/dev/null
  echo "Build tools ready (Composer in build-cache)." >&2
}
