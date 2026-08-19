<?php

declare(strict_types=1);

use App\Controllers\AppUpdateController;
use App\Controllers\DiagnosticApiController;
use App\Controllers\DiagnosticController;
use App\Controllers\DownloadController;
use App\Controllers\SettingsApiController;
use App\Controllers\VerifyController;
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
$downloads = new DownloadController();
$settings = new SettingsApiController();
$updates = new AppUpdateController();
$verify = new VerifyController();

$router->get('/', fn () => $pages->index());
$router->get('/diagnostic', fn () => $pages->index());
$router->get('/verify/{hash}', fn (string $hash) => $verify->show($hash));
$router->get('/download/windows', fn () => $downloads->windowsApp());
$router->get('/download/linux', fn () => $downloads->linuxApp());
$router->get('/download/probe-windows', fn () => $downloads->probeWindows());

$router->get('/api/diagnostic/games', fn () => $api->diagnosticGames());
$router->get('/api/diagnostic/config', fn () => $api->diagnosticConfig());
$router->get('/api/diagnostic/live', fn () => $api->diagnosticLive());
$router->get('/api/diagnostic/toolkit', fn () => $api->diagnosticToolkit());
$router->get('/api/diagnostic/arena', fn () => $api->diagnosticArena());
$router->get('/api/diagnostic/silicon-aging', fn () => $api->diagnosticSiliconAging());
$router->post('/api/diagnostic/hardware-graph', fn () => $api->diagnosticHardwareGraph());
$router->get('/api/diagnostic/telemetry/stream', fn () => $api->diagnosticTelemetryStream());
$router->get('/api/diagnostic/fleet/discover', fn () => $api->diagnosticFleetDiscover());
$router->get('/api/diagnostic/federated/aggregates', fn () => $api->diagnosticFederatedAggregates());
$router->get('/api/diagnostic/history', fn () => $api->diagnosticHistory());
$router->get('/api/diagnostic/report/{token}', fn (string $token) => $api->diagnosticReport($token));
$router->get('/api/diagnostic/report/{token}/export', fn (string $token) => $api->diagnosticReportExport($token));
$router->post('/api/diagnostic/lite', fn () => $api->diagnosticLite());
$router->post('/api/diagnostic/full', fn () => $api->diagnosticFull());
$router->post('/api/diagnostic/agent', fn () => $api->diagnosticAgent());
$router->post('/api/diagnostic/import', fn () => $api->diagnosticImport());
$router->post('/api/diagnostic/telemetry/present', fn () => $api->diagnosticTelemetryPresent());
$router->post('/api/diagnostic/drivers/present', fn () => $api->diagnosticDriversPresent());
$router->post('/api/diagnostic/inventory/present', fn () => $api->diagnosticInventoryPresent());
$router->post('/api/diagnostic/oc/plan', fn () => $api->diagnosticOcPlan());
$router->post('/api/diagnostic/oc/report', fn () => $api->diagnosticOcReportExport());
$router->post('/api/diagnostic/stress/certificate', fn () => $api->diagnosticStressCertificate());
$router->post('/api/diagnostic/dossier/present', fn () => $api->diagnosticDossierPresent());
$router->post('/api/diagnostic/assembly/certificate', fn () => $api->diagnosticAssemblyCertificate());
$router->get('/api/diagnostic/rgb/catalog', fn () => $api->diagnosticRgbCatalog());
$router->post('/api/diagnostic/orchestrate', fn () => $api->diagnosticOrchestrate());
$router->post('/api/diagnostic/orchestrate/narrate', fn () => $api->diagnosticOrchestrateNarrate());
$router->post('/api/diagnostic/game-settings', fn () => $api->diagnosticGameSettings());
$router->get('/api/diagnostic/suite/profiles', fn () => $api->diagnosticSuiteProfiles());
$router->post('/api/diagnostic/suite/start', fn () => $api->diagnosticSuiteStart());
$router->get('/api/diagnostic/suite/status/{id}', fn (string $id) => $api->diagnosticSuiteStatus($id));
$router->post('/api/diagnostic/suite/cancel/{id}', fn (string $id) => $api->diagnosticSuiteCancel($id));
$router->post('/api/diagnostic/suite/patch/{id}', fn (string $id) => $api->diagnosticSuitePatch($id));
$router->post('/api/diagnostic/suite/finalize/{id}', fn (string $id) => $api->diagnosticSuiteFinalize($id));
$router->get('/api/diagnostic/sensor-deck', fn () => $api->diagnosticSensorDeckGet());
$router->post('/api/diagnostic/sensor-deck', fn () => $api->diagnosticSensorDeckSave());
$router->get('/api/diagnostic/sensor-deck/export', fn () => $api->diagnosticSensorDeckExport());
$router->post('/api/diagnostic/topology', fn () => $api->diagnosticTopology());
$router->post('/api/diagnostic/session/export', fn () => $api->diagnosticSessionExport());
$router->post('/api/diagnostic/session/import', fn () => $api->diagnosticSessionImport());
$router->get('/api/diagnostic/session/verify', fn () => $api->diagnosticSessionVerify());
$router->post('/api/diagnostic/session/verify', fn () => $api->diagnosticSessionVerify());
$router->get('/api/diagnostic/stability-oracle/profiles', fn () => $api->diagnosticStabilityOracleProfiles());
$router->post('/api/diagnostic/stability-oracle/interpret', fn () => $api->diagnosticStabilityOracleInterpret());
$router->post('/api/track/event', fn () => $api->trackEvent());
$router->get('/api/settings', fn () => $settings->get());
$router->post('/api/settings', fn () => $settings->save());
$router->get('/api/app/update', fn () => $updates->check());

$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);
$path = is_string($path) ? $path : '/';

$router->dispatch($_SERVER['REQUEST_METHOD'] ?? 'GET', $path);
