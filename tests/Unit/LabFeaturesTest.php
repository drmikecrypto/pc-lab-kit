<?php

declare(strict_types=1);

use App\Services\HardwareKnowledgeGraphService;
use App\Services\LabReportExportService;
use App\Services\StressCertificateService;
use App\Services\ToonSerializer;

test('toon serializer encodes nested context compactly', function () {
    $toon = new ToonSerializer();
    $out = $toon->encode([
        'health' => 88,
        'grade' => 'B',
        'metrics' => ['cpu_score' => 12000, 'gpu_score' => 18000],
        'actions' => ['repaste', 'undervolt'],
    ], 'diag');

    expect($out)->toContain('health=88')
        ->and($out)->toContain('grade=B')
        ->and($out)->toContain('cpu_score=12000')
        ->and($out)->not->toContain('{');
});

test('hardware knowledge graph links cpu gpu ram', function () {
    $graph = (new HardwareKnowledgeGraphService())->fromProbe([
        'cpu' => ['model' => 'Ryzen 7 5800X', 'cores' => 8],
        'gpu' => ['model' => 'RTX 4070', 'vram_gb' => 12],
        'ram' => ['total_gb' => 32],
        'psu' => ['wattage' => 750],
        'device' => ['form_factor' => 'desktop'],
    ], [
        'metrics' => ['cpu_score' => 28000, 'gpu_score' => 22000, 'cpu_temp_max' => 72],
        'percentiles' => ['cpu' => 85, 'gpu' => 70],
        'bottleneck' => ['type' => 'gpu', 'message' => 'GPU limited'],
        'risks' => [],
    ]);

    expect($graph['summary']['node_count'])->toBeGreaterThanOrEqual(4);
    $ids = array_column($graph['nodes'], 'id');
    expect($ids)->toContain('cpu', 'gpu', 'ram', 'psu');
    $rels = array_column($graph['edges'], 'relation');
    expect($rels)->toContain('pcie_attached_to');
});

test('lab report export includes percentiles and history delta', function () {
    $built = (new LabReportExportService())->buildDocument([
        'mode' => 'full',
        'health_score' => 84,
        'health_grade' => 'B',
        'metrics' => ['cpu_score' => 20000, 'gpu_score' => 15000, 'ram_gb' => 32],
        'percentiles' => ['cpu' => 80, 'gpu' => 65, 'gaming' => 70],
        'bottleneck' => ['type' => 'gpu', 'message' => 'GPU bound'],
        'risks' => [['severity' => 'warn', 'message' => 'Watch hotspot']],
        'comparison' => [
            'has_previous' => true,
            'overall' => 'improved',
            'summary' => 'Score up 4 points',
            'delta' => ['health_score' => 4],
        ],
        'report_summary' => ['cpu' => 'Test CPU', 'gpu' => 'Test GPU', 'ram_gb' => 32],
        'saved' => ['token' => 'abc123'],
    ], ['token' => 'abc123']);

    expect($built['html'])->toContain('PC Lab Kit Report')
        ->and($built['html'])->toContain('80th')
        ->and($built['html'])->toContain('History delta')
        ->and($built['html'])->toContain('Print / Save as PDF')
        ->and($built['document']['percentiles']['cpu'])->toBe(80);
});

test('stress certificate fails on GPU artifact errors', function () {
    $fail = (new StressCertificateService())->issue([
        'id' => 'gpu_adaptive',
        'status' => 'failed',
        'duration_s' => 90,
        'artifact_errors' => 3,
        'error' => 'GPU artifact/CRC errors: 3',
        'cpu_temp_max' => 70,
        'gpu_temp_max' => 75,
    ]);
    expect($fail['passed'])->toBeFalse()
        ->and($fail['verdict'])->toBe('FAIL')
        ->and(implode(' ', $fail['failures']))->toContain('artifact');
});

test('tool catalog runnable lists expanded bench and stress profiles', function () {
    $payload = (new \App\Services\DiagnosticToolCatalogService())->payload();
    $benchIds = array_column($payload['runnable']['bench'], 'id');
    $stressIds = array_column($payload['runnable']['stress'], 'id');
    expect($benchIds)->toContain('cpu', 'cpu_mt', 'cpu_cache', 'storage', 'gpu')
        ->and($stressIds)->toContain('cpu', 'gpu', 'combined', 'quick');
    $gpu = null;
    foreach ($payload['runnable']['bench'] as $row) {
        if (($row['id'] ?? '') === 'gpu') {
            $gpu = $row;
            break;
        }
    }
    expect($gpu['label'] ?? '')->toContain('Native');
});
