<?php

declare(strict_types=1);

namespace App\Services;

use App\Database;

/**
 * Public pulse stats for Engine + Advisor lab signals (non-PII aggregates).
 */
final class DiagnosticIntelligencePulseService
{
    /** @return array<string, mixed> */
    public function publicPulse(int $toolsReplaced = 13): array
    {
        $stats = (new DiagnosticHistoryService())->stats();
        $activity = $this->recentActivity();

        return [
            'tagline' => 'Tools — not a store. Everything in one lab.',
            'engine' => [
                'label' => 'Engine',
                'role' => 'Depth · telemetry · RGB · safe OC',
                'deep_scans' => (int) ($stats['full_scans'] ?? 0),
                'orchestrations' => (int) ($activity['vakhsh_orchestrations'] ?? 0),
                'sensor_layers' => 11,
                'tools_unified' => $toolsReplaced,
                'live_line' => $this->engineLiveLine($stats, $activity),
            ],
            'advisor' => [
                'label' => 'Advisor',
                'role' => 'Insight · bottleneck · guidance',
                'insights_total' => (int) ($stats['total_scans'] ?? 0),
                'insights_today' => (int) ($stats['scans_today'] ?? 0),
                'avg_health_24h' => $stats['avg_health_24h'] ?? null,
                'bottlenecks_mapped' => $this->bottlenecksMapped(),
                'live_line' => $this->advisorLiveLine($stats, $activity),
            ],
            'neural' => [
                'whispers' => $this->whispers($stats, $activity, $toolsReplaced),
                'feed' => $this->feedLines(),
                'sync_label' => 'PCVerse local network',
            ],
        ];
    }

    private function bottlenecksMapped(): int
    {
        try {
            $pdo = Database::connection();
            $n = $pdo->query(
                "SELECT COUNT(*) FROM diagnostic_reports WHERE bottleneck_type IS NOT NULL AND bottleneck_type != ''"
            )->fetchColumn();

            return (int) $n;
        } catch (\Throwable) {
            return 0;
        }
    }

    /** @return array{vakhsh_orchestrations: int} */
    private function recentActivity(): array
    {
        return ['vakhsh_orchestrations' => 0];
    }

    /** @param array<string, mixed> $stats @param array<string, mixed> $activity */
    private function engineLiveLine(array $stats, array $activity): string
    {
        if (($activity['vakhsh_orchestrations'] ?? 0) > 0) {
            return sprintf('%d RGB/telemetry orchestrations — no separate iCUE/CAM stack', $activity['vakhsh_orchestrations']);
        }
        if ((int) ($stats['full_scans'] ?? 0) > 0) {
            return sprintf('%d deep scans · 11 sensor layers', (int) $stats['full_scans']);
        }

        return 'Ready — connect PCVerse Probe';
    }

    /** @param array<string, mixed> $stats @param array<string, mixed> $activity */
    private function advisorLiveLine(array $stats, array $activity): string
    {
        if (isset($stats['avg_health_24h']) && $stats['avg_health_24h'] !== null) {
            return sprintf('24h avg health: %s · bottleneck mapping', number_format((float) $stats['avg_health_24h'], 1));
        }
        if ((int) ($stats['total_scans'] ?? 0) > 0) {
            return sprintf('%d analyses completed — live feed active', (int) $stats['total_scans']);
        }

        return 'Waiting for your first scan';
    }

    /** @return list<string> */
    private function whispers(array $stats, array $activity, int $tools): array
    {
        return [
            sprintf('%d pro apps → one Probe. We are a lab, not a store.', $tools),
            'Engine adds depth · Advisor adds meaning — both run locally on your PC.',
            sprintf('%d bottlenecks mapped so far — anonymous aggregates only.', $this->bottlenecksMapped()),
            'GIF, telemetry, and OC stay on your machine. Only anonymized signals leave if you opt in.',
            'SignalRGB + Fan Control + HWiNFO — one lab, less RAM leak.',
        ];
    }

    /** @return list<array{line: string, ago: string}> */
    private function feedLines(): array
    {
        try {
            $db = Database::connection();
            $rows = $db->query(
                'SELECT mode, health_grade, bottleneck_type, form_factor, created_at
                 FROM diagnostic_reports ORDER BY id DESC LIMIT 8'
            )->fetchAll(\PDO::FETCH_ASSOC) ?: [];

            $out = [];
            foreach ($rows as $r) {
                $mode = ($r['mode'] ?? '') === 'lite' ? 'Advisor' : 'Engine';
                $bn = trim((string) ($r['bottleneck_type'] ?? ''));
                $line = $bn !== ''
                    ? sprintf('%s scan · grade %s · %s', $mode, $r['health_grade'], $bn)
                    : sprintf('%s scan · grade %s', $mode, $r['health_grade']);
                $out[] = [
                    'line' => $line,
                    'ago' => $this->ago((string) ($r['created_at'] ?? '')),
                ];
            }

            return $out;
        } catch (\Throwable) {
            return [];
        }
    }

    private function ago(string $createdAt): string
    {
        if ($createdAt === '') {
            return 'now';
        }
        $ts = strtotime($createdAt);
        if ($ts === false) {
            return 'now';
        }
        $d = time() - $ts;
        if ($d < 60) {
            return 'now';
        }
        if ($d < 3600) {
            return (int) floor($d / 60) . 'm ago';
        }
        if ($d < 86400) {
            return (int) floor($d / 3600) . 'h ago';
        }

        return (int) floor($d / 86400) . 'd ago';
    }
}
