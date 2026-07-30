<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Turns probe driver/device JSON into assembler-facing action cards.
 */
class DiagnosticDriverAdvisorService
{
    /** @param array<string, mixed> $probe */
    public function present(array $probe): array
    {
        $drivers = (array) ($probe['drivers'] ?? []);
        $devices = (array) ($probe['devices'] ?? []);
        if ($drivers === [] && isset($probe['advice'])) {
            $drivers = $probe;
        }

        $actions = [];
        foreach ((array) ($drivers['actions'] ?? []) as $a) {
            if (!is_array($a)) {
                continue;
            }
            $actions[] = [
                'severity' => (string) ($a['severity'] ?? 'info'),
                'code' => (string) ($a['code'] ?? ''),
                'title' => (string) ($a['title'] ?? ''),
                'detail' => (string) ($a['detail'] ?? ''),
                'category' => (string) ($a['category'] ?? ''),
                'device' => (string) ($a['device'] ?? ''),
                'priority' => (int) ($a['priority'] ?? 50),
                'links' => $this->links((array) ($a['links'] ?? [])),
            ];
        }

        $queue = [];
        foreach ((array) ($drivers['install_queue'] ?? []) as $step) {
            if (!is_array($step)) {
                continue;
            }
            $queue[] = [
                'id' => (string) ($step['id'] ?? ''),
                'label' => (string) ($step['label'] ?? ''),
                'why' => (string) ($step['why'] ?? ''),
                'status' => (string) ($step['status'] ?? 'ok'),
                'action_count' => count((array) ($step['actions'] ?? [])),
                'links' => $this->links((array) ($step['links'] ?? [])),
            ];
        }

        $gpus = [];
        foreach ((array) ($drivers['gpus'] ?? []) as $g) {
            if (!is_array($g)) {
                continue;
            }
            $gpus[] = [
                'name' => (string) ($g['name'] ?? ''),
                'vendor' => (string) ($g['vendor'] ?? ''),
                'driver' => (string) ($g['driver'] ?? ''),
                'driver_date' => (string) ($g['driver_date'] ?? ''),
                'age_days' => $g['age_days'] ?? null,
                'is_stale' => !empty($g['is_stale']),
                'is_generic' => !empty($g['is_generic']),
                'updater_installed' => !empty($g['updater_installed']),
                'updater_name' => $g['updater_name'] ?? null,
                'links' => $this->links((array) ($g['links'] ?? [])),
            ];
        }

        $driverless = [];
        foreach ((array) ($devices['driverless'] ?? []) as $d) {
            if (!is_array($d)) {
                continue;
            }
            $driverless[] = [
                'name' => (string) ($d['name'] ?? ''),
                'category' => (string) ($d['category'] ?? ''),
                'problem_message' => (string) ($d['problem_message'] ?? ''),
                'vendor_name' => (string) ($d['vendor_name'] ?? ''),
                'instance_id' => (string) ($d['instance_id'] ?? ''),
            ];
        }

        $summary = (array) ($drivers['summary'] ?? []);
        $deviceSummary = (array) ($devices['summary'] ?? []);

        return [
            'score' => (int) ($drivers['score'] ?? 0),
            'grade' => (string) ($drivers['grade'] ?? '—'),
            'is_laptop' => !empty($drivers['is_laptop']),
            'board' => (array) ($drivers['board'] ?? []),
            'system' => (array) ($drivers['system'] ?? []),
            'summary' => [
                'critical_actions' => (int) ($summary['critical_actions'] ?? 0),
                'warn_actions' => (int) ($summary['warn_actions'] ?? 0),
                'info_actions' => (int) ($summary['info_actions'] ?? 0),
                'driverless_devices' => (int) ($deviceSummary['driverless'] ?? count($driverless)),
                'problem_devices' => (int) ($deviceSummary['problem_devices'] ?? 0),
                'total_devices' => (int) ($deviceSummary['total_devices'] ?? 0),
            ],
            'install_queue' => $queue,
            'actions' => $actions,
            'gpus' => $gpus,
            'driverless' => $driverless,
            'highlights' => $this->highlights($drivers, $devices, $actions),
        ];
    }

    /**
     * @param array<string, mixed> $drivers
     * @param array<string, mixed> $devices
     * @param list<array<string, mixed>> $actions
     * @return list<array{id: string, label_fa: string, value: mixed, unit?: string, severity?: string}>
     */
    private function highlights(array $drivers, array $devices, array $actions): array
    {
        $out = [];
        $score = (int) ($drivers['score'] ?? 0);
        $grade = (string) ($drivers['grade'] ?? '—');
        $out[] = [
            'id' => 'driver_score',
            'label_fa' => 'Driver health',
            'value' => $score . ' / ' . $grade,
            'severity' => $score < 60 ? 'critical' : ($score < 80 ? 'warn' : 'ok'),
        ];

        $critical = 0;
        foreach ($actions as $a) {
            if (($a['severity'] ?? '') === 'critical') {
                $critical++;
            }
        }
        if ($critical > 0) {
            $out[] = [
                'id' => 'driver_critical',
                'label_fa' => 'Must install',
                'value' => $critical,
                'severity' => 'critical',
            ];
        }

        $driverless = count((array) ($devices['driverless'] ?? []));
        if ($driverless > 0) {
            $out[] = [
                'id' => 'driverless',
                'label_fa' => 'No driver',
                'value' => $driverless,
                'severity' => 'critical',
            ];
        }

        return $out;
    }

    /**
     * @param list<mixed> $links
     * @return list<array{label: string, url: string, note: ?string}>
     */
    private function links(array $links): array
    {
        $out = [];
        foreach ($links as $l) {
            if (!is_array($l)) {
                continue;
            }
            $url = (string) ($l['url'] ?? '');
            if ($url === '') {
                continue;
            }
            $out[] = [
                'label' => (string) ($l['label'] ?? $url),
                'url' => $url,
                'note' => isset($l['note']) ? (string) $l['note'] : null,
            ];
        }

        return $out;
    }
}
