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
            'adaptive' => [
                'id' => 'adaptive',
                'label' => 'Adaptive Lab',
                'duration_hint_min' => 12,
                'benches' => [],
                'stress_id' => 'combined',
                'stress_seconds' => 180,
                'adaptive' => true,
            ],
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
                'duration_hint_min' => 14,
                'benches' => ['cpu', 'cpu_mt', 'cpu_cache', 'memory', 'storage', 'gpu'],
                'stress_id' => 'combined',
                'stress_seconds' => 180,
            ],
            'deep' => [
                'id' => 'deep',
                'label' => 'Deep Lab',
                'duration_hint_min' => 22,
                'benches' => ['cpu', 'cpu_mt', 'cpu_cache', 'memory', 'storage', 'gpu'],
                'stress_id' => 'oracle',
                'stress_seconds' => 300,
            ],
            'soak_15' => [
                'id' => 'soak_15',
                'label' => 'Soak 15 min',
                'duration_hint_min' => 18,
                'benches' => ['cpu', 'memory', 'storage', 'gpu'],
                'stress_id' => 'combined',
                'stress_seconds' => 900,
            ],
            'soak_30' => [
                'id' => 'soak_30',
                'label' => 'Soak 30 min',
                'duration_hint_min' => 35,
                'benches' => ['cpu', 'memory', 'storage', 'gpu'],
                'stress_id' => 'combined',
                'stress_seconds' => 1800,
            ],
            'soak_60' => [
                'id' => 'soak_60',
                'label' => 'Soak 60 min',
                'duration_hint_min' => 65,
                'benches' => ['cpu', 'memory', 'storage', 'gpu'],
                'stress_id' => 'oracle',
                'stress_seconds' => 3600,
            ],
        ];
    }

    /**
     * Preview an adaptive (or static) lab plan before start.
     *
     * @param array<string, mixed> $input probe devices/fingerprint/platform optional
     * @return array<string, mixed>
     */
    public function planPreview(array $input = []): array
    {
        $profileId = strtolower(trim((string) ($input['profile'] ?? 'adaptive')));
        $profiles = $this->profiles();
        if (!isset($profiles[$profileId])) {
            $profileId = 'adaptive';
        }
        $profile = $profiles[$profileId];

        if (!empty($profile['adaptive']) || $profileId === 'adaptive') {
            $devices = (array) ($input['devices'] ?? []);
            $fingerprint = (array) ($input['fingerprint'] ?? $devices['fingerprint'] ?? []);
            $platform = (array) ($input['platform'] ?? $devices['platform'] ?? []);
            $steps = $this->compileAdaptiveSteps($fingerprint, $devices, $platform);

            return [
                'ok' => true,
                'profile' => 'adaptive',
                'label' => 'Adaptive Lab',
                'adaptive' => true,
                'steps' => $steps['steps'],
                'benches' => $steps['benches'],
                'stress_id' => $steps['stress_id'],
                'stress_seconds' => $steps['stress_seconds'],
                'gated' => $steps['gated'],
                'gate_reason' => $steps['gate_reason'],
                'findings' => $steps['findings'],
                'duration_hint_min' => $steps['duration_hint_min'],
                'fingerprint_id' => $fingerprint['id'] ?? null,
                'coverage_score' => $fingerprint['coverage_score'] ?? null,
                'form_factor' => $fingerprint['form_factor'] ?? null,
            ];
        }

        return [
            'ok' => true,
            'profile' => $profileId,
            'label' => $profile['label'],
            'adaptive' => false,
            'steps' => $this->stepList($profile),
            'benches' => $profile['benches'],
            'stress_id' => $profile['stress_id'],
            'stress_seconds' => $profile['stress_seconds'],
            'gated' => false,
            'gate_reason' => null,
            'findings' => [],
            'duration_hint_min' => $profile['duration_hint_min'] ?? null,
        ];
    }

    /**
     * @param array<string, mixed> $fingerprint
     * @param array<string, mixed> $devices
     * @param array<string, mixed> $platform
     * @return array<string, mixed>
     */
    private function compileAdaptiveSteps(array $fingerprint, array $devices, array $platform): array
    {
        $steps = [];
        $findings = [];
        $benches = [];
        $gated = false;
        $gateReason = null;

        $driverless = (int) ($devices['summary']['driverless'] ?? count((array) ($devices['driverless'] ?? [])));
        $chipsetMissing = false;
        foreach ((array) ($devices['driverless'] ?? []) as $d) {
            if (!is_array($d)) {
                continue;
            }
            $n = (string) ($d['name'] ?? '') . (string) ($d['category'] ?? '');
            if (preg_match('/chipset|SMBus|LPC|Host Bridge|PCI Express Root/i', $n)) {
                $chipsetMissing = true;
            }
        }
        if ($chipsetMissing || $driverless >= 5) {
            $gated = true;
            $gateReason = $chipsetMissing
                ? 'Chipset / platform driver missing — run Drivers action plan before Full Lab soak'
                : "$driverless driverless devices — prefer inventory + driver fix before long stress";
            $findings[] = ['severity' => 'warn', 'code' => 'adaptive_gate_drivers', 'detail' => $gateReason];
        }

        $steps[] = [
            'id' => 'inventory',
            'kind' => 'inventory',
            'label' => 'Platform inventory',
            'reason' => 'Capture PnP, SMBIOS, UEFI/TPM, and coverage before benches',
            'hardware_refs' => ['platform', 'pnp'],
        ];

        if ($gated) {
            $steps[] = [
                'id' => 'drivers_gate',
                'kind' => 'sensor',
                'label' => 'Driver gate (review)',
                'reason' => $gateReason,
                'hardware_refs' => ['drivers'],
                'gate' => true,
            ];

            return [
                'steps' => $steps,
                'benches' => [],
                'stress_id' => null,
                'stress_seconds' => 0,
                'gated' => true,
                'gate_reason' => $gateReason,
                'findings' => $findings,
                'duration_hint_min' => 3,
            ];
        }

        $hasGpu = !empty($fingerprint['has_discrete_gpu']);
        $nvme = (int) ($fingerprint['nvme_count'] ?? 0);
        $isLaptop = (($fingerprint['form_factor'] ?? '') === 'laptop');

        $benches[] = 'cpu';
        $steps[] = ['id' => 'bench:cpu', 'kind' => 'bench', 'label' => 'CPU single-thread', 'reason' => 'Baseline single-thread throughput', 'hardware_refs' => ['cpu']];
        $benches[] = 'cpu_mt';
        $steps[] = ['id' => 'bench:cpu_mt', 'kind' => 'bench', 'label' => 'CPU multi-thread', 'reason' => 'Multi-thread scaling', 'hardware_refs' => ['cpu']];
        $benches[] = 'cpu_cache';
        $steps[] = ['id' => 'bench:cpu_cache', 'kind' => 'bench', 'label' => 'CPU cache', 'reason' => 'Cache hierarchy', 'hardware_refs' => ['cpu']];
        $benches[] = 'memory';
        $steps[] = ['id' => 'bench:memory', 'kind' => 'bench', 'label' => 'Memory bandwidth', 'reason' => 'RAM vs SMBIOS modules', 'hardware_refs' => ['ram']];

        if ((int) ($fingerprint['disk_count'] ?? 1) > 0) {
            $benches[] = 'storage';
            $reason = $nvme >= 2 ? "$nvme NVMe drives — multi-disk storage" : ($nvme === 1 ? 'Single NVMe sequential' : 'Storage sequential');
            $steps[] = ['id' => 'bench:storage', 'kind' => 'bench', 'label' => 'Storage', 'reason' => $reason, 'hardware_refs' => ['storage']];
        }

        if ($hasGpu) {
            $benches[] = 'gpu';
            $steps[] = ['id' => 'bench:gpu', 'kind' => 'bench', 'label' => 'GPU compute', 'reason' => 'Discrete GPU detected', 'hardware_refs' => ['gpu']];
            $stressId = 'combined';
            $stressSec = 180;
            $stressReason = 'Discrete GPU — combined soak';
        } elseif ($isLaptop) {
            $stressId = 'quick';
            $stressSec = 90;
            $stressReason = 'Laptop — shorter thermal soak';
            $findings[] = ['severity' => 'info', 'code' => 'adaptive_skip_gpu', 'detail' => 'No discrete GPU — GPU bench skipped'];
        } else {
            $stressId = 'combined';
            $stressSec = 120;
            $stressReason = 'Desktop without discrete GPU — moderate CPU stress';
            $findings[] = ['severity' => 'info', 'code' => 'adaptive_skip_gpu', 'detail' => 'No discrete GPU — GPU bench skipped'];
        }

        if ($isLaptop && count((array) ($devices['battery'] ?? [])) > 0) {
            $steps[] = ['id' => 'sensor:battery', 'kind' => 'sensor', 'label' => 'Battery / AC path', 'reason' => 'Laptop battery present', 'hardware_refs' => ['battery']];
        }

        $steps[] = [
            'id' => 'stress',
            'kind' => 'stress',
            'label' => 'Stress: ' . $stressId,
            'reason' => $stressReason,
            'hardware_refs' => $hasGpu ? ['cpu', 'gpu'] : ['cpu'],
            'params' => ['id' => $stressId, 'seconds' => $stressSec],
        ];

        return [
            'steps' => $steps,
            'benches' => $benches,
            'stress_id' => $stressId,
            'stress_seconds' => $stressSec,
            'gated' => false,
            'gate_reason' => null,
            'findings' => $findings,
            'duration_hint_min' => (int) round(2 + count($benches) * 1.5 + $stressSec / 60),
        ];
    }

    /** @param array<string, mixed> $input @return array<string, mixed> */
    public function start(array $input): array
    {
        $profileId = strtolower(trim((string) ($input['profile'] ?? 'adaptive')));
        $profiles = $this->profiles();
        if (!isset($profiles[$profileId])) {
            $profileId = 'adaptive';
        }
        $profile = $profiles[$profileId];
        $plan = null;
        $steps = $this->stepList($profile);
        if (!empty($profile['adaptive']) || $profileId === 'adaptive') {
            $plan = $this->planPreview($input);
            $steps = [];
            foreach ((array) ($plan['steps'] ?? []) as $s) {
                if (!is_array($s)) {
                    continue;
                }
                $steps[] = [
                    'id' => (string) ($s['id'] ?? ''),
                    'label' => (string) ($s['label'] ?? $s['id'] ?? ''),
                    'reason' => (string) ($s['reason'] ?? ''),
                    'kind' => (string) ($s['kind'] ?? ''),
                ];
            }
            if ($steps === []) {
                $steps = $this->stepList($profiles['standard']);
                $profileId = 'standard';
                $profile = $profiles['standard'];
            }
        }
        $id = bin2hex(random_bytes(8));
        $job = [
            'id' => $id,
            'profile' => $profileId,
            'label' => $plan['label'] ?? $profile['label'],
            'status' => 'pending',
            'progress' => 0,
            'step' => 'awaiting_probe',
            'steps' => $steps,
            'plan' => $plan,
            'created_at' => gmdate('c'),
            'updated_at' => gmdate('c'),
            'cancel_requested' => false,
            'fp' => substr(trim((string) ($input['fp'] ?? $input['fingerprint'] ?? '')), 0, 64),
            'result' => null,
            'error' => null,
            'resumable' => true,
            'probe_job' => null,
            'probe_payload' => null,
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
        // Soft-cancel: keep probe payload so finalize / resume can still run.
        $hasProbeWork = !empty($job['probe_job']) || !empty($job['probe_payload']);
        $job['status'] = $hasProbeWork ? 'awaiting_finalize' : 'cancelled';
        $job['step'] = $hasProbeWork ? 'awaiting_finalize' : 'cancelled';
        $job['resumable'] = $hasProbeWork;
        $job['updated_at'] = gmdate('c');
        $this->write($job);

        return $job;
    }

    /**
     * Discard a resumable job (user explicit discard only).
     *
     * @return array<string, mixed>|null
     */
    public function discard(string $id): ?array
    {
        $job = $this->read($id);
        if ($job === null) {
            return null;
        }
        $job['status'] = 'discarded';
        $job['step'] = 'discarded';
        $job['resumable'] = false;
        $job['cancel_requested'] = true;
        $job['updated_at'] = gmdate('c');
        $this->write($job);

        return $job;
    }

    /**
     * List jobs that can be resumed or finalized after a UI crash.
     *
     * @return list<array<string, mixed>>
     */
    public function listResumable(int $limit = 10): array
    {
        $out = [];
        if (!is_dir($this->dir)) {
            return $out;
        }
        $files = glob($this->dir . '/*.json') ?: [];
        usort($files, static fn ($a, $b) => filemtime($b) <=> filemtime($a));
        foreach ($files as $file) {
            if (count($out) >= $limit) {
                break;
            }
            $data = json_decode((string) file_get_contents($file), true);
            if (!is_array($data)) {
                continue;
            }
            $status = (string) ($data['status'] ?? '');
            $resumable = !empty($data['resumable'])
                || in_array($status, ['pending', 'running', 'awaiting_finalize'], true)
                || ($status === 'failed' && !empty($data['probe_job']));
            if (!$resumable || $status === 'completed' || $status === 'discarded') {
                continue;
            }
            $out[] = [
                'id' => $data['id'] ?? basename($file, '.json'),
                'profile' => $data['profile'] ?? null,
                'label' => $data['label'] ?? null,
                'status' => $status,
                'progress' => $data['progress'] ?? 0,
                'step' => $data['step'] ?? null,
                'updated_at' => $data['updated_at'] ?? null,
                'resumable' => true,
                'probe_job' => $data['probe_job'] ?? null,
            ];
        }

        return $out;
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
            $probeStatus = (string) ($patch['probe_job']['status'] ?? '');
            if ($probeStatus === 'completed') {
                $job['status'] = 'awaiting_finalize';
                $job['step'] = 'awaiting_finalize';
                $job['resumable'] = true;
            } elseif (in_array($probeStatus, ['running', 'interrupted'], true)) {
                $job['status'] = 'running';
                $job['resumable'] = true;
            }
        }
        if (isset($patch['probe_payload']) && is_array($patch['probe_payload'])) {
            $job['probe_payload'] = $patch['probe_payload'];
            $job['resumable'] = true;
        }
        $job['updated_at'] = gmdate('c');
        $this->write($job);

        return $job;
    }

    /**
     * Finalize with probe suite payload: analysis, certificate, graph, advisor cards.
     * Accepts completed probe work even if the PHP job was soft-cancelled or marked failed.
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

        $probePayload = (array) ($input['probe'] ?? $input['agent'] ?? $job['probe_payload'] ?? []);
        $suiteRun = (array) ($input['suite'] ?? $input['probe_suite'] ?? []);
        if ($suiteRun === [] && is_array($job['probe_job'] ?? null)) {
            $pj = $job['probe_job'];
            $suiteRun = [
                'status' => $pj['status'] ?? null,
                'benches' => $pj['benches'] ?? [],
                'stress' => $pj['stress'] ?? [],
                'samples' => $pj['samples'] ?? [],
                'duration_s' => $pj['duration_s'] ?? null,
                'plan' => $pj['plan'] ?? null,
            ];
            if ($probePayload === [] && is_array($pj['probe'] ?? null)) {
                $probePayload = $pj['probe'];
            }
        }

        $hasWork = $probePayload !== [] || !empty($suiteRun['benches']) || !empty($suiteRun['stress']);
        // Only hard-block pure cancel with zero probe work.
        if (($job['status'] ?? '') === 'cancelled' && !$hasWork) {
            return $job;
        }
        if (($job['status'] ?? '') === 'discarded') {
            throw new \InvalidArgumentException('Suite job was discarded');
        }
        if (($job['status'] ?? '') === 'completed' && is_array($job['result'] ?? null)) {
            return $job;
        }

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
            'profile' => $job['profile'] ?? 'adaptive',
            'benches' => $benches,
            'stress' => $stress,
            'duration_s' => $suiteRun['duration_s'] ?? null,
            'plan' => $job['plan'] ?? $suiteRun['plan'] ?? null,
        ];
        if (!empty($input['fingerprint']) && is_array($input['fingerprint'])) {
            $analysis['fingerprint'] = $input['fingerprint'];
        }
        if (!empty($input['platform']) && is_array($input['platform'])) {
            $analysis['platform'] = $input['platform'];
        }
        if (is_array($analysis['silicon_dossier'] ?? null)) {
            if (empty($analysis['silicon_dossier']['fingerprint']) && !empty($analysis['fingerprint'])) {
                $analysis['silicon_dossier']['fingerprint'] = $analysis['fingerprint'];
            }
            if (empty($analysis['silicon_dossier']['platform']) && !empty($analysis['platform'])) {
                $analysis['silicon_dossier']['platform'] = $analysis['platform'];
            }
        }

        $cert = (new StressCertificateService())->issue($stress !== [] ? $stress : [
            'id' => 'suite',
            'label' => 'Full Lab stress',
            'status' => ($suiteRun['status'] ?? 'ok') === 'failed' ? 'failed' : 'ok',
        ], $samples);
        if (($stress['id'] ?? '') === 'oracle' || !empty($stress['oracle_steps'])) {
            $cert = (new StabilityOracleService())->enrichCertificate($cert, $stress);
        }
        $cert['timeline'] = $this->buildTimeline($samples);
        $analysis['stress_certificate'] = $cert;
        $analysis['silicon_dossier'] = (new SiliconDossierService())->present(
            $probePayload !== [] ? $probePayload : $normalized
        );

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
        // Stability Oracle first-class on verdict cards
        if (!empty($cert['oracle_grade']) || isset($cert['stability_margin_pct'])) {
            array_unshift($analysis['advisor_cards'], [
                'title' => 'Stability Oracle',
                'body' => sprintf(
                    'Grade %s · margin %s%% · verdict %s',
                    (string) ($cert['oracle_grade'] ?? '—'),
                    (string) ($cert['stability_margin_pct'] ?? '—'),
                    (string) ($cert['verdict'] ?? '—')
                ),
                'severity' => (($cert['verdict'] ?? '') === 'fail' || ($cert['verdict'] ?? '') === 'failed') ? 'critical' : 'info',
                'source' => 'stability_oracle',
            ]);
        }
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
        $sessionExport = (new LabSessionService())->export($analysis, [
            'fingerprint' => $fp,
            'profile' => $job['profile'] ?? 'standard',
            'probe_version' => '6',
        ]);
        $analysis['session_hash'] = $sessionExport['session']['session_hash'];
        $assembly = (new AssemblyCertificateService())->build($analysis, [
            'token' => $saved['token'] ?? null,
            'shop_name' => (new SettingsService())->shopName(),
            'session_hash' => $sessionExport['session']['session_hash'],
        ]);

        $job['status'] = 'completed';
        $job['progress'] = 100;
        $job['step'] = 'done';
        $job['resumable'] = false;
        $job['updated_at'] = gmdate('c');
        $job['result'] = [
            'analysis' => $analysis,
            'saved' => $saved,
            'report' => [
                'title' => $export['title'],
                'document' => $export['document'],
            ],
            'report_html' => $export['html'],
            'assembly_certificate' => $assembly['document'],
            'assembly_certificate_html' => $assembly['html'],
            'pclab_session' => $sessionExport['session'],
            'pclab_session_file' => $sessionExport['filename'],
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
            if ($id === 'cpu' || $id === 'cpu-mt' || $id === 'cpu_mt') {
                if (isset($row['score'])) {
                    $metrics['cpu_score'] = (int) $row['score'];
                }
                if (isset($row['ops_per_sec'])) {
                    $metrics['cpu_ops'] = $row['ops_per_sec'];
                }
            }
            if ($id === 'cpu_cache' && isset($row['score'])) {
                $metrics['cpu_cache_score'] = (int) $row['score'];
            }
            if ($id === 'memory') {
                if (isset($row['bandwidth_mb_s'])) {
                    $metrics['mem_bandwidth_mb_s'] = $row['bandwidth_mb_s'];
                } elseif (isset($row['score'])) {
                    $metrics['mem_bandwidth_mb_s'] = $row['score'];
                }
            }
            if ($id === 'storage') {
                $seqRead = $row['seq_read_mb_s'] ?? $row['seq_read_mbps'] ?? null;
                $seqWrite = $row['seq_write_mb_s'] ?? $row['seq_write_mbps'] ?? null;
                if ($seqRead !== null) {
                    $metrics['storage_read_mb_s'] = $seqRead;
                }
                if ($seqWrite !== null) {
                    $metrics['storage_write_mb_s'] = $seqWrite;
                }
                if (isset($row['score'])) {
                    $metrics['storage_score'] = $row['score'];
                }
            }
            if ($id === 'gpu' && isset($row['score'])) {
                $metrics['gpu_score'] = (int) $row['score'];
                if (isset($row['engine'])) {
                    $metrics['gpu_engine'] = (string) $row['engine'];
                }
                if (isset($row['gflops'])) {
                    $metrics['gpu_gflops'] = $row['gflops'];
                }
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
