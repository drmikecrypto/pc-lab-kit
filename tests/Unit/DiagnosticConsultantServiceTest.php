<?php

declare(strict_types=1);

use App\Services\DiagnosticConsultantService;

describe('DiagnosticConsultantService', function () {
    test('high score clean thermal yields solid stance', function () {
        $p = (new DiagnosticConsultantService())->plan([
            'health_score' => 88,
            'health_grade' => 'A',
            'bottleneck' => ['type' => 'balanced'],
            'metrics' => ['gpu_temp_max' => 72, 'cpu_temp_max' => 68],
            'risks' => [],
        ]);

        expect($p['stance'] ?? '')->toBe('solid');
        expect($p['horizons'] ?? [])->not->toBeEmpty();
        expect($p['headline'] ?? '')->not->toBe('');
    });

    test('thermal stress forces watch or upgrade stance', function () {
        $p = (new DiagnosticConsultantService())->plan([
            'health_score' => 62,
            'health_grade' => 'C',
            'bottleneck' => ['type' => 'gpu'],
            'metrics' => ['gpu_temp_max' => 92, 'cpu_temp_max' => 70],
            'risks' => [],
        ]);

        expect(($p['stance'] ?? '') === 'watch' || ($p['stance'] ?? '') === 'upgrade')->toBeTrue();
    });

    test('returns English advisor fields without catalog picks', function () {
        $p = (new DiagnosticConsultantService())->plan([
            'health_score' => 62,
            'health_grade' => 'C',
            'bottleneck' => ['type' => 'gpu', 'component' => 'gpu'],
            'metrics' => ['gpu_temp_max' => 92, 'cpu_temp_max' => 70],
            'risks' => [],
        ]);

        expect($p)->not->toHaveKey('catalog_picks');
        expect($p['neural_tags'] ?? [])->toContain('bn:gpu');
    });
});
