<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Shop / fleet mode — discover probes on localhost and queue batch jobs.
 */
class ShopFleetService
{
    public const DEFAULT_PROBE_PORT = 18765;
    public const FLEET_PORT_BASE = 18760;

    /** @return list<array<string, mixed>> */
    public function discover(int $timeoutMs = 800): array
    {
        $hosts = [];
        $base = (int) (getenv('PCLAB_FLEET_SCAN') ?: 0);
        if ($base <= 0) {
            return $this->localhostProbe();
        }
        for ($i = 1; $i <= min(32, $base); ++$i) {
            $port = self::FLEET_PORT_BASE + $i;
            $url = 'http://127.0.0.1:' . $port . '/health';
            $ctx = stream_context_create(['http' => ['timeout' => $timeoutMs / 1000]]);
            $raw = @file_get_contents($url, false, $ctx);
            if ($raw === false) {
                continue;
            }
            $json = json_decode($raw, true);
            if (is_array($json) && !empty($json['ok'])) {
                // Never forward secrets if a legacy probe still echoes them
                unset($json['auth_token']);
                $hosts[] = ['host' => '127.0.0.1', 'port' => $port, 'health' => $json];
            }
        }

        return array_merge($this->localhostProbe(), $hosts);
    }

    /**
     * Normalize and allowlist probe_base to loopback ports only.
     */
    public function allowlistProbeBase(?string $probeBase, ?int $fleetScanMax = null): ?string
    {
        $raw = trim((string) ($probeBase ?? ''));
        if ($raw === '') {
            $raw = 'http://127.0.0.1:' . self::DEFAULT_PROBE_PORT;
        }
        $parts = parse_url($raw);
        if (!is_array($parts)) {
            return null;
        }
        $scheme = strtolower((string) ($parts['scheme'] ?? 'http'));
        if ($scheme !== 'http' && $scheme !== 'https') {
            return null;
        }
        $host = strtolower((string) ($parts['host'] ?? ''));
        if ($host !== '127.0.0.1' && $host !== 'localhost' && $host !== '::1') {
            return null;
        }
        $port = (int) ($parts['port'] ?? self::DEFAULT_PROBE_PORT);
        $maxExtra = $fleetScanMax ?? (int) (getenv('PCLAB_FLEET_SCAN') ?: 0);
        $allowed = [self::DEFAULT_PROBE_PORT];
        for ($i = 1; $i <= min(32, max(0, $maxExtra)); ++$i) {
            $allowed[] = self::FLEET_PORT_BASE + $i;
        }
        if (!in_array($port, $allowed, true)) {
            return null;
        }

        return 'http://127.0.0.1:' . $port;
    }

    /**
     * @param list<string> $targets
     * @param array<string, mixed> $opts
     * @return array<string, mixed>
     */
    public function queueBurnIn(array $targets, string $profile = 'deep', array $opts = []): array
    {
        $probeBase = $this->allowlistProbeBase(
            isset($opts['probe_base']) ? (string) $opts['probe_base'] : null
        );
        if ($probeBase === null) {
            throw new \InvalidArgumentException('probe_base must be a loopback allowlisted port');
        }

        $queue = new JobQueueService();
        $jobs = [];
        $hours = (float) ($opts['duration_hours'] ?? 24);
        $seconds = isset($opts['duration_seconds']) ? (int) $opts['duration_seconds'] : null;
        foreach ($targets as $t) {
            $payload = [
                'target' => $t,
                'profile' => $profile,
                'duration_hours' => $hours,
                'probe_base' => $probeBase,
            ];
            if ($seconds !== null) {
                $payload['duration_seconds'] = $seconds;
            }
            $jobs[] = $queue->enqueue('burn_in_24h', $payload, $t);
        }

        return ['queued' => count($jobs), 'job_ids' => $jobs, 'probe_base' => $probeBase];
    }

    /** @return list<array<string, mixed>> */
    private function localhostProbe(): array
    {
        $cfg = require dirname(__DIR__, 2) . '/config/diagnostic.php';
        $wa = $cfg['probe_agent'] ?? $cfg['windows_agent'] ?? [];
        $port = (int) ($wa['local_port'] ?? self::DEFAULT_PROBE_PORT);
        $url = 'http://127.0.0.1:' . $port . '/health';
        $ctx = stream_context_create(['http' => ['timeout' => 1]]);
        $raw = @file_get_contents($url, false, $ctx);
        if ($raw === false) {
            return [];
        }
        $json = json_decode($raw, true);
        if (!is_array($json) || empty($json['ok'])) {
            return [];
        }
        unset($json['auth_token']);

        return [['host' => '127.0.0.1', 'port' => $port, 'health' => $json]];
    }
}
