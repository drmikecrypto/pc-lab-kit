<?php

declare(strict_types=1);

namespace App\Services;

/**
 * PC Lab Kit RGB Lab — unified lighting catalog + orchestration (SignalRGB-class, OpenRGB-light).
 */
class DiagnosticRgbService
{
    /** @return array<string, mixed> */
    public function catalog(): array
    {
        return [
            'engine' => 'orchestrator',
            'tagline' => 'Open-source core · SignalRGB + Fan Control + sensor panel — without bloat',
            'tagline_fa' => 'Open-source core · قابلیت SignalRGB + Fan Control + AIDA64 panel — بدون bloat',
            'privacy' => 'GIF, dashboard, and fan curves stay on your PC — PC Lab Kit never uploads them.',
            'privacy_fa' => 'GIF، dashboard و fan curve فقط روی PC شما — سرور PC Lab Kit هیچ فایلی نمی‌گیرد.',
            'philosophy' => 'One light controller instead of iCUE + Armoury Crate + CAM + SignalRGB at once.',
            'philosophy_fa' => 'یک کنترلر سبک به‌جای iCUE + Armoury Crate + CAM + SignalRGB همزمان. بدون RAM leak، بدون خراب کردن telemetry.',
            'effects' => [
                ['id' => 'static', 'label' => 'Static', 'label_fa' => 'ثابت'],
                ['id' => 'breathing', 'label' => 'Breathing', 'label_fa' => 'تنفس'],
                ['id' => 'pulse', 'label' => 'Pulse', 'label_fa' => 'ضربان'],
                ['id' => 'blink', 'label' => 'Blink', 'label_fa' => 'چشمک', 'blink_timing' => true],
                ['id' => 'rainbow', 'label' => 'Rainbow', 'label_fa' => 'رنگین‌کمان'],
                ['id' => 'wave', 'label' => 'Wave', 'label_fa' => 'موج'],
                ['id' => 'spectrum', 'label' => 'Spectrum', 'label_fa' => 'طیف'],
                ['id' => 'off', 'label' => 'Off', 'label_fa' => 'خاموش'],
                ['id' => 'gif', 'label' => 'GIF (LCD)', 'label_fa' => 'GIF (LCD)', 'lcd_only' => true],
            ],
            'blink_defaults' => [
                'on_ms' => 500,
                'off_ms' => 500,
                'min_ms' => 50,
                'max_ms' => 60000,
            ],
            'orchestrator_profiles' => [
                ['id' => 'dashboard_thermal', 'label' => 'Thermal dashboard', 'label_fa' => 'داشبورد حرارتی', 'desc' => 'RGB follows live telemetry', 'desc_fa' => 'RGB = telemetry زنده — مثل setup حرفه‌ای'],
                ['id' => 'thermal_warning', 'label' => 'Thermal warning', 'label_fa' => 'هشدار دما', 'desc' => 'GPU/CPU > 85°C → red pulse', 'desc_fa' => 'GPU/CPU > 85°C → قرمز pulse'],
                ['id' => 'gaming_pulse', 'label' => 'Gaming', 'label_fa' => 'گیمینگ', 'desc' => 'High load → spectrum + speed', 'desc_fa' => 'load بالا → spectrum + سرعت بیشتر'],
                ['id' => 'stealth_idle', 'label' => 'Stealth', 'label_fa' => 'Stealth', 'desc' => 'Dim idle — no flash', 'desc_fa' => 'idle کم‌نور — بدون flash'],
                ['id' => 'health_sync', 'label' => 'System health', 'label_fa' => 'سلامت سیستم', 'desc' => 'Color from Diagnostic Lab', 'desc_fa' => 'رنگ از Diagnostic Lab'],
            ],
            'features' => [
                'Multi-brand sync (board + fans + strip + AIO) via OpenRGB',
                'Per-zone: fan ring ≠ strip ≠ LCD',
                'Blink with custom on/off duration (ms)',
                'LCD GIF cache + OpenRGB push attempt — 100% local',
                'Conflict detection: iCUE, CAM, SignalRGB, Armoury Crate',
                'Local sensor dashboard HTML for case / cooler panels',
            ],
            'features_fa' => [
                'sync چندبرندی (مادربرد + فن + strip + AIO) via OpenRGB',
                'per-zone: حلقه فن ≠ strip ≠ LCD',
                'fan curve سبک Fan Control — max(CPU, GPU, hotspot)',
                'LCD sensor panel محلی — جایگزین سبک AIDA64',
                'conflict detection: iCUE, CAM, SignalRGB, Armoury Crate',
                'GIF LCD با اعتبارسنجی ابعاد — 100% محلی',
            ],
            'replaces' => [
                'SignalRGB' => 'unified sync + thermal — without bloat',
                'OpenRGB' => 'core + Orchestrator',
                'Fan Control' => 'curve export + max(sensor) rules',
                'AIDA64 panel' => 'local HTML dashboard',
                'iCUE / CAM / Crate' => 'no telemetry spyware',
            ],
            'replaces_fa' => [
                'SignalRGB' => 'unified sync + thermal — بدون سنگینی',
                'OpenRGB' => 'هسته + Orchestrator orchestration',
                'Fan Control' => 'export منحنی + قوانین max(sensor)',
                'AIDA64 panel' => 'HTML dashboard localhost',
                'iCUE / CAM / Crate' => 'بدون bloat و telemetry اضافه',
            ],
        ];
    }

    /**
     * @param array<string, mixed> $telemetry
     * @param array<string, mixed> $context
     * @return array<string, mixed>
     */
    public function orchestrate(array $telemetry, array $context = []): array
    {
        $lighting = new DiagnosticOrchestratorService();
        $plan = $lighting->buildOrchestrationPlan($telemetry, $context);

        return [
            'plan' => $plan,
            'narrative' => $lighting->narrate($plan),
        ];
    }

    /**
     * @param array<string, mixed> $plan
     * @param array<string, mixed> $applyResult
     */
    public function narrateApply(array $plan, array $applyResult): array
    {
        return (new DiagnosticOrchestratorService())->narrate($plan, $applyResult);
    }

    /**
     * Normalize / validate blink timing from a zone payload (UI or API).
     *
     * @param array<string, mixed> $zone
     * @return array{blink_on_ms: int, blink_off_ms: int}
     */
    public function normalizeBlinkTiming(array $zone): array
    {
        $defaults = $this->catalog()['blink_defaults'];
        $on = (int) ($zone['blink_on_ms'] ?? $zone['on_ms'] ?? $defaults['on_ms']);
        $off = (int) ($zone['blink_off_ms'] ?? $zone['off_ms'] ?? $defaults['off_ms']);
        $min = (int) $defaults['min_ms'];
        $max = (int) $defaults['max_ms'];

        return [
            'blink_on_ms' => max($min, min($max, $on)),
            'blink_off_ms' => max($min, min($max, $off)),
        ];
    }

    /** @return array{title: string, title_fa: string, why: string, why_fa: string, steps: list<string>, steps_fa: list<string>} */
    public function defaultEnableGuide(): array
    {
        $steps = [
            'Place OpenRGB.exe in agent/pclab_probe/tools/OpenRGB/',
            'Close iCUE · NZXT CAM · SignalRGB · Armoury Crate',
            'Run Start-PcLabProbe.bat as Administrator once',
            'Click Rescan RGB, then Auto setup or Apply zones',
        ];

        return [
            'title' => 'Enable RGB control',
            'title_fa' => 'فعال‌سازی RGB — چرا الان فقط detect می‌بینی؟',
            'why' => 'Case LEDs use USB/SMBus. Vendor suites install heavy drivers and conflict. PC Lab Kit uses portable OpenRGB — user-mode, light, no brand spyware.',
            'why_fa' => 'LED کیس از USB/SMBus کنترل می‌شود. iCUE و Armoury Crate «درایور» نصب می‌کنند ولی سنگین و conflict‌زا هستند. PcLab Probe با OpenRGB portable — user-mode، سبک، بدون spyware برند.',
            'steps' => $steps,
            'steps_fa' => $steps,
        ];
    }
}
