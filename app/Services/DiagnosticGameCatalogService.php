<?php

declare(strict_types=1);

namespace App\Services;

use App\Support\Log;
use GuzzleHttp\Client;

/**
 * Auto-refreshes the 300-title diagnostic game catalog from awards, Steam charts, optional RAWG/LLM.
 */
class DiagnosticGameCatalogService
{
    private const TARGET = 300;

    private string $catalogPath;
    private ?Client $http;
    private SettingsService $settings;

    public function __construct(?Client $http = null, ?SettingsService $settings = null)
    {
        $this->catalogPath = dirname(__DIR__, 2) . '/config/diagnostic_games.json';
        $this->settings = $settings ?? new SettingsService();
        $this->http = $http;
    }

    private function httpClient(): Client
    {
        if ($this->http === null) {
            throw new \RuntimeException('Game catalog HTTP refresh requires guzzlehttp/guzzle (disabled in standalone kit).');
        }

        return $this->http;
    }

    /** @return list<array<string, mixed>> */
    public function loadGames(): array
    {
        if (!is_file($this->catalogPath)) {
            $this->refreshIfStale(true);

            return $this->readCatalog()['games'] ?? [];
        }

        $data = $this->readCatalog();
        $updated = (string) ($data['updated_at'] ?? '');
        if ($updated === '' || strtotime($updated) === false || $this->isStale($updated)) {
            if ($this->settings->diagnosticGamesAutoRefresh()) {
                try {
                    $this->refresh(false);
                    $data = $this->readCatalog();
                } catch (\Throwable $e) {
                    Log::error('DiagnosticGameCatalog: lazy refresh failed', ['error' => $e->getMessage()]);
                }
            }
        }

        return $data['games'] ?? [];
    }

    public function refreshIfStale(bool $force = false): array
    {
        if (!$force && !$this->settings->diagnosticGamesAutoRefresh()) {
            return ['skipped' => true, 'reason' => 'auto_refresh_disabled'];
        }

        if (!$force && is_file($this->catalogPath)) {
            $data = $this->readCatalog();
            $updated = (string) ($data['updated_at'] ?? '');
            if ($updated !== '' && !$this->isStale($updated)) {
                return ['skipped' => true, 'updated_at' => $updated, 'count' => (int) ($data['count'] ?? 0)];
            }
        }

        return $this->refresh($force);
    }

    /** @return array<string, mixed> */
    public function refresh(bool $force = false): array
    {
        $existing = is_file($this->catalogPath) ? ($this->readCatalog()['games'] ?? []) : [];
        $bySlug = [];
        foreach ($existing as $g) {
            $slug = (string) ($g['slug'] ?? '');
            if ($slug !== '') {
                $bySlug[$slug] = $g;
            }
        }

        /** @var list<array{name: string, tier?: string, tags?: list<string>, source: string, priority: int}> $candidates */
        $candidates = [];

        foreach ($this->anchorTitles() as $name) {
            $candidates[] = ['name' => $name, 'tier' => 'high', 'tags' => ['anchor'], 'source' => 'anchor', 'priority' => 95];
        }

        foreach ($this->awardTitles() as $row) {
            $candidates[] = array_merge($row, ['source' => 'award', 'priority' => 100]);
        }

        foreach ($this->fetchSteamFeatured() as $row) {
            $candidates[] = $row;
        }

        foreach ($this->fetchRawgTrending() as $row) {
            $candidates[] = $row;
        }

        foreach ($this->fetchLlmGapFill($candidates) as $row) {
            $candidates[] = $row;
        }

        // Keep prior slugs with lower priority so IDs stay stable
        foreach ($existing as $g) {
            $candidates[] = [
                'name' => (string) ($g['name'] ?? ''),
                'tier' => (string) ($g['tier'] ?? 'mid'),
                'tags' => (array) ($g['tags'] ?? []),
                'source' => 'legacy',
                'priority' => 40,
            ];
        }

        $merged = $this->mergeCandidates($candidates, $bySlug);
        $payload = [
            'version' => 2,
            'count' => count($merged),
            'updated_at' => date('c'),
            'sources' => $this->summarizeSources($merged),
            'games' => $merged,
        ];

        file_put_contents(
            $this->catalogPath,
            json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT)
        );

        (new SettingsService())->clearCache();
        try {
            (new AdminService())->updateSetting('diagnostic_games_updated_at', date('c'));
        } catch (\Throwable) {
            // settings table optional on first boot
        }

        Log::info('DiagnosticGameCatalog refreshed', ['count' => count($merged), 'force' => $force]);

        return [
            'ok' => true,
            'count' => count($merged),
            'updated_at' => $payload['updated_at'],
            'sources' => $payload['sources'],
        ];
    }

    /** @return list<string> */
    private function anchorTitles(): array
    {
        $path = dirname(__DIR__, 2) . '/config/diagnostic_game_anchors.php';

        return is_file($path) ? (require $path) : [];
    }

    /** @return list<array{name: string, tier?: string, tags?: list<string>}> */
    private function awardTitles(): array
    {
        $path = dirname(__DIR__, 2) . '/config/diagnostic_game_awards.php';
        if (!is_file($path)) {
            return [];
        }
        $years = require $path;
        $out = [];
        foreach ($years as $year => $games) {
            foreach ($games as $g) {
                $tags = (array) ($g['tags'] ?? []);
                $tags[] = 'award_' . $year;
                $out[] = [
                    'name' => (string) $g['name'],
                    'tier' => (string) ($g['tier'] ?? 'high'),
                    'tags' => array_values(array_unique($tags)),
                ];
            }
        }

        return $out;
    }

    /** @return list<array{name: string, tier?: string, tags?: list<string>, source: string, priority: int}> */
    private function fetchSteamFeatured(): array
    {
        $out = [];
        try {
            $res = $this->httpClient()->get('https://store.steampowered.com/api/featuredcategories/', [
                'query' => ['cc' => 'us', 'l' => 'english'],
            ]);
            if ($res->getStatusCode() !== 200) {
                return [];
            }
            $data = \App\json_decode_assoc((string) $res->getBody(), '{}');
            if ($data === []) {
                return [];
            }

            $buckets = [
                'top_sellers' => ['priority' => 85, 'tier' => 'high', 'tag' => 'steam_top'],
                'specials' => ['priority' => 70, 'tier' => 'mid', 'tag' => 'steam_special'],
                'coming_soon' => ['priority' => 75, 'tier' => 'high', 'tag' => 'steam_hype'],
                'new_releases' => ['priority' => 72, 'tier' => 'mid', 'tag' => 'steam_new'],
                'top_vr' => ['priority' => 55, 'tier' => 'high', 'tag' => 'vr'],
            ];

            foreach ($buckets as $key => $meta) {
                $items = $data[$key]['items'] ?? [];
                if (!is_array($items)) {
                    continue;
                }
                foreach ($items as $item) {
                    $name = trim((string) ($item['name'] ?? ''));
                    if ($name === '' || str_contains(strtolower($name), 'steam deck')) {
                        continue;
                    }
                    $out[] = [
                        'name' => $name,
                        'tier' => $meta['tier'],
                        'tags' => [$meta['tag'], 'steam'],
                        'source' => 'steam_' . $key,
                        'priority' => $meta['priority'],
                    ];
                }
            }
        } catch (\Throwable $e) {
            Log::error('DiagnosticGameCatalog: Steam fetch failed', ['error' => $e->getMessage()]);
        }

        return $out;
    }

    /** @return list<array{name: string, tier?: string, tags?: list<string>, source: string, priority: int}> */
    private function fetchRawgTrending(): array
    {
        $key = Env::get('RAWG_API_KEY', '');
        if ($key === '') {
            return [];
        }

        $out = [];
        $endpoints = [
            ['path' => '/api/games', 'query' => ['ordering' => '-metacritic', 'page_size' => 40, 'dates' => (date('Y') - 1) . '-01-01,' . date('Y') . '-12-31'], 'priority' => 78, 'tag' => 'rawg_metacritic'],
            ['path' => '/api/games', 'query' => ['ordering' => '-added', 'page_size' => 40], 'priority' => 65, 'tag' => 'rawg_new'],
        ];

        foreach ($endpoints as $ep) {
            try {
                $res = $this->httpClient()->get('https://api.rawg.io' . $ep['path'], [
                    'query' => array_merge($ep['query'], ['key' => $key]),
                ]);
                if ($res->getStatusCode() !== 200) {
                    continue;
                }
                $data = \App\json_decode_assoc((string) $res->getBody(), '{}');
                foreach ($data['results'] ?? [] as $row) {
                    $name = trim((string) ($row['name'] ?? ''));
                    if ($name === '') {
                        continue;
                    }
                    $rating = (float) ($row['rating'] ?? 0);
                    $tier = $rating >= 4.2 ? 'high' : ($rating >= 3.5 ? 'mid' : 'low');
                    $out[] = [
                        'name' => $name,
                        'tier' => $tier,
                        'tags' => [$ep['tag'], 'rawg'],
                        'source' => $ep['tag'],
                        'priority' => $ep['priority'],
                    ];
                }
            } catch (\Throwable $e) {
                Log::error('DiagnosticGameCatalog: RAWG failed', ['error' => $e->getMessage()]);
            }
        }

        return $out;
    }

    /**
     * @param list<array<string, mixed>> $current
     * @return list<array{name: string, tier?: string, tags?: list<string>, source: string, priority: int}>
     */
    private function fetchLlmGapFill(array $current): array
    {
        $llm = new LlmService();
        if (!$llm->isConfigured() || count($this->uniqueNames($current)) >= self::TARGET - 20) {
            return [];
        }

        $year = (int) date('Y');
        $sample = array_slice($this->uniqueNames($current), 0, 40);
        $prompt = "List 40 PC games released or major-updated in {$year} and " . ($year - 1)
            . " that are graphically heavy OR won major awards (GOTY, BAFTA, Steam hits). "
            . 'Exclude duplicates from: ' . implode(', ', $sample)
            . '. Return JSON: {"games":[{"name":"...","tier":"low|mid|high|ultra","tags":["..."]}]}';

        try {
            $decoded = (new LlmService())->generateJson(
                'You curate PC game benchmarks for a hardware diagnostic lab. Output valid JSON only.',
                $prompt,
                1200,
                0.3
            );
            if (!is_array($decoded)) {
                return [];
            }
            $list = isset($decoded['games']) && is_array($decoded['games']) ? $decoded['games'] : $decoded;
            if (!is_array($list)) {
                return [];
            }
            $out = [];
            foreach ($list as $row) {
                if (!is_array($row) || empty($row['name'])) {
                    continue;
                }
                $out[] = [
                    'name' => (string) $row['name'],
                    'tier' => (string) ($row['tier'] ?? 'high'),
                    'tags' => array_merge((array) ($row['tags'] ?? []), ['llm_curated']),
                    'source' => 'llm',
                    'priority' => 68,
                ];
            }

            return $out;
        } catch (\Throwable $e) {
            Log::error('DiagnosticGameCatalog: LLM gap fill failed', ['error' => $e->getMessage()]);

            return [];
        }
    }

    /**
     * @param list<array<string, mixed>> $candidates
     * @param array<string, array<string, mixed>> $existingBySlug
     * @return list<array<string, mixed>>
     */
    private function mergeCandidates(array $candidates, array $existingBySlug): array
    {
        usort($candidates, fn ($a, $b) => ($b['priority'] ?? 0) <=> ($a['priority'] ?? 0));

        $picked = [];
        $slugSeen = [];
        $nextId = 1;

        foreach ($existingBySlug as $slug => $g) {
            $nextId = max($nextId, (int) preg_replace('/\D/', '', (string) ($g['id'] ?? '0')) + 1);
        }

        foreach ($candidates as $c) {
            $name = trim((string) ($c['name'] ?? ''));
            if ($name === '') {
                continue;
            }
            $slug = $this->slug($name);
            if (isset($slugSeen[$slug])) {
                continue;
            }
            $slugSeen[$slug] = true;

            if (isset($existingBySlug[$slug])) {
                $row = $existingBySlug[$slug];
                $row['name'] = $name;
                $row['tier'] = (string) ($c['tier'] ?? $row['tier'] ?? 'mid');
                $row['tags'] = array_values(array_unique(array_merge((array) ($row['tags'] ?? []), (array) ($c['tags'] ?? []), [(string) ($c['source'] ?? 'refresh')])));
                $row['source'] = (string) ($c['source'] ?? 'refresh');
            } else {
                $tier = (string) ($c['tier'] ?? 'mid');
                $row = $this->buildGameRow('g' . $nextId++, $name, $slug, $tier, (array) ($c['tags'] ?? []), (string) ($c['source'] ?? 'refresh'));
            }

            $picked[] = $row;
            if (count($picked) >= self::TARGET) {
                break;
            }
        }

        // Pad from legacy if still short
        if (count($picked) < self::TARGET) {
            foreach ($existingBySlug as $slug => $g) {
                if (isset($slugSeen[$slug])) {
                    continue;
                }
                $picked[] = $g;
                $slugSeen[$slug] = true;
                if (count($picked) >= self::TARGET) {
                    break;
                }
            }
        }

        return array_slice($picked, 0, self::TARGET);
    }

    /** @param list<string> $tags */
    private function buildGameRow(string $id, string $name, string $slug, string $tier, array $tags, string $source): array
    {
        $vram = match ($tier) {
            'low' => 2,
            'mid' => 4,
            'high' => 8,
            'ultra' => 12,
            default => 6,
        };
        $cpu = match ($tier) {
            'ultra' => 90,
            'high' => 75,
            'mid' => 55,
            'low' => 35,
            default => 50,
        };
        $gpu = match ($tier) {
            'ultra' => 95,
            'high' => 80,
            'mid' => 60,
            'low' => 40,
            default => 55,
        };

        return [
            'id' => $id,
            'slug' => $slug,
            'name' => $name,
            'name_fa' => $name,
            'tier' => $tier,
            'min_vram_gb' => $vram,
            'cpu_demand' => $cpu,
            'gpu_demand' => $gpu,
            'tags' => array_values(array_unique(array_merge($tags, [$tier]))),
            'source' => $source,
        ];
    }

    private function slug(string $name): string
    {
        $s = strtolower(trim($name));
        $s = preg_replace('/[^a-z0-9]+/', '-', $s) ?? $s;

        return trim($s, '-');
    }

    /** @return array<string, mixed> */
    private function readCatalog(): array
    {
        $raw = file_get_contents($this->catalogPath);

        return \App\json_decode_assoc($raw !== false ? (string) $raw : '', '{}');
    }

    private function isStale(string $updatedAt): bool
    {
        $ts = strtotime($updatedAt);
        $days = $this->settings->diagnosticGamesRefreshDays();

        return $ts === false || $ts < strtotime('-' . $days . ' days');
    }

    /** @return array<string, mixed> */
    public function adminStatus(): array
    {
        $data = is_file($this->catalogPath) ? $this->readCatalog() : [];
        $updated = (string) ($data['updated_at'] ?? $this->settings->get('diagnostic_games_updated_at', ''));
        $days = $this->settings->diagnosticGamesRefreshDays();
        $nextDue = '';
        if ($updated !== '' && ($ts = strtotime($updated)) !== false) {
            $nextDue = date('c', $ts + ($days * 86400));
        }
        $awardMax = self::maxAwardConfigYear();
        $currentYear = (int) date('Y');

        return [
            'count' => (int) ($data['count'] ?? 0),
            'updated_at' => $updated,
            'sources' => $data['sources'] ?? [],
            'auto_refresh' => $this->settings->diagnosticGamesAutoRefresh(),
            'refresh_days' => $days,
            'next_due_at' => $nextDue,
            'is_stale' => $updated === '' || $this->isStale($updated),
            'award_config_max_year' => $awardMax,
            'award_config_needs_update' => $awardMax < $currentYear,
            'cron_command' => 'php ' . dirname(__DIR__, 2) . '/cron/refresh_diagnostic_games.php',
        ];
    }

    public static function maxAwardConfigYear(): int
    {
        $path = dirname(__DIR__, 2) . '/config/diagnostic_game_awards.php';
        if (!is_file($path)) {
            return 0;
        }
        $years = require $path;
        if (!is_array($years)) {
            return 0;
        }
        $keys = array_filter(array_keys($years), static fn ($y) => is_numeric($y));

        return $keys === [] ? 0 : (int) max($keys);
    }

    /** @param list<array<string, mixed>> $candidates */
    /** @return list<string> */
    private function uniqueNames(array $candidates): array
    {
        $names = [];
        foreach ($candidates as $c) {
            $n = trim((string) ($c['name'] ?? ''));
            if ($n !== '') {
                $names[] = $n;
            }
        }

        return array_values(array_unique($names));
    }

    /** @param list<array<string, mixed>> $games @return array<string, int> */
    private function summarizeSources(array $games): array
    {
        $counts = [];
        foreach ($games as $g) {
            $src = (string) ($g['source'] ?? 'unknown');
            $counts[$src] = ($counts[$src] ?? 0) + 1;
        }
        arsort($counts);

        return $counts;
    }
}
