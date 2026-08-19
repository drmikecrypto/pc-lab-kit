<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Opt-in federated benchmark pool (local aggregate export only in v1).
 */
class FederatedBenchmarkService
{
    private string $path;

    public function __construct(?string $projectRoot = null)
    {
        $root = $projectRoot ?? dirname(__DIR__, 2);
        $dir = $root . '/storage/federated';
        if (!is_dir($dir)) {
            mkdir($dir, 0755, true);
        }
        $this->path = $dir . '/contributions.jsonl';
    }

    /** @param array<string, mixed> $metrics */
    public function contribute(array $metrics, string $fingerprint): bool
    {
        $settings = (new SettingsService())->publicSettings();
        if (empty($settings['federated_benchmarks_opt_in'])) {
            return false;
        }
        $anon = hash('sha256', $fingerprint . '|pclab|salt');
        $row = [
            'anon_id' => substr($anon, 0, 16),
            'gpu_score' => $metrics['gpu_score'] ?? null,
            'cpu_cache_score' => $metrics['cpu_cache_score'] ?? null,
            'storage_read_mb_s' => $metrics['storage_read_mb_s'] ?? null,
            'at' => gmdate('c'),
        ];
        file_put_contents($this->path, json_encode($row) . "\n", FILE_APPEND | LOCK_EX);

        return true;
    }

    /** @return array{count: int, aggregates: array<string, float|null>} */
    public function localAggregates(): array
    {
        if (!is_file($this->path)) {
            return ['count' => 0, 'aggregates' => []];
        }
        $keys = ['gpu_score', 'cpu_cache_score', 'storage_read_mb_s'];
        $sums = array_fill_keys($keys, 0.0);
        $counts = array_fill_keys($keys, 0);
        foreach (file($this->path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
            $row = json_decode($line, true);
            if (!is_array($row)) {
                continue;
            }
            foreach ($keys as $k) {
                if (isset($row[$k]) && is_numeric($row[$k])) {
                    $sums[$k] += (float) $row[$k];
                    ++$counts[$k];
                }
            }
        }
        $agg = [];
        foreach ($keys as $k) {
            $agg[$k] = $counts[$k] > 0 ? round($sums[$k] / $counts[$k], 1) : null;
        }

        return ['count' => count(file($this->path) ?: []), 'aggregates' => $agg];
    }
}
