<?php

declare(strict_types=1);

/**
 * Export config/tool_catalog.php to native/assets/tool_catalog.json for the Qt desktop shell.
 */
$root = dirname(__DIR__);
require $root . '/vendor/autoload.php';

use App\Services\DiagnosticToolCatalogService;

$outDir = $root . '/native/assets';
if (!is_dir($outDir)) {
    mkdir($outDir, 0775, true);
}

$payload = (new DiagnosticToolCatalogService())->payload();
$json = json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
if ($json === false) {
    fwrite(STDERR, "JSON encode failed\n");
    exit(1);
}

$outFile = $outDir . '/tool_catalog.json';
file_put_contents($outFile, $json . "\n");

echo "Wrote {$outFile} (" . count($payload['tools'] ?? []) . " tools)\n";
