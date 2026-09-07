<?php

declare(strict_types=1);

use App\Services\LabSessionService;
use App\Services\StabilityOracleService;
use App\Services\StressCertificateService;

test('lab session export import round trip verifies hash', function () {
    $svc = new LabSessionService(sys_get_temp_dir() . '/pclab_sess_' . bin2hex(random_bytes(4)));
    $analysis = [
        'fingerprint' => 'abc123fingerprint',
        'metrics' => ['cpu_score' => 12000, 'gpu_score' => 8500],
        'silicon_dossier' => [
            'cpu' => ['model' => 'Ryzen 7'],
            'open_book' => ['count' => 2, 'sensors' => [['source' => 'blackwell_therm_mmio']]],
        ],
        'stress_certificate' => [
            'verdict' => 'PASS',
            'passed' => true,
            'pcie_warnings' => ['GPU x8 in x16 slot'],
            'stability_margin_pct' => 42.5,
        ],
        'suite' => ['profile' => 'standard', 'benches' => []],
        'hardware_graph' => ['summary' => ['node_count' => 5]],
    ];
    $exported = $svc->export($analysis, ['fingerprint' => 'abc123fingerprint', 'profile' => 'standard']);
    expect($exported['session']['format'])->toBe('pclab-session-v1')
        ->and($exported['session']['session_hash'])->toMatch('/^[a-f0-9]{64}$/')
        ->and($exported['session']['verification_qr'])->toContain('pclab://verify/');

    $json = json_encode($exported['session'], JSON_THROW_ON_ERROR);
    $imported = $svc->import($json);
    expect($imported['verified'])->toBeTrue()
        ->and($imported['openbook_snapshot'])->toHaveCount(1);
});

test('lab session drift score detects thermal spread widening', function () {
    $svc = new LabSessionService(sys_get_temp_dir() . '/pclab_drift_' . bin2hex(random_bytes(4)));
    $session = [
        'dossier' => [
            'gpu' => ['gpu_therm_spread' => 6],
            'open_book' => ['count' => 3],
            'storage' => [['smart_wear_pct' => 10]],
        ],
    ];
    $current = [
        'silicon_dossier' => [
            'gpu' => ['gpu_therm_spread' => 12],
            'open_book' => ['count' => 3],
            'storage' => [['smart_wear_pct' => 14]],
        ],
    ];
    $drift = $svc->driftScore($session, $current);
    expect($drift['silicon_aging_index'])->toBeLessThan(100)
        ->and($drift['thermal_spread_delta'])->toBe(6.0)
        ->and($drift['notes'])->not->toBeEmpty();
});

test('stability oracle interprets probe payload', function () {
    $svc = new StabilityOracleService();
    $run = [
        'stability_margin_pct' => 28.5,
        'breached' => false,
        'oracle_steps' => [
            ['id' => 'cpu', 'status' => 'ok', 'stability_margin_pct' => 40],
            ['id' => 'gpu', 'status' => 'ok', 'stability_margin_pct' => 28.5],
        ],
    ];
    $interp = $svc->interpret($run);
    expect($interp['grade'])->toBe('B')
        ->and($interp['step_count'])->toBe(2);

    $cert = (new StressCertificateService())->issue($run, []);
    $enriched = $svc->enrichCertificate($cert, $run);
    expect($enriched['oracle_grade'])->toBe('B')
        ->and($enriched['stability_margin_pct'])->toBe(28.5);
});

test('stress certificate includes whea timeline and pcie warnings', function () {
    $cert = (new StressCertificateService())->issue([
        'id' => 'combined',
        'status' => 'completed',
        'whea_errors' => 1,
        'whea_timeline' => ['count' => 1, 'events' => [['id' => 19, 'message' => 'cache error']]],
        'pcie_warnings' => ['GPU running x8 / max x16'],
        'stability_margin_pct' => 55,
    ], []);
    expect($cert['whea_timeline']['count'])->toBe(1)
        ->and($cert['pcie_warnings'])->toContain('GPU running x8 / max x16')
        ->and($cert['stability_margin_pct'])->toBe(55.0);
});
