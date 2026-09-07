<?php

declare(strict_types=1);

namespace App {
    use App\Support\View;

    function view(string $name, array $data = []): string
    {
        return View::make($name, $data)->render();
    }

    function json_response(array $data, int $code = 200): string
    {
        if (PHP_SAPI !== 'cli' && !headers_sent()) {
            http_response_code($code);
            header('Content-Type: application/json; charset=utf-8');
        }

        return json_encode($data, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT) ?: '{}';
    }

    /** @return array<string, mixed>|null */
    function decode_json_body_limited(int $maxBytes = 65536): ?array
    {
        $raw = (string) file_get_contents('php://input');
        if (strlen($raw) > $maxBytes) {
            return null;
        }
        if ($raw === '') {
            return [];
        }
        $decoded = json_decode($raw, true);

        return is_array($decoded) ? $decoded : [];
    }

    function e(?string $s): string
    {
        return htmlspecialchars($s ?? '', ENT_QUOTES, 'UTF-8');
    }

    /** @return array<string, mixed> */
    function json_decode_assoc(?string $json, string $whenEmptyOrInvalid = '[]'): array
    {
        $raw = $json ?? '';
        $trimmed = trim($raw);
        $payload = $trimmed === '' ? $whenEmptyOrInvalid : $raw;
        $decoded = json_decode($payload, true);

        return is_array($decoded) ? $decoded : [];
    }

    /** Ensure session CSRF token exists; return it. */
    function csrf_token(): string
    {
        if (session_status() !== PHP_SESSION_ACTIVE) {
            @session_start();
        }
        if (empty($_SESSION['pclab_csrf']) || !is_string($_SESSION['pclab_csrf'])) {
            $_SESSION['pclab_csrf'] = bin2hex(random_bytes(16));
        }

        return $_SESSION['pclab_csrf'];
    }

    /**
     * Verify X-CSRF-TOKEN (or body _csrf) for mutating requests.
     * On failure sends 403 JSON and exits (or returns false under CLI tests).
     */
    function require_csrf(): bool
    {
        if (session_status() !== PHP_SESSION_ACTIVE) {
            @session_start();
        }
        $expected = (string) ($_SESSION['pclab_csrf'] ?? '');
        $got = (string) (
            $_SERVER['HTTP_X_CSRF_TOKEN']
            ?? $_SERVER['HTTP_X_CSRFTOKEN']
            ?? ''
        );
        if ($got === '' && isset($_POST['_csrf'])) {
            $got = (string) $_POST['_csrf'];
        }
        if ($expected !== '' && $got !== '' && hash_equals($expected, $got)) {
            return true;
        }
        if (PHP_SAPI === 'cli') {
            return false;
        }
        http_response_code(403);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode(['ok' => false, 'error' => 'csrf_invalid', 'message' => 'Invalid or missing CSRF token.'], JSON_UNESCAPED_UNICODE);
        exit;
    }

    /**
     * Per-session rate limit. On failure sends 429 JSON and exits (false under CLI).
     */
    function require_rate_limit(string $bucket, int $maxPerMinute = 60): bool
    {
        $result = \App\Support\RateLimit::attempt($bucket, $maxPerMinute);
        if ($result === true) {
            return true;
        }
        if (PHP_SAPI === 'cli') {
            return false;
        }
        http_response_code(429);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode(['ok' => false, 'error' => 'rate_limited', 'message' => $result], JSON_UNESCAPED_UNICODE);
        exit;
    }
}

namespace {
    if (!function_exists('view')) {
        function view(string $name, array $data = []): string
        {
            return \App\view($name, $data);
        }
    }

    if (!function_exists('json_response')) {
        function json_response(array $data, int $code = 200): string
        {
            return \App\json_response($data, $code);
        }
    }

    if (!function_exists('decode_json_body_limited')) {
        /** @return array<string, mixed>|null */
        function decode_json_body_limited(int $maxBytes = 65536): ?array
        {
            return \App\decode_json_body_limited($maxBytes);
        }
    }

    if (!function_exists('e')) {
        function e(?string $s): string
        {
            return \App\e($s);
        }
    }

    if (!function_exists('csrf_token')) {
        function csrf_token(): string
        {
            return \App\csrf_token();
        }
    }

    if (!function_exists('require_csrf')) {
        function require_csrf(): bool
        {
            return \App\require_csrf();
        }
    }

    if (!function_exists('require_rate_limit')) {
        function require_rate_limit(string $bucket, int $maxPerMinute = 60): bool
        {
            return \App\require_rate_limit($bucket, $maxPerMinute);
        }
    }
}
