<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Rule-based consultant layer — English, no catalog, no PII.
 */
final class DiagnosticConsultantService
{
    /**
     * @param array<string, mixed> $analysis
     * @return array<string, mixed>
     */
    public function plan(array $analysis): array
    {
        $score = (int) ($analysis['health_score'] ?? 0);
        $grade = strtoupper((string) ($analysis['health_grade'] ?? 'C'));
        $bn = (array) ($analysis['bottleneck'] ?? []);
        $bnType = (string) ($bn['type'] ?? '');
        $metrics = (array) ($analysis['metrics'] ?? []);
        $gpuT = (float) ($metrics['gpu_temp_max'] ?? 0);
        $cpuT = (float) ($metrics['cpu_temp_max'] ?? 0);
        $ft = (float) ($metrics['frametime_p99_ms'] ?? 0);

        $thermalStress = ($gpuT > 0 && $gpuT >= 86) || ($cpuT > 0 && $cpuT >= 90);
        $frametimeBad = $ft > 0 && $ft >= 22;

        $solid = $score >= 76
            && in_array($grade, ['A', 'B'], true)
            && !$thermalStress
            && !$frametimeBad
            && ($bnType === '' || $bnType === 'unknown' || $bnType === 'balanced');

        $risks = (array) ($analysis['risks'] ?? []);
        $riskHeavy = false;
        foreach ($risks as $r) {
            if (!is_array($r)) {
                continue;
            }
            $sev = (string) ($r['severity'] ?? '');
            if ($sev === 'high' || $sev === 'critical') {
                $riskHeavy = true;
                break;
            }
        }

        if ($solid && !$riskHeavy) {
            return $this->pack(
                'solid',
                'Your system looks healthy from this scan — no mandatory upgrade path unless you target heavy 4K ray tracing or pro streaming.',
                'If you are happy at your current resolution, keep your budget; maintain drivers and cooling periodically.',
                $bnType,
                $score,
                $thermalStress,
                $frametimeBad
            );
        }

        $focus = $this->focusText($bnType, $thermalStress, $frametimeBad, $score);

        return $this->pack(
            $riskHeavy ? 'upgrade' : 'watch',
            'This scan still shows room before you are fully comfortable — priority: ' . $focus . '.',
            'Run a full probe scan for real sensors, then enable the AI advisor if you want part-level upgrade suggestions.',
            $bnType,
            $score,
            $thermalStress,
            $frametimeBad
        );
    }

    /** @return array<string, mixed> */
    private function pack(
        string $stance,
        string $headline,
        string $angle,
        string $bnType,
        int $score,
        bool $thermalStress,
        bool $frametimeBad,
    ): array {
        return [
            'stance' => $stance,
            'headline' => $headline,
            'honest_assessment' => $this->honestText($stance, $score, $thermalStress, $frametimeBad, $bnType),
            'horizons' => [
                ['months' => 8, 'label' => '8 months', 'advice' => $this->horizonText(8, $stance, $bnType, $thermalStress, $frametimeBad, $score)],
                ['months' => 12, 'label' => '1 year', 'advice' => $this->horizonText(12, $stance, $bnType, $thermalStress, $frametimeBad, $score)],
                ['months' => 24, 'label' => '2 years', 'advice' => $this->horizonText(24, $stance, $bnType, $thermalStress, $frametimeBad, $score)],
            ],
            'angle' => $angle,
            'neural_tags' => array_values(array_filter([
                'stance:' . $stance,
                $bnType !== '' ? 'bn:' . $bnType : null,
                $thermalStress ? 'thermal:stress' : null,
                $frametimeBad ? 'frametime:high' : null,
            ])),
        ];
    }

    private function honestText(string $stance, int $score, bool $thermalStress, bool $frametimeBad, string $bnType): string
    {
        $parts = ["Overall score ~{$score}."];
        if ($thermalStress) {
            $parts[] = 'Thermal headroom is tight — fix cooling before buying a heavier GPU.';
        }
        if ($frametimeBad) {
            $parts[] = 'Frametime p99 is high — check RAM, drivers, and in-game settings before replacing hardware.';
        }
        if ($bnType === 'gpu') {
            $parts[] = 'GPU bottleneck dominates in your benchmark profile.';
        } elseif ($bnType === 'cpu') {
            $parts[] = 'CPU bottleneck shows up in CPU-bound workloads.';
        }
        if ($stance === 'solid') {
            $parts = ['You are well balanced today; upgrades are optional.'];
        }

        return implode(' ', $parts);
    }

    private function focusText(string $bnType, bool $thermalStress, bool $frametimeBad, int $score): string
    {
        if ($thermalStress) {
            return 'cooling and thermal stability';
        }
        if ($frametimeBad) {
            return 'frametime stability and memory tuning';
        }
        if ($bnType === 'gpu') {
            return 'GPU power for your target resolution';
        }
        if ($bnType === 'cpu') {
            return 'CPU power for your workload';
        }
        if ($score < 55) {
            return 'foundational upgrades (CPU/GPU/RAM)';
        }

        return 'periodic monitoring and small optimizations';
    }

    private function horizonText(int $months, string $stance, string $bnType, bool $thermalStress, bool $frametimeBad, int $score): string
    {
        if ($stance === 'solid') {
            return $months <= 12
                ? 'At your current resolution, no urgent upgrade is required — keep drivers and thermals in check.'
                : 'Over two years, re-scan annually and keep GPU temps under 85°C; revisit GPU only if you jump resolution.';
        }
        if ($thermalStress) {
            return "Within {$months} months, thermal limits will cap performance until cooling is fixed.";
        }
        if ($bnType === 'gpu') {
            return "With a GPU bottleneck, new titles may drop frames within {$months} months — a GPU upgrade has the highest impact.";
        }
        if ($bnType === 'cpu') {
            return "With a CPU bottleneck, streaming and CPU-heavy games may degrade within {$months} months.";
        }
        if ($score < 55) {
            return "Low overall score — a targeted CPU or GPU upgrade in the next {$months} months beats spreading budget thin.";
        }

        return "Monitor every {$months} months unless you change resolution or ray tracing settings.";
    }
}
