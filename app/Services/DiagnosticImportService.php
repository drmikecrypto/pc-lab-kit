<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Merge HWiNFO / CapFrameX / CPU-Z / MSI Afterburner exports into diagnostic data.
 */
class DiagnosticImportService
{
    /**
     * @return array{gaming: array, sensors: array, ram?: array, geek?: array, source: string}
     */
    public function parse(string $format, string $content): array
    {
        $format = strtolower(trim($format));

        return match ($format) {
            'hwinfo_csv', 'hwinfo' => $this->parseHwinfoCsv($content),
            'capframex_json', 'capframex' => $this->parseCapFrameXJson($content),
            'frametime_csv' => $this->parseFrametimeCsv($content),
            'cpuz_txt', 'cpuz' => $this->parseCpuZTxt($content),
            default => ['gaming' => [], 'sensors' => [], 'source' => 'unknown'],
        };
    }

    /** @return array{gaming: array, sensors: array, ram?: array, geek?: array, source: string} */
    public function parseHwinfoCsv(string $content): array
    {
        $lines = preg_split('/\r\n|\n|\r/', trim($content)) ?: [];
        if (count($lines) < 2) {
            return ['gaming' => [], 'sensors' => [], 'source' => 'hwinfo_csv'];
        }

        $headers = str_getcsv($lines[0]);
        $headerLower = array_map('strtolower', $headers);
        $isWide = count($headers) > 4 && (str_contains($headerLower[0] ?? '', 'date') || str_contains($headerLower[1] ?? '', 'time'));

        if ($isWide) {
            return $this->parseHwinfoWideCsv($lines, $headers, $headerLower);
        }

        return $this->parseHwinfoLabelCsv($lines);
    }

    /**
     * HWiNFO sensor log — columns per sensor.
     *
     * @param list<string> $lines
     * @param list<string> $headers
     * @param list<string> $headerLower
     * @return array{gaming: array, sensors: array, ram?: array, geek?: array, source: string}
     */
    private function parseHwinfoWideCsv(array $lines, array $headers, array $headerLower): array
    {
        $gaming = [
            'gpu_util_samples' => [],
            'cpu_util_samples' => [],
            'frametime_samples' => [],
            'fps_samples' => [],
        ];
        $sensors = [
            'gpu_temp_samples' => [],
            'cpu_temp_samples' => [],
            'cpu_package_temp_samples' => [],
        ];
        $cstateCols = [];
        $ramCols = [];

        foreach ($headerLower as $i => $h) {
            if (preg_match('/\bc[0-7]\b|cc[0-7]|c-state|c state|core c[0-7]/i', $h)) {
                $cstateCols[$i] = $this->normalizeCstateLabel($h);
            }
            if (preg_match('/cas|tcl|cl\b|trcd|trp|tras|tRFC|memory.*timing|dram/i', $h)) {
                $ramCols[$i] = $h;
            }
        }

        $cstateSamples = [];

        for ($rowIdx = 1; $rowIdx < count($lines); $rowIdx++) {
            $row = str_getcsv($lines[$rowIdx]);
            foreach ($headerLower as $i => $h) {
                $val = $this->cellNumeric($row[$i] ?? null);
                if ($val === null) {
                    continue;
                }

                if (str_contains($h, 'gpu') && (str_contains($h, 'usage') || str_contains($h, 'util'))) {
                    $gaming['gpu_util_samples'][] = $val;
                }
                if (str_contains($h, 'cpu') && (str_contains($h, 'usage') || str_contains($h, 'util')) && !str_contains($h, 'package')) {
                    $gaming['cpu_util_samples'][] = $val;
                }
                if (str_contains($h, 'gpu') && str_contains($h, 'temp')) {
                    $sensors['gpu_temp_samples'][] = $val;
                }
                if (str_contains($h, 'cpu') && str_contains($h, 'temp') && !str_contains($h, 'package')) {
                    $sensors['cpu_temp_samples'][] = $val;
                }
                if (str_contains($h, 'cpu package') || str_contains($h, 'cpu (tctl') || str_contains($h, 'cpu die')) {
                    $sensors['cpu_package_temp_samples'][] = $val;
                }
                if (str_contains($h, 'frametime') || str_contains($h, 'frame time')) {
                    $gaming['frametime_samples'][] = $val;
                }
                if (str_contains($h, 'fps') || str_contains($h, 'framerate')) {
                    $gaming['fps_samples'][] = $val;
                }
                if (isset($cstateCols[$i])) {
                    $state = $cstateCols[$i];
                    $cstateSamples[$state][] = $val;
                }
            }
        }

        $geek = $this->finalizeCstateStats($cstateSamples);
        $ram = $this->finalizeRamFromHwinfoHeaders($headerLower, $lines);

        return [
            'gaming' => $this->finalizeGamingStats($gaming),
            'sensors' => $this->finalizeSensorStats($sensors),
            'geek' => $geek,
            'ram' => $ram,
            'source' => 'hwinfo_csv',
        ];
    }

    /** @param list<string> $lines @return array{gaming: array, sensors: array, source: string} */
    private function parseHwinfoLabelCsv(array $lines): array
    {
        $gaming = [];
        $sensors = ['samples' => []];
        $cstateSamples = [];

        for ($i = 1; $i < count($lines); $i++) {
            $row = str_getcsv($lines[$i]);
            if (count($row) < 2) {
                continue;
            }
            $label = strtolower(trim($row[0] ?? ''));
            $val = $this->lastNumeric($row);

            if (str_contains($label, 'gpu') && str_contains($label, 'usage')) {
                $gaming['gpu_util_samples'][] = $val;
            }
            if (str_contains($label, 'cpu') && (str_contains($label, 'usage') || str_contains($label, 'util'))) {
                $gaming['cpu_util_samples'][] = $val;
            }
            if (str_contains($label, 'gpu') && str_contains($label, 'temp')) {
                $sensors['gpu_temp_samples'][] = $val;
            }
            if (str_contains($label, 'cpu') && str_contains($label, 'temp') && !str_contains($label, 'package')) {
                $sensors['cpu_temp_samples'][] = $val;
            }
            if (str_contains($label, 'cpu package') || str_contains($label, 'cpu (tctl')) {
                $sensors['cpu_package_temp_samples'][] = $val;
            }
            if (str_contains($label, 'frametime') || str_contains($label, 'frame time')) {
                $gaming['frametime_samples'][] = $val;
            }
            if (str_contains($label, 'fps') || str_contains($label, 'framerate')) {
                $gaming['fps_samples'][] = $val;
            }
            if (preg_match('/\bc[0-7]\b|cc[0-7]|c-state|c state residency/i', $label)) {
                $state = $this->normalizeCstateLabel($label);
                $cstateSamples[$state][] = $val;
            }
            if (preg_match('/\bcas\b|\bcl\b|trcd|trp|tras/i', $label)) {
                $gaming['ram_timing_labels'][$label] = $val;
            }
        }

        $out = [
            'gaming' => $this->finalizeGamingStats($gaming),
            'sensors' => $this->finalizeSensorStats($sensors),
            'source' => 'hwinfo_csv',
        ];
        $geek = $this->finalizeCstateStats($cstateSamples);
        if ($geek !== []) {
            $out['geek'] = $geek;
        }

        return $out;
    }

    /** @return array{gaming: array, sensors: array, ram?: array, source: string} */
    public function parseCapFrameXJson(string $content): array
    {
        $data = json_decode($content, true);
        if (!is_array($data)) {
            return ['gaming' => [], 'sensors' => [], 'source' => 'capframex'];
        }

        $gaming = [];
        $samples = [];
        $timestamps = [];

        if (isset($data['Runs'][0])) {
            $run = $data['Runs'][0];
            $m = $run['Metrics'] ?? [];
            $gaming['fps_avg'] = $m['AvgFps'] ?? $m['AverageFPS'] ?? null;
            $gaming['fps_1pct_low'] = $m['Fps1PctLow'] ?? $m['OnePercentLow'] ?? null;
            $gaming['frametime_p99_ms'] = $m['FrametimeP99'] ?? null;
            $gaming['frametime_variance'] = $m['FrametimeVariance'] ?? null;

            $cap = $run['CaptureData'] ?? $run['CapturedData'] ?? [];
            foreach (['Frametime', 'Frametimes', 'FrameTimes', 'MsBetweenPresents'] as $key) {
                if (!empty($cap[$key]) && is_array($cap[$key])) {
                    $samples = array_map('floatval', $cap[$key]);
                    break;
                }
            }
            if ($samples === [] && !empty($m['FrametimeSeries'])) {
                $samples = array_map('floatval', $m['FrametimeSeries']);
            }
            if (!empty($cap['FrametimeTime'])) {
                $timestamps = array_map('floatval', $cap['FrametimeTime']);
            }
        } elseif (isset($data['fps']) || isset($data['frametime'])) {
            $gaming = array_merge($gaming, array_filter([
                'fps_avg' => $data['fps']['avg'] ?? $data['average_fps'] ?? null,
                'fps_1pct_low' => $data['fps']['1pct_low'] ?? null,
                'frametime_p99_ms' => $data['frametime']['p99'] ?? null,
            ]));
            if (!empty($data['frametime']) && is_array($data['frametime']) && !isset($data['frametime']['p99'])) {
                $samples = array_map('floatval', $data['frametime']);
            }
        }

        if ($samples !== []) {
            $map = $this->buildSpikeMap($samples, $timestamps);
            $gaming = array_merge($gaming, [
                'frametime_p99_ms' => $gaming['frametime_p99_ms'] ?? $map['stats']['p99_ms'],
                'frametime_mean_ms' => $map['stats']['mean_ms'],
                'spike_count' => $map['stats']['spike_count'],
                'spike_map' => $map,
                'samples' => count($samples),
            ]);
        }

        return ['gaming' => $gaming, 'sensors' => [], 'source' => 'capframex'];
    }

    /** @return array{gaming: array, sensors: array, ram: array, source: string} */
    public function parseCpuZTxt(string $content): array
    {
        $modules = [];
        $blocks = preg_split('/(?=Memory Slot #|SPD slot #|DIMM #)/i', $content) ?: [];

        foreach ($blocks as $block) {
            if (!preg_match('/Memory|SPD|DIMM|Module Size/i', $block)) {
                continue;
            }
            $mod = [];
            if (preg_match('/#\s*(\d+)/', $block, $m)) {
                $mod['slot'] = $m[1];
            }
            if (preg_match('/Module Manufacturer\s+(.+)/i', $block, $m)) {
                $mod['manufacturer'] = trim($m[1]);
            }
            if (preg_match('/(?:Part Number|Module Part Number)\s+(.+)/i', $block, $m)) {
                $mod['part_number'] = trim($m[1]);
            }
            if (preg_match('/@\s*(\d+)\s*MHz\s+(\d+)-(\d+)-(\d+)-(\d+)\s+([\d.]+)\s*V/i', $block, $m)) {
                $mod['timings'] = [
                    'frequency_mhz' => (int) $m[1],
                    'cl' => (int) $m[2],
                    'trcd' => (int) $m[3],
                    'trp' => (int) $m[4],
                    'tras' => (int) $m[5],
                    'voltage' => (float) $m[6],
                ];
            }
            if ($mod !== []) {
                $pn = (string) ($mod['part_number'] ?? '');
                $die = $this->resolveRamDieType($pn);
                $mod['die_type'] = $die['die_type'];
                $mod['die_confidence'] = $die['confidence'];
                $modules[] = $mod;
            }
        }

        $primary = $modules[0] ?? [];
        return [
            'gaming' => [],
            'sensors' => [],
            'ram' => [
                'modules' => $modules,
                'primary_timings' => $primary['timings'] ?? null,
                'primary_die' => $primary['die_type'] ?? null,
                'spd_source' => 'cpuz_txt',
            ],
            'source' => 'cpuz_txt',
        ];
    }

    /** @return array{gaming: array, sensors: array, source: string} */
    public function parseFrametimeCsv(string $content): array
    {
        $lines = preg_split('/\r\n|\n|\r/', trim($content)) ?: [];
        $samples = [];
        $timestamps = [];
        $hasHeader = str_contains(strtolower($lines[0] ?? ''), 'frametime') || str_contains(strtolower($lines[0] ?? ''), 'ms');

        foreach ($lines as $idx => $line) {
            if ($idx === 0 && $hasHeader) {
                continue;
            }
            $cols = str_getcsv($line);
            if (count($cols) >= 2 && is_numeric($cols[0]) && is_numeric($cols[1])) {
                $timestamps[] = (float) $cols[0];
                $samples[] = (float) $cols[1];
            } elseif (preg_match('/([\d.]+)/', $line, $m)) {
                $samples[] = (float) $m[1];
            }
        }

        $map = $this->buildSpikeMap($samples, $timestamps);
        $gaming = array_merge($this->finalizeGamingStats(['frametime_samples' => $samples]), [
            'spike_map' => $map,
            'spike_count' => $map['stats']['spike_count'],
            'frametime_mean_ms' => $map['stats']['mean_ms'],
            'samples' => count($samples),
        ]);

        return [
            'gaming' => $gaming,
            'sensors' => [],
            'source' => 'frametime_csv',
        ];
    }

    /**
     * @param list<float> $samples
     * @param list<float> $timestampsMs
     * @return array{available: bool, spikes: list<array>, series: list<array>, stats: array}
     */
    public function buildSpikeMap(array $samples, array $timestampsMs = [], float $spikeThresholdMs = 25.0, int $maxSpikes = 40, int $maxSeries = 600): array
    {
        if (count($samples) < 3) {
            return ['available' => false, 'spikes' => [], 'series' => [], 'stats' => []];
        }

        $mean = array_sum($samples) / count($samples);
        $threshold = max($spikeThresholdMs, $mean * 2.5);
        $step = max(1, (int) floor(count($samples) / $maxSeries));

        $spikes = [];
        $series = [];
        $sorted = $samples;
        sort($sorted);
        $p99 = $sorted[(int) floor(count($sorted) * 0.99)] ?? end($sorted);
        $p01 = $sorted[(int) floor(count($sorted) * 0.01)] ?? reset($sorted);

        foreach ($samples as $i => $v) {
            $t = $timestampsMs[$i] ?? ($i * (1000.0 / 60.0));
            if ($i % $step === 0) {
                $series[] = ['t_ms' => round($t, 1), 'ft_ms' => round($v, 2)];
            }
            $prev = $i > 0 ? $samples[$i - 1] : $v;
            $delta = $v - $prev;
            if ($v >= $threshold || $delta >= ($threshold * 0.5)) {
                $severity = $v >= 50 ? 'critical' : ($v >= 35 ? 'high' : 'medium');
                $spikes[] = [
                    'index' => $i,
                    't_ms' => round($t, 1),
                    'ft_ms' => round($v, 2),
                    'delta_ms' => round($delta, 2),
                    'severity' => $severity,
                    'likely_cause' => $v >= 50 ? 'severe_stutter' : ($delta >= 15 ? 'spike_up' : 'frametime_high'),
                ];
            }
        }

        usort($spikes, static fn ($a, $b) => $b['ft_ms'] <=> $a['ft_ms']);
        $spikes = array_slice($spikes, 0, $maxSpikes);
        usort($spikes, static fn ($a, $b) => $a['t_ms'] <=> $b['t_ms']);

        return [
            'available' => true,
            'spikes' => $spikes,
            'series' => $series,
            'stats' => [
                'count' => count($samples),
                'mean_ms' => round($mean, 2),
                'p99_ms' => round((float) $p99, 2),
                'p01_ms' => round((float) $p01, 2),
                'spike_count' => count($spikes),
                'threshold_ms' => round($threshold, 1),
            ],
        ];
    }

    /** @param array<string, list<float>> $cstateSamples @return array<string, mixed> */
    private function finalizeCstateStats(array $cstateSamples): array
    {
        if ($cstateSamples === []) {
            return [];
        }

        $cstates = [];
        $summary = [];
        foreach ($cstateSamples as $state => $vals) {
            if ($vals === []) {
                continue;
            }
            $avg = array_sum($vals) / count($vals);
            $cstates[] = ['state' => $state, 'residency_pct' => round($avg, 2)];
            $summary[$state . '_pct'] = round($avg, 2);
        }

        $deep = 0.0;
        foreach ($cstates as $c) {
            if (preg_match('/C[6-9]|CC6|CC7|Parked/i', $c['state'])) {
                $deep += $c['residency_pct'];
            }
        }

        return [
            'cstates' => $cstates,
            'idle_states' => $cstates,
            'residency_summary' => $summary,
            'deep_idle_pct' => round($deep, 2),
            'cstate_source' => 'hwinfo_import',
        ];
    }

    /** @param list<string> $headerLower @param list<string> $lines @return array<string, mixed> */
    private function finalizeRamFromHwinfoHeaders(array $headerLower, array $lines): array
    {
        $timings = [];
        foreach ($headerLower as $h) {
            if (preg_match('/\bcas\b|\bcl\b/', $h)) {
                $timings['cl'] = $timings['cl'] ?? null;
            }
            if (str_contains($h, 'trcd')) {
                $timings['trcd'] = $timings['trcd'] ?? null;
            }
            if (str_contains($h, 'trp')) {
                $timings['trp'] = $timings['trp'] ?? null;
            }
            if (str_contains($h, 'tras')) {
                $timings['tras'] = $timings['tras'] ?? null;
            }
        }

        if ($timings === [] || count($lines) < 2) {
            return [];
        }

        $row = str_getcsv($lines[1]);
        foreach ($headerLower as $i => $h) {
            $v = $this->cellNumeric($row[$i] ?? null);
            if ($v === null) {
                continue;
            }
            if (preg_match('/\bcas\b|\bcl\b/', $h)) {
                $timings['cl'] = (int) $v;
            }
            if (str_contains($h, 'trcd')) {
                $timings['trcd'] = (int) $v;
            }
            if (str_contains($h, 'trp')) {
                $timings['trp'] = (int) $v;
            }
            if (str_contains($h, 'tras')) {
                $timings['tras'] = (int) $v;
            }
        }

        $timings = array_filter($timings, static fn ($v) => $v !== null);
        if ($timings === []) {
            return [];
        }

        return [
            'primary_timings' => $timings,
            'spd_source' => 'hwinfo_import',
        ];
    }

    /** @return array{die_type: string, confidence: string, vendor_hint?: string} */
    public function resolveRamDieType(string $partNumber): array
    {
        $pn = strtoupper(preg_replace('/\s+/', '', $partNumber) ?? '');
        if ($pn === '') {
            return ['die_type' => 'Unknown', 'confidence' => 'low'];
        }

        $rules = [
            ['re' => '/BCPB|BCPV|BCTD|BCTB|BCRC|BCT0|BCT1|K4AAG085WB|K4A8G085WB|HMA81GU6AFR8N|M378A/', 'die' => 'Samsung B-die', 'vendor' => 'Samsung'],
            ['re' => '/CBCRC|CBCPC|CBCPB|CBCPV|M391A|HMAA1GS6CJR6N/', 'die' => 'Samsung C-die/E-die', 'vendor' => 'Samsung'],
            ['re' => '/F4-3200C14|F4-3600C15|F4-4000C15|F4-4133C19/', 'die' => 'Samsung B-die (G.Skill)', 'vendor' => 'G.Skill'],
            ['re' => '/F4-3600C16|F4-3200C16/', 'die' => 'Hynix C-die / mixed', 'vendor' => 'G.Skill'],
            ['re' => '/HMAA|HMA8|HMA81|HMCG|HMCC/', 'die' => 'SK Hynix', 'vendor' => 'Hynix'],
            ['re' => '/CMW|CMK|CMT|CMH/', 'die' => 'Corsair (bin varies)', 'vendor' => 'Corsair'],
            ['re' => '/BLD|BLT|BL8|BL16/', 'die' => 'Crucial Ballistix', 'vendor' => 'Crucial'],
            ['re' => '/CT16G4SFRA|CT8G4DFRA|CT32G4DFD32A/', 'die' => 'Micron / Crucial', 'vendor' => 'Crucial'],
        ];

        foreach ($rules as $r) {
            if (preg_match($r['re'], $pn)) {
                return ['die_type' => $r['die'], 'confidence' => 'heuristic', 'vendor_hint' => $r['vendor']];
            }
        }

        return ['die_type' => 'Unknown', 'confidence' => 'low'];
    }

    private function normalizeCstateLabel(string $label): string
    {
        if (preg_match('/\b(CC?[0-7]|C[0-7])\b/i', $label, $m)) {
            return strtoupper($m[1]);
        }

        return trim($label);
    }

    /** @param array<string, list<float>> $gaming */
    private function finalizeGamingStats(array $gaming): array
    {
        $out = [];

        if (!empty($gaming['gpu_util_samples'])) {
            $out['gpu_util_avg'] = round(array_sum($gaming['gpu_util_samples']) / count($gaming['gpu_util_samples']), 1);
        }
        if (!empty($gaming['cpu_util_samples'])) {
            $out['cpu_core_max_pct'] = round(max($gaming['cpu_util_samples']), 1);
        }
        if (!empty($gaming['fps_samples'])) {
            $fps = $gaming['fps_samples'];
            sort($fps);
            $out['fps_avg'] = round(array_sum($fps) / count($fps), 1);
            $idx = (int) floor(count($fps) * 0.01);
            $out['fps_1pct_low'] = $fps[$idx] ?? null;
        }
        if (!empty($gaming['frametime_samples'])) {
            $ft = $gaming['frametime_samples'];
            $map = $this->buildSpikeMap($ft);
            $out['frametime_p99_ms'] = $map['stats']['p99_ms'] ?? null;
            $out['frametime_mean_ms'] = $map['stats']['mean_ms'] ?? null;
            $out['spike_count'] = $map['stats']['spike_count'] ?? 0;
            $out['spike_map'] = $map;
            $mean = array_sum($ft) / count($ft);
            $variance = 0.0;
            foreach ($ft as $v) {
                $variance += ($v - $mean) ** 2;
            }
            $out['frametime_variance'] = round(sqrt($variance / max(1, count($ft))), 2);
        }

        foreach (['fps_avg', 'fps_1pct_low', 'frametime_p99_ms', 'frametime_variance', 'spike_count', 'spike_map', 'frametime_mean_ms', 'samples'] as $k) {
            if (isset($gaming[$k])) {
                $out[$k] = $gaming[$k];
            }
        }

        return $out;
    }

    /** @param array<string, mixed> $sensors */
    private function finalizeSensorStats(array $sensors): array
    {
        $out = [];
        foreach (['gpu_temp_samples', 'cpu_temp_samples', 'cpu_package_temp_samples'] as $key) {
            if (empty($sensors[$key])) {
                continue;
            }
            $max = max($sensors[$key]);
            if ($key === 'gpu_temp_samples') {
                $out['gpu_temp_max'] = $max;
            } elseif ($key === 'cpu_package_temp_samples') {
                $out['cpu_temp_max'] = max($out['cpu_temp_max'] ?? 0, $max);
            } else {
                $out['cpu_temp_max'] = max($out['cpu_temp_max'] ?? 0, $max);
            }
        }

        return $out;
    }

    /** @param list<string> $row */
    private function lastNumeric(array $row): float
    {
        for ($i = count($row) - 1; $i >= 0; $i--) {
            $clean = preg_replace('/[^\d.-]/', '', (string) $row[$i]);
            if ($clean !== '' && is_numeric($clean)) {
                return (float) $clean;
            }
        }

        return 0.0;
    }

    private function cellNumeric(?string $cell): ?float
    {
        if ($cell === null || $cell === '') {
            return null;
        }
        $clean = preg_replace('/[^\d.-]/', '', $cell);
        if ($clean === '' || !is_numeric($clean)) {
            return null;
        }

        return (float) $clean;
    }
}
