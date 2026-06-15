<?php

declare(strict_types=1);

namespace App\Services;

use App\Database;

/**
 * Persists diagnostic runs + powers live feed / community benchmark on /diagnostic.
 */
class DiagnosticHistoryService
{
    /** @param array<string, mixed> $analysis Result from analyzeLite/analyzeFull */
    /** @param array<string, mixed> $raw Original probe/quiz payload (stored for owner only) */
    public function save(
        string $fingerprint,
        ?int $userId,
        string $mode,
        array $analysis,
        array $raw = [],
    ): array {
        $pdo = Database::connection();
        $token = bin2hex(random_bytes(8));
        $summary = (array) ($analysis['report_summary'] ?? []);
        $metrics = (array) ($analysis['metrics'] ?? []);
        $bn = (array) ($analysis['bottleneck'] ?? []);

        $cpu = $summary['cpu'] ?? $raw['cpu']['model'] ?? null;
        $gpu = $summary['gpu'] ?? $raw['gpu']['model'] ?? null;
        $ram = (int) ($summary['ram_gb'] ?? $raw['ram']['total_gb'] ?? $metrics['ram_gb'] ?? 0);
        $form = (string) ($summary['is_laptop'] ?? false ? 'laptop' : ($raw['device']['form_factor'] ?? 'desktop'));

        $row = [
            'fingerprint' => substr($fingerprint, 0, 64),
            'user_id' => $userId,
            'mode' => substr($mode, 0, 20),
            'health_score' => (int) ($analysis['health_score'] ?? 0),
            'health_grade' => substr((string) ($analysis['health_grade'] ?? 'C'), 0, 2),
            'bottleneck_type' => substr((string) ($bn['type'] ?? ''), 0, 32),
            'bottleneck_fa' => substr((string) ($bn['message'] ?? $bn['message_fa'] ?? ''), 0, 255),
            'cpu_model' => $cpu ? substr((string) $cpu, 0, 255) : null,
            'gpu_model' => $gpu ? substr((string) $gpu, 0, 255) : null,
            'ram_gb' => $ram,
            'form_factor' => substr($form, 0, 20),
            'metrics_json' => json_encode($metrics, JSON_UNESCAPED_UNICODE),
            'summary_json' => json_encode($summary, JSON_UNESCAPED_UNICODE),
            'report_json' => json_encode([
                'analysis' => $this->ownerSnapshot($analysis),
                'raw_meta' => $this->rawMeta($raw),
            ], JSON_UNESCAPED_UNICODE),
            'report_token' => $token,
            'is_public' => 1,
        ];

        $cols = implode(', ', array_keys($row));
        $ph = implode(', ', array_fill(0, count($row), '?'));
        $pdo->prepare("INSERT INTO diagnostic_reports ($cols) VALUES ($ph)")->execute(array_values($row));
        $id = (int) $pdo->lastInsertId();

        return [
            'id' => $id,
            'token' => $token,
            'public_label' => $this->publicLabel($row),
            'created_at' => date('c'),
        ];
    }

    /** Latest saved test for this device — used before persisting a new run. */
    public function latestSnapshot(string $fingerprint): ?array
    {
        $pdo = Database::connection();
        $stmt = $pdo->prepare(
            'SELECT id, mode, health_score, health_grade, bottleneck_type, bottleneck_fa,
                    metrics_json, summary_json, report_json, report_token, created_at
             FROM diagnostic_reports
             WHERE fingerprint = ?
             ORDER BY created_at DESC, id DESC
             LIMIT 1'
        );
        $stmt->execute([substr($fingerprint, 0, 64)]);
        $row = $stmt->fetch(\PDO::FETCH_ASSOC);
        if (!$row) {
            return null;
        }

        $report = \App\json_decode_assoc((string) ($row['report_json'] ?? '{}'), '{}');
        $analysis = is_array($report['analysis'] ?? null) ? $report['analysis'] : [];

        return [
            'id' => (int) ($row['id'] ?? 0),
            'token' => (string) ($row['report_token'] ?? ''),
            'mode' => (string) ($row['mode'] ?? ''),
            'health_score' => (int) ($row['health_score'] ?? 0),
            'health_grade' => (string) ($row['health_grade'] ?? ''),
            'bottleneck_type' => (string) ($row['bottleneck_type'] ?? ''),
            'bottleneck' => is_array($analysis['bottleneck'] ?? null)
                ? $analysis['bottleneck']
                : ['type' => $row['bottleneck_type'] ?? '', 'message' => $row['bottleneck_fa'] ?? ''],
            'metrics' => \App\json_decode_assoc((string) ($row['metrics_json'] ?? '{}'), '{}'),
            'summary' => \App\json_decode_assoc((string) ($row['summary_json'] ?? '{}'), '{}'),
            'created_at' => (string) ($row['created_at'] ?? ''),
            'ago' => $this->timeAgo((string) ($row['created_at'] ?? '')),
        ];
    }

    /** @return list<array> */
    public function userHistoryWithDeltas(string $fingerprint, ?int $userId, int $limit = 20): array
    {
        $rows = $this->userHistory($fingerprint, $userId, $limit);
        $compare = new DiagnosticHistoryCompareService();
        for ($i = 0; $i < count($rows); $i++) {
            if ($i + 1 >= count($rows)) {
                break;
            }
            $current = $this->rowToAnalysis($rows[$i]);
            $previous = $this->rowToAnalysis($rows[$i + 1]);
            $delta = $compare->compare($current, $previous);
            $rows[$i]['delta_score'] = $delta['delta']['health_score'] ?? 0;
            $rows[$i]['vs_previous'] = [
                'score_delta' => $delta['delta']['health_score'] ?? 0,
                'summary' => $delta['summary'] ?? '',
                'overall' => $delta['overall'] ?? 'stable',
            ];
        }

        return $rows;
    }

    /** @param array<string, mixed> $row */
    private function rowToAnalysis(array $row): array
    {
        return [
            'health_score' => (int) ($row['score'] ?? 0),
            'health_grade' => (string) ($row['grade'] ?? ''),
            'bottleneck' => ['type' => (string) ($row['bottleneck_type'] ?? ''), 'message' => $row['bottleneck_fa'] ?? ''],
            'metrics' => is_array($row['metrics'] ?? null) ? $row['metrics'] : [],
            'token' => $row['token'] ?? '',
            'mode' => $row['mode'] ?? '',
            'created_at' => $row['created_at'] ?? '',
            'ago' => $row['ago'] ?? '',
        ];
    }

    /** @return array{stats: array, feed: list, benchmark: array, capabilities: list, yours: list} */
    public function livePayload(string $fingerprint, ?int $userId = null): array
    {
        $catalog = new DiagnosticToolCatalogService();
        $total = $catalog->total();

        return [
            'stats' => $this->stats(),
            'feed' => $this->liveFeed(18),
            'benchmark' => $this->communityBenchmark(),
            'capabilities' => $catalog->capabilitiesSummary(),
            'yours' => $this->userHistoryWithDeltas($fingerprint, $userId, 12),
            'tools_replaced' => $total,
            'toolkit' => $catalog->summary(),
            'pulse' => (new DiagnosticIntelligencePulseService())->publicPulse($total),
            'updated_at' => date('c'),
        ];
    }

    /** @return list<array> */
    public function userHistory(string $fingerprint, ?int $userId, int $limit = 20): array
    {
        $pdo = Database::connection();
        $sql = 'SELECT id, mode, health_score, health_grade, bottleneck_type, bottleneck_fa, cpu_model, gpu_model,
                       ram_gb, form_factor, metrics_json, report_token, created_at
                FROM diagnostic_reports
                WHERE fingerprint = ?';
        $params = [substr($fingerprint, 0, 64)];
        if ($userId) {
            $sql .= ' OR user_id = ?';
            $params[] = $userId;
        }
        $sql .= ' ORDER BY created_at DESC LIMIT ' . max(1, min(50, $limit));

        $stmt = $pdo->prepare($sql);
        $stmt->execute($params);

        return array_map(fn ($r) => $this->formatRow($r, true), $stmt->fetchAll() ?: []);
    }

    public function getByToken(string $token, string $fingerprint, ?int $userId): ?array
    {
        $pdo = Database::connection();
        $stmt = $pdo->prepare('SELECT * FROM diagnostic_reports WHERE report_token = ? LIMIT 1');
        $stmt->execute([substr($token, 0, 32)]);
        $row = $stmt->fetch();
        if (!$row) {
            return null;
        }
        $owned = ($row['fingerprint'] ?? '') === substr($fingerprint, 0, 64)
            || ($userId && (int) ($row['user_id'] ?? 0) === $userId);

        $out = $this->formatRow($row, $owned);
        if ($owned && !empty($row['report_json'])) {
            $out['report'] = \App\json_decode_assoc((string) $row['report_json'], '{}');
            $analysis = is_array($out['report']['analysis'] ?? null) ? $out['report']['analysis'] : [];
            if ($analysis !== []) {
                $previous = $this->previousSnapshotBefore((string) ($row['created_at'] ?? ''), (string) ($row['fingerprint'] ?? ''));
                if ($previous) {
                    $out['comparison'] = (new DiagnosticHistoryCompareService())->compare($analysis, $previous);
                }
            }
        }

        return $out;
    }

    public function previousSnapshotBefore(string $createdAt, string $fingerprint): ?array
    {
        if ($createdAt === '') {
            return null;
        }
        $pdo = Database::connection();
        $stmt = $pdo->prepare(
            'SELECT id, mode, health_score, health_grade, bottleneck_type, bottleneck_fa,
                    metrics_json, summary_json, report_json, report_token, created_at
             FROM diagnostic_reports
             WHERE fingerprint = ? AND created_at < ?
             ORDER BY created_at DESC, id DESC
             LIMIT 1'
        );
        $stmt->execute([substr($fingerprint, 0, 64), $createdAt]);
        $row = $stmt->fetch(\PDO::FETCH_ASSOC);
        if (!$row) {
            return null;
        }

        $report = \App\json_decode_assoc((string) ($row['report_json'] ?? '{}'), '{}');
        $analysis = is_array($report['analysis'] ?? null) ? $report['analysis'] : [];

        return [
            'id' => (int) ($row['id'] ?? 0),
            'token' => (string) ($row['report_token'] ?? ''),
            'mode' => (string) ($row['mode'] ?? ''),
            'health_score' => (int) ($row['health_score'] ?? 0),
            'health_grade' => (string) ($row['health_grade'] ?? ''),
            'bottleneck_type' => (string) ($row['bottleneck_type'] ?? ''),
            'bottleneck' => is_array($analysis['bottleneck'] ?? null)
                ? $analysis['bottleneck']
                : ['type' => $row['bottleneck_type'] ?? '', 'message' => $row['bottleneck_fa'] ?? ''],
            'metrics' => \App\json_decode_assoc((string) ($row['metrics_json'] ?? '{}'), '{}'),
            'created_at' => (string) ($row['created_at'] ?? ''),
            'ago' => $this->timeAgo((string) ($row['created_at'] ?? '')),
        ];
    }

    /** @return list<array> */
    private function liveFeed(int $limit): array
    {
        $pdo = Database::connection();
        $stmt = $pdo->query(
            'SELECT mode, health_score, health_grade, bottleneck_type, bottleneck_fa,
                    gpu_model, form_factor, ram_gb, metrics_json, created_at
             FROM diagnostic_reports
             WHERE is_public = 1
             ORDER BY created_at DESC
             LIMIT ' . max(1, min(30, $limit))
        );

        return array_map(function ($r) {
            $m = \App\json_decode_assoc((string) ($r['metrics_json'] ?? '{}'), '{}');

            return [
                'label' => $this->publicLabel($r),
                'mode' => $r['mode'],
                'score' => (int) $r['health_score'],
                'grade' => $r['health_grade'],
                'bottleneck' => $r['bottleneck_type'],
                'bottleneck_fa' => $r['bottleneck_fa'],
                'gpu_temp' => $m['gpu_temp_max'] ?? null,
                'cpu_temp' => $m['cpu_temp_max'] ?? null,
                'gpu_util' => $m['gpu_util_avg'] ?? null,
                'ram_gb' => (int) ($r['ram_gb'] ?? 0),
                'ago' => $this->timeAgo((string) $r['created_at']),
                'ts' => $r['created_at'],
            ];
        }, $stmt->fetchAll() ?: []);
    }

    /** @return array<string, int|float> */
    public function stats(): array
    {
        $pdo = Database::connection();
        $isMysql = Database::usesMysqlDialect();

        if ($isMysql) {
            $today = $pdo->query(
                'SELECT COUNT(*) FROM diagnostic_reports WHERE DATE(created_at) = CURDATE()'
            )->fetchColumn();
            $hour = $pdo->query(
                'SELECT COUNT(*) FROM diagnostic_reports WHERE created_at >= NOW() - INTERVAL 1 HOUR'
            )->fetchColumn();
            $avg = $pdo->query(
                'SELECT ROUND(AVG(health_score), 1) FROM diagnostic_reports WHERE created_at >= NOW() - INTERVAL 24 HOUR'
            )->fetchColumn();
        } else {
            $today = $pdo->query(
                "SELECT COUNT(*) FROM diagnostic_reports WHERE date(created_at) = date('now')"
            )->fetchColumn();
            $hour = $pdo->query(
                "SELECT COUNT(*) FROM diagnostic_reports WHERE created_at >= datetime('now', '-1 hour')"
            )->fetchColumn();
            $avg = $pdo->query(
                "SELECT ROUND(AVG(health_score), 1) FROM diagnostic_reports WHERE created_at >= datetime('now', '-24 hours')"
            )->fetchColumn();
        }

        $total = $pdo->query('SELECT COUNT(*) FROM diagnostic_reports')->fetchColumn();
        $full = $pdo->query(
            "SELECT COUNT(*) FROM diagnostic_reports WHERE mode IN ('full','agent')"
        )->fetchColumn();

        return [
            'scans_today' => (int) $today,
            'scans_hour' => (int) $hour,
            'avg_health_24h' => (float) ($avg ?: 0),
            'total_scans' => (int) $total,
            'full_scans' => (int) $full,
        ];
    }

    public function communityBenchmark(): array
    {
        $pdo = Database::connection();
        $grades = $pdo->query(
            "SELECT health_grade, COUNT(*) AS c FROM diagnostic_reports GROUP BY health_grade"
        )->fetchAll() ?: [];

        $gradeMap = [];
        foreach ($grades as $g) {
            $gradeMap[$g['health_grade'] ?? '?'] = (int) $g['c'];
        }

        $stmt = $pdo->query(
            "SELECT gpu_model, COUNT(*) AS scans, ROUND(AVG(health_score), 1) AS avg_score
             FROM diagnostic_reports
             WHERE gpu_model IS NOT NULL AND gpu_model != ''
             GROUP BY gpu_model
             ORDER BY scans DESC
             LIMIT 8"
        );
        $gpuRows = [];
        foreach ($stmt->fetchAll() ?: [] as $r) {
            $gpuRows[] = [
                'gpu' => $this->shortGpu((string) $r['gpu_model']),
                'scans' => (int) $r['scans'],
                'avg_score' => (float) $r['avg_score'],
            ];
        }

        $bn = $pdo->query(
            "SELECT bottleneck_type, COUNT(*) AS c FROM diagnostic_reports
             WHERE bottleneck_type IS NOT NULL AND bottleneck_type != ''
             GROUP BY bottleneck_type ORDER BY c DESC LIMIT 6"
        )->fetchAll() ?: [];

        return [
            'grades' => $gradeMap,
            'top_gpus' => $gpuRows,
            'bottlenecks' => array_map(fn ($b) => [
                'type' => $b['bottleneck_type'],
                'count' => (int) $b['c'],
            ], $bn),
            'thermal_lab_24h' => $this->communityThermalSnapshot(),
            'gpu_temp_rows' => $this->anonymousGpuThermalLeaderboard(10),
        ];
    }

    /**
     * Anonymous aggregate: popular GPU labels with mean health + mean peak GPU temp (no fingerprint / user id).
     *
     * @return list<array{gpu: string, scans: int, avg_health: float, avg_gpu_temp_c: float|null}>
     */
    public function anonymousGpuThermalLeaderboard(int $limit = 12): array
    {
        $pdo = Database::connection();
        $isMysql = Database::usesMysqlDialect();
        $days = 30;
        $where = $isMysql
            ? "is_public = 1 AND created_at >= NOW() - INTERVAL {$days} DAY"
            : "is_public = 1 AND created_at >= datetime('now', '-{$days} days')";

        $sql = 'SELECT gpu_model, health_score, metrics_json FROM diagnostic_reports WHERE '
            . $where
            . " AND gpu_model IS NOT NULL AND TRIM(gpu_model) != ''"
            . ' ORDER BY created_at DESC LIMIT 2500';
        $stmt = $pdo->query($sql);
        if ($stmt === false) {
            return [];
        }

        $acc = [];
        foreach ($stmt->fetchAll(\PDO::FETCH_ASSOC) ?: [] as $row) {
            $label = $this->shortGpu((string) ($row['gpu_model'] ?? ''));
            if ($label === '') {
                continue;
            }
            if (!isset($acc[$label])) {
                $acc[$label] = ['scans' => 0, 'health_sum' => 0, 'gpu_temp_sum' => 0.0, 'gpu_temp_n' => 0];
            }
            $acc[$label]['scans']++;
            $acc[$label]['health_sum'] += (int) ($row['health_score'] ?? 0);
            $m = \App\json_decode_assoc((string) ($row['metrics_json'] ?? '{}'), '{}');
            $gt = (float) ($m['gpu_temp_max'] ?? 0);
            if ($gt > 15 && $gt < 125) {
                $acc[$label]['gpu_temp_sum'] += $gt;
                $acc[$label]['gpu_temp_n']++;
            }
        }

        $rows = [];
        foreach ($acc as $gpu => $a) {
            $rows[] = [
                'gpu' => $gpu,
                'scans' => $a['scans'],
                'avg_health' => round($a['health_sum'] / max(1, $a['scans']), 1),
                'avg_gpu_temp_c' => $a['gpu_temp_n'] > 0 ? round($a['gpu_temp_sum'] / $a['gpu_temp_n'], 1) : null,
            ];
        }
        usort($rows, static fn (array $x, array $y): int => ($y['scans'] <=> $x['scans']));

        return array_slice($rows, 0, max(1, min(30, $limit)));
    }

    /**
     * @return list<array{type: string, count: int}>
     */
    public function anonymousBottleneckMixLastDays(int $days = 30): array
    {
        $days = max(7, min(90, $days));
        $pdo = Database::connection();
        $isMysql = Database::usesMysqlDialect();
        $where = $isMysql
            ? "is_public = 1 AND created_at >= NOW() - INTERVAL {$days} DAY"
            : "is_public = 1 AND created_at >= datetime('now', '-{$days} days')";

        $sql = "SELECT COALESCE(NULLIF(TRIM(bottleneck_type), ''), 'unknown') AS bt, COUNT(*) AS c
                FROM diagnostic_reports WHERE {$where}
                GROUP BY bt ORDER BY c DESC LIMIT 12";
        $stmt = $pdo->query($sql);
        if ($stmt === false) {
            return [];
        }

        return array_map(static fn (array $b): array => [
            'type' => (string) ($b['bt'] ?? ''),
            'count' => (int) ($b['c'] ?? 0),
        ], $stmt->fetchAll(\PDO::FETCH_ASSOC) ?: []);
    }

    /**
     * Aggregates real sensor peaks from recent public diagnostic reports (stored metrics_json).
     *
     * @return array<string, mixed>
     */
    public function communityThermalSnapshot(): array
    {
        $pdo = Database::connection();
        $isMysql = Database::usesMysqlDialect();
        $where = $isMysql
            ? "created_at >= NOW() - INTERVAL 24 HOUR AND is_public = 1"
            : "created_at >= datetime('now', '-1 day') AND is_public = 1";

        $lim = 500;
        $sql = "SELECT metrics_json FROM diagnostic_reports WHERE {$where}
                AND metrics_json IS NOT NULL AND TRIM(metrics_json) != '' AND metrics_json != '{}'
                ORDER BY created_at DESC LIMIT {$lim}";
        $stmt = $pdo->query($sql);
        if ($stmt === false) {
            return $this->emptyCommunityThermal();
        }

        $cpuVals = [];
        $gpuVals = [];
        $hsVals = [];
        $samples = 0;

        foreach ($stmt->fetchAll(\PDO::FETCH_ASSOC) ?: [] as $row) {
            $m = \App\json_decode_assoc((string) ($row['metrics_json'] ?? '{}'), '{}');
            $ct = (float) ($m['cpu_temp_max'] ?? 0);
            $gt = (float) ($m['gpu_temp_max'] ?? 0);
            $ht = (float) ($m['gpu_hotspot_max'] ?? 0);
            $had = false;
            if ($ct > 15 && $ct < 125) {
                $cpuVals[] = (int) round($ct);
                $had = true;
            }
            if ($gt > 15 && $gt < 125) {
                $gpuVals[] = (int) round($gt);
                $had = true;
            }
            if ($ht > 15 && $ht < 125) {
                $hsVals[] = (int) round($ht);
                $had = true;
            }
            if ($had) {
                ++$samples;
            }
        }

        return [
            'window_hours' => 24,
            'samples' => $samples,
            'cpu_avg_c' => $this->avgIntList($cpuVals),
            'gpu_avg_c' => $this->avgIntList($gpuVals),
            'gpu_hotspot_avg_c' => $this->avgIntList($hsVals),
            'cpu_p95_c' => $this->percentileInt($cpuVals, 95),
            'gpu_p95_c' => $this->percentileInt($gpuVals, 95),
        ];
    }

    /** @return array<string, mixed>|null */
    public function lastPublicMetricsForFingerprint(string $fingerprint): ?array
    {
        $fp = substr(trim($fingerprint), 0, 64);
        if ($fp === '' || strcasecmp($fp, 'unknown') === 0) {
            return null;
        }
        $pdo = Database::connection();
        $stmt = $pdo->prepare(
            'SELECT metrics_json FROM diagnostic_reports WHERE fingerprint = ? ORDER BY created_at DESC LIMIT 1'
        );
        $stmt->execute([$fp]);
        $row = $stmt->fetch(\PDO::FETCH_ASSOC);
        if (!$row) {
            return null;
        }
        $m = \App\json_decode_assoc((string) ($row['metrics_json'] ?? '{}'), '{}');

        return $m === [] ? null : $m;
    }

    /** @return array<string, mixed> */
    private function emptyCommunityThermal(): array
    {
        return [
            'window_hours' => 24,
            'samples' => 0,
            'cpu_avg_c' => null,
            'gpu_avg_c' => null,
            'gpu_hotspot_avg_c' => null,
            'cpu_p95_c' => null,
            'gpu_p95_c' => null,
        ];
    }

    /** @param list<int> $vals */
    private function avgIntList(array $vals): ?float
    {
        if ($vals === []) {
            return null;
        }

        return round(array_sum($vals) / count($vals), 1);
    }

    /** @param list<int> $vals */
    private function percentileInt(array $vals, int $pct): ?int
    {
        if ($vals === []) {
            return null;
        }
        sort($vals);
        $n = count($vals);
        $idx = (int) floor(($pct / 100.0) * max(0, $n - 1));

        return (int) $vals[$idx];
    }

    /** @param array<string, mixed> $cfg */
    private function capabilitiesLive(array $cfg): array
    {
        $pdo = Database::connection();
        $latest = $pdo->query(
            "SELECT metrics_json, summary_json, mode FROM diagnostic_reports
             WHERE mode IN ('full','agent') AND metrics_json IS NOT NULL
             ORDER BY created_at DESC LIMIT 1"
        )->fetch();

        $metrics = $latest ? \App\json_decode_assoc((string) $latest['metrics_json'], '{}') : [];

        $samples = [
            'cpu_temp' => $metrics['cpu_temp_max'] ?? null,
            'gpu_temp' => $metrics['gpu_temp_max'] ?? null,
            'gpu_hotspot' => $metrics['gpu_hotspot_max'] ?? null,
            'gpu_util' => $metrics['gpu_util_avg'] ?? null,
            'frametime_p99' => $metrics['frametime_p99_ms'] ?? null,
            'battery_health' => $metrics['battery_health_pct'] ?? null,
            'lan_mbps' => $metrics['lan_link_mbps'] ?? null,
            'vram_gb' => $metrics['vram_gb'] ?? null,
        ];

        $toolMap = [
            'hwinfo' => ['keys' => ['cpu_temp', 'gpu_temp', 'gpu_util'], 'label' => 'Live sensors'],
            'gpuz' => ['keys' => ['vram_gb', 'gpu_temp'], 'label' => 'VRAM & GPU'],
            'capframex' => ['keys' => ['frametime_p99'], 'label' => 'Frametime P99'],
            'afterburner' => ['keys' => ['gpu_util', 'gpu_temp'], 'label' => 'In-game OSD'],
            'cpuz' => ['keys' => ['cpu_temp'], 'label' => 'CPU monitor'],
        ];

        $out = [];
        foreach ($cfg['pro_tools'] ?? [] as $tool) {
            $id = $tool['id'] ?? '';
            $map = $toolMap[$id] ?? null;
            $liveVal = null;
            if ($map) {
                foreach ($map['keys'] as $k) {
                    if ($samples[$k] !== null && $samples[$k] !== 0) {
                        $liveVal = $samples[$k];
                        break;
                    }
                }
            }
            $out[] = [
                'id' => $id,
                'name' => $tool['name'],
                'desc' => $tool['desc'] ?? $tool['desc_fa'] ?? '',
                'replaced' => true,
                'live_sample' => $liveVal,
                'live_label' => $map['label'] ?? null,
            ];
        }

        return $out;
    }

    /** @param array<string, mixed> $row */
    private function formatRow(array $row, bool $detailed): array
    {
        $m = \App\json_decode_assoc((string) ($row['metrics_json'] ?? '{}'), '{}');

        return [
            'id' => (int) ($row['id'] ?? 0),
            'token' => $row['report_token'] ?? '',
            'mode' => $row['mode'] ?? 'lite',
            'score' => (int) ($row['health_score'] ?? 0),
            'grade' => $row['health_grade'] ?? '',
            'bottleneck_fa' => $row['bottleneck_fa'] ?? '',
            'bottleneck_type' => $row['bottleneck_type'] ?? '',
            'cpu' => $detailed ? ($row['cpu_model'] ?? null) : $this->shortCpu((string) ($row['cpu_model'] ?? '')),
            'gpu' => $this->shortGpu((string) ($row['gpu_model'] ?? '')),
            'ram_gb' => (int) ($row['ram_gb'] ?? 0),
            'form_factor' => $row['form_factor'] ?? 'desktop',
            'metrics' => $detailed ? $m : array_filter([
                'gpu_temp_max' => $m['gpu_temp_max'] ?? null,
                'cpu_temp_max' => $m['cpu_temp_max'] ?? null,
            ]),
            'ago' => $this->timeAgo((string) ($row['created_at'] ?? '')),
            'created_at' => $row['created_at'] ?? '',
        ];
    }

    /** @param array<string, mixed> $row */
    private function publicLabel(array $row): string
    {
        $ff = ($row['form_factor'] ?? '') === 'laptop' ? 'Laptop' : 'PC';
        $gpu = $this->shortGpu((string) ($row['gpu_model'] ?? ''));
        if ($gpu !== '') {
            return "$ff · $gpu";
        }

        return $ff . ' · ' . $this->shortCpu((string) ($row['cpu_model'] ?? 'System'));
    }

    private function shortGpu(string $model): string
    {
        if ($model === '') {
            return '';
        }
        if (preg_match('/(RTX|GTX|RX|Arc)\s*[\d\w\s]+/i', $model, $m)) {
            return trim($m[0]);
        }
        if (preg_match('/(GeForce|Radeon|Intel).*?(\\d+[\\w\\s]*)/i', $model, $m)) {
            return trim($m[0]);
        }

        return mb_strlen($model) > 28 ? mb_substr($model, 0, 25) . '…' : $model;
    }

    private function shortCpu(string $model): string
    {
        if ($model === '') {
            return '';
        }
        if (preg_match('/(Ryzen|Core|Threadripper|Xeon)[^\,]*/i', $model, $m)) {
            return trim($m[0]);
        }

        return mb_strlen($model) > 24 ? mb_substr($model, 0, 21) . '…' : $model;
    }

    private function timeAgo(string $dt): string
    {
        if ($dt === '') {
            return '';
        }
        $ts = strtotime($dt);
        if ($ts === false) {
            return '';
        }
        $diff = time() - $ts;
        if ($diff < 60) {
            return 'just now';
        }
        if ($diff < 3600) {
            return (int) floor($diff / 60) . 'm ago';
        }
        if ($diff < 86400) {
            return (int) floor($diff / 3600) . 'h ago';
        }

        return (int) floor($diff / 86400) . 'd ago';
    }

    /** @param array<string, mixed> $analysis */
    private function ownerSnapshot(array $analysis): array
    {
        return array_intersect_key($analysis, array_flip([
            'mode', 'health_score', 'health_grade', 'metrics', 'bottleneck', 'risks',
            'issues', 'upgrade_suggestions', 'game_settings', 'report_summary',
            'ai_narrative', 'ai_narrative_fa', 'ai',
        ]));
    }

    /** @param array<string, mixed> $raw */
    private function rawMeta(array $raw): array
    {
        return [
            'probe_version' => $raw['probe_version'] ?? null,
            'agent' => $raw['agent'] ?? null,
            'collected_at' => $raw['collected_at'] ?? null,
            'import_sources' => $raw['import_sources'] ?? [],
        ];
    }
}
