<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Benchmark Arena — percentile rings vs reference datasets + user run comparison.
 */
class BenchmarkArenaService
{
    public function __construct(
        private ?BenchmarkDatasetService $datasets = null,
        private ?DiagnosticHistoryService $history = null,
    ) {
        $this->datasets = $datasets ?? new BenchmarkDatasetService();
        $this->history = $history ?? new DiagnosticHistoryService();
    }

    /** @return array<string, mixed> */
    public function buildPayload(?string $fingerprint = null): array
    {
        $fp = $fingerprint ?? $this->resolveFingerprint();
        $userScores = $this->userLatestScores($fp);
        $honesty = $this->scorecardHonesty();
        $components = $this->buildComponentCards($userScores, $honesty);
        $global = $this->datasets->getGlobalStats();
        $catalog = $this->datasets->getCatalog();

        return [
            'global' => $global,
            'user' => [
                'fingerprint' => $fp,
                'scores' => $userScores,
                'has_run' => $userScores !== [],
            ],
            'components' => $components,
            'radar' => $this->buildRadar($components),
            'percentile_method' => $honesty['percentile_method'],
            'dataset_version' => $honesty['dataset_version'],
            'datasets' => array_values(array_map(static fn (array $d) => [
                'key' => $d['key'] ?? '',
                'label' => $d['label'] ?? '',
                'component' => $d['component'] ?? '',
                'count' => $d['count'] ?? 0,
                'source_tier' => $d['source_tier'] ?? 'lab',
            ], $catalog)),
        ];
    }

    /** @return array{percentile_method: string, dataset_version: string} */
    private function scorecardHonesty(): array
    {
        return [
            'percentile_method' => $this->datasets->percentileMethodBlurb(),
            'dataset_version' => $this->datasets->datasetVersion(),
        ];
    }

    /** @param array<string, int|float> $userScores @param array{percentile_method: string, dataset_version: string} $honesty @return list<array<string, mixed>> */
    private function buildComponentCards(array $userScores, array $honesty): array
    {
        $defs = [
            'cpu' => ['label' => 'CPU', 'score_key' => 'cpu_score', 'metric' => 'mark'],
            'gpu' => ['label' => 'GPU', 'score_key' => 'gpu_score', 'metric' => 'mark'],
            'ram' => ['label' => 'Memory', 'score_key' => 'mem_bandwidth_mb_s', 'metric' => 'mark'],
            'storage' => ['label' => 'Storage', 'score_key' => 'storage_read_mb_s', 'metric' => 'mark'],
            'cpu_cache' => ['label' => 'CPU Cache', 'score_key' => 'cpu_cache_score', 'metric' => 'mark'],
        ];

        $out = [];
        foreach ($defs as $component => $def) {
            $score = (int) round((float) ($userScores[$def['score_key']] ?? 0));
            $pct = $score > 0 ? $this->datasets->scorePercentile($component, $score) : null;
            $match = null;
            if ($score > 0) {
                $match = $this->datasets->matchPart([
                    'category_slug' => $component,
                    'name' => (string) ($userScores[$component . '_name'] ?? $component),
                ]);
            }
            $out[] = [
                'id' => $component,
                'label' => $def['label'],
                'score' => $score > 0 ? $score : null,
                'percentile' => $pct,
                'reference_name' => $match['name'] ?? null,
                'source_tier' => $match['source_tier'] ?? null,
                'reproducibility' => $this->reproducibilityBadge($userScores, $def['score_key']),
                'percentile_method' => $honesty['percentile_method'],
                'dataset_version' => $honesty['dataset_version'],
            ];
        }

        return $out;
    }

    /** @param list<array<string, mixed>> $components @return array<string, mixed> */
    private function buildRadar(array $components): array
    {
        $labels = [];
        $values = [];
        foreach ($components as $c) {
            $labels[] = (string) ($c['label'] ?? '');
            $values[] = (int) ($c['percentile'] ?? 0);
        }

        return ['labels' => $labels, 'values' => $values];
    }

    /** @return array<string, int|float|string> */
    private function userLatestScores(string $fp): array
    {
        $rows = $this->history->userHistory($fp, null, 5);
        foreach ($rows as $row) {
            $metrics = is_array($row['metrics'] ?? null) ? $row['metrics'] : [];
            if ($metrics === []) {
                continue;
            }
            $hasBench = isset($metrics['gpu_score']) || isset($metrics['cpu_cache_score'])
                || isset($metrics['storage_read_mb_s']) || isset($metrics['mem_bandwidth_mb_s']);
            if (!$hasBench && ($row['mode'] ?? '') !== 'suite') {
                continue;
            }

            return array_merge($metrics, [
                'run_at' => $row['created_at'] ?? null,
                'health_score' => $row['health_score'] ?? null,
            ]);
        }

        return [];
    }

    /** @param array<string, mixed> $scores */
    private function reproducibilityBadge(array $scores, string $key): string
    {
        $current = (float) ($scores[$key] ?? 0);
        $prev = (float) ($scores['prev_' . $key] ?? 0);
        if ($current <= 0) {
            return 'pending';
        }
        if ($prev <= 0) {
            return 'first_run';
        }
        $delta = abs($current - $prev) / max($prev, 1);

        return $delta <= 0.01 ? 'verified' : 'pending';
    }

    private function resolveFingerprint(): string
    {
        if (!empty($_COOKIE['pclab_fp'])) {
            return substr((string) $_COOKIE['pclab_fp'], 0, 64);
        }
        if (!empty($_SESSION['pclab_fp'])) {
            return substr((string) $_SESSION['pclab_fp'], 0, 64);
        }

        return '';
    }
}
