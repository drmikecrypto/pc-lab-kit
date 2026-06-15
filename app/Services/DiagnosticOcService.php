<?php

declare(strict_types=1);

namespace App\Services;

/**
 * وخش — conservative auto-overclock planner from diagnostic telemetry.
 * Only recommends/applies reversible, margin-based tuning when safety gates pass.
 */
class DiagnosticOcService
{
    private const GPU_TEMP_LIMIT = 83.0;
    private const GPU_HOTSPOT_LIMIT = 92.0;
    private const CPU_TEMP_LIMIT = 82.0;
    private const MIN_SAFETY_SCORE = 72;
    private const MIN_HEALTH_SCORE = 70;

    /**
     * @param array<string, mixed> $report Normalized probe + telemetry report
     * @param array<string, mixed> $analysis Result from DiagnosticService::analyzeFull
     * @return array<string, mixed>
     */
    public function buildPlan(array $report, array $analysis = []): array
    {
        $tel = (array) ($report['telemetry'] ?? []);
        if ($tel === [] && isset($report['cpu']['architecture'])) {
            $tel = $report;
        }

        $metrics = (array) ($analysis['metrics'] ?? []);
        $health = (int) ($analysis['health_score'] ?? 0);
        $risks = (array) ($analysis['risks'] ?? []);

        $cpu = (array) ($tel['cpu'] ?? []);
        $gpu = (array) ($tel['gpu'] ?? []);
        $nvidia = (array) ($gpu['nvidia'] ?? $report['nvidia_smi'] ?? []);
        $ram = (array) ($tel['ram'] ?? $report['ram'] ?? []);
        $geek = (array) ($tel['geek'] ?? []);
        $os = (array) ($tel['os_kernel'] ?? []);
        $device = (array) ($report['device'] ?? []);
        $gaming = (array) ($tel['gaming'] ?? $report['gaming'] ?? []);

        $cpuTemp = (float) ($cpu['thermal']['package_c'] ?? $metrics['cpu_temp_max'] ?? 0);
        $gpuTemp = (float) ($gpu['thermal']['core_c'] ?? $nvidia['temp_core_c'] ?? $metrics['gpu_temp_max'] ?? 0);
        $gpuHot = (float) ($nvidia['temp_core_c'] ?? $gpuTemp);
        $throttle = (int) ($report['sensors']['throttle_count'] ?? $metrics['throttle_events'] ?? 0);
        $spikeCount = (int) ($gaming['spike_count'] ?? ($gaming['spike_map']['stats']['spike_count'] ?? 0));
        $isLaptop = ($device['form_factor'] ?? '') === 'laptop'
            || str_contains(strtolower((string) ($device['model'] ?? '')), 'laptop');

        $blockers = $this->collectBlockers(
            $health,
            $cpuTemp,
            $gpuTemp,
            $gpuHot,
            $throttle,
            $spikeCount,
            $isLaptop,
            $os,
            $risks
        );

        $headroom = [
            'cpu_temp_c' => round($cpuTemp, 1),
            'gpu_temp_c' => round($gpuTemp, 1),
            'thermal_margin_cpu' => round(max(0, self::CPU_TEMP_LIMIT - $cpuTemp), 1),
            'thermal_margin_gpu' => round(max(0, self::GPU_TEMP_LIMIT - $gpuTemp), 1),
        ];

        $targets = [];
        $warnings = [];

        if ($blockers === []) {
            $targets = array_merge(
                $targets,
                $this->planGpuTargets($nvidia, $gpuTemp, $headroom['thermal_margin_gpu']),
                $this->planCpuTargets($cpu, $cpuTemp, $headroom['thermal_margin_cpu'], $isLaptop),
                $this->planRamTargets($ram, $isLaptop),
                $this->planPowerPlanTargets($isLaptop)
            );
        }

        if ($isLaptop && $blockers === []) {
            $warnings[] = 'Laptop: software and power plan only — no automatic voltage or XMP.';
            $targets = array_values(array_filter($targets, fn ($t) => in_array($t['domain'] ?? '', ['power_plan', 'cpu_power'], true)));
        }

        $autoTargets = array_values(array_filter($targets, fn ($t) => !empty($t['apply_auto'])));
        $safetyScore = $this->safetyScore($health, $headroom, $throttle, $spikeCount, count($blockers), count($autoTargets));

        $eligible = $blockers === []
            && $safetyScore >= self::MIN_SAFETY_SCORE
            && $autoTargets !== [];

        if ($eligible && $safetyScore < 80) {
            $warnings[] = 'Moderate thermal headroom — conservative profile will be used.';
        }

        return [
            'version' => 1,
            'engine' => 'vakhsh',
            'profile' => $this->chooseProfile($safetyScore, $headroom),
            'eligible' => $eligible,
            'safety_score' => $safetyScore,
            'blockers' => $blockers,
            'warnings' => $warnings,
            'headroom' => $headroom,
            'targets' => $targets,
            'auto_targets' => $autoTargets,
            'summary' => $this->summaryText($eligible, $blockers, $autoTargets, $safetyScore),
            'disclaimer' => 'PCVerse only applies reversible OS/GPU settings. XMP/BIOS and manual voltage need separate confirmation.',
        ];
    }

    /** @param list<array<string, mixed>> $risks @return list<string> */
    private function collectBlockers(
        int $health,
        float $cpuTemp,
        float $gpuTemp,
        float $gpuHot,
        int $throttle,
        int $spikeCount,
        bool $isLaptop,
        array $os,
        array $risks
    ): array {
        $blockers = [];

        if ($health > 0 && $health < self::MIN_HEALTH_SCORE) {
            $blockers[] = 'Low health score — fix thermal or stability issues first.';
        }
        if ($cpuTemp > self::CPU_TEMP_LIMIT) {
            $blockers[] = sprintf('CPU %.0f°C exceeds OC limit (%.0f°C).', $cpuTemp, self::CPU_TEMP_LIMIT);
        }
        if ($gpuTemp > self::GPU_TEMP_LIMIT || $gpuHot > self::GPU_HOTSPOT_LIMIT) {
            $blockers[] = sprintf('GPU %.0f°C — not enough thermal headroom.', max($gpuTemp, $gpuHot));
        }
        if ($throttle > 0) {
            $blockers[] = 'Throttling detected — system is limiting power or heat.';
        }
        if ($spikeCount > 25) {
            $blockers[] = 'High frametime spikes — stability not confirmed for OC.';
        }
        if (!empty($os['whea_errors'])) {
            $blockers[] = 'WHEA hardware errors — auto OC disabled.';
        }
        foreach ($risks as $r) {
            if (($r['severity'] ?? '') === 'critical') {
                $blockers[] = 'Critical risk: ' . ($r['message'] ?? $r['message_fa'] ?? $r['code'] ?? 'unknown');
            }
        }

        return array_values(array_unique($blockers));
    }

    /** @return list<array<string, mixed>> */
    private function planGpuTargets(array $nvidia, float $gpuTemp, float $margin): array
    {
        if ($nvidia === [] || empty($nvidia['name'])) {
            return [];
        }

        $targets = [];
        $powerLimit = (float) ($nvidia['power_limit_w'] ?? 0);
        $powerDefault = (float) ($nvidia['power_default_w'] ?? $powerLimit);
        $powerDraw = (float) ($nvidia['power_draw_w'] ?? 0);
        $coreMhz = (float) ($nvidia['core_clock_mhz'] ?? $nvidia['sm_clock_mhz'] ?? 0);
        $coreMax = (float) ($nvidia['core_clock_max'] ?? 0);
        $memMhz = (float) ($nvidia['mem_clock_mhz'] ?? 0);
        $memMax = (float) ($nvidia['mem_clock_max'] ?? 0);

        if ($powerLimit > 0 && $margin >= 12) {
            $deltaPct = $margin >= 25 ? 8.0 : ($margin >= 18 ? 5.0 : 3.0);
            $newPl = (int) round(min($powerLimit * (1 + $deltaPct / 100), $powerDefault * 1.1, $powerLimit + 25));
            if ($newPl > $powerLimit) {
                $targets[] = [
                    'domain' => 'gpu_power',
                    'action' => 'nvidia_smi_power_limit',
                    'apply_auto' => true,
                    'current' => $powerLimit,
                    'target' => $newPl,
                    'delta_pct' => round(($newPl - $powerLimit) / $powerLimit * 100, 1),
                    'reason' => sprintf('GPU thermal margin ~%.0f°C — raise power limit %.0f→%.0fW.', $margin, $powerLimit, $newPl),
                    'reversible' => true,
                ];
            }
        }

        if ($coreMhz > 0 && $coreMax > $coreMhz && $margin >= 15 && $gpuTemp < 72) {
            $headroomMhz = min(120, (int) floor(($coreMax - $coreMhz) * 0.35));
            $offset = $margin >= 25 ? min(100, $headroomMhz) : min(60, $headroomMhz);
            if ($offset >= 30) {
                $targets[] = [
                    'domain' => 'gpu_clock',
                    'action' => 'nvidia_smi_clock_offset',
                    'apply_auto' => true,
                    'graphics_offset_mhz' => $offset,
                    'mem_offset_mhz' => ($memMhz > 0 && $memMax > $memMhz && $margin >= 22) ? min(200, (int) floor(($memMax - $memMhz) * 0.15)) : 0,
                    'current_core_mhz' => $coreMhz,
                    'current_mem_mhz' => $memMhz,
                    'reason' => sprintf('GPU clock +%d MHz (no voltage change).', $offset),
                    'reversible' => true,
                ];
            }
        }

        if ($powerDraw > 0 && $powerLimit > 0 && ($powerDraw / $powerLimit) > 0.92 && $margin < 18) {
            // skip aggressive steps — already near limit
        }

        return $targets;
    }

    /** @return list<array<string, mixed>> */
    private function planCpuTargets(array $cpu, float $cpuTemp, float $margin, bool $isLaptop): array
    {
        if ($margin < 10) {
            return [];
        }

        $boostMode = $margin >= 22 && !$isLaptop ? 2 : 1;
        $maxPerf = $margin >= 18 ? 100 : 95;

        return [[
            'domain' => 'cpu_power',
            'action' => 'powercfg_processor',
            'apply_auto' => true,
            'perf_boost_mode' => $boostMode,
            'proc_throttle_max' => $maxPerf,
            'proc_throttle_min' => $isLaptop ? 5 : 100,
            'reason' => $boostMode === 2
                ? 'Enable aggressive Performance Boost mode (no BIOS voltage change).'
                : 'Raise CPU frequency cap in Windows Power Plan.',
            'reversible' => true,
        ]];
    }

    /** @return list<array<string, mixed>> */
    private function planRamTargets(array $ram, bool $isLaptop): array
    {
        $timings = (array) ($ram['primary_timings'] ?? ($ram['modules'][0]['timings'] ?? []));
        $mhz = (int) ($timings['frequency_mhz'] ?? $ram['modules'][0]['configured_mhz'] ?? $ram['modules'][0]['speed_mhz'] ?? 0);
        $cl = (int) ($timings['cl'] ?? 0);

        if ($mhz <= 0) {
            return [];
        }

        $xmpHint = null;
        if ($mhz <= 2667 && $cl >= 18) {
            $xmpHint = 'Enable official XMP/EXPO in BIOS — likely 3200+ MHz';
        } elseif ($mhz >= 3200 && $cl <= 16) {
            $xmpHint = 'RAM already tuned — RAM OC not recommended.';
        }

        return [[
            'domain' => 'ram',
            'action' => 'manual_bios',
            'apply_auto' => false,
            'configured_mhz' => $mhz,
            'timings' => $timings,
            'die_type' => $ram['primary_die'] ?? ($ram['modules'][0]['die_type'] ?? null),
            'recommendation' => $xmpHint ?? 'Enable official XMP/EXPO in BIOS only — PCVerse does not change RAM from the OS.',
            'reason' => sprintf('RAM %d MHz CL%s — BIOS guide only.', $mhz, $cl > 0 ? (string) $cl : '?'),
            'reversible' => true,
        ]];
    }

    /** @return list<array<string, mixed>> */
    private function planPowerPlanTargets(bool $isLaptop): array
    {
        return [[
            'domain' => 'power_plan',
            'action' => 'powercfg_high_performance',
            'apply_auto' => true,
            'scheme' => 'high_performance',
            'reason' => $isLaptop
                ? 'Power Plan: High Performance (plug in recommended).'
                : 'Power Plan: High Performance for stable max clocks.',
            'reversible' => true,
        ]];
    }

    /** @param array<string, float> $headroom */
    private function safetyScore(int $health, array $headroom, int $throttle, int $spikes, int $blockerCount, int $autoCount): int
    {
        if ($blockerCount > 0) {
            return max(0, 40 - $blockerCount * 15);
        }

        $score = $health > 0 ? $health : 78;
        $score += (int) min(12, ($headroom['thermal_margin_cpu'] ?? 0) / 2);
        $score += (int) min(12, ($headroom['thermal_margin_gpu'] ?? 0) / 2);
        $score -= $throttle * 10;
        $score -= min(15, (int) floor($spikes / 3));
        $score += min(8, $autoCount * 2);

        return max(0, min(99, (int) round($score)));
    }

    /** @param array<string, float> $headroom */
    private function chooseProfile(int $safetyScore, array $headroom): string
    {
        if ($safetyScore >= 88 && ($headroom['thermal_margin_gpu'] ?? 0) >= 22) {
            return 'balanced_plus';
        }
        if ($safetyScore >= 78) {
            return 'balanced';
        }

        return 'conservative';
    }

    /** @param list<string> $blockers @param list<array<string, mixed>> $autoTargets */
    private function summaryText(bool $eligible, array $blockers, array $autoTargets, int $safetyScore): string
    {
        if (!$eligible) {
            if ($blockers !== []) {
                return 'Auto OC is not allowed in this state — ' . $blockers[0];
            }

            return 'Not enough data or safety margin for automatic OC.';
        }

        $domains = array_unique(array_map(fn ($t) => $t['domain'] ?? '?', $autoTargets));

        return sprintf(
            'System ready (safety score %d). %d reversible setting(s) on %s.',
            $safetyScore,
            count($autoTargets),
            implode(', ', $domains)
        );
    }
}
