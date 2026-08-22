<?php

declare(strict_types=1);

/**
 * Local job queue worker — leases one job at a time (burn_in_24h, batch).
 *
 * Usage:
 *   php bin/job-worker.php
 *   php bin/job-worker.php --once
 *   php bin/job-worker.php --type=burn_in_24h --lease=600
 */

$root = dirname(__DIR__);
require $root . '/vendor/autoload.php';

use App\Database;
use App\Services\JobQueueService;
use App\Services\LabSuiteService;
use App\Services\ProbeAuthService;
use App\Services\ShopFleetService;
use App\Support\Env;

Env::load($root . '/.env');
Database::migrate();

$once = in_array('--once', $argv, true);
$typeFilter = null;
$leaseSec = 300;
foreach ($argv as $arg) {
    if (str_starts_with($arg, '--type=')) {
        $typeFilter = substr($arg, 7);
    }
    if (str_starts_with($arg, '--lease=')) {
        $leaseSec = max(60, (int) substr($arg, 8));
    }
}

$owner = 'worker-' . gethostname() . '-' . getmypid();
$queue = new JobQueueService();

fwrite(STDOUT, "[job-worker] owner={$owner} once=" . ($once ? '1' : '0') . "\n");

do {
    $job = $queue->leaseNext($owner, $leaseSec, $typeFilter);
    if ($job === null) {
        if ($once) {
            fwrite(STDOUT, "[job-worker] idle — no jobs\n");
            exit(0);
        }
        sleep(5);
        continue;
    }

    $id = (string) ($job['id'] ?? '');
    $type = (string) ($job['type'] ?? '');
    fwrite(STDOUT, "[job-worker] leased {$id} type={$type}\n");

    try {
        $result = processJob($job, $queue, $owner, $leaseSec);
        $queue->complete($id, $result);
        fwrite(STDOUT, "[job-worker] completed {$id}\n");
    } catch (Throwable $e) {
        $attempts = (int) ($job['attempts'] ?? 1);
        $requeue = $attempts < 3;
        $queue->fail($id, $e->getMessage(), $requeue);
        fwrite(STDERR, "[job-worker] failed {$id}: {$e->getMessage()}" . ($requeue ? ' (requeued)' : '') . "\n");
    }
} while (!$once);

exit(0);

/**
 * @param array<string, mixed> $job
 * @return array<string, mixed>
 */
function processJob(array $job, JobQueueService $queue, string $owner, int $leaseSec): array
{
    $type = (string) ($job['type'] ?? '');
    $payload = is_array($job['payload'] ?? null) ? $job['payload'] : [];
    $id = (string) ($job['id'] ?? '');

    if ($type === 'burn_in_24h') {
        return runBurnIn($id, $payload, $queue, $owner, $leaseSec);
    }
    if ($type === 'suite_finalize') {
        $suiteId = (string) ($payload['suite_id'] ?? '');
        if ($suiteId === '') {
            throw new RuntimeException('suite_id required');
        }
        $svc = new LabSuiteService();
        $final = $svc->finalize($suiteId, $payload);

        return ['suite_id' => $suiteId, 'status' => $final['status'] ?? null];
    }

    throw new RuntimeException('unknown job type: ' . $type);
}

/**
 * @param array<string, mixed> $payload
 * @return array<string, mixed>
 */
function runBurnIn(string $jobId, array $payload, JobQueueService $queue, string $owner, int $leaseSec): array
{
    $hours = (float) ($payload['duration_hours'] ?? 24);
    // Cap wall clock for safety in worker; real soak uses probe stress seconds.
    $seconds = (int) min(86400, max(60, (int) round($hours * 3600)));
    // For lab UX / CI, allow override via payload.duration_seconds
    if (isset($payload['duration_seconds'])) {
        $seconds = max(30, min(86400, (int) $payload['duration_seconds']));
    }
    $profile = (string) ($payload['profile'] ?? 'deep');
    $probeBaseRaw = (string) ($payload['probe_base'] ?? 'http://127.0.0.1:18765');
    $probeBase = (new ShopFleetService())->allowlistProbeBase($probeBaseRaw);
    if ($probeBase === null) {
        throw new RuntimeException('probe_base not allowlisted for loopback fleet');
    }
    // Never trust client-supplied probe_token in job payload — read local token only.
    $resolved = (new ProbeAuthService())->resolve();
    $token = (string) ($resolved['token'] ?? '');

    $queue->updateProgress($jobId, 5, 'running');
    $queue->heartbeat($jobId, $owner, $leaseSec);

    // Start probe soak suite (uses soak profiles when available).
    $suiteProfile = match (true) {
        $seconds >= 3600 => 'soak_60',
        $seconds >= 1800 => 'soak_30',
        $seconds >= 900 => 'soak_15',
        default => $profile,
    };

    $startBody = json_encode(['profile' => $suiteProfile], JSON_UNESCAPED_UNICODE);
    $ctx = stream_context_create([
        'http' => [
            'method' => 'POST',
            'header' => "Content-Type: application/json\r\n"
                . ($token !== '' ? "X-PcLab-Token: {$token}\r\n" : ''),
            'content' => $startBody,
            'timeout' => 30,
        ],
    ]);
    $raw = @file_get_contents($probeBase . '/suite/start', false, $ctx);
    if ($raw === false) {
        throw new RuntimeException('probe suite/start failed');
    }
    $start = json_decode($raw, true);
    if (!is_array($start) || empty($start['ok'])) {
        throw new RuntimeException('probe refused burn-in: ' . ($start['error'] ?? 'unknown'));
    }

    $deadline = time() + $seconds + 120;
    $lastPct = 5;
    while (time() < $deadline) {
        $queue->heartbeat($jobId, $owner, $leaseSec);
        $stRaw = @file_get_contents($probeBase . '/suite/status', false, stream_context_create([
            'http' => ['timeout' => 10],
        ]));
        $st = is_string($stRaw) ? json_decode($stRaw, true) : null;
        $job = is_array($st) ? ($st['job'] ?? $st) : [];
        $pct = (int) ($job['progress'] ?? $lastPct);
        $lastPct = max($lastPct, $pct);
        $queue->updateProgress($jobId, min(95, $lastPct), 'running');
        $status = (string) ($job['status'] ?? '');
        if (in_array($status, ['completed', 'failed', 'cancelled', 'interrupted'], true)) {
            return [
                'burn_in' => true,
                'profile' => $suiteProfile,
                'probe_status' => $status,
                'probe_job' => $job,
                'duration_s' => $job['duration_s'] ?? null,
                'finished_at' => gmdate('c'),
            ];
        }
        sleep(5);
    }

    throw new RuntimeException('burn-in timed out waiting for probe suite');
}
