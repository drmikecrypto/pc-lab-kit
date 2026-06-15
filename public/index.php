<?php

declare(strict_types=1);

$uri = urldecode(parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/');
$file = __DIR__ . $uri;

if ($uri !== '/' && is_file($file)) {
    $ext = strtolower(pathinfo($file, PATHINFO_EXTENSION));
    $types = [
        'css' => 'text/css; charset=utf-8',
        'js' => 'application/javascript; charset=utf-8',
        'json' => 'application/json; charset=utf-8',
        'svg' => 'image/svg+xml',
        'png' => 'image/png',
        'zip' => 'application/zip',
        'woff2' => 'font/woff2',
    ];
    if (isset($types[$ext])) {
        header('Content-Type: ' . $types[$ext]);
    }
    readfile($file);

    return;
}

require __DIR__ . '/../routes/web.php';
