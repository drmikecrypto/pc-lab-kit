<?php

declare(strict_types=1);

use App\Services\AssemblyCertificateService;
use App\Services\SensorDeckService;
use App\Services\SiliconDossierService;

test('silicon dossier presents cpu gpu and open book', function () {
    $out = (new SiliconDossierService())->present([
        'telemetry' => [
            'dossier' => [
                'collected_at' => '2026-08-18T00:00:00Z',
                'cpu' => ['model' => 'Ryzen 7 5800X', 'family' => 25],
                'gpu' => ['name' => 'RTX 5090', 'hotspot_source' => 'blackwell_therm_mmio'],
                'ram' => ['modules' => [['part_number' => 'F4-3600']], 'source' => 'smbios'],
                'board' => ['product' => 'X570', 'serial' => 'B1'],
                'storage' => [['friendly_name' => 'Samsung 990']],
                'monitors' => [['name' => 'Dell', 'edid_hex' => '00FF']],
            ],
            'open_book' => [
                'count' => 2,
                'open_book_therm' => true,
                'open_book_vram' => true,
                'sensors' => [
                    ['name' => 'GPU Hot Spot', 'value' => 82.5, 'source' => 'blackwell_therm_mmio'],
                    ['name' => 'GPU Memory Junction', 'value' => 78, 'source' => 'blackwell_vram_mmio'],
                ],
            ],
        ],
    ]);

    expect($out['cpu']['model'])->toBe('Ryzen 7 5800X')
        ->and($out['gpu']['name'])->toBe('RTX 5090')
        ->and($out['open_book']['count'])->toBe(2)
        ->and($out['open_book']['open_book_vram'])->toBeTrue()
        ->and($out['monitors'][0]['edid_hex'])->toBe('00FF');
});

test('assembly certificate html includes verdict and open-book count', function () {
    $built = (new AssemblyCertificateService())->build([
        'report_summary' => ['cpu' => 'Ryzen 7 5800X', 'gpu' => 'RTX 4070', 'ram_gb' => 32],
        'metrics' => [
            'gpu_temp_max' => 71,
            'gpu_hotspot_max' => 84,
            'gpu_hotspot_source' => 'nvapi_raw',
            'gpu_therm_spread' => 8,
            'gpu_vram_temp' => 76,
        ],
        'stress_certificate' => ['passed' => true, 'verdict' => 'PASS'],
        'silicon_dossier' => [
            'open_book' => [
                'count' => 3,
                'sensors' => [
                    ['source' => 'nvapi_raw'],
                    ['source' => 'nvapi_raw'],
                    ['source' => 'adl'],
                ],
            ],
        ],
    ], ['shop_name' => 'Northside Builds', 'token' => 'abc']);

    expect($built['html'])->toContain('Assembly Certificate')
        ->and($built['html'])->toContain('PASS')
        ->and($built['html'])->toContain('Northside Builds')
        ->and($built['html'])->toContain('nvapi_raw')
        ->and($built['document']['open_book_count'])->toBe(3)
        ->and($built['document']['passed'])->toBeTrue();
});

test('assembly certificate html includes whea pcie margin and verification qr', function () {
    $hash = hash('sha256', 'pclab-session-test');
    $built = (new AssemblyCertificateService())->build([
        'report_summary' => ['cpu' => 'Ryzen 7 5800X', 'gpu' => 'RTX 5090', 'ram_gb' => 32],
        'metrics' => [
            'gpu_temp_max' => 71,
            'gpu_hotspot_max' => 84,
            'gpu_therm_spread' => 8,
        ],
        'stress_certificate' => [
            'passed' => true,
            'verdict' => 'PASS',
            'whea_timeline' => ['count' => 2, 'events' => []],
            'pcie_warnings' => ['GPU running x8 / max x16'],
            'stability_margin_pct' => 41.5,
        ],
        'silicon_dossier' => [
            'open_book' => [
                'count' => 3,
                'sensors' => [
                    ['source' => 'blackwell_therm_mmio'],
                    ['source' => 'pcie_measured'],
                    ['source' => 'whea_correlated'],
                ],
            ],
        ],
        'session_hash' => $hash,
    ], ['shop_name' => 'Truth Lab', 'token' => 'abc']);

    expect($built['html'])->toContain('WHEA errors')
        ->and($built['html'])->toContain('PCIe warnings')
        ->and($built['html'])->toContain('x8 / max x16')
        ->and($built['html'])->toContain('Stability margin')
        ->and($built['html'])->toContain('41.5')
        ->and($built['html'])->toContain('pclab://verify/' . $hash);
});

test('register catalog exposes at least twelve provenance tags', function () {
    $path = dirname(__DIR__, 2) . '/agent/pclab_probe/data/register-catalog.json';
    $json = json_decode((string) file_get_contents($path), true);
    expect($json)->toBeArray()
        ->and($json['provenance_tags'])->toBeArray()
        ->and(count($json['provenance_tags']))->toBeGreaterThanOrEqual(12);
});

test('sensor deck defaults include vram and therm s1', function () {
    $sources = array_column((new SensorDeckService(sys_get_temp_dir() . '/pclab_deck_ob'))->defaultLayout()['widgets'], 'source');
    expect($sources)->toContain('gpu_vram_temp', 'gpu_therm_s1', 'gpu_therm_spread');
});
