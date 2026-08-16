<?php

declare(strict_types=1);

use App\Services\DiagnosticRgbService;

test('rgb catalog includes blink with english labels and timing defaults', function () {
    $catalog = (new DiagnosticRgbService())->catalog();

    expect($catalog['effects'])->toBeArray();
    $ids = array_column($catalog['effects'], 'id');
    expect($ids)->toContain('blink', 'static', 'gif');

    $blink = null;
    foreach ($catalog['effects'] as $fx) {
        if (($fx['id'] ?? '') === 'blink') {
            $blink = $fx;
            break;
        }
    }
    expect($blink)->not->toBeNull()
        ->and($blink['label'])->toBe('Blink')
        ->and($blink['blink_timing'] ?? false)->toBeTrue();

    expect($catalog['blink_defaults']['on_ms'])->toBe(500)
        ->and($catalog['blink_defaults']['off_ms'])->toBe(500)
        ->and($catalog['blink_defaults']['min_ms'])->toBe(50);
});

test('rgb blink timing normalizes and clamps', function () {
    $svc = new DiagnosticRgbService();

    $ok = $svc->normalizeBlinkTiming(['blink_on_ms' => 200, 'blink_off_ms' => 800]);
    expect($ok['blink_on_ms'])->toBe(200)->and($ok['blink_off_ms'])->toBe(800);

    $aliases = $svc->normalizeBlinkTiming(['on_ms' => 100, 'off_ms' => 100]);
    expect($aliases['blink_on_ms'])->toBe(100)->and($aliases['blink_off_ms'])->toBe(100);

    $clamped = $svc->normalizeBlinkTiming(['blink_on_ms' => 1, 'blink_off_ms' => 999999]);
    expect($clamped['blink_on_ms'])->toBe(50)
        ->and($clamped['blink_off_ms'])->toBe(60000);
});

test('rgb enable guide is english-first', function () {
    $guide = (new DiagnosticRgbService())->defaultEnableGuide();

    expect($guide['title'])->toContain('Enable RGB')
        ->and($guide['why'])->toContain('OpenRGB')
        ->and($guide['steps'])->not->toBeEmpty()
        ->and($guide['steps'][0])->toContain('OpenRGB');
});

test('orchestrator narrate returns english-first keys', function () {
    $svc = new \App\Services\DiagnosticOrchestratorService();
    $plan = $svc->buildOrchestrationPlan([
        'cpu_temp' => 62,
        'gpu_temp' => 58,
        'gpu' => ['thermal' => ['core_c' => 58], 'render' => ['gpu_util_pct' => 20]],
    ], ['health_score' => 88]);

    $narrative = $svc->narrate($plan, [
        'ok' => true,
        'applied' => [['zone_id' => 'z1']],
        'fan_curve_path' => 'C:\\fans.json',
        'lcd_dashboard_path' => 'C:\\lcd\\index.html',
    ]);

    expect($narrative['headline'])->not->toBeEmpty()
        ->and($narrative['why'])->toContain('OpenRGB')
        ->and($narrative['did'])->toBeArray()->not->toBeEmpty()
        ->and($narrative['did'][0])->toContain('RGB zone')
        ->and($narrative['benefit'])->toContain('85')
        ->and($narrative['compare'])->toHaveKey('openrgb')
        ->and($narrative['next_steps'])->toBeArray()->not->toBeEmpty()
        ->and($narrative['headline_fa'])->not->toBeEmpty()
        ->and($narrative['did_fa'])->toBeArray();
});
