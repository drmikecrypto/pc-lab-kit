<?php

declare(strict_types=1);

namespace App\Support;

final class Env
{
    private static bool $loaded = false;

    public static function load(string $path): void
    {
        if (self::$loaded) {
            return;
        }

        if (is_file($path)) {
            $dotenv = \Dotenv\Dotenv::createImmutable(dirname($path), basename($path));
            $dotenv->safeLoad();
        }

        self::$loaded = true;
    }

    public static function get(string $key, mixed $default = null): mixed
    {
        $v = $_ENV[$key] ?? $_SERVER[$key] ?? getenv($key);

        return ($v === false || $v === null || $v === '') ? $default : $v;
    }
}
