<?php

declare(strict_types=1);

use App\Controllers\AppUpdateController;
use App\Controllers\DiagnosticApiController;
use App\Controllers\DiagnosticController;
use App\Controllers\DownloadController;
use App\Controllers\LabPitchController;
use App\Controllers\SettingsApiController;
use App\Database;
use App\Router;
use App\Support\Env;

require dirname(__DIR__) . '/vendor/autoload.php';

Env::load(dirname(__DIR__) . '/.env');
Database::migrate();

if (session_status() !== PHP_SESSION_ACTIVE) {
    session_start();
}

$router = new Router();
$api = new DiagnosticApiController();
$pages = new DiagnosticController();
$pitch = new LabPitchController();
$downloads = new DownloadController();
$settings = new SettingsApiController();
$updates = new AppUpdateController();

$router->get('/', fn () => $pages->index());
$router->get('/diagnostic', fn () => $pages->index());
$router->get('/lab/pc-test', fn () => $pitch->pcTest());
$router->get('/lab/rgb-sync', fn () => $pitch->rgbSync());
$router->get('/download', fn () => $downloads->index());
$router->get('/download/windows', fn () => $downloads->windows());
$router->get('/download/linux-mac', fn () => $downloads->linuxMac());
$router->get('/download/pcverse-windows-x64', fn () => $downloads->windowsInstaller());
$router->get('/download/pcverse-linux-x64', fn () => $downloads->linuxInstaller());

$router->get('/api/diagnostic/games', fn () => $api->diagnosticGames());
$router->get('/api/diagnostic/config', fn () => $api->diagnosticConfig());
$router->get('/api/diagnostic/live', fn () => $api->diagnosticLive());
$router->get('/api/diagnostic/toolkit', fn () => $api->diagnosticToolkit());
$router->get('/api/diagnostic/history', fn () => $api->diagnosticHistory());
$router->get('/api/diagnostic/report/{token}', fn (string $token) => $api->diagnosticReport($token));
$router->post('/api/diagnostic/lite', fn () => $api->diagnosticLite());
$router->post('/api/diagnostic/full', fn () => $api->diagnosticFull());
$router->post('/api/diagnostic/agent', fn () => $api->diagnosticAgent());
$router->post('/api/diagnostic/import', fn () => $api->diagnosticImport());
$router->post('/api/diagnostic/telemetry/present', fn () => $api->diagnosticTelemetryPresent());
$router->post('/api/diagnostic/oc/plan', fn () => $api->diagnosticOcPlan());
$router->get('/api/diagnostic/rgb/catalog', fn () => $api->diagnosticRgbCatalog());
$router->post('/api/diagnostic/vakhsh/orchestrate', fn () => $api->diagnosticVakhshOrchestrate());
$router->post('/api/diagnostic/vakhsh/narrate', fn () => $api->diagnosticVakhshNarrate());
$router->post('/api/diagnostic/game-settings', fn () => $api->diagnosticGameSettings());
$router->post('/api/track/event', fn () => $api->trackEvent());
$router->get('/api/settings', fn () => $settings->get());
$router->post('/api/settings', fn () => $settings->save());
$router->get('/api/app/update', fn () => $updates->check());

$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);
$path = is_string($path) ? $path : '/';

$router->dispatch($_SERVER['REQUEST_METHOD'] ?? 'GET', $path);
