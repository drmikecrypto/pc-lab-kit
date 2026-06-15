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
}
