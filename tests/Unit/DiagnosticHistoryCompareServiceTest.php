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

it('semver detects newer GitHub release tag', function () {
    expect(version_compare('1.1.0', '1.0.0', '>'))->toBeTrue()
        ->and(version_compare('1.0.0', '1.0.0', '>'))->toBeFalse()
        ->and(version_compare('1.0.0', '1.2.0', '>'))->toBeFalse();
});
