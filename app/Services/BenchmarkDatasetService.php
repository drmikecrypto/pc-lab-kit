<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Loads, normalizes, caches, and queries PassMark / UserBenchmark JSON datasets.
 */
class BenchmarkDatasetService
{
    private string $root;
    /** @var array<string, array<string, mixed>> */
    private array $catalog;
    /** @var array<string, array{rows: list<array>, stats: array}> */
    private array $memory = [];
    private ?BenchmarkPricingService $pricing = null;

    public function __construct(?string $projectRoot = null, ?BenchmarkPricingService $pricing = null)
    {
        $this->root = $projectRoot ?? dirname(__DIR__, 2);
        $this->catalog = require $this->root . '/config/benchmark_datasets.php';
        $this->pricing = $pricing;
    }

    public function normalizeName(string $s): string
    {
        return $this->normalizeToken($s);
    }

    private function pricing(): BenchmarkPricingService
    {
        return $this->pricing ??= new BenchmarkPricingService(null, $this);
    }

    /** @return array<string, array<string, mixed>> */
    public function getCatalog(): array
    {
        $out = [];
        foreach ($this->catalog as $key => $meta) {
            $stats = $this->datasetStats($key);
            $tier = self::resolveSourceTier($meta['file'], $meta['source_tier'] ?? null);
            $out[$key] = array_merge($meta, [
                'key' => $key,
                'count' => $stats['count'],
                'updated_at' => $stats['updated_at'],
                'source_tier' => $tier,
                'source_label' => self::sourceLabel($tier),
                'source_label_fa' => self::sourceLabel($tier),
            ]);
        }

        return $out;
    }

    /** lab = controlled PassMark test; gold = crowd backtest files (*benchmark* in filename). */
    public static function resolveSourceTier(string $filePath, ?string $override = null): string
    {
        if ($override === 'lab' || $override === 'gold') {
            return $override;
        }
        $base = strtolower(basename(str_replace('\\', '/', $filePath)));

        return str_contains($base, 'benchmark') ? 'gold' : 'lab';
    }

    /** @return array{total_rows: int, datasets: int, components: array<string, int>} */
    public function getGlobalStats(): array
    {
        $total = 0;
        $components = [];
        foreach ($this->catalog as $key => $meta) {
            $count = $this->datasetStats($key)['count'];
            $total += $count;
            $comp = $meta['component'] ?? 'other';
            $components[$comp] = ($components[$comp] ?? 0) + $count;
        }

        return [
            'total_rows' => $total,
            'datasets' => count($this->catalog),
            'components' => $components,
        ];
    }

    /**
     * @return array{rows: list<array>, total: int, page: int, per_page: int, columns: list<array>, meta: array}
     */
    public function query(string $datasetKey, array $opts = []): array
    {
        if (!isset($this->catalog[$datasetKey])) {
            return ['rows' => [], 'total' => 0, 'page' => 1, 'per_page' => 50, 'columns' => [], 'meta' => []];
        }

        $meta = $this->catalog[$datasetKey];
        $bundle = $this->loadDataset($datasetKey);
        $rows = $bundle['rows'];

        $q = trim((string) ($opts['q'] ?? ''));
        if ($q !== '') {
            $needle = mb_strtolower($q);
            $rows = array_values(array_filter($rows, fn ($r) => str_contains(mb_strtolower($r['name']), $needle)));
        }

        $rows = $this->pricing()->applyToRows($rows);
        $quote = $this->pricing()->quote();

        $sort = (string) ($opts['sort'] ?? ($meta['primary_metric'] ?? 'mark'));
        $dir = strtolower((string) ($opts['dir'] ?? 'desc')) === 'asc' ? 'asc' : 'desc';
        $rows = $this->sortRows($rows, $sort, $dir);

        $perPage = max(10, min(200, (int) ($opts['per_page'] ?? 50)));
        $page = max(1, (int) ($opts['page'] ?? 1));
        $total = count($rows);
        $offset = ($page - 1) * $perPage;
        $pageRows = array_slice($rows, $offset, $perPage);

        return [
            'rows' => $pageRows,
            'total' => $total,
            'page' => $page,
            'per_page' => $perPage,
            'columns' => $this->normalizeColumns($meta['columns'] ?? []),
            'meta' => [
                'key' => $datasetKey,
                'label' => $this->datasetLabel($meta, $datasetKey),
                'label_fa' => $this->datasetLabel($meta, $datasetKey),
                'component' => $meta['component'] ?? '',
                'primary_metric' => $meta['primary_metric'] ?? 'mark',
                'source_tier' => self::resolveSourceTier($meta['file'], $meta['source_tier'] ?? null),
                'source_label' => self::sourceLabel(self::resolveSourceTier($meta['file'], $meta['source_tier'] ?? null)),
                'source_label_fa' => self::sourceLabel(self::resolveSourceTier($meta['file'], $meta['source_tier'] ?? null)),
                'stats' => $bundle['stats'],
                'pricing' => [
                    'usdt_rate' => $quote['rate'],
                    'usdt_source' => $quote['source'],
                    'usdt_stale' => $quote['stale'],
                    'legacy_usd_toman' => UsdtExchangeService::LEGACY_USD_TOMAN,
                ],
            ],
        ];
    }

    /** @return list<array> */
    public function search(string $query, int $limit = 20): array
    {
        $needle = mb_strtolower(trim($query));
        if ($needle === '') {
            return [];
        }

        $results = [];
        foreach (array_keys($this->catalog) as $key) {
            $bundle = $this->loadDataset($key);
            foreach ($bundle['rows'] as $row) {
                if (!str_contains(mb_strtolower($row['name']), $needle)) {
                    continue;
                }
                $results[] = array_merge($row, [
                    'dataset' => $key,
                    'component' => $this->catalog[$key]['component'] ?? '',
                    'label' => $this->datasetLabel($this->catalog[$key], $key),
                    'label_fa' => $this->datasetLabel($this->catalog[$key], $key),
                ]);
                if (count($results) >= $limit) {
                    return $this->rankSearchResults($this->pricing()->applyToRows($results), $needle);
                }
            }
        }

        return $this->rankSearchResults($this->pricing()->applyToRows($results), $needle);
    }

    /** Match a catalog part — lab score primary, gold crowd data when available. */
    public function matchPart(array $part): ?array
    {
        $slug = (string) ($part['category_slug'] ?? '');
        $keys = $this->datasetsForCategory($slug);
        if ($keys === []) {
            return null;
        }

        $candidates = $this->partSearchTerms($part);
        if ($candidates === []) {
            return null;
        }

        $specs = is_array($part['specs_json'] ?? null)
            ? $part['specs_json']
            : \App\json_decode_assoc((string) ($part['specs_json'] ?? ''), '{}');

        $bestLab = null;
        $bestLabScore = 0;
        $bestGold = null;
        $bestGoldScore = 0;

        foreach ($keys as $key) {
            $meta = $this->catalog[$key];
            $tier = self::resolveSourceTier($meta['file'], $meta['source_tier'] ?? null);
            $bundle = $this->loadDataset($key);

            foreach ($bundle['rows'] as $row) {
                $score = $this->matchScore($candidates, $row['name'], $row['name_norm'] ?? '', $specs);
                if ($score <= 0) {
                    continue;
                }

                $hit = array_merge($row, [
                    'dataset' => $key,
                    'match_score' => $score,
                    'source_tier' => $tier,
                    'component' => $meta['component'] ?? $slug,
                ]);

                if ($tier === 'lab') {
                    if ($score > $bestLabScore) {
                        $bestLabScore = $score;
                        $bestLab = $hit;
                    }
                } elseif ($score > $bestGoldScore) {
                    $bestGoldScore = $score;
                    $bestGold = $hit;
                }
            }
        }

        $primary = $bestLab ?? $bestGold;
        $primaryScore = $primary['match_score'] ?? 0;
        if ($primary === null || $primaryScore < 65) {
            return null;
        }

        $confidence = $this->matchConfidence($primaryScore);
        $metricKey = $this->catalog[$primary['dataset']]['primary_metric'] ?? 'mark';
        $primaryMetric = (int) ($primary[$metricKey] ?? $primary['mark'] ?? $primary['bench'] ?? 0);

        if ($bestLab && $bestGold && $bestGoldScore >= 65) {
            $sourceTier = 'blend';
        } else {
            $sourceTier = ($primary['source_tier'] ?? 'lab');
        }

        return [
            'name' => $primary['name'],
            'name_raw' => $primary['name_raw'] ?? $primary['name'],
            'mark' => $primaryMetric,
            'bench' => (int) ($primary['bench'] ?? $primaryMetric),
            'primary_score' => $primaryMetric,
            'percentile' => $primary['percentile'] ?? null,
            'dataset' => $primary['dataset'],
            'source_tier' => $sourceTier,
            'confidence' => $confidence,
            'match_score' => $primaryScore,
            'component' => $primary['component'] ?? $slug,
            'lab' => $bestLab && $bestLabScore >= 65 ? $this->matchSummary($bestLab) : null,
            'gold' => $bestGold && $bestGoldScore >= 65 ? $this->matchSummary($bestGold) : null,
            'score_pct_of_max' => $primary['score_pct_of_max'] ?? 0,
        ];
    }

    private function matchSummary(array $hit): array
    {
        $key = $hit['dataset'];
        $metric = $this->catalog[$key]['primary_metric'] ?? 'mark';

        return [
            'name' => $hit['name'],
            'score' => (int) ($hit[$metric] ?? $hit['mark'] ?? $hit['bench'] ?? 0),
            'dataset' => $key,
            'match_score' => (int) ($hit['match_score'] ?? 0),
            'source_tier' => $hit['source_tier'] ?? 'lab',
        ];
    }

    private function matchConfidence(int $score): string
    {
        return match (true) {
            $score >= 92 => 'high',
            $score >= 75 => 'medium',
            default => 'low',
        };
    }

    /** Percentile (0-100) for a primary score within a component class. */
    public function scorePercentile(string $component, int $score): int
    {
        if ($score <= 0) {
            return 0;
        }

        $scores = [];
        foreach ($this->catalog as $key => $meta) {
            if (($meta['component'] ?? '') !== $component) {
                continue;
            }
            $metric = $meta['primary_metric'] ?? 'mark';
            foreach ($this->loadDataset($key)['rows'] as $row) {
                $v = (int) ($row[$metric] ?? $row['mark'] ?? $row['bench'] ?? 0);
                if ($v > 0) {
                    $scores[] = $v;
                }
            }
        }

        if ($scores === []) {
            return min(100, (int) round($score / 500));
        }

        sort($scores);
        $below = 0;
        foreach ($scores as $s) {
            if ($s <= $score) {
                ++$below;
            }
        }

        return (int) min(100, max(1, round(($below / count($scores)) * 100)));
    }

    /** Compact context string for LLM / Amin recommendations. */
    public function buildAiContext(array $selectedParts, array $analysis = []): string
    {
        $lines = ['=== PCVerse benchmark context (PassMark lab + gold crowd datasets) ==='];
        foreach ($selectedParts as $p) {
            $match = $this->matchPart($p);
            if (!$match) {
                continue;
            }
            $metric = (int) ($match['primary_score'] ?? $match['mark'] ?? 0);
            $pct = $match['percentile'] ?? $this->scorePercentile((string) ($match['component'] ?? ''), $metric);
            $tierLabel = match ($match['source_tier'] ?? 'lab') {
                'gold' => 'Gold standard (2M+ crowd)',
                'blend' => 'Lab + gold blend',
                default => 'PassMark lab',
            };
            $conf = $match['confidence'] ?? 'medium';
            $lines[] = sprintf(
                '- %s (%s): score %s, percentile %d%%, source: %s, match confidence: %s',
                $p['name'] ?? $p['name_fa'] ?? $match['name'],
                $p['category_slug'] ?? '',
                number_format($metric),
                $pct,
                $tierLabel,
                $conf
            );
            if (!empty($match['gold']['name'])) {
                $lines[] = '  └ crowd: ' . $match['gold']['name'] . ' (' . number_format((int) $match['gold']['score']) . ')';
            }
        }

        $bnMsg = $analysis['bottleneck']['message'] ?? $analysis['bottleneck']['label_fa'] ?? $analysis['bottleneck']['message_fa'] ?? '';
        if ($bnMsg !== '') {
            $lines[] = 'Bottleneck: ' . $bnMsg;
        }
        if (!empty($analysis['tier']['name'])) {
            $lines[] = 'Performance tier: ' . $analysis['tier']['name'];
        }

        return implode("\n", $lines);
    }

    /** Top N performers for spark charts on palace landing. */
    public function topPerformers(string $datasetKey, int $limit = 8): array
    {
        if (!isset($this->catalog[$datasetKey])) {
            return [];
        }
        $meta = $this->catalog[$datasetKey];
        $metric = $meta['primary_metric'] ?? 'mark';
        $rows = $this->loadDataset($datasetKey)['rows'];
        usort($rows, fn ($a, $b) => ((int) ($b[$metric] ?? 0)) <=> ((int) ($a[$metric] ?? 0)));

        return array_slice($rows, 0, $limit);
    }

    // --- internals ---

    private static function sourceLabel(string $tier): string
    {
        return $tier === 'gold' ? 'Gold standard (2M+ crowd tests)' : 'PassMark lab';
    }

    /** @param array<string, mixed> $meta */
    private function datasetLabel(array $meta, string $fallback): string
    {
        return (string) ($meta['label_en'] ?? $meta['label'] ?? $meta['label_fa'] ?? $fallback);
    }

    /** @param list<array<string, mixed>> $columns @return list<array<string, mixed>> */
    private function normalizeColumns(array $columns): array
    {
        return array_map(function (array $col): array {
            $col['label'] = (string) ($col['label_en'] ?? $col['label'] ?? $col['label_fa'] ?? ($col['key'] ?? ''));

            return $col;
        }, $columns);
    }

    /** @return array{count: int, updated_at: ?string} */
    private function datasetStats(string $key): array
    {
        $bundle = $this->loadDataset($key);

        return [
            'count' => count($bundle['rows']),
            'updated_at' => $bundle['stats']['source_mtime'] ?? null,
        ];
    }

    /** @return array{rows: list<array>, stats: array} */
    private function loadDataset(string $key): array
    {
        if (isset($this->memory[$key])) {
            return $this->memory[$key];
        }

        $meta = $this->catalog[$key];
        $source = $this->root . '/' . ltrim($meta['file'], '/');
        $cacheDir = $this->root . '/storage/cache/benchmark';
        if (!is_dir($cacheDir)) {
            @mkdir($cacheDir, 0755, true);
        }
        $cacheFile = $cacheDir . '/' . $key . '.json';

        $sourceMtime = is_file($source) ? (int) filemtime($source) : 0;
        if (is_file($cacheFile) && filemtime($cacheFile) >= $sourceMtime && $sourceMtime > 0) {
            $cached = \App\json_decode_assoc((string) file_get_contents($cacheFile), '{}');
            if (isset($cached['rows']) && is_array($cached['rows'])) {
                $this->memory[$key] = $cached;

                return $cached;
            }
        }

        $raw = is_file($source) ? \App\json_decode_assoc((string) file_get_contents($source), '[]') : [];

        $rows = [];
        foreach (array_values($raw) as $i => $item) {
            if (!is_array($item)) {
                continue;
            }
            $normalized = $this->normalizeRow($item, $meta, $i);
            if ($normalized !== null) {
                $rows[] = $normalized;
            }
        }

        $metric = $meta['primary_metric'] ?? 'mark';
        $values = array_values(array_filter(array_map(fn ($r) => (int) ($r[$metric] ?? 0), $rows), fn ($v) => $v > 0));
        $max = $values !== [] ? max($values) : 1;

        foreach ($rows as &$row) {
            $v = (int) ($row[$metric] ?? 0);
            $row['score_pct_of_max'] = $max > 0 && $v > 0 ? (int) round(($v / $max) * 100) : 0;
        }
        unset($row);

        $bundle = [
            'rows' => $rows,
            'stats' => [
                'count' => count($rows),
                'max_' . $metric => $max,
                'source_mtime' => $sourceMtime ? date('c', $sourceMtime) : null,
            ],
        ];

        @file_put_contents($cacheFile, json_encode($bundle, JSON_UNESCAPED_UNICODE));

        $this->memory[$key] = $bundle;

        return $bundle;
    }

    private function normalizeRow(array $item, array $meta, int $index): ?array
    {
        $nameKey = $meta['name_key'] ?? 'Name';
        $rawName = trim((string) ($item[$nameKey] ?? ''));
        if ($rawName === '') {
            return null;
        }

        $parsed = $this->parsePassmarkName($rawName);
        $fieldMap = $meta['field_map'] ?? [];

        $mark = $this->fieldInt($item, $fieldMap['mark'] ?? 'CPU Mark', ['CPU Mark', 'G3D Mark', 'Mark', 'Disk Mark']);
        if ($mark === null && preg_match('/[\d,]+/', $parsed['tail'] ?? '', $m)) {
            $mark = $this->parseInt($m[0]);
        }

        $row = [
            'id' => substr(hash('xxh128', ($meta['file'] ?? '') . $index . $parsed['name']), 0, 16),
            'name' => $parsed['name'],
            'name_raw' => $rawName,
            'name_norm' => $this->normalizeToken($parsed['name']),
            'source_tier' => self::resolveSourceTier($meta['file'], $meta['source_tier'] ?? null),
            'percentile' => $parsed['percentile'],
            'mark' => $mark,
            'rank' => $this->fieldInt($item, $fieldMap['rank'] ?? 'List_Rank', ['List_Rank', 'Rank(lower is better)', 'Rank']),
            'value' => $this->fieldFloat($item, $fieldMap['value'] ?? 'Value %', ['Value %', 'CPU Value(higher is better)', 'Ratio']),
            'bench' => $this->extractBenchScore($item['Avg. bench %'] ?? null) ?? $mark,
            'mark_secondary' => $this->fieldInt($item, $fieldMap['mark_secondary'] ?? 'Secondary_Mark', ['Secondary_Mark']),
            'price_usd' => $this->parsePriceUsd((string) ($item['Price (USD)'] ?? '')),
            'price_toman' => $this->parsePriceToman((string) ($item['Price (Toman)'] ?? '')),
        ];

        if (($row['mark'] ?? 0) <= 0 && ($row['bench'] ?? 0) > 0) {
            $row['mark'] = $row['bench'];
        }

        return $row;
    }

    /** @return array{name: string, percentile: ?int, tail: string} */
    private function parsePassmarkName(string $raw): array
    {
        $name = trim($raw);
        $percentile = null;
        $tail = '';

        if (preg_match('/^(.+?)\((\d+)%\)(.*)$/u', $raw, $m)) {
            $name = trim($m[1]);
            $percentile = (int) $m[2];
            $tail = $m[3];
        }

        return ['name' => $name, 'percentile' => $percentile, 'tail' => $tail];
    }

    private function fieldInt(array $item, string $preferred, array $fallbacks = []): ?int
    {
        $keys = array_unique(array_merge([$preferred], $fallbacks));
        foreach ($keys as $k) {
            if (!isset($item[$k]) || $item[$k] === '' || $item[$k] === 'NA') {
                continue;
            }
            $v = $this->parseInt((string) $item[$k]);
            if ($v !== null) {
                return $v;
            }
        }

        return null;
    }

    private function fieldFloat(array $item, string $preferred, array $fallbacks = []): ?float
    {
        $keys = array_unique(array_merge([$preferred], $fallbacks));
        foreach ($keys as $k) {
            if (!isset($item[$k]) || $item[$k] === '' || $item[$k] === 'NA') {
                continue;
            }
            $raw = (string) $item[$k];
            if (preg_match('/([\d.]+)/', $raw, $m)) {
                return (float) $m[1];
            }
        }

        return null;
    }

    private function extractBenchScore(mixed $raw): ?int
    {
        if ($raw === null || $raw === '') {
            return null;
        }
        $s = (string) $raw;
        if (preg_match('/^([\d.]+)/', trim($s), $m)) {
            return (int) round((float) $m[1]);
        }

        return null;
    }

    private function parseInt(string $val): ?int
    {
        $clean = preg_replace('/[^\d]/', '', $val);

        return ($clean !== '' && $clean !== null) ? (int) $clean : null;
    }

    private function parsePriceUsd(string $val): ?float
    {
        if ($val === '' || $val === 'NA') {
            return null;
        }
        if (!preg_match('/([\d,.]+)/', $val, $m)) {
            return null;
        }

        return (float) str_replace(',', '', $m[1]);
    }

    private function parsePriceToman(string $val): ?int
    {
        if ($val === '' || $val === 'NA') {
            return null;
        }

        return $this->parseInt($val);
    }

    /** @param list<array> $rows */
    private function sortRows(array $rows, string $sort, string $dir): array
    {
        usort($rows, function ($a, $b) use ($sort, $dir) {
            $va = $a[$sort] ?? ($sort === 'name' ? ($a['name'] ?? '') : 0);
            $vb = $b[$sort] ?? ($sort === 'name' ? ($b['name'] ?? '') : 0);

            if ($sort === 'name') {
                $cmp = strcmp((string) $va, (string) $vb);
            } else {
                $cmp = ((float) $va) <=> ((float) $vb);
            }

            return $dir === 'asc' ? $cmp : -$cmp;
        });

        return $rows;
    }

    /** Lab datasets first (absolute scores), then gold crowd lists. */
    private function datasetsForCategory(string $slug): array
    {
        $map = [
            'cpu' => ['cpu-multithread', 'cpu-single', 'cpu-value'],
            'gpu' => ['gpu-high', 'gpu-mid', 'gpu-low', 'gpu-all'],
            'ram' => ['ram-ddr5', 'ram-ddr5-amd', 'ram-ddr5-intel'],
            'memory' => ['ram-ddr5', 'ram-ddr5-amd', 'ram-ddr5-intel'],
            'storage' => ['ssd', 'hdd'],
        ];

        return $map[$slug] ?? [];
    }

    /** @return list<string> */
    private function partSearchTerms(array $part): array
    {
        $terms = [];
        foreach (['model', 'brand', 'name_fa', 'name_en'] as $k) {
            if (!empty($part[$k])) {
                $terms[] = $this->normalizeToken((string) $part[$k]);
            }
        }
        $full = trim(($part['brand'] ?? '') . ' ' . ($part['model'] ?? ''));
        if ($full !== '') {
            $terms[] = $this->normalizeToken($full);
        }

        return array_values(array_unique(array_filter($terms)));
    }

    private function normalizeToken(string $s): string
    {
        $s = mb_strtolower($s);
        $s = preg_replace('/[^\p{L}\p{N}\s]/u', ' ', $s) ?? $s;
        $s = preg_replace('/\s+/', ' ', $s) ?? $s;

        return trim($s);
    }

    /** @param array<string, mixed> $partSpecs */
    private function matchScore(array $candidates, string $benchName, string $benchNorm, array $partSpecs = []): int
    {
        $benchNorm = $benchNorm !== '' ? $benchNorm : $this->normalizeToken($benchName);
        $benchTokens = $this->extractIdentityTokens($benchName);
        $score = 0;

        foreach ($candidates as $term) {
            if ($term === '') {
                continue;
            }
            if ($term === $benchNorm) {
                $score = max($score, 100);
                continue;
            }

            $partTokens = $this->extractIdentityTokens($term);
            if ($benchTokens !== [] && $partTokens !== []) {
                $overlap = count(array_intersect($benchTokens, $partTokens));
                $need = max(1, min(count($partTokens), count($benchTokens)));
                $ratio = $overlap / $need;
                if ($ratio >= 1.0) {
                    $score = max($score, 98);
                } elseif ($ratio >= 0.66) {
                    $score = max($score, 86);
                } elseif ($ratio >= 0.5) {
                    $score = max($score, 74);
                }

                $pGb = $this->capacityTokens($partTokens);
                $bGb = $this->capacityTokens($benchTokens);
                if ($pGb !== [] && $bGb !== [] && $pGb !== $bGb) {
                    $score = (int) round($score * 0.5);
                }
            }

            if (str_contains($benchNorm, $term) || str_contains($term, $benchNorm)) {
                $score = max($score, 78);
            } else {
                similar_text($term, $benchNorm, $pct);
                if ($pct >= 72) {
                    $score = max($score, (int) $pct);
                }
            }
        }

        return min(100, $score);
    }

    /** @return list<string> */
    private function extractIdentityTokens(string $s): array
    {
        $s = mb_strtolower($s);
        $tokens = [];

        if (preg_match_all('/\b(rtx|gtx|rx|arc)\s*-?\s*(\d{3,4}(?:\s*(?:ti|super|xt|xtx))?)/i', $s, $m, PREG_SET_ORDER)) {
            foreach ($m as $hit) {
                $tokens[] = strtolower(preg_replace('/\s+/', ' ', trim($hit[1] . ' ' . $hit[2])) ?? '');
            }
        }
        if (preg_match_all('/\b(ryzen|threadripper|epyc)\s+[\d\s\-]+[a-z0-9]*/i', $s, $m)) {
            foreach ($m[0] as $hit) {
                $tokens[] = $this->normalizeToken($hit);
            }
        }
        if (preg_match_all('/\bcore\s*i[3579]\s*-?\s*\d{4,5}[a-z]*/i', $s, $m)) {
            foreach ($m[0] as $hit) {
                $tokens[] = $this->normalizeToken($hit);
            }
        }
        if (preg_match_all('/\b(\d+)\s*gb\b/i', $s, $m, PREG_SET_ORDER)) {
            foreach ($m as $hit) {
                $tokens[] = $hit[1] . 'gb';
            }
        }
        if (preg_match_all('/\b[a-z0-9]{2,}-[a-z0-9]{4,}[a-z0-9-]*/i', $s, $m)) {
            foreach ($m[0] as $hit) {
                if (strlen($hit) >= 8) {
                    $tokens[] = strtolower($hit);
                }
            }
        }

        return array_values(array_unique(array_filter($tokens)));
    }

    /** @param list<string> $tokens @return list<string> */
    private function capacityTokens(array $tokens): array
    {
        return array_values(array_filter($tokens, static fn ($t) => str_ends_with($t, 'gb')));
    }

    /** @param list<array> $results */
    private function rankSearchResults(array $results, string $needle): array
    {
        usort($results, function ($a, $b) use ($needle) {
            $aExact = str_contains(mb_strtolower($a['name']), $needle) ? 1 : 0;
            $bExact = str_contains(mb_strtolower($b['name']), $needle) ? 1 : 0;
            if ($aExact !== $bExact) {
                return $bExact <=> $aExact;
            }
            $aScore = (int) ($a['mark'] ?? $a['bench'] ?? 0);
            $bScore = (int) ($b['mark'] ?? $b['bench'] ?? 0);

            return $bScore <=> $aScore;
        });

        return $results;
    }
}
