<?php

declare(strict_types=1);

namespace App\Support;

final class Log
{
    public static function error(string $message, array $context = []): void
    {
        $ctx = $context !== [] ? ' ' . json_encode($context, JSON_UNESCAPED_UNICODE) : '';
        error_log('[PCVerse] ' . $message . $ctx);
    }

    public static function warning(string $message, array $context = []): void
    {
        self::error($message, $context);
    }
}
