<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Full Lab suite — profiles, job state, and finalize (analysis + certificate + advisor cards).
 */
class LabSuiteService
{
    private string $dir;

    public function __construct(?string $projectRoot = null)
    {
        $root = $projectRoot ?? dirname(__DIR__, 2);
        $this->dir = $root . '/storage/suite';
        if (!is_dir($this->dir)) {
            mkdir($this->dir, 0755, true);
        }
    }

    /** @return array<string, array<string, mixed>> */
    public function profiles(): array
    {
        return [
            'quick' => [
                'id' => 'quick',
                'label' => 'Quick Lab',
                'duration_hint_min' => 5,
                'benches' => ['cpu'],
                'stress_id' => 'quick',
                'stress_seconds' => 60,
            ],
            'standard' => [
                'id' => 'standard',
                'label' => 'Full Lab',
                'duration_hint_min' => 12,
                'benches' => ['cpu', 'cpu_mt', 'memory', 'storage'],
                'stress_id' => 'combined',
                'stress_seconds' => 180,
            ],
            'deep' => [
                'id' => 'deep',
                'label' => 'Deep Lab',
                'duration_hint_min' => 20,
                'benches' => ['cpu', 'cpu_mt', 'memory', 'storage', 'gpu'],
                'stress_id' => 'combined',
                'stress_seconds' => 300,
            ],
        ];
    }

    /** @param array<string, mixed> $input @return array<string, mixed> */
    public function start(array $input): array
    {
        $profileId = strtolower(trim((string) ($input['profile'] ?? 'standard')));
        $profiles = $this->profiles();
        if (!isset($profiles[$profileId])) {
            $profileId = 'standard';
        }
        $profile = $profiles[$profileId];
        $id = bin2hex(random_bytes(8));
        $job = [
            'id' => $id,
            'profile' => $profileId,
            'label' => $profile['label'],
            'status' => 'pending',
            'progress' => 0,
            'step' => 'awaiting_probe',
            'steps' => $this->stepList($profile),
            'created_at' => gmdate('c'),
            'updated_at' => gmdate('c'),
            'cancel_requested' => false,
            'fp' => substr(trim((string) ($input['fp'] ?? $input['fingerprint'] ?? '')), 0, 64),
            'result' => null,
            'error' => null,
        ];
        $this->write($job);

        return $job;
    }

    /** @return array<string, mixed>|null */
    public function status(string $id): ?array
    {
        return $this->read($id);
    }

    /** @return array<string, mixed>|null */
    public function cancel(string $id): ?array
    {
        $job = $this->read($id);
        if ($job === null) {
            return null;
        }
        if (in_array($job['status'] ?? '', ['completed', 'failed', 'cancelled'], true)) {
            return $job;
        }
        $job['cancel_requested'] = true;
        $job['status'] = 'cancelled';
        $job['step'] = 'cancelled';
        $job['updated_at'] = gmdate('c');
        $this->write($job);

        return $job;
    }

    /**
     * Update progress from the client/probe while the suite runs.
     *
     * @param array<string, mixed> $patch
     * @return array<string, mixed>|null
     */
    public function patch(string $id, array $patch): ?array
    {
        $job = $this->read($id);
        if ($job === null) {
            return null;
        }
        foreach (['status', 'progress', 'step', 'error'] as $k) {
            if (array_key_exists($k, $patch)) {
                $job[$k] = $patch[$k];
            }
        }
        if (isset($patch['probe_job']) && is_array($patch['probe_job'])) {
            $job['probe_job'] = $patch['probe_job'];
        }
        $job['updated_at'] = gmdate('c');
        $this->write($job);

        return $job;
    }

    /**
     * Finalize with probe suite payload: analysis, certificate, graph, advisor cards.
     *
     * @param array<string, mixed> $input
     * @return array<string, mixed>
     */
    public function finalize(string $id, array $input): array
    {
        $job = $this->read($id);
        if ($job === null) {
            throw new \InvalidArgumentException('Suite job not found');
        }
        if (($job['status'] ?? '') === 'cancelled') {
            return $job;
        }

        $probePayload = (array) ($input['probe'] ?? $input['agent'] ?? []);
        $suiteRun = (array) ($input['suite'] ?? $input['probe_suite'] ?? []);
        $samples = is_array($input['samples'] ?? null) ? $input['samples'] : (array) ($suiteRun['samples'] ?? []);
        $benches = is_array($suiteRun['benches'] ?? null) ? $suiteRun['benches'] : [];
        $stress = is_array($suiteRun['stress'] ?? null) ? $suiteRun['stress'] : [];

        $agent = new DiagnosticAgentService();
        $normalized = $probePayload !== []
            ? $agent->normalize($probePayload)
            : ['cpu' => [], 'gpu' => [], 'ram' => [], 'sensors' => [], 'device' => []];

        if ($benches !== []) {
            $normalized['suite_benches'] = $benches;
            $this->mergeBenchMetrics($normalized, $benches);
        }

        $analysis = (new DiagnosticService())->analyzeFull($normalized);
        $analysis['mode'] = 'suite';
        $analysis['suite'] = [
            'job_id' => $id,
            'profile' => $job['profile'] ?? 'standard',
            'benches' => $benches,
            'stress' => $stress,
            'duration_s' => $suiteRun['duration_s'] ?? null,
        ];

        $cert = (new StressCertificateService())->issue($stress !== [] ? $stress : [
            'id' => 'suite',
            'label' => 'Full Lab stress',
            'status' => ($suiteRun['status'] ?? 'ok') === 'failed' ? 'failed' : 'ok',
        ], $samples);
        $cert['timeline'] = $this->buildTimeline($samples);
        $analysis['stress_certificate'] = $cert;

        $graphSvc = new HardwareKnowledgeGraphService();
        $graph = $graphSvc->fromProbe($normalized, $analysis);
        $analysis['hardware_graph'] = $graph;

        $fp = (string) ($job['fp'] ?? '');
        if ($fp === '') {
            $fp = substr(trim((string) ($input['fp'] ?? '')), 0, 64);
        }
        $history = new DiagnosticHistoryService();
        $previous = $fp !== '' ? $history->latestSnapshot($fp) : null;
        $comparison = $previous
            ? (new DiagnosticHistoryCompareService())->compare($analysis, $previous)
            : null;

        $analysis = (new DiagnosticAiService())->enrich($analysis, [
            'previous_snapshot' => $previous,
            'comparison' => $comparison,
            'suite' => true,
        ]);
        $analysis['advisor_cards'] = (new DiagnosticAiService())->advisorCards($analysis);
        $analysis['consultant'] = (new DiagnosticConsultantService())->plan($analysis);
        if ($comparison !== null) {
            $analysis['comparison'] = $comparison;
        }

        $saved = ['saved' => false];
        try {
            if ($fp !== '') {
                $saved = $history->save($fp, null, 'suite', $analysis, $normalized);
            }
        } catch (\Throwable $e) {
            error_log('suite save: ' . $e->getMessage());
        }

        $export = (new LabReportExportService())->buildDocument($analysis, [
            'token' => $saved['token'] ?? null,
            'mode' => 'suite',
        ]);

        $job['status'] = 'completed';
        $job['progress'] = 100;
        $job['step'] = 'done';
        $job['updated_at'] = gmdate('c');
        $job['result'] = [
            'analysis' => $analysis,
            'saved' => $saved,
            'report' => [
                'title' => $export['title'],
                'document' => $export['document'],
            ],
            'report_html' => $export['html'],
        ];
        $this->write($job);

        return $job;
    }

    /** @param array<string, mixed> $profile @return list<array{id: string, label: string}> */
    private function stepList(array $profile): array
    {
        $steps = [['id' => 'probe', 'label' => 'Hardware probe']];
        foreach ((array) ($profile['benches'] ?? []) as $b) {
            $steps[] = ['id' => 'bench:' . $b, 'label' => 'Benchmark: ' . $b];
        }
        $steps[] = ['id' => 'stress', 'label' => 'Stress: ' . ($profile['stress_id'] ?? 'combined')];
        $steps[] = ['id' => 'analyze', 'label' => 'Analyze & report'];

        return $steps;
    }

    /**
     * @param array<string, mixed> $normalized
     * @param list<array<string, mixed>>|array<string, mixed> $benches
     */
    private function mergeBenchMetrics(array &$normalized, array $benches): void
    {
        $metrics = is_array($normalized['metrics'] ?? null) ? $normalized['metrics'] : [];
        foreach ($benches as $row) {
            if (!is_array($row)) {
                continue;
            }
            $id = (string) ($row['id'] ?? '');
            if ($id === 'cpu' || $id === 'cpu-mt') {
                if (isset($row['score'])) {
                    $metrics['cpu_score'] = (int) $row['score'];
                }
                if (isset($row['ops_per_sec'])) {
                    $metrics['cpu_ops'] = $row['ops_per_sec'];
                }
            }
            if ($id === 'memory' && isset($row['bandwidth_mb_s'])) {
                $metrics['mem_bandwidth_mb_s'] = $row['bandwidth_mb_s'];
            }
            if ($id === 'storage') {
                if (isset($row['seq_read_mb_s'])) {
                    $metrics['storage_read_mb_s'] = $row['seq_read_mb_s'];
                }
                if (isset($row['seq_write_mb_s'])) {
                    $metrics['storage_write_mb_s'] = $row['seq_write_mb_s'];
                }
            }
            if ($id === 'gpu' && isset($row['score'])) {
                $metrics['gpu_score'] = (int) $row['score'];
            }
        }
        $normalized['metrics'] = $metrics;
    }

    /**
     * @param list<array<string, mixed>> $samples
     * @return list<array{t: string|null, cpu_temp: float|null, gpu_temp: float|null}>
     */
    private function buildTimeline(array $samples): array
    {
        $out = [];
        foreach (array_slice($samples, 0, 240) as $s) {
            if (!is_array($s)) {
                continue;
            }
            $out[] = [
                't' => isset($s['t']) ? (string) $s['t'] : (isset($s['ts']) ? (string) $s['ts'] : null),
                'cpu_temp' => isset($s['cpu_temp']) ? (float) $s['cpu_temp'] : (isset($s['cpu_temp_max']) ? (float) $s['cpu_temp_max'] : null),
                'gpu_temp' => isset($s['gpu_temp']) ? (float) $s['gpu_temp'] : (isset($s['gpu_temp_max']) ? (float) $s['gpu_temp_max'] : null),
            ];
        }

        return $out;
    }

    /** @return array<string, mixed>|null */
    private function read(string $id): ?array
    {
        $id = preg_replace('/[^a-f0-9]/', '', strtolower($id)) ?? '';
        if ($id === '') {
            return null;
        }
        $path = $this->dir . '/' . $id . '.json';
        if (!is_file($path)) {
            return null;
        }
        $data = json_decode((string) file_get_contents($path), true);

        return is_array($data) ? $data : null;
    }

    /** @param array<string, mixed> $job */
    private function write(array $job): void
    {
        $id = (string) ($job['id'] ?? '');
        if ($id === '') {
            return;
        }
        file_put_contents(
            $this->dir . '/' . $id . '.json',
            json_encode($job, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
            LOCK_EX
        );
    }
}
