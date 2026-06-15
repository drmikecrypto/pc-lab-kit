<?php

/**
 * Refresh diagnostic game catalog (300 titles) from Steam + awards + optional RAWG/LLM.
 *
 * crontab (weekly Sunday 04:00):
 *   php /path/to/pcverse/cron/refresh_diagnostic_games.php >> storage/logs/diagnostic_games.log 2>&1
 */

require_once __DIR__ . '/../vendor/autoload.php';
require_once __DIR__ . '/../app/bootstrap.php';

use App\Services\DiagnosticGameCatalogService;

echo '[' . date('c') . "] diagnostic games refresh starting...\n";

try {
    $result = (new DiagnosticGameCatalogService())->refreshIfStale(true);
    echo json_encode($result, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT) . "\n";
} catch (\Throwable $e) {
    echo '[' . date('c') . '] ERROR: ' . $e->getMessage() . "\n";
    error_log('refresh_diagnostic_games: ' . $e->getMessage());
    exit(1);
}
