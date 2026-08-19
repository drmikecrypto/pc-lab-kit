<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Pass/fail certificate from a stress run + optional thermal overlay samples.
 */
class StressCertificateService
{
    /**
     * @param array<string, mixed> $run Result from Probe /stress/run
     * @param list<array<string, mixed>> $samples Telemetry samples during/after run
     * @param array<string, mixed> $limits Optional override limits
     * @return array<string, mixed>
     */
    public function issue(array $run, array $samples = [], array $limits = []): array
    {
        $cpuLimit = (float) ($limits['cpu_temp_max'] ?? 95);
        $gpuLimit = (float) ($limits['gpu_temp_max'] ?? 90);
        $hotspotLimit = (float) ($limits['gpu_hotspot_max'] ?? 105);

        $cpuPeak = null;
        $gpuPeak = null;
        $hotspotPeak = null;
        $whea = 0;
        foreach ($samples as $s) {
            if (!is_array($s)) {
                continue;
            }
            $cpu = $this->num($s['cpu_temp'] ?? $s['cpu_temp_max'] ?? $s['cpu'] ?? null);
            $gpu = $this->num($s['gpu_temp'] ?? $s['gpu_temp_max'] ?? $s['gpu'] ?? null);
            $hs = $this->num($s['gpu_hotspot'] ?? $s['gpu_hotspot_max'] ?? null);
            if ($cpu !== null) {
                $cpuPeak = $cpuPeak === null ? $cpu : max($cpuPeak, $cpu);
            }
            if ($gpu !== null) {
                $gpuPeak = $gpuPeak === null ? $gpu : max($gpuPeak, $gpu);
            }
            if ($hs !== null) {
                $hotspotPeak = $hotspotPeak === null ? $hs : max($hotspotPeak, $hs);
            }
            $whea += (int) ($s['whea_errors'] ?? $s['whea'] ?? 0);
        }

        // Prefer peaks embedded in the run payload when present
        $cpuPeak = $this->num($run['cpu_temp_max'] ?? null) ?? $cpuPeak;
        $gpuPeak = $this->num($run['gpu_temp_max'] ?? null) ?? $gpuPeak;
        $hotspotPeak = $this->num($run['gpu_hotspot_max'] ?? null) ?? $hotspotPeak;
        $whea += (int) ($run['whea_errors'] ?? 0);
        $wheaTimeline = is_array($run['whea_timeline'] ?? null) ? $run['whea_timeline'] : null;
        if ($wheaTimeline !== null && isset($wheaTimeline['count'])) {
            $whea = max($whea, (int) $wheaTimeline['count']);
        }

        $pcieWarnings = is_array($run['pcie_warnings'] ?? null) ? $run['pcie_warnings'] : [];
        $oracleSteps = is_array($run['oracle_steps'] ?? null) ? $run['oracle_steps'] : [];
        $stabilityMargin = isset($run['stability_margin_pct']) ? (float) $run['stability_margin_pct'] : null;

        $failures = [];
        if ($cpuPeak !== null && $cpuPeak >= $cpuLimit) {
            $failures[] = "CPU peaked at {$cpuPeak}°C (limit {$cpuLimit}°C)";
        }
        if ($gpuPeak !== null && $gpuPeak >= $gpuLimit) {
            $failures[] = "GPU peaked at {$gpuPeak}°C (limit {$gpuLimit}°C)";
        }
        if ($hotspotPeak !== null && $hotspotPeak >= $hotspotLimit) {
            $failures[] = "GPU hotspot peaked at {$hotspotPeak}°C (limit {$hotspotLimit}°C)";
        }
        if ($whea > 0) {
            $failures[] = "WHEA / hardware errors reported: {$whea}";
        }
        if (($run['status'] ?? '') === 'failed' || !empty($run['error'])) {
            $failures[] = (string) ($run['error'] ?? 'Stress run reported failure');
        }
        if (($run['errors_found'] ?? 0) > 0) {
            $failures[] = 'Memory errors detected: ' . (int) $run['errors_found'];
        }

        $pass = $failures === [];
        $profile = (string) ($run['id'] ?? $run['profile'] ?? 'stress');
        $duration = $run['duration_s'] ?? $run['seconds'] ?? null;

        return [
            'verdict' => $pass ? 'PASS' : 'FAIL',
            'passed' => $pass,
            'profile' => $profile,
            'label' => $run['label'] ?? ('PC Lab Kit ' . $profile . ' stress'),
            'duration_s' => $duration,
            'issued_at' => gmdate('c'),
            'peaks' => array_filter([
                'cpu_temp_max' => $cpuPeak,
                'gpu_temp_max' => $gpuPeak,
                'gpu_hotspot_max' => $hotspotPeak,
                'whea_errors' => $whea > 0 ? $whea : null,
            ], static fn ($v) => $v !== null),
            'whea_timeline' => $wheaTimeline,
            'pcie_warnings' => $pcieWarnings !== [] ? array_values($pcieWarnings) : null,
            'stability_margin_pct' => $stabilityMargin,
            'oracle_steps' => $oracleSteps !== [] ? $oracleSteps : null,
            'limits' => [
                'cpu_temp_max' => $cpuLimit,
                'gpu_temp_max' => $gpuLimit,
                'gpu_hotspot_max' => $hotspotLimit,
            ],
            'failures' => $failures,
            'summary' => $pass
                ? sprintf('PASS — %s completed cleanly%s.', $profile, $duration ? " ({$duration}s)" : '')
                : ('FAIL — ' . implode('; ', $failures)),
            'sample_count' => count($samples),
            'engine' => 'pclab-probe',
        ];
    }

    private function num(mixed $v): ?float
    {
        if ($v === null || $v === '') {
            return null;
        }
        if (!is_numeric($v)) {
            return null;
        }

        return (float) $v;
    }
}
