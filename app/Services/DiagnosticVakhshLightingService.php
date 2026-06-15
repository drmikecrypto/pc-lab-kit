<?php

declare(strict_types=1);

namespace App\Services;

/**
 * وخش Lighting — unified RGB + fan + LCD dashboard orchestration narrative.
 * Open-source core, commercial-grade features, zero bloat/conflict philosophy.
 */
class DiagnosticVakhshLightingService
{
    /**
     * Build orchestration plan from telemetry + optional diagnostic context.
     *
     * @param array<string, mixed> $telemetry
     * @param array<string, mixed> $context health_score, gpu_util, etc.
     * @return array<string, mixed>
     */
    public function buildOrchestrationPlan(array $telemetry, array $context = []): array
    {
        $cpuTemp = (float) ($telemetry['cpu_temp'] ?? $telemetry['cpu']['thermal']['package_c'] ?? 0);
        $gpuTemp = (float) ($telemetry['gpu_temp'] ?? $telemetry['gpu']['thermal']['core_c'] ?? 0);
        $gpuHot = (float) ($telemetry['gpu']['thermal']['core_c'] ?? $gpuTemp);
        $gpuUtil = (float) ($context['gpu_util_avg'] ?? $telemetry['gpu']['render']['gpu_util_pct'] ?? 0);
        $cpuUtil = (float) ($context['cpu_core_max'] ?? $telemetry['cpu']['clocks']['queue_length'] ?? 0);
        $health = (int) ($context['health_score'] ?? 0);
        $maxTemp = max($cpuTemp, $gpuTemp, $gpuHot);

        $profile = $this->selectProfile($maxTemp, $gpuUtil, $health);
        $rgb = $this->rgbZonePlan($profile, $cpuTemp, $gpuTemp, $gpuUtil);
        $fans = $this->fanCurvePlan($cpuTemp, $gpuTemp, $gpuHot);
        $lcd = $this->lcdDashboardPlan($telemetry, $context);

        return [
            'version' => 2,
            'engine' => 'vakhsh',
            'profile' => $profile,
            'philosophy' => 'minimal_conflict',
            'avoided_bloat' => ['iCUE', 'Armoury Crate', 'NZXT CAM', 'SignalRGB background service'],
            'rgb' => $rgb,
            'fans' => $fans,
            'lcd' => $lcd,
            'telemetry_snapshot' => [
                'cpu_temp_c' => round($cpuTemp, 1),
                'gpu_temp_c' => round($gpuTemp, 1),
                'max_temp_c' => round($maxTemp, 1),
                'gpu_util_pct' => round($gpuUtil, 1),
            ],
        ];
    }

    /**
     * Friendly Persian story after orchestration.
     *
     * @param array<string, mixed> $plan
     * @param array<string, mixed> $applyResult From agent
     */
    public function narrate(array $plan, array $applyResult = []): array
    {
        $profile = (string) ($plan['profile'] ?? 'dashboard_thermal');
        $snap = (array) ($plan['telemetry_snapshot'] ?? []);
        $applied = (array) ($applyResult['applied'] ?? []);
        $fanFile = (string) ($applyResult['fan_curve_path'] ?? $plan['fans']['export_path'] ?? '');
        $lcdPath = (string) ($applyResult['lcd_dashboard_path'] ?? $plan['lcd']['local_path'] ?? '');
        $blocked = (array) ($applyResult['conflicts_closed'] ?? []);

        $headline = match ($profile) {
            'thermal_warning' => 'کیست الان مثل داشبورد حرارتیه — داغ شد، رنگ هشدار می‌ده.',
            'gaming_pulse' => 'حالت گیمینگ: RGB با load پules هم‌زمان شد.',
            'stealth_idle' => 'حالت آرام — LED کم‌نور و بدون فلashing اضافی.',
            'health_sync' => 'RGB با امتیاز سلامت سیستم هم‌خوان شد.',
            default => 'RGB تبدیل شد به telemetry زنده — نه فقط چراغ تزئینی.',
        };

        $why = 'نیمی از نرم‌افزار RGB (iCUE، Armoury Crate، CAM) سنگینن، با هم conflict دارن و telemetry رو خراب می‌کنن. '
            . 'وخش همون قابلیت‌های حرفه‌ای رو می‌ده — sync چندبرندی، thermal warning، fan curve هوشمند، LCD dashboard — '
            . 'ولی فقط با OpenRGB سبک + Probe محلی. هیچ سرویس پس‌زمینه‌ای نصب نمی‌کنی.';

        $did = [];
        if (count($applied) > 0) {
            $did[] = sprintf('%d zone RGB تنظیم شد (فن، حلقه، strip) — هرکدوم نقش خودش رو داره.', count($applied));
        }
        if ($fanFile !== '') {
            $did[] = 'منحنی فن حرفه‌ای (سبک Fan Control) ساخته شد: max(CPU, GPU, hotspot) با hysteresis — فایل محلی برای import.';
        }
        if ($lcdPath !== '') {
            $did[] = 'داشبورد LCD/sensor panel محلی ساخته شد — temps، clocks، util زنده از Agent (بدون AIDA64 سنگین).';
        }
        if ($blocked !== []) {
            $did[] = 'این processها conflict می‌ساختن و بستیم/شناسایی کردیم: ' . implode('، ', $blocked) . '.';
        }
        if ($did === []) {
            $did[] = 'پلن آماده است — OpenRGB portable را فعال کن و دوباره «setup حرفه‌ای» بزن.';
        }

        $benefit = 'دیگه RGB فقط «رنگ بازی» نیست: وقتی GPU از ۸۵°C رد بشه قرمز می‌بینی، '
            . 'فن‌ها قبل از throttle بالا می‌رن، و LCD کیست همون چیزی رو نشون می‌ده که HWiNFO نشون می‌ده — '
            . 'ولی روی خود کیس. RAM leak نداری، telemetry PCVerse Probe خراب نمی‌شه.';

        return [
            'headline_fa' => $headline,
            'why_fa' => $why,
            'did_fa' => $did,
            'benefit_fa' => $benefit,
            'profile' => $profile,
            'compare_fa' => [
                'signalrgb' => 'هم‌تراز: unified sync، thermal، per-zone — بدون سنگینی SignalRGB',
                'openrgb' => 'هسته OpenRGB + orchestration وخش',
                'fan_control' => 'منحنی max(sensor) مثل Fan Control — export محلی',
                'aida64' => 'LCD dashboard سبک‌تر — HTML محلی، داده از Probe',
                'icue_crate_cam' => 'جایگزین بدون bloat و بدون telemetry اضافی',
            ],
            'next_steps_fa' => $this->nextSteps($applyResult),
        ];
    }

    /** @return array<string, mixed> */
    private function rgbZonePlan(string $profile, float $cpuTemp, float $gpuTemp, float $gpuUtil): array
    {
        $hot = max($cpuTemp, $gpuTemp) >= 75;
        $gaming = $gpuUtil >= 60;

        $baseColor = match (true) {
            max($cpuTemp, $gpuTemp) >= 85 => 'FF3355',
            max($cpuTemp, $gpuTemp) >= 70 => 'F29F05',
            default => '00E5CC',
        };

        return [
            'profile' => $profile,
            'zones' => [
                ['role' => 'fan_ring', 'effect' => $hot ? 'pulse' : 'breathing', 'color' => $baseColor, 'speed' => $gaming ? 65 : 40, 'reason_fa' => 'حلقه فن = وضعیت حرارتی'],
                ['role' => 'pump_ring', 'effect' => 'wave', 'color' => $baseColor, 'speed' => 35, 'reason_fa' => 'پمپ AIO = جریان thermal'],
                ['role' => 'strip', 'effect' => $gaming ? 'spectrum' : 'static', 'color' => '8899FF', 'speed' => 25, 'reason_fa' => 'strip کیس = load / ambient'],
                ['role' => 'pump_lcd', 'mode' => 'dashboard', 'reason_fa' => 'LCD = sensor panel زنده'],
            ],
            'global' => ['thermal_warning_c' => 85, 'pulse_on_hot' => true],
        ];
    }

    /** @return array<string, mixed> */
    private function fanCurvePlan(float $cpuTemp, float $gpuTemp, float $gpuHot): array
    {
        $ref = max($cpuTemp, $gpuTemp, $gpuHot, 40);

        return [
            'strategy' => 'max_of_sensors',
            'sensors' => ['cpu_package', 'gpu_core', 'gpu_hotspot'],
            'hysteresis_c' => 3,
            'response_sec' => 4,
            'curves' => [
                [
                    'name_fa' => 'فن‌های کیس',
                    'points' => [[40, 25], [55, 40], [65, 65], [75, 85], [85, 100]],
                ],
                [
                    'name_fa' => 'فن GPU (اگر قابل کنترل)',
                    'points' => [[50, 30], [70, 55], [80, 80], [88, 100]],
                ],
            ],
            'rules_fa' => [
                'اگر GPU hotspot > 85°C → فن کیس 100%',
                'منحنی بر اساس max(CPU, GPU) — مثل Fan Control',
            ],
            'export_path' => '%LOCALAPPDATA%\\PCVerseProbe\\fan-curves.json',
        ];
    }

    /** @param array<string, mixed> $telemetry @param array<string, mixed> $context */
    private function lcdDashboardPlan(array $telemetry, array $context): array
    {
        return [
            'mode' => 'telemetry_panel',
            'widgets' => ['cpu_temp', 'gpu_temp', 'cpu_clock', 'gpu_clock', 'fps', 'vcore', 'fan_rpm'],
            'style' => 'minimal_dark',
            'refresh_ms' => 2000,
            'local_path' => '%LOCALAPPDATA%\\PCVerseProbe\\lcd-dashboard\\index.html',
            'privacy_fa' => 'فقط localhost — هیچ تصویری به سرور PCVerse نمی‌رود.',
        ];
    }

    private function selectProfile(float $maxTemp, float $gpuUtil, int $health): string
    {
        if ($maxTemp >= 85) {
            return 'thermal_warning';
        }
        if ($gpuUtil >= 55) {
            return 'gaming_pulse';
        }
        if ($health > 0 && $health >= 85) {
            return 'health_sync';
        }
        if ($gpuUtil < 15 && $maxTemp < 55) {
            return 'stealth_idle';
        }

        return 'dashboard_thermal';
    }

    /** @param array<string, mixed> $applyResult @return list<string> */
    private function nextSteps(array $applyResult): array
    {
        $steps = [];
        if (empty($applyResult['ok'])) {
            $steps[] = 'OpenRGB.exe را در tools/OpenRGB/ بگذار و Probe را Admin اجرا کن.';
            $steps[] = 'iCUE / Armoury Crate / CAM را ببند — فقط یک کنترلر RGB.';
        }
        if (!empty($applyResult['lcd_dashboard_path'])) {
            $steps[] = 'فایل lcd-dashboard/index.html را برای LCD کیس یا OBS Browser Source باز کن.';
        }
        if (!empty($applyResult['fan_curve_path'])) {
            $steps[] = 'fan-curves.json را در Fan Control import کن (اختیاری — منحنی حرفه‌ای).';
        }
        $steps[] = 'GIF شخصی برای LCD? از بخش zone آپلود کن — باز هم فقط محلی.';

        return $steps;
    }
}
