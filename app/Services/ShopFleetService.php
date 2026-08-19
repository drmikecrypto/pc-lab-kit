<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Shop / fleet mode — discover probes on LAN and queue batch jobs.
 */
class ShopFleetService
{
    /** @return list<array<string, mixed>> */
    public function discover(int $timeoutMs = 800): array
    {
        $hosts = [];
        $base = (int) (getenv('PCLAB_FLEET_SCAN') ?: 0);
        if ($base <= 0) {
            return $this->localhostProbe();
        }
        for ($i = 1; $i <= min(32, $base); ++$i) {
            $url = "http://127.0.0.1:1876{$i}/health";
            $ctx = stream_context_create(['http' => ['timeout' => $timeoutMs / 1000]]);
            $raw = @file_get_contents($url, false, $ctx);
            if ($raw === false) {
                continue;
            }
            $json = json_decode($raw, true);
            if (is_array($json) && !empty($json['ok'])) {
                $hosts[] = ['host' => "127.0.0.1", 'port' => 18760 + $i, 'health' => $json];
            }
        }

        return array_merge($this->localhostProbe(), $hosts);
    }

    /** @param list<string> $targets @return array<string, mixed> */
    public function queueBurnIn(array $targets, string $profile = 'deep'): array
    {
        $queue = new JobQueueService();
        $jobs = [];
        foreach ($targets as $t) {
            $jobs[] = $queue->enqueue('burn_in_24h', [
                'target' => $t,
                'profile' => $profile,
                'duration_hours' => 24,
            ], $t);
        }

        return ['queued' => count($jobs), 'job_ids' => $jobs];
    }

    /** @return list<array<string, mixed>> */
    private function localhostProbe(): array
    {
        $cfg = require dirname(__DIR__, 2) . '/config/diagnostic.php';
        $wa = $cfg['windows_agent'] ?? [];
        $port = (int) ($wa['local_port'] ?? 18765);
        $url = 'http://127.0.0.1:' . $port . '/health';
        $ctx = stream_context_create(['http' => ['timeout' => 1]]);
        $raw = @file_get_contents($url, false, $ctx);
        if ($raw === false) {
            return [];
        }
        $json = json_decode($raw, true);

        return is_array($json) && !empty($json['ok'])
            ? [['host' => '127.0.0.1', 'port' => $port, 'health' => $json]]
            : [];
    }
}
