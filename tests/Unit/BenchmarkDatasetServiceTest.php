<?php

declare(strict_types=1);

use App\Services\BenchmarkDatasetService;

test('benchmark dataset loads CPU multithread rows', function () {
    $svc = new BenchmarkDatasetService(dirname(__DIR__, 2));
    $result = $svc->query('cpu-multithread', ['per_page' => 5]);
    expect($result['rows'])->not->toBeEmpty();
    expect($result['total'])->toBeGreaterThan(100);
});

test('benchmark match finds RTX-style GPU names', function () {
    $svc = new BenchmarkDatasetService(dirname(__DIR__, 2));
    $match = $svc->matchPart([
        'category_slug' => 'gpu',
        'brand' => 'NVIDIA',
        'model' => 'RTX 4090',
        'name_fa' => 'RTX 4090',
    ]);
    expect($match)->not->toBeNull();
});
