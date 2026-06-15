<?php

declare(strict_types=1);

use App\Services\DiagnosticToolCatalogService;

test('tool catalog lists exactly 80 unified tools', function () {
    $svc = new DiagnosticToolCatalogService();
    expect($svc->total())->toBe(80);
});

test('tool catalog coverage counts sum to total', function () {
    $svc = new DiagnosticToolCatalogService();
    $counts = $svc->coverageCounts();
    expect(array_sum($counts))->toBe(80);
    expect($counts['live'])->toBeGreaterThan(0);
});

test('tool catalog payload includes runnable bench and stress modules', function () {
    $payload = (new DiagnosticToolCatalogService())->payload();
    expect($payload['runnable']['bench'])->not->toBeEmpty();
    expect($payload['runnable']['stress'])->not->toBeEmpty();
    expect($payload['summary']['headline'])->toContain('80');
});
