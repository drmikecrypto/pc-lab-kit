<?php
/**
 * Register these routes in your app router (copied from pcbuilder app/bootstrap.php).
 * Adjust controller class names if you extract DiagnosticApiController.
 */

use App\Controllers\DiagnosticController;
use App\Controllers\LabPitchController;
use App\Controllers\DownloadController;
use App\Controllers\ApiController; // or DiagnosticApiController after extraction

// Pages
$router->get('/diagnostic', fn () => $container->get(DiagnosticController::class)->index());
$router->get('/lab/pc-test', fn () => $container->get(LabPitchController::class)->pcTest());
$router->get('/lab/rgb-sync', fn () => $container->get(LabPitchController::class)->rgbSync());
$router->get('/download', fn () => $container->get(DownloadController::class)->index());
$router->get('/download/pcverse-windows-x64', fn () => $container->get(DownloadController::class)->windowsInstaller());
$router->get('/download/pcverse-linux-x64', fn () => $container->get(DownloadController::class)->linuxInstaller());

// API — prefix with /api in your front controller
$router->get('/diagnostic/games', fn () => $container->get(ApiController::class)->diagnosticGames());
$router->get('/diagnostic/config', fn () => $container->get(ApiController::class)->diagnosticConfig());
$router->get('/diagnostic/live', fn () => $container->get(ApiController::class)->diagnosticLive());
$router->get('/diagnostic/history', fn () => $container->get(ApiController::class)->diagnosticHistory());
$router->get('/diagnostic/report/{token}', fn ($token) => $container->get(ApiController::class)->diagnosticReport($token));
$router->post('/diagnostic/lite', fn () => $container->get(ApiController::class)->diagnosticLite());
$router->post('/diagnostic/full', fn () => $container->get(ApiController::class)->diagnosticFull());
$router->post('/diagnostic/agent', fn () => $container->get(ApiController::class)->diagnosticAgent());
$router->post('/diagnostic/import', fn () => $container->get(ApiController::class)->diagnosticImport());
$router->post('/diagnostic/telemetry/present', fn () => $container->get(ApiController::class)->diagnosticTelemetryPresent());
$router->post('/diagnostic/oc/plan', fn () => $container->get(ApiController::class)->diagnosticOcPlan());
$router->get('/diagnostic/rgb/catalog', fn () => $container->get(ApiController::class)->diagnosticRgbCatalog());
$router->post('/diagnostic/vakhsh/orchestrate', fn () => $container->get(ApiController::class)->diagnosticVakhshOrchestrate());
$router->post('/diagnostic/vakhsh/narrate', fn () => $container->get(ApiController::class)->diagnosticVakhshNarrate());
$router->post('/diagnostic/game-settings', fn () => $container->get(ApiController::class)->diagnosticGameSettings());
