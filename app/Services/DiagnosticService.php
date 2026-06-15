<?php

declare(strict_types=1);

namespace App\Services;

/**
 * PCVerse Diagnostic Lab — lite web scan + full hardware report analysis.
 */
class DiagnosticService
{
    private array $config;
    /** @var list<array>|null */
    private ?array $games = null;

    public function __construct(
        private ?BenchmarkDatasetService $benchmark = null,
        private ?BenchmarkService $benchAnalyze = null,
    ) {
        $this->benchmark = $benchmark ?? new BenchmarkDatasetService();
        $this->benchAnalyze = $benchAnalyze ?? new BenchmarkService($this->benchmark);
        $this->config = require dirname(__DIR__, 2) . '/config/diagnostic.php';
    }

    public function getConfig(): array
    {
        return $this->config;
    }

    /** @return array{games: list<array>, total: int, page: int, per_page: int} */
    public function searchGames(string $q = '', int $page = 1, int $perPage = 40): array
    {
        $all = $this->loadGames();
        if ($q !== '') {
            $needle = mb_strtolower($q);
            $all = array_values(array_filter($all, fn ($g) => str_contains(mb_strtolower($g['name']), $needle)));
        }
        $total = count($all);
        $offset = max(0, ($page - 1) * $perPage);

        return [
            'games' => array_slice($all, $offset, $perPage),
            'total' => $total,
            'page' => $page,
            'per_page' => $perPage,
        ];
    }

    /** @param array<string, mixed> $answers */
    public function analyzeLite(array $answers): array
    {
        $flags = $this->scoreLiteAnswers($answers);
        $health = max(15, min(98, 100 - array_sum($flags['penalties'])));

        $issues = $this->issuesFromFlags($flags, $answers);
        $bottleneck = $this->inferLiteBottleneck($answers, $flags);
        $upgrades = $this->suggestUpgrades($bottleneck['component'] ?? 'gpu', $answers);

        return [
            'mode' => 'lite',
            'health_score' => $health,
            'health_grade' => $this->grade($health),
            'flags' => $flags,
            'issues' => $issues,
            'bottleneck' => $bottleneck,
            'upgrade_suggestions' => $upgrades,
            'needs_full_scan' => true,
            'full_scan_reason' => 'For real temps, voltage, frametime, battery health, and sensors, run a full scan with PCVerse Probe.',
            'app_download' => $this->appDownloadForUserAgent($answers['user_agent'] ?? ''),
        ];
    }

    /**
     * Normalize agent probe + merge optional HWiNFO/CapFrameX imports before analysis.
     *
     * @param array<string, mixed> $report
     * @return array<string, mixed>
     */
    public function prepareFullReport(array $report): array
    {
        $agentSvc = new DiagnosticAgentService();
        $importSvc = new DiagnosticImportService();

        if (($report['probe_version'] ?? 0) >= 2 || ($report['agent'] ?? '') === 'pcverse-probe') {
            $report = $agentSvc->normalize($report);
        }

        if (!empty($report['agent_report']) && is_array($report['agent_report'])) {
            $report = $this->mergeFullReports($report, $agentSvc->normalize($report['agent_report']));
            unset($report['agent_report']);
        }

        foreach ((array) ($report['imports'] ?? []) as $imp) {
            if (!is_array($imp)) {
                continue;
            }
            $report = $this->mergeImportData(
                $report,
                $importSvc->parse((string) ($imp['format'] ?? ''), (string) ($imp['content'] ?? ''))
            );
        }

        if (!empty($report['import_format']) && !empty($report['import_content'])) {
            $report = $this->mergeImportData(
                $report,
                $importSvc->parse((string) $report['import_format'], (string) $report['import_content'])
            );
            unset($report['import_format'], $report['import_content']);
        }

        $nvidia = (array) ($report['nvidia_smi'] ?? []);
        if ($nvidia !== []) {
            $gaming = (array) ($report['gaming'] ?? []);
            if (empty($gaming['gpu_util_avg']) && isset($nvidia['gpu_util_pct'])) {
                $gaming['gpu_util_avg'] = (float) $nvidia['gpu_util_pct'];
            }
            if (empty($gaming['gpu_mem_util_avg']) && isset($nvidia['mem_util_pct'])) {
                $gaming['gpu_mem_util_avg'] = (float) $nvidia['mem_util_pct'];
            }
            $report['gaming'] = $gaming;
        }

        return $report;
    }

    /** @param array<string, mixed> $report Full payload from Flutter / Windows agent */
    public function analyzeFull(array $report): array
    {
        $report = $this->prepareFullReport($report);
        $normalized = $this->normalizeFullReport($report);
        $metrics = $this->extractMetrics($normalized);
        $health = $this->healthFromMetrics($metrics);
        $bottleneck = $this->bottleneckFromMetrics($metrics);
        $risks = $this->thermalAndStabilityRisks($normalized, $metrics);
        $upgrades = $this->suggestUpgradesFromMetrics($bottleneck, $metrics, $normalized);

        $gameIds = array_slice((array) ($report['selected_games'] ?? []), 0, 20);
        $gameSettings = $this->predictGameSettings($metrics, $gameIds);

        $result = [
            'mode' => 'full',
            'health_score' => $health,
            'health_grade' => $this->grade($health),
            'metrics' => $metrics,
            'bottleneck' => $bottleneck,
            'risks' => $risks,
            'upgrade_suggestions' => $upgrades,
            'game_settings' => $gameSettings,
            'report_summary' => $this->buildReportSummary($normalized),
        ];

        $result['vakhsh_oc'] = (new DiagnosticOcService())->buildPlan($report, $result);

        return $result;
    }

    /** @param list<string> $gameIds */
    public function predictGameSettings(array $metrics, array $gameIds): array
    {
        $gpuScore = (int) ($metrics['gpu_score'] ?? 0);
        $cpuScore = (int) ($metrics['cpu_score'] ?? 0);
        $vramGb = (float) ($metrics['vram_gb'] ?? 0);
        $ramGb = (int) ($metrics['ram_gb'] ?? 16);

        $out = [];
        foreach ($gameIds as $gid) {
            $game = $this->gameById((string) $gid);
            if (!$game) {
                continue;
            }

            $tier = (string) ($game['tier'] ?? 'mid');
            $needVram = (int) ($game['min_vram_gb'] ?? 4);
            $gpuDemand = (int) ($game['gpu_demand'] ?? 60);
            $cpuDemand = (int) ($game['cpu_demand'] ?? 50);

            $gpuOk = $gpuScore >= $gpuDemand * 50 || $gpuScore >= 8000;
            $cpuOk = $cpuScore >= $cpuDemand * 40 || $cpuScore >= 6000;
            $vramOk = $vramGb >= $needVram;

            $resolution = '1080p';
            $preset = 'Medium';
            $fpsTarget = '60';
            $notes = [];

            if (!$vramOk) {
                $notes[] = 'VRAM below recommended — use lower texture settings';
                $preset = 'Low';
            }

            if ($gpuOk && $cpuOk && $vramOk && $tier !== 'ultra') {
                $resolution = $gpuScore >= 15000 ? '1440p' : '1080p';
                $preset = $gpuScore >= 12000 ? 'Ultra' : 'High';
                $fpsTarget = $gpuScore >= 18000 ? '120+' : '60-90';
            } elseif ($gpuOk && !$cpuOk) {
                $preset = 'High';
                $notes[] = 'Possible CPU bottleneck — reduce CPU-heavy preset settings';
            } elseif (!$gpuOk) {
                $preset = 'Low';
                $fpsTarget = '30-45';
                $notes[] = 'GPU is the main limiter';
            }

            if ($ramGb < 16 && $tier === 'ultra') {
                $notes[] = '16GB+ RAM recommended for this title';
            }

            $out[] = [
                'game_id' => $game['id'],
                'game_name' => $game['name'],
                'recommended' => [
                    'resolution' => $resolution,
                    'preset' => $preset,
                    'fps_target' => $fpsTarget,
                    'dlss_fsr' => $gpuScore < 10000 ? 'Quality / FSR Quality' : 'Off or Quality',
                    'ray_tracing' => ($gpuScore >= 20000 && $vramGb >= 10) ? 'Medium' : 'Off',
                ],
                'notes' => $notes,
            ];
        }

        return $out;
    }

    // --- Lite scoring ---

    /** @param array<string, mixed> $answers */
    private function scoreLiteAnswers(array $answers): array
    {
        $penalties = [
            'thermal' => 0, 'stability' => 0, 'storage' => 0, 'ram_stress' => 0,
            'gpu' => 0, 'bottleneck' => 0, 'battery' => 0, 'frametime' => 0, 'psu' => 0,
        ];

        foreach ($this->config['lite_steps'] as $step) {
            foreach ($step['questions'] as $q) {
                $key = $q['id'];
                $val = $answers[$key] ?? null;
                if ($val === null) {
                    continue;
                }
                $values = $q['type'] === 'multi' ? (array) $val : [$val];
                foreach ($q['options'] as $opt) {
                    if (!in_array($opt['value'], $values, true)) {
                        continue;
                    }
                    foreach ($opt['score'] ?? [] as $flag => $pts) {
                        $penalties[$flag] = ($penalties[$flag] ?? 0) + (int) $pts * 4;
                    }
                }
            }
        }

        return ['penalties' => $penalties];
    }

    /** @param array<string, mixed> $answers */
    private function inferLiteBottleneck(array $answers, array $flags): array
    {
        $gpuTier = (string) ($answers['gpu_tier'] ?? 'mid');
        $use = (string) ($answers['primary_use'] ?? 'mixed');
        $p = $flags['penalties'];

        if ($use === 'gaming' && in_array($gpuTier, ['igpu', 'mid'], true)) {
            return ['type' => 'gpu', 'component' => 'gpu', 'confidence' => 'medium', 'message' => 'For gaming, the GPU is likely the limiting factor.'];
        }
        if (($p['cpu_stress'] ?? 0) > ($p['gpu'] ?? 0) && $use === 'workstation') {
            return ['type' => 'cpu', 'component' => 'cpu', 'confidence' => 'medium', 'message' => 'For render/AI workloads, CPU or RAM may be the bottleneck.'];
        }
        if (($p['storage'] ?? 0) >= 8) {
            return ['type' => 'storage', 'component' => 'storage', 'confidence' => 'high', 'message' => 'A system HDD can slow boot and loading.'];
        }
        if (($p['ram_stress'] ?? 0) >= 8) {
            return ['type' => 'ram', 'component' => 'memory', 'confidence' => 'high', 'message' => 'Low RAM causes stutter and crashes in modern games.'];
        }

        return ['type' => 'balanced', 'component' => 'gpu', 'confidence' => 'low', 'message' => 'Run a full probe scan for accurate frametime and core usage.'];
    }

    /** @return list<array{title_fa: string, severity: string, detail_fa: string}> */
    private function issuesFromFlags(array $flags, array $answers): array
    {
        $issues = [];
        $p = $flags['penalties'];
        if (($p['thermal'] ?? 0) > 0) {
            $issues[] = ['title' => 'Heat / fans', 'severity' => 'high', 'detail' => 'Check thermal paste, dust, fan curves, or throttling in a full probe scan.'];
        }
        if (($p['stability'] ?? 0) > 0) {
            $issues[] = ['title' => 'Stability', 'severity' => 'critical', 'detail' => 'PSU, RAM, or unstable OC — run OCCT/MemTest via Probe.'];
        }
        if (($answers['form_factor'] ?? '') === 'laptop' && ($p['battery'] ?? 0) > 0) {
            $issues[] = ['title' => 'Laptop battery', 'severity' => 'medium', 'detail' => 'Battery health and power limits need a full probe scan.'];
        }
        if (($p['frametime'] ?? 0) > 0) {
            $issues[] = ['title' => 'Stutter', 'severity' => 'medium', 'detail' => '1% lows and frametime spikes matter more than average FPS — PresentMon/CapFrameX import supported.'];
        }

        return $issues;
    }

    private function suggestUpgrades(string $categorySlug, array $answers, ?string $reason = null): array
    {
        return [];
    }

    // --- Full report ---

    /** @param array<string, mixed> $report */
    private function normalizeFullReport(array $report): array
    {
        $gpu = (array) ($report['gpu'] ?? []);
        $nvidia = (array) ($report['nvidia_smi'] ?? []);
        if (empty($gpu['hotspot_max']) && isset($nvidia['temp_c'])) {
            $gpu['hotspot_max'] = $nvidia['temp_c'];
        }

        return [
            'device' => (array) ($report['device'] ?? []),
            'cpu' => (array) ($report['cpu'] ?? []),
            'gpu' => $gpu,
            'ram' => (array) ($report['ram'] ?? []),
            'storage' => (array) ($report['storage'] ?? []),
            'motherboard' => (array) ($report['motherboard'] ?? []),
            'psu' => (array) ($report['psu'] ?? []),
            'network' => (array) ($report['network'] ?? []),
            'battery' => (array) ($report['battery'] ?? []),
            'sensors' => (array) ($report['sensors'] ?? []),
            'gaming' => (array) ($report['gaming'] ?? []),
            'peripherals' => (array) ($report['peripherals'] ?? []),
            'nvidia_smi' => $nvidia,
            'probe_version' => (int) ($report['probe_version'] ?? 0),
        ];
    }

    /** @param array<string, mixed> $base @param array<string, mixed> $overlay */
    private function mergeFullReports(array $base, array $overlay): array
    {
        foreach (['device', 'cpu', 'gpu', 'ram', 'storage', 'battery', 'network', 'sensors', 'gaming', 'motherboard', 'psu', 'nvidia_smi'] as $key) {
            if (empty($overlay[$key]) || !is_array($overlay[$key])) {
                continue;
            }
            $base[$key] = array_merge((array) ($base[$key] ?? []), $overlay[$key]);
        }

        return $base;
    }

    /** @param array<string, mixed> $report @param array{gaming?: array, sensors?: array, ram?: array, geek?: array} $parsed */
    private function mergeImportData(array $report, array $parsed): array
    {
        if (!empty($parsed['gaming'])) {
            $existing = (array) ($report['gaming'] ?? []);
            $incoming = $parsed['gaming'];
            if (!empty($existing['spike_map']) && empty($incoming['spike_map'])) {
                unset($incoming['spike_map']);
            }
            $report['gaming'] = array_merge($existing, $incoming);
        }
        if (!empty($parsed['sensors'])) {
            $report['sensors'] = array_merge((array) ($report['sensors'] ?? []), $parsed['sensors']);
        }
        if (!empty($parsed['ram'])) {
            $ram = (array) ($report['ram'] ?? []);
            $importRam = $parsed['ram'];
            if (!empty($importRam['modules'])) {
                $ram['modules'] = $this->mergeRamModules((array) ($ram['modules'] ?? []), $importRam['modules']);
            }
            foreach (['primary_timings', 'primary_die', 'spd_source'] as $k) {
                if (!empty($importRam[$k])) {
                    $ram[$k] = $importRam[$k];
                }
            }
            $report['ram'] = $ram;
        }
        if (!empty($parsed['geek'])) {
            $tel = (array) ($report['telemetry'] ?? []);
            $tel['geek'] = array_merge((array) ($tel['geek'] ?? []), $parsed['geek']);
            $report['telemetry'] = $tel;
            $report['geek'] = array_merge((array) ($report['geek'] ?? []), $parsed['geek']);
        }
        if (!empty($parsed['source'])) {
            $report['import_sources'] = array_values(array_unique(array_merge(
                (array) ($report['import_sources'] ?? []),
                [$parsed['source']]
            )));
        }

        return $report;
    }

    /** @param list<array<string, mixed>> $existing @param list<array<string, mixed>> $imported @return list<array<string, mixed>> */
    private function mergeRamModules(array $existing, array $imported): array
    {
        if ($existing === []) {
            return $imported;
        }
        foreach ($imported as $i => $mod) {
            if (!isset($existing[$i])) {
                $existing[$i] = $mod;
                continue;
            }
            if (!empty($mod['timings'])) {
                $existing[$i]['timings'] = $mod['timings'];
            }
            if (!empty($mod['die_type']) && ($mod['die_type'] ?? '') !== 'Unknown') {
                $existing[$i]['die_type'] = $mod['die_type'];
            }
            if (!empty($mod['part_number'])) {
                $existing[$i]['part_number'] = $mod['part_number'];
            }
        }

        return $existing;
    }

    /** @param array<string, mixed> $normalized */
    private function extractMetrics(array $normalized): array
    {
        $cpu = $normalized['cpu'];
        $gpu = $normalized['gpu'];
        $ram = $normalized['ram'];
        $gaming = $normalized['gaming'];

        $cpuScore = (int) ($cpu['benchmark_score'] ?? 0);
        $gpuScore = (int) ($gpu['benchmark_score'] ?? 0);

        if ($cpuScore <= 0 && !empty($cpu['model'])) {
            $match = $this->benchmark->matchPart(['category_slug' => 'cpu', 'model' => $cpu['model'], 'name_fa' => $cpu['model']]);
            $cpuScore = (int) ($match['primary_score'] ?? $match['mark'] ?? 0);
        }
        if ($gpuScore <= 0 && !empty($gpu['model'])) {
            $match = $this->benchmark->matchPart(['category_slug' => 'gpu', 'model' => $gpu['model'], 'name_fa' => $gpu['model']]);
            $gpuScore = (int) ($match['primary_score'] ?? $match['mark'] ?? 0);
        }

        return [
            'cpu_score' => $cpuScore,
            'gpu_score' => $gpuScore,
            'ram_gb' => (int) ($ram['total_gb'] ?? $ram['capacity_gb'] ?? 0),
            'vram_gb' => (float) ($gpu['vram_gb'] ?? 0),
            'gpu_util_avg' => (float) ($gaming['gpu_util_avg'] ?? 0),
            'cpu_core_max' => (float) ($gaming['cpu_core_max_pct'] ?? 0),
            'frametime_p99_ms' => (float) ($gaming['frametime_p99_ms'] ?? 0),
            'frametime_variance' => (float) ($gaming['frametime_variance'] ?? 0),
            'spike_count' => (int) ($gaming['spike_count'] ?? ($gaming['spike_map']['stats']['spike_count'] ?? 0)),
            'cpu_temp_max' => (float) ($normalized['sensors']['cpu_temp_max'] ?? $cpu['temp_max'] ?? 0),
            'gpu_temp_max' => (float) ($normalized['sensors']['gpu_temp_max'] ?? $gpu['temp_max'] ?? 0),
            'gpu_hotspot_max' => (float) ($gpu['hotspot_max'] ?? 0),
            'battery_health_pct' => (float) ($normalized['battery']['health_percent'] ?? 0),
            'throttle_events' => (int) ($normalized['sensors']['throttle_count'] ?? 0),
            'lan_link_mbps' => (int) ($normalized['network']['lan_speed_mbps'] ?? 0),
            'wifi_standard' => (string) ($normalized['network']['wifi_standard'] ?? ''),
        ];
    }

    private function healthFromMetrics(array $m): int
    {
        $score = 92;
        if ($m['cpu_temp_max'] > 90) {
            $score -= 15;
        } elseif ($m['cpu_temp_max'] > 80) {
            $score -= 8;
        }
        if ($m['gpu_hotspot_max'] > 95 || $m['gpu_temp_max'] > 88) {
            $score -= 12;
        }
        if ($m['frametime_variance'] > 4 || $m['frametime_p99_ms'] > 25) {
            $score -= 10;
        }
        if ($m['throttle_events'] > 0) {
            $score -= 12;
        }
        if ($m['battery_health_pct'] > 0 && $m['battery_health_pct'] < 70) {
            $score -= 10;
        }
        if ($m['ram_gb'] > 0 && $m['ram_gb'] < 16) {
            $score -= 6;
        }

        return max(20, min(99, $score));
    }

    private function bottleneckFromMetrics(array $m): array
    {
        $gpuUtil = $m['gpu_util_avg'];
        $cpuCore = $m['cpu_core_max'];

        if ($gpuUtil >= 95 && $cpuCore < 85) {
            return ['type' => 'gpu', 'component' => 'gpu', 'confidence' => 'high', 'message' => 'GPU at ~99% — primary limiter.'];
        }
        if ($cpuCore >= 95 && $gpuUtil < 70) {
            return ['type' => 'cpu', 'component' => 'cpu', 'confidence' => 'high', 'message' => 'A CPU core is saturated — CPU bottleneck.'];
        }
        if ($m['frametime_variance'] > 3) {
            return ['type' => 'frametime', 'component' => 'memory', 'confidence' => 'medium', 'message' => 'Unstable frametime — check RAM, drivers, or asset streaming.'];
        }
        if ($m['vram_gb'] > 0 && $m['vram_gb'] < 8) {
            return ['type' => 'vram', 'component' => 'gpu', 'confidence' => 'medium', 'message' => 'Limited VRAM — lower textures and ray tracing.'];
        }

        return ['type' => 'balanced', 'component' => 'gpu', 'confidence' => 'low', 'message' => 'System looks fairly balanced — stress a heavy game for more detail.'];
    }

    /** @return list<array> */
    private function thermalAndStabilityRisks(array $normalized, array $m): array
    {
        $risks = [];
        if ($m['cpu_temp_max'] > 90) {
            $risks[] = ['code' => 'cpu_thermal', 'severity' => 'critical', 'message' => 'Dangerous CPU temperature — repaste, fans, or power limits.'];
        }
        if ($m['gpu_hotspot_max'] > 100) {
            $risks[] = ['code' => 'gpu_hotspot', 'severity' => 'critical', 'message' => 'GPU hotspot too high — undervolt or repaste.'];
        }
        if ($m['throttle_events'] > 0) {
            $risks[] = ['code' => 'throttle', 'severity' => 'high', 'message' => 'Thermal or power throttling detected.'];
        }
        if (!empty($normalized['psu']['wattage']) && (int) $normalized['psu']['wattage'] < 550 && $m['gpu_score'] > 12000) {
            $risks[] = ['code' => 'psu_headroom', 'severity' => 'high', 'message' => 'PSU may be undersized for this GPU.'];
        }

        return $risks;
    }

    private function suggestUpgradesFromMetrics(array $bottleneck, array $m, array $normalized): array
    {
        return [];
    }

    private function buildReportSummary(array $normalized): array
    {
        return [
            'cpu' => $normalized['cpu']['model'] ?? null,
            'gpu' => $normalized['gpu']['model'] ?? null,
            'ram_gb' => $normalized['ram']['total_gb'] ?? null,
            'is_laptop' => ($normalized['device']['form_factor'] ?? '') === 'laptop',
        ];
    }

    private function grade(int $score): string
    {
        return match (true) {
            $score >= 90 => 'A',
            $score >= 75 => 'B',
            $score >= 60 => 'C',
            $score >= 45 => 'D',
            default => 'F',
        };
    }

    private function appDownloadForUserAgent(string $ua): array
    {
        $probe = (string) ($this->config['windows_agent']['download_url'] ?? '/download/pcverse-windows-x64');

        return [
            'platform' => 'windows',
            'url' => $probe,
            'download_url' => $probe,
            'label' => 'Download PCVerse Probe',
        ];
    }

    /** @return list<array> */
    public function loadGames(): array
    {
        if ($this->games !== null) {
            return $this->games;
        }

        return $this->games = (new DiagnosticGameCatalogService())->loadGames();
    }

    private function gameById(string $id): ?array
    {
        foreach ($this->loadGames() as $g) {
            if (($g['id'] ?? '') === $id) {
                return $g;
            }
        }

        return null;
    }
}
