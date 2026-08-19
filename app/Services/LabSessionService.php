<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Signed .pclab session export/import — reproducible hardware lab experiments.
 */
class LabSessionService
{
    public const FORMAT = 'pclab-session-v1';

    private string $dir;

    public function __construct(?string $projectRoot = null)
    {
        $root = $projectRoot ?? dirname(__DIR__, 2);
        $this->dir = $root . '/storage/sessions';
        if (!is_dir($this->dir)) {
            mkdir($this->dir, 0755, true);
        }
    }

    /**
     * @param array<string, mixed> $analysis Full suite/analysis payload
     * @param array<string, mixed> $meta fingerprint, profile, probe_version
     * @return array<string, mixed>
     */
    public function export(array $analysis, array $meta = []): array
    {
        $fp = substr(trim((string) ($meta['fingerprint'] ?? $analysis['fingerprint'] ?? '')), 0, 64);
        $dossier = is_array($analysis['silicon_dossier'] ?? null) ? $analysis['silicon_dossier'] : [];
        $openBook = (array) ($dossier['open_book'] ?? []);
        $cert = is_array($analysis['stress_certificate'] ?? null) ? $analysis['stress_certificate'] : [];
        $suite = is_array($analysis['suite'] ?? null) ? $analysis['suite'] : [];

        $body = [
            'format' => self::FORMAT,
            'fingerprint' => $fp,
            'probe_version' => (string) ($meta['probe_version'] ?? '6'),
            'profile' => (string) ($meta['profile'] ?? $suite['profile'] ?? 'standard'),
            'dossier' => $dossier,
            'dossier_hash' => $this->hashJson($dossier),
            'openbook_snapshot' => (array) ($openBook['sensors'] ?? []),
            'bench_scores' => $this->extractBenchScores($analysis),
            'stress_certificate' => $cert,
            'stress_certificate_id' => $this->hashJson($cert),
            'telemetry_archive' => (array) ($cert['timeline'] ?? []),
            'pcie_warnings' => (array) ($cert['pcie_warnings'] ?? []),
            'stability_margin_pct' => $cert['stability_margin_pct'] ?? null,
            'hardware_graph_summary' => (array) (($analysis['hardware_graph'] ?? [])['summary'] ?? []),
            'signed_at' => gmdate('c'),
        ];

        $body['session_hash'] = $this->sign($body);
        $body['verification_qr'] = $this->verificationQrPayload($body['session_hash']);

        $id = bin2hex(random_bytes(8));
        $path = $this->dir . '/' . $id . '.pclab.json';
        file_put_contents($path, json_encode($body, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT), LOCK_EX);

        return [
            'id' => $id,
            'path' => $path,
            'filename' => 'session-' . ($fp !== '' ? substr($fp, 0, 12) : $id) . '.pclab.json',
            'session' => $body,
        ];
    }

    /**
     * @return array<string, mixed>
     */
    public function import(string $json): array
    {
        $data = json_decode($json, true);
        if (!is_array($data)) {
            throw new \InvalidArgumentException('Invalid .pclab JSON');
        }
        if (($data['format'] ?? '') !== self::FORMAT) {
            throw new \InvalidArgumentException('Unsupported session format: ' . (string) ($data['format'] ?? ''));
        }
        $expected = $this->sign($data);
        $valid = hash_equals($expected, (string) ($data['session_hash'] ?? ''));
        $data['verified'] = $valid;
        $data['drift'] = null;

        return $data;
    }

    /**
     * Compare imported session with current analysis for drift scoring.
     *
     * @param array<string, mixed> $session
     * @param array<string, mixed> $current
     * @return array<string, mixed>
     */
    public function driftScore(array $session, array $current): array
    {
        $prev = is_array($session['dossier'] ?? null) ? $session['dossier'] : [];
        $curr = is_array($current['silicon_dossier'] ?? null) ? $current['silicon_dossier'] : [];
        $prevOb = (array) ($prev['open_book'] ?? []);
        $currOb = (array) ($curr['open_book'] ?? []);
        $prevSpread = $this->metric($prev, 'gpu_therm_spread');
        $currSpread = $this->metric($curr, 'gpu_therm_spread');
        $spreadDelta = ($prevSpread !== null && $currSpread !== null) ? round($currSpread - $prevSpread, 2) : null;

        $prevSmart = $this->smartWear($prev);
        $currSmart = $this->smartWear($curr);
        $smartDelta = ($prevSmart !== null && $currSmart !== null) ? $currSmart - $prevSmart : null;

        $score = 100;
        $notes = [];
        if ($spreadDelta !== null && $spreadDelta > 3.0) {
            $score -= min(25, (int) round($spreadDelta * 3));
            $notes[] = "Thermal spread widened by {$spreadDelta}°C";
        }
        if ($smartDelta !== null && $smartDelta > 2) {
            $score -= min(20, $smartDelta * 2);
            $notes[] = "Storage wear index increased by {$smartDelta}";
        }
        if ((int) ($prevOb['count'] ?? 0) !== (int) ($currOb['count'] ?? 0)) {
            $score -= 5;
            $notes[] = 'Open-book channel count changed';
        }
        $score = max(0, min(100, $score));

        return [
            'silicon_aging_index' => $score,
            'thermal_spread_delta' => $spreadDelta,
            'smart_wear_delta' => $smartDelta,
            'notes' => $notes,
            'label' => $score >= 85 ? 'healthy' : ($score >= 65 ? 'watch' : 'degraded'),
        ];
    }

    /** @param array<string, mixed> $session */
    public function verifyHash(string $sessionHash): bool
    {
        $sessionHash = strtolower(trim($sessionHash));
        if ($sessionHash === '' || !preg_match('/^[a-f0-9]{64}$/', $sessionHash)) {
            return false;
        }
        foreach (glob($this->dir . '/*.pclab.json') ?: [] as $path) {
            $data = json_decode((string) file_get_contents($path), true);
            if (is_array($data) && hash_equals($sessionHash, (string) ($data['session_hash'] ?? ''))) {
                return hash_equals($this->sign($data), $sessionHash);
            }
        }

        return false;
    }

    /** @param array<string, mixed> $body */
    private function sign(array $body): string
    {
        $copy = $body;
        unset($copy['session_hash'], $copy['verification_qr']);
        $canonical = json_encode($copy, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);

        return hash('sha256', 'pclab-session-v1|' . ($canonical ?: ''));
    }

    private function verificationQrPayload(string $hash): string
    {
        return 'pclab://verify/' . $hash;
    }

    /** @param array<string, mixed> $data */
    private function hashJson(array $data): string
    {
        return 'sha256:' . hash('sha256', json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) ?: '');
    }

    /** @param array<string, mixed> $analysis @return array<string, mixed> */
    private function extractBenchScores(array $analysis): array
    {
        $out = [];
        $metrics = (array) ($analysis['metrics'] ?? []);
        foreach (['cpu_score', 'cpu_cache_score', 'gpu_score', 'gpu_gflops', 'mem_bandwidth_mb_s', 'storage_read_mb_s', 'storage_write_mb_s'] as $k) {
            if (isset($metrics[$k])) {
                $out[$k] = $metrics[$k];
            }
        }
        $benches = (array) (($analysis['suite'] ?? [])['benches'] ?? []);
        if ($benches !== []) {
            $out['suite_benches'] = $benches;
        }

        return $out;
    }

    /** @param array<string, mixed> $dossier */
    private function metric(array $dossier, string $key): ?float
    {
        $gpu = (array) ($dossier['gpu'] ?? []);
        if (isset($gpu[$key]) && is_numeric($gpu[$key])) {
            return (float) $gpu[$key];
        }
        $metrics = (array) ($dossier['metrics'] ?? []);

        return isset($metrics[$key]) && is_numeric($metrics[$key]) ? (float) $metrics[$key] : null;
    }

    /** @param array<string, mixed> $dossier */
    private function smartWear(array $dossier): ?int
    {
        $storage = (array) ($dossier['storage'] ?? []);
        $max = null;
        foreach ($storage as $disk) {
            if (!is_array($disk)) {
                continue;
            }
            $pct = $disk['smart_wear_pct'] ?? $disk['percent_used'] ?? null;
            if (is_numeric($pct)) {
                $max = $max === null ? (int) $pct : max($max, (int) $pct);
            }
        }

        return $max;
    }
}
