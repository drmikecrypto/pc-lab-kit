<?php

declare(strict_types=1);

namespace App\Services;

/**
 * PHP-side stability oracle helpers — interprets probe oracle stress payloads.
 */
class StabilityOracleService
{
    /** @return array<string, mixed> */
    public function profiles(): array
    {
        return [
            'oracle' => [
                'id' => 'oracle',
                'label' => 'Stability Oracle',
                'duration_hint_min' => 8,
                'stress_id' => 'oracle',
                'step_seconds' => 20,
                'limits' => [
                    'cpu_temp_max' => 82,
                    'gpu_temp_max' => 83,
                    'gpu_hotspot_max' => 92,
                ],
            ],
        ];
    }

    /**
     * @param array<string, mixed> $run Probe oracle result
     * @return array<string, mixed>
     */
    public function interpret(array $run): array
    {
        $margin = isset($run['stability_margin_pct']) ? (float) $run['stability_margin_pct'] : null;
        $steps = is_array($run['oracle_steps'] ?? null) ? $run['oracle_steps'] : [];
        $breached = !empty($run['breached']);
        $grade = 'A';
        if ($margin !== null) {
            if ($margin < 15 || $breached) {
                $grade = 'C';
            } elseif ($margin < 35) {
                $grade = 'B';
            }
        }

        return [
            'grade' => $grade,
            'stability_margin_pct' => $margin,
            'breached' => $breached,
            'breach_reason' => $run['breach_reason'] ?? null,
            'step_count' => count($steps),
            'steps' => $steps,
            'summary' => $this->summary($margin, $breached, $run['breach_reason'] ?? null),
        ];
    }

    /**
     * Merge oracle interpretation into stress certificate fields.
     *
     * @param array<string, mixed> $cert
     * @param array<string, mixed> $run
     * @return array<string, mixed>
     */
    public function enrichCertificate(array $cert, array $run): array
    {
        $interp = $this->interpret($run);
        $cert['stability_margin_pct'] = $interp['stability_margin_pct'];
        $cert['oracle_grade'] = $interp['grade'];
        $cert['oracle_steps'] = $interp['steps'];
        if ($interp['breach_reason']) {
            $cert['oracle_breach'] = $interp['breach_reason'];
        }

        return $cert;
    }

    private function summary(?float $margin, bool $breached, ?string $reason): string
    {
        if ($breached) {
            return 'Stability limit reached: ' . ($reason ?: 'thermal or WHEA breach');
        }
        if ($margin === null) {
            return 'Oracle completed — margin unknown';
        }

        return sprintf('Stability margin %.1f%% — headroom before thermal limits', $margin);
    }
}
