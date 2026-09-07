<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Silicon Aging Index — track drift across .pclab sessions for a fingerprint.
 */
class SiliconAgingService
{
    public function __construct(
        private ?LabSessionService $sessions = null,
        private ?DiagnosticHistoryService $history = null,
    ) {
        $root = dirname(__DIR__, 2);
        $this->sessions = $sessions ?? new LabSessionService($root);
        $this->history = $history ?? new DiagnosticHistoryService();
    }

    /** @return array<string, mixed> */
    public function dashboard(?string $fingerprint): array
    {
        $fp = $fingerprint ?? '';
        $sessions = $this->loadSessions($fp);
        $timeline = [];
        $indices = [];

        foreach ($sessions as $s) {
            $signedAt = (string) ($s['signed_at'] ?? '');
            $drift = is_array($s['import_drift'] ?? null) ? $s['import_drift'] : null;
            if ($drift === null && isset($s['bench_scores'])) {
                $drift = ['silicon_aging_index' => 100, 'label' => 'baseline'];
            }
            $idx = (int) ($drift['silicon_aging_index'] ?? 100);
            $indices[] = $idx;
            $timeline[] = [
                'signed_at' => $signedAt,
                'silicon_aging_index' => $idx,
                'label' => $drift['label'] ?? 'unknown',
                'thermal_spread_delta' => $drift['thermal_spread_delta'] ?? null,
                'notes' => $drift['notes'] ?? [],
            ];
        }

        $current = $this->history->latestSnapshot($fp);
        $currentDrift = null;
        if ($current && $sessions !== []) {
            $last = $sessions[0];
            try {
                $currentDrift = $this->sessions->driftScore($last, $current);
            } catch (\Throwable) {
                $currentDrift = null;
            }
        }

        return [
            'fingerprint' => $fp,
            'session_count' => count($sessions),
            'timeline' => $timeline,
            'current_index' => $currentDrift['silicon_aging_index'] ?? ($indices[0] ?? null),
            'current_label' => $currentDrift['label'] ?? ($timeline[0]['label'] ?? 'no_data'),
            'trend' => $this->trend($indices),
        ];
    }

    /** @return list<array<string, mixed>> */
    private function loadSessions(string $fp): array
    {
        $dir = dirname(__DIR__, 2) . '/storage/sessions';
        if (!is_dir($dir)) {
            return [];
        }
        $out = [];
        foreach (glob($dir . '/*.pclab.json') ?: [] as $path) {
            $data = json_decode((string) file_get_contents($path), true);
            if (!is_array($data)) {
                continue;
            }
            if ($fp !== '' && ($data['fingerprint'] ?? '') !== $fp) {
                continue;
            }
            $out[] = $data;
        }
        usort($out, static fn ($a, $b) => strcmp((string) ($b['signed_at'] ?? ''), (string) ($a['signed_at'] ?? '')));

        return array_slice($out, 0, 12);
    }

    /** @param list<int> $indices */
    private function trend(array $indices): string
    {
        if (count($indices) < 2) {
            return 'insufficient_data';
        }
        $delta = $indices[0] - $indices[count($indices) - 1];

        return match (true) {
            $delta >= 5 => 'improving',
            $delta <= -5 => 'degrading',
            default => 'stable',
        };
    }
}
