<?php

declare(strict_types=1);

namespace App\Services;

/**
 * وخش RGB Lab — unified lighting catalog + orchestration (SignalRGB-class, OpenRGB-light).
 */
class DiagnosticRgbService
{
    /** @return array<string, mixed> */
    public function catalog(): array
    {
        return [
            'engine' => 'vakhsh',
            'tagline_fa' => 'Open-source core · قابلیت SignalRGB + Fan Control + AIDA64 panel — بدون bloat',
            'privacy_fa' => 'GIF، dashboard و fan curve فقط روی PC شما — سرور PCVerse هیچ فایلی نمی‌گیرد.',
            'philosophy_fa' => 'یک کنترلر سبک به‌جای iCUE + Armoury Crate + CAM + SignalRGB همزمان. بدون RAM leak، بدون خراب کردن telemetry.',
            'effects' => [
                ['id' => 'static', 'label_fa' => 'ثابت'],
                ['id' => 'breathing', 'label_fa' => 'تنفس'],
                ['id' => 'pulse', 'label_fa' => 'ضربان'],
                ['id' => 'rainbow', 'label_fa' => 'رنگین‌کمان'],
                ['id' => 'wave', 'label_fa' => 'موج'],
                ['id' => 'spectrum', 'label_fa' => 'طیف'],
                ['id' => 'off', 'label_fa' => 'خاموش'],
                ['id' => 'gif', 'label_fa' => 'GIF (LCD)', 'lcd_only' => true],
            ],
            'vakhsh_profiles' => [
                ['id' => 'dashboard_thermal', 'label_fa' => 'داشبورد حرارتی', 'desc_fa' => 'RGB = telemetry زنده — مثل setup حرفه‌ای'],
                ['id' => 'thermal_warning', 'label_fa' => 'هشدار دما', 'desc_fa' => 'GPU/CPU > 85°C → قرمز pulse'],
                ['id' => 'gaming_pulse', 'label_fa' => 'گیمینگ', 'desc_fa' => 'load بالا → spectrum + سرعت بیشتر'],
                ['id' => 'stealth_idle', 'label_fa' => 'Stealth', 'desc_fa' => 'idle کم‌نور — بدون flash'],
                ['id' => 'health_sync', 'label_fa' => 'سلامت سیستم', 'desc_fa' => 'رنگ از Diagnostic Lab'],
            ],
            'features_fa' => [
                'sync چندبرندی (مادربرد + فن + strip + AIO) via OpenRGB',
                'per-zone: حلقه فن ≠ strip ≠ LCD',
                'fan curve سبک Fan Control — max(CPU, GPU, hotspot)',
                'LCD sensor panel محلی — جایگزین سبک AIDA64',
                'conflict detection: iCUE, CAM, SignalRGB, Armoury Crate',
                'GIF LCD با اعتبارسنجی ابعاد — 100% محلی',
            ],
            'replaces_fa' => [
                'SignalRGB' => 'unified sync + thermal — بدون سنگینی',
                'OpenRGB' => 'هسته + orchestration وخش',
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
        $lighting = new DiagnosticVakhshLightingService();
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
        return (new DiagnosticVakhshLightingService())->narrate($plan, $applyResult);
    }

    /** @return array{title_fa: string, why_fa: string, steps_fa: list<string>} */
    public function defaultEnableGuide(): array
    {
        return [
            'title_fa' => 'فعال‌سازی RGB — چرا الان فقط detect می‌بینی؟',
            'why_fa' => 'LED کیس از USB/SMBus کنترل می‌شود. iCUE و Armoury Crate «درایور» نصب می‌کنند ولی سنگین و conflict‌زا هستند. PCVerse Probe با OpenRGB portable — user-mode، سبک، بدون spyware برند.',
            'steps_fa' => [
                'OpenRGB.exe → agent/pcverse_probe/tools/OpenRGB/',
                'iCUE · NZXT CAM · SignalRGB · Armoury Crate را ببند',
                'Start-PCVerseProbe.bat → Run as Administrator',
                '«setup حرفه‌ای وخش» را بزن',
            ],
        ];
    }
}
