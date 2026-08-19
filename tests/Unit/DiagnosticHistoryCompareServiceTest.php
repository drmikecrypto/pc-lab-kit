<?php

declare(strict_types=1);

use App\Services\DiagnosticHistoryCompareService;

it('compare detects health score improvement', function () {
    $svc = new DiagnosticHistoryCompareService();
    $previous = [
        'health_score' => 62,
        'health_grade' => 'C',
        'bottleneck_type' => 'gpu',
        'bottleneck' => ['type' => 'gpu'],
        'metrics' => ['gpu_temp_max' => 88, 'cpu_temp_max' => 72],
        'token' => 'abc',
        'mode' => 'lite',
        'created_at' => '2026-06-01 10:00:00',
        'ago' => '2d ago',
    ];
    $current = [
        'health_score' => 71,
        'health_grade' => 'B',
        'bottleneck' => ['type' => 'balanced'],
        'metrics' => ['gpu_temp_max' => 76, 'cpu_temp_max' => 68],
    ];

    $out = $svc->compare($current, $previous);

    expect($out['has_previous'])->toBeTrue()
        ->and($out['delta']['health_score'])->toBe(9)
        ->and($out['overall'])->toBe('improved')
        ->and($out['summary'])->toContain('9');
});

it('compare includes open book delta when dossier changes', function () {
    $svc = new DiagnosticHistoryCompareService();
    $previous = [
        'health_score' => 70,
        'health_grade' => 'B',
        'metrics' => ['gpu_therm_spread' => 6],
        'silicon_dossier' => [
            'open_book' => ['count' => 2, 'sensors' => [['source' => 'nvapi_raw']]],
            'gpu' => ['gpu_therm_spread' => 6],
        ],
    ];
    $current = [
        'health_score' => 72,
        'health_grade' => 'B',
        'metrics' => ['gpu_therm_spread' => 10],
        'silicon_dossier' => [
            'open_book' => ['count' => 4, 'sensors' => [
                ['source' => 'blackwell_therm_mmio'],
                ['source' => 'blackwell_vram_mmio'],
            ]],
            'gpu' => ['gpu_therm_spread' => 10],
        ],
    ];

    $out = $svc->compare($current, $previous);

    expect($out['open_book_delta']['sensor_count']['delta'])->toBe(2)
        ->and($out['open_book_delta']['therm_spread']['delta'])->toBe(4.0)
        ->and($out['open_book_delta']['changed'])->toBeTrue()
        ->and($out['summary'])->toContain('Open-book');
});

it('semver detects newer GitHub release tag', function () {
    expect(version_compare('1.1.0', '1.0.0', '>'))->toBeTrue()
        ->and(version_compare('1.0.0', '1.0.0', '>'))->toBeFalse()
        ->and(version_compare('1.0.0', '1.2.0', '>'))->toBeFalse();
});
