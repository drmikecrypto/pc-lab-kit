<?php

declare(strict_types=1);

namespace App\Services;

/**
 * PC Lab Kit Lighting — unified RGB + fan + LCD dashboard orchestration narrative.
 * Open-source core, commercial-grade features, zero bloat/conflict philosophy.
 */
class DiagnosticOrchestratorService
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
            'engine' => 'orchestrator',
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
     * Friendly bilingual story after orchestration (English-first for GitHub UI).
     *
     * @param array<string, mixed> $plan
     * @param array<string, mixed> $applyResult From agent
     */
    public function narrate(array $plan, array $applyResult = []): array
    {
        $profile = (string) ($plan['profile'] ?? 'dashboard_thermal');
        $applied = (array) ($applyResult['applied'] ?? []);
        $fanFile = (string) ($applyResult['fan_curve_path'] ?? $plan['fans']['export_path'] ?? '');
        $lcdPath = (string) ($applyResult['lcd_dashboard_path'] ?? $plan['lcd']['local_path'] ?? '');
        $blocked = (array) ($applyResult['conflicts_closed'] ?? []);

        $headline = match ($profile) {
            'thermal_warning' => 'Thermal dashboard mode — lights warn when the system runs hot.',
            'gaming_pulse' => 'Gaming mode: RGB follows GPU load.',
            'stealth_idle' => 'Stealth mode — dim LEDs, no extra flashing.',
            'health_sync' => 'RGB synced to system health score.',
            default => 'RGB follows live telemetry — not just decoration.',
        };
        $headlineFa = match ($profile) {
            'thermal_warning' => 'کیست الان مثل داشبورد حرارتیه — داغ شد، رنگ هشدار می‌ده.',
            'gaming_pulse' => 'حالت گیمینگ: RGB با load پules هم‌زمان شد.',
            'stealth_idle' => 'حالت آرام — LED کم‌نور و بدون فلashing اضافی.',
            'health_sync' => 'RGB با امتیاز سلامت سیستم هم‌خوان شد.',
            default => 'RGB تبدیل شد به telemetry زنده — نه فقط چراغ تزئینی.',
        };

        $why = 'Many RGB suites (iCUE, Armoury Crate, CAM) conflict and break telemetry. '
            . 'PC Lab Kit gives multi-brand sync, thermal warning, smart fan curves, and an LCD dashboard '
            . 'via lightweight OpenRGB + the local Probe — no heavy background suite.';

        $did = [];
        $didFa = [];
        if (count($applied) > 0) {
            $n = count($applied);
            $did[] = sprintf('%d RGB zone(s) applied (fans, rings, strips) — each zone has its own role.', $n);
            $didFa[] = sprintf('%d zone RGB تنظیم شد (فن، حلقه، strip) — هرکدوم نقش خودش رو داره.', $n);
        }
        if ($fanFile !== '') {
            $did[] = 'Professional fan curve (Fan Control–style) saved: max(CPU, GPU, hotspot) with hysteresis — local import file.';
            $didFa[] = 'منحنی فن حرفه‌ای (سبک Fan Control) ساخته شد: max(CPU, GPU, hotspot) با hysteresis — فایل محلی برای import.';
        }
        if ($lcdPath !== '') {
            $did[] = 'Local LCD / sensor panel dashboard built — live temps, clocks, util from the Probe (no heavy AIDA64).';
            $didFa[] = 'داشبورد LCD/sensor panel محلی ساخته شد — temps، clocks، util زنده از Agent (بدون AIDA64 سنگین).';
        }
        if ($blocked !== []) {
            $list = implode(', ', $blocked);
            $did[] = 'Conflicting processes detected/closed: ' . $list . '.';
            $didFa[] = 'این processها conflict می‌ساختن و بستیم/شناسایی کردیم: ' . implode('، ', $blocked) . '.';
        }
        if ($did === []) {
            $did[] = 'Plan is ready — enable OpenRGB Portable and run Auto setup again.';
            $didFa[] = 'پلن آماده است — OpenRGB portable را فعال کن و دوباره «setup حرفه‌ای» بزن.';
        }

        $benefit = 'RGB is no longer just “pretty lights”: when the GPU crosses 85°C you see red, '
            . 'fans ramp before throttle, and the case LCD shows what HWiNFO would — on the case itself. '
            . 'No RAM leak, and PcLab Probe telemetry stays intact.';
        $benefitFa = 'دیگه RGB فقط «رنگ بازی» نیست: وقتی GPU از ۸۵°C رد بشه قرمز می‌بینی، '
            . 'فن‌ها قبل از throttle بالا می‌رن، و LCD کیست همون چیزی رو نشون می‌ده که HWiNFO نشون می‌ده — '
            . 'ولی روی خود کیس. RAM leak نداری، telemetry PcLab Probe خراب نمی‌شه.';

        $compare = [
            'signalrgb' => 'Parity: unified sync, thermal, per-zone — without SignalRGB bloat',
            'openrgb' => 'OpenRGB core + Orchestrator',
            'fan_control' => 'max(sensor) curves like Fan Control — local export',
            'aida64' => 'Lighter LCD dashboard — local HTML, Probe data',
            'icue_crate_cam' => 'Replacement without bloat or extra telemetry',
        ];
        $compareFa = [
            'signalrgb' => 'هم‌تراز: unified sync، thermal، per-zone — بدون سنگینی SignalRGB',
            'openrgb' => 'هسته OpenRGB + Orchestrator orchestration',
            'fan_control' => 'منحنی max(sensor) مثل Fan Control — export محلی',
            'aida64' => 'LCD dashboard سبک‌تر — HTML محلی، داده از Probe',
            'icue_crate_cam' => 'جایگزین بدون bloat و بدون telemetry اضافی',
        ];

        $next = $this->nextSteps($applyResult);
        $nextFa = $this->nextStepsFa($applyResult);

        return [
            'headline' => $headline,
            'why' => $why,
            'did' => $did,
            'benefit' => $benefit,
            'compare' => $compare,
            'next_steps' => $next,
            'headline_fa' => $headlineFa,
            'why_fa' => $why,
            'did_fa' => $didFa,
            'benefit_fa' => $benefitFa,
            'profile' => $profile,
            'compare_fa' => $compareFa,
            'next_steps_fa' => $nextFa,
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
            'export_path' => '%LOCALAPPDATA%\\PcLabKit\Probe\\fan-curves.json',
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
            'local_path' => '%LOCALAPPDATA%\\PcLabKit\Probe\\lcd-dashboard\\index.html',
            'privacy_fa' => 'فقط localhost — هیچ تصویری به سرور PC Lab Kit نمی‌رود.',
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
            $steps[] = 'Place OpenRGB.exe in tools/OpenRGB/ and run the Probe as Administrator.';
            $steps[] = 'Close iCUE / Armoury Crate / CAM — only one RGB controller at a time.';
        }
        if (!empty($applyResult['lcd_dashboard_path'])) {
            $steps[] = 'Open lcd-dashboard/index.html on the case LCD or as an OBS Browser Source.';
        }
        if (!empty($applyResult['fan_curve_path'])) {
            $steps[] = 'Import fan-curves.json into Fan Control (optional — pro curve).';
        }
        $steps[] = 'Personal GIF for the LCD? Upload from the zone section — stays local only.';

        return $steps;
    }

    /** @param array<string, mixed> $applyResult @return list<string> */
    private function nextStepsFa(array $applyResult): array
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
