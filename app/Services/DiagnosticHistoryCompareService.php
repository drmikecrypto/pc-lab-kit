<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Compares the current diagnostic run with the user's previous saved test.
 */
class DiagnosticHistoryCompareService
{
    private const METRIC_LABELS = [
        'health_score' => 'Health score',
        'cpu_score' => 'CPU score',
        'gpu_score' => 'GPU score',
        'ram_gb' => 'RAM',
        'gpu_temp_max' => 'GPU temp peak',
        'cpu_temp_max' => 'CPU temp peak',
        'gpu_hotspot_max' => 'GPU hotspot',
        'gpu_util_avg' => 'GPU utilization',
        'frametime_p99_ms' => 'Frametime P99',
        'lan_link_mbps' => 'LAN link',
        'battery_health_pct' => 'Battery health',
    ];

    /** @param array<string, mixed> $currentAnalysis */
    /** @param array<string, mixed> $previousSnapshot From DiagnosticHistoryService::latestSnapshot() */
    public function compare(array $currentAnalysis, array $previousSnapshot): array
    {
        $prevScore = (int) ($previousSnapshot['health_score'] ?? 0);
        $curScore = (int) ($currentAnalysis['health_score'] ?? 0);
        $scoreDelta = $curScore - $prevScore;

        $prevGrade = (string) ($previousSnapshot['health_grade'] ?? '');
        $curGrade = (string) ($currentAnalysis['health_grade'] ?? '');

        $prevBn = (array) ($previousSnapshot['bottleneck'] ?? []);
        $curBn = (array) ($currentAnalysis['bottleneck'] ?? []);
        $prevBnType = (string) ($prevBn['type'] ?? $previousSnapshot['bottleneck_type'] ?? '');
        $curBnType = (string) ($curBn['type'] ?? '');

        $prevMetrics = (array) ($previousSnapshot['metrics'] ?? []);
        $curMetrics = (array) ($currentAnalysis['metrics'] ?? []);

        $metricRows = [];
        foreach (self::METRIC_LABELS as $key => $label) {
            if ($key === 'health_score') {
                continue;
            }
            if (!array_key_exists($key, $curMetrics) && !array_key_exists($key, $prevMetrics)) {
                continue;
            }
            $prevVal = $this->numericOrNull($prevMetrics[$key] ?? null);
            $curVal = $this->numericOrNull($curMetrics[$key] ?? null);
            if ($prevVal === null && $curVal === null) {
                continue;
            }
            $delta = ($curVal !== null && $prevVal !== null) ? round($curVal - $prevVal, 2) : null;
            $metricRows[] = [
                'key' => $key,
                'label' => $label,
                'previous' => $prevVal,
                'current' => $curVal,
                'delta' => $delta,
                'improved' => $this->metricImproved($key, $delta),
                'unit' => $this->metricUnit($key),
            ];
        }

        $improvedCount = count(array_filter($metricRows, static fn (array $r): bool => ($r['improved'] ?? null) === true));
        $worseCount = count(array_filter($metricRows, static fn (array $r): bool => ($r['improved'] ?? null) === false));
        $openBookDelta = $this->openBookDelta($currentAnalysis, $previousSnapshot);

        return [
            'has_previous' => true,
            'previous' => [
                'token' => $previousSnapshot['token'] ?? '',
                'mode' => $previousSnapshot['mode'] ?? '',
                'score' => $prevScore,
                'grade' => $prevGrade,
                'created_at' => $previousSnapshot['created_at'] ?? '',
                'ago' => $previousSnapshot['ago'] ?? '',
            ],
            'delta' => [
                'health_score' => $scoreDelta,
                'health_grade' => [
                    'from' => $prevGrade,
                    'to' => $curGrade,
                    'changed' => $prevGrade !== '' && $curGrade !== '' && $prevGrade !== $curGrade,
                ],
                'bottleneck' => [
                    'from' => $prevBnType,
                    'to' => $curBnType,
                    'changed' => $prevBnType !== '' && $curBnType !== '' && strcasecmp($prevBnType, $curBnType) !== 0,
                ],
            ],
            'metrics' => $metricRows,
            'summary' => $this->buildSummary($scoreDelta, $metricRows, $prevGrade, $curGrade, $prevBnType, $curBnType, $openBookDelta),
            'open_book_delta' => $openBookDelta,
            'overall' => $scoreDelta > 0 ? 'improved' : ($scoreDelta < 0 ? 'worse' : ($improvedCount > $worseCount ? 'improved' : ($worseCount > $improvedCount ? 'worse' : 'stable'))),
        ];
    }

    /** @param array<string, mixed> $current @param array<string, mixed> $previous */
    private function openBookDelta(array $current, array $previous): array
    {
        $prevOb = $this->openBookSlice($previous);
        $curOb = $this->openBookSlice($current);
        $prevCount = (int) ($prevOb['count'] ?? 0);
        $curCount = (int) ($curOb['count'] ?? 0);
        $prevSpread = $this->numericOrNull($prevOb['gpu_therm_spread'] ?? ($previous['metrics']['gpu_therm_spread'] ?? null));
        $curSpread = $this->numericOrNull($curOb['gpu_therm_spread'] ?? ($current['metrics']['gpu_therm_spread'] ?? null));
        $spreadDelta = ($prevSpread !== null && $curSpread !== null) ? round($curSpread - $prevSpread, 2) : null;

        $prevSources = array_values(array_unique(array_filter(array_map('strval', (array) ($prevOb['sources'] ?? [])))));
        $curSources = array_values(array_unique(array_filter(array_map('strval', (array) ($curOb['sources'] ?? [])))));
        sort($prevSources);
        sort($curSources);

        return [
            'sensor_count' => [
                'previous' => $prevCount,
                'current' => $curCount,
                'delta' => $curCount - $prevCount,
            ],
            'therm_spread' => [
                'previous' => $prevSpread,
                'current' => $curSpread,
                'delta' => $spreadDelta,
            ],
            'sources_added' => array_values(array_diff($curSources, $prevSources)),
            'sources_removed' => array_values(array_diff($prevSources, $curSources)),
            'changed' => $prevCount !== $curCount
                || ($spreadDelta !== null && abs($spreadDelta) >= 0.5)
                || $prevSources !== $curSources,
        ];
    }

    /** @param array<string, mixed> $row */
    private function openBookSlice(array $row): array
    {
        if (isset($row['openbook_snapshot']) && is_array($row['openbook_snapshot'])) {
            $sensors = (array) $row['openbook_snapshot'];
            $sources = [];
            foreach ($sensors as $s) {
                if (is_array($s) && !empty($s['source'])) {
                    $sources[] = (string) $s['source'];
                }
            }

            return [
                'count' => count($sensors),
                'sources' => $sources,
                'gpu_therm_spread' => $row['dossier']['gpu']['gpu_therm_spread'] ?? null,
            ];
        }

        $dossier = is_array($row['silicon_dossier'] ?? null) ? $row['silicon_dossier'] : [];
        $open = is_array($dossier['open_book'] ?? null) ? $dossier['open_book'] : [];
        $sensors = (array) ($open['sensors'] ?? []);
        $sources = [];
        foreach ($sensors as $s) {
            if (is_array($s) && !empty($s['source'])) {
                $sources[] = (string) $s['source'];
            }
        }
        if ($sources === [] && !empty($open['sources']) && is_array($open['sources'])) {
            $sources = array_values(array_filter(array_map('strval', $open['sources'])));
        }

        return [
            'count' => (int) ($open['count'] ?? count($sensors)),
            'sources' => $sources,
            'gpu_therm_spread' => $dossier['gpu']['gpu_therm_spread'] ?? ($row['metrics']['gpu_therm_spread'] ?? null),
        ];
    }

    /** @param list<array<string, mixed>> $metricRows */
    private function buildSummary(
        int $scoreDelta,
        array $metricRows,
        string $prevGrade,
        string $curGrade,
        string $prevBn,
        string $curBn,
        array $openBookDelta = [],
    ): string {
        $parts = [];
        if ($scoreDelta > 0) {
            $parts[] = "Health score up {$scoreDelta} points ({$prevGrade} → {$curGrade}).";
        } elseif ($scoreDelta < 0) {
            $parts[] = 'Health score down ' . abs($scoreDelta) . " points ({$prevGrade} → {$curGrade}).";
        } elseif ($prevGrade !== $curGrade && $prevGrade !== '' && $curGrade !== '') {
            $parts[] = "Grade changed: {$prevGrade} → {$curGrade}.";
        }

        if ($prevBn !== '' && $curBn !== '' && strcasecmp($prevBn, $curBn) !== 0) {
            $parts[] = 'Bottleneck shifted from ' . $this->humanBottleneck($prevBn) . ' to ' . $this->humanBottleneck($curBn) . '.';
        }

        if (!empty($openBookDelta['changed'])) {
            $obCount = $openBookDelta['sensor_count'] ?? [];
            $obDelta = (int) ($obCount['delta'] ?? 0);
            if ($obDelta !== 0) {
                $parts[] = 'Open-book sensor count ' . ($obDelta > 0 ? 'up' : 'down') . ' ' . abs($obDelta) . '.';
            }
            $spread = $openBookDelta['therm_spread']['delta'] ?? null;
            if ($spread !== null && abs((float) $spread) >= 0.5) {
                $parts[] = 'GPU therm spread ' . ($spread > 0 ? 'widened' : 'narrowed') . ' ' . abs((float) $spread) . '°C.';
            }
        }

        foreach (array_slice($metricRows, 0, 3) as $row) {
            if ($row['delta'] === null || abs((float) $row['delta']) < 0.01) {
                continue;
            }
            $dir = ($row['improved'] ?? null) === true ? 'down' : (($row['improved'] ?? null) === false ? 'up' : 'changed');
            if (in_array($row['key'], ['cpu_score', 'gpu_score', 'ram_gb', 'lan_link_mbps', 'battery_health_pct'], true)) {
                $dir = ($row['delta'] ?? 0) > 0 ? 'up' : 'down';
            }
            $unit = $row['unit'] ?? '';
            $parts[] = ($row['label'] ?? 'Metric') . ' ' . $dir . ' ' . abs((float) $row['delta']) . $unit . '.';
        }

        if ($parts === []) {
            return 'Compared with your last test — results are very similar.';
        }

        return implode(' ', $parts);
    }

    private function humanBottleneck(string $type): string
    {
        return match (strtolower($type)) {
            'gpu' => 'GPU',
            'cpu' => 'CPU',
            'ram' => 'RAM',
            'storage' => 'storage',
            'thermal' => 'thermals',
            'psu' => 'power',
            default => $type !== '' ? $type : 'unknown',
        };
    }

    private function metricImproved(string $key, ?float $delta): ?bool
    {
        if ($delta === null || abs($delta) < 0.01) {
            return null;
        }

        return match ($key) {
            'gpu_temp_max', 'cpu_temp_max', 'gpu_hotspot_max', 'frametime_p99_ms' => $delta < 0,
            'cpu_score', 'gpu_score', 'ram_gb', 'gpu_util_avg', 'lan_link_mbps', 'battery_health_pct' => $delta > 0,
            default => null,
        };
    }

    private function metricUnit(string $key): string
    {
        return match ($key) {
            'gpu_temp_max', 'cpu_temp_max', 'gpu_hotspot_max' => '°C',
            'gpu_util_avg', 'battery_health_pct' => '%',
            'frametime_p99_ms' => ' ms',
            'ram_gb' => ' GB',
            'lan_link_mbps' => ' Mbps',
            default => '',
        };
    }

    private function numericOrNull(mixed $value): ?float
    {
        if ($value === null || $value === '') {
            return null;
        }
        if (!is_numeric($value)) {
            return null;
        }

        return (float) $value;
    }
}
