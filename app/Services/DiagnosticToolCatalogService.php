<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Maps the 80-tool enthusiast/OEM catalog to PCVerse lab modules and coverage status.
 */
class DiagnosticToolCatalogService
{
    /** @var array<string, mixed>|null */
    private static ?array $catalog = null;

    /** @return array<string, mixed> */
    public function raw(): array
    {
        if (self::$catalog === null) {
            self::$catalog = require dirname(__DIR__, 2) . '/config/tool_catalog.php';
        }

        return self::$catalog;
    }

    /** @return list<array<string, mixed>> */
    public function tools(): array
    {
        return array_values($this->raw()['tools'] ?? []);
    }

    public function total(): int
    {
        return count($this->tools());
    }

    /** @return array<string, string> */
    public function categories(): array
    {
        return (array) ($this->raw()['categories'] ?? []);
    }

    /** @return array<string, int> */
    public function coverageCounts(): array
    {
        $counts = ['live' => 0, 'beta' => 0, 'import' => 0, 'orchestrate' => 0, 'planned' => 0];
        foreach ($this->tools() as $tool) {
            $c = (string) ($tool['coverage'] ?? 'planned');
            if (!isset($counts[$c])) {
                $counts[$c] = 0;
            }
            $counts[$c]++;
        }

        return $counts;
    }

    /** @return array<string, int> */
    public function moduleCounts(): array
    {
        $counts = [];
        foreach ($this->tools() as $tool) {
            $m = (string) ($tool['module'] ?? 'system');
            $counts[$m] = ($counts[$m] ?? 0) + 1;
        }

        return $counts;
    }

    /**
     * @return array{
     *   meta: array<string, mixed>,
     *   categories: array<string, string>,
     *   tools: list<array<string, mixed>>,
     *   summary: array<string, mixed>,
     *   runnable: array{bench: list<array>, stress: list<array>}
     * }
     */
    public function payload(): array
    {
        $raw = $this->raw();
        $coverage = $this->coverageCounts();
        $ready = ($coverage['live'] ?? 0) + ($coverage['beta'] ?? 0) + ($coverage['orchestrate'] ?? 0) + ($coverage['import'] ?? 0);

        return [
            'meta' => array_merge((array) ($raw['meta'] ?? []), [
                'total' => $this->total(),
                'ready_now' => $ready,
                'live' => $coverage['live'] ?? 0,
            ]),
            'categories' => $this->categories(),
            'tools' => $this->tools(),
            'summary' => [
                'coverage' => $coverage,
                'modules' => $this->moduleCounts(),
                'headline' => sprintf(
                    '%d tools unified — %d live today, %d via native modules, imports, or orchestration',
                    $this->total(),
                    $coverage['live'] ?? 0,
                    $ready
                ),
            ],
            'runnable' => [
                'bench' => $this->runnableBench(),
                'stress' => $this->runnableStress(),
            ],
        ];
    }

    /** @return list<array{id: string, label: string, desc: string, replaces: list<string>}> */
    public function runnableBench(): array
    {
        return [
            ['id' => 'cpu', 'label' => 'CPU benchmark', 'desc' => 'Multi-thread synthetic score (Cinebench-class workflow)', 'replaces' => ['Cinebench', 'CPU-Z Benchmark', 'Linpack Xtreme']],
            ['id' => 'memory', 'label' => 'Memory bandwidth', 'desc' => 'RAM throughput test', 'replaces' => ['PassMark RAM', 'AIDA64 Cache & Memory']],
            ['id' => 'storage', 'label' => 'Storage benchmark', 'desc' => 'Sequential read/write on system drive', 'replaces' => ['CrystalDiskMark', 'DiskSpd', 'AS SSD Benchmark']],
        ];
    }

    /** @return list<array{id: string, label: string, desc: string, replaces: list<string>}> */
    public function runnableStress(): array
    {
        return [
            ['id' => 'cpu', 'label' => 'CPU stress', 'desc' => 'All-core thermal soak with telemetry', 'replaces' => ['Prime95', 'OCCT', 'AIDA64']],
            ['id' => 'memory', 'label' => 'Memory stress', 'desc' => 'In-OS RAM pressure test', 'replaces' => ['TestMem5', 'HCI MemTest', 'MemTest64']],
        ];
    }

    /**
     * Capabilities grid for live dashboard — one card per category summary.
     *
     * @return list<array<string, mixed>>
     */
    public function capabilitiesSummary(): array
    {
        $byCat = [];
        foreach ($this->tools() as $tool) {
            $cat = (string) ($tool['category'] ?? 'system');
            if (!isset($byCat[$cat])) {
                $byCat[$cat] = ['count' => 0, 'live' => 0, 'names' => []];
            }
            $byCat[$cat]['count']++;
            if (($tool['coverage'] ?? '') === 'live') {
                $byCat[$cat]['live']++;
            }
            if (count($byCat[$cat]['names']) < 4) {
                $byCat[$cat]['names'][] = $tool['name'];
            }
        }

        $labels = $this->categories();
        $out = [];
        foreach ($byCat as $key => $row) {
            $out[] = [
                'id' => $key,
                'category' => $labels[$key] ?? $key,
                'tool_count' => $row['count'],
                'live_count' => $row['live'],
                'examples' => $row['names'],
                'replaced' => true,
            ];
        }

        return $out;
    }

    /** @return list<array<string, mixed>> */
    public function proToolsLegacy(): array
    {
        $priority = ['hwinfo', 'cpuz', 'gpuz', 'occt', 'prime95', 'aida64', 'memtest86', '3dmark', 'furmark', 'crystaldiskmark', 'openrgb', 'signalrgb', 'presentmon'];
        $map = [];
        foreach ($this->tools() as $tool) {
            $map[$tool['id']] = $tool;
        }
        $out = [];
        foreach ($priority as $id) {
            if (!isset($map[$id])) {
                continue;
            }
            $t = $map[$id];
            $out[] = [
                'id' => $id,
                'name' => $t['name'],
                'category' => $t['category'],
                'desc' => $t['pcverse'] ?? '',
            ];
        }

        return $out;
    }
}
