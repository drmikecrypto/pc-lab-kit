<?php

declare(strict_types=1);

namespace App\Support;

/**
 * Simple per-session file rate limit for mutating lab APIs (shop-floor shared host).
 */
final class RateLimit
{
    /**
     * @return true|string true if allowed, or error message
     */
    public static function attempt(string $bucket, int $maxPerMinute = 60): true|string
    {
        if (session_status() !== PHP_SESSION_ACTIVE) {
            @session_start();
        }
        $sid = session_id() ?: 'anon';
        $dir = dirname(__DIR__, 2) . '/storage/rate_limit';
        if (!is_dir($dir)) {
            @mkdir($dir, 0775, true);
        }
        $safeBucket = preg_replace('/[^a-zA-Z0-9_-]/', '_', $bucket) ?: 'api';
        $file = $dir . '/' . hash('sha256', $sid . '|' . $safeBucket) . '.json';
        $now = time();
        $window = 60;
        $hits = [];
        if (is_file($file)) {
            $decoded = json_decode((string) file_get_contents($file), true);
            if (is_array($decoded)) {
                $hits = array_values(array_filter(
                    array_map('intval', $decoded),
                    static fn (int $t): bool => ($now - $t) < $window
                ));
            }
        }
        if (count($hits) >= $maxPerMinute) {
            return 'Too many requests. Wait a minute and try again.';
        }
        $hits[] = $now;
        @file_put_contents($file, json_encode($hits), LOCK_EX);

        return true;
    }
}
