<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Turns probe driver/device JSON into assembler-facing action cards.
 */
class DiagnosticDriverAdvisorService
{
    public function __construct(
        private ?DriverPackageMatcherService $matcher = null,
    ) {
        $this->matcher = $matcher ?? new DriverPackageMatcherService();
    }

    /** @param array<string, mixed> $probe */
    public function present(array $probe): array
    {
        $drivers = (array) ($probe['drivers'] ?? []);
        $devices = (array) ($probe['devices'] ?? []);
        if ($drivers === [] && isset($probe['advice'])) {
            $drivers = $probe;
        }

        $board = (array) ($drivers['board'] ?? []);
        $system = (array) ($drivers['system'] ?? []);

        $actions = [];
        foreach ((array) ($drivers['actions'] ?? []) as $a) {
            if (!is_array($a)) {
                continue;
            }
            $a = $this->matcher->enrich($a, $board, $system);
            $actions[] = [
                'severity' => (string) ($a['severity'] ?? 'info'),
                'code' => (string) ($a['code'] ?? ''),
                'title' => (string) ($a['title'] ?? ''),
                'detail' => (string) ($a['detail'] ?? ''),
                'category' => (string) ($a['category'] ?? ''),
                'device' => (string) ($a['device'] ?? ''),
                'priority' => (int) ($a['priority'] ?? 50),
                'instance_id' => (string) ($a['instance_id'] ?? ''),
                'vendor_id' => (string) ($a['vendor_id'] ?? ''),
                'device_id' => (string) ($a['device_id'] ?? ''),
                'bus' => (string) ($a['bus'] ?? ''),
                'inf' => (string) ($a['inf'] ?? ''),
                'provider' => (string) ($a['provider'] ?? ''),
                'driver_version' => (string) ($a['driver_version'] ?? ''),
                'driver_date' => (string) ($a['driver_date'] ?? ''),
                'age_days' => $a['age_days'] ?? null,
                'is_generic' => !empty($a['is_generic']),
                'is_stale' => !empty($a['is_stale']),
                'match_confidence' => (string) ($a['match_confidence'] ?? ''),
                'primary_link' => $this->linkOne((array) ($a['primary_link'] ?? [])),
                'links' => $this->links((array) ($a['links'] ?? [])),
                'install_method' => (string) ($a['install_method'] ?? ($a['primary_link']['install_method'] ?? '')),
                'package_version' => (string) ($a['package_version'] ?? ($a['primary_link']['version'] ?? '')),
                'installable' => !empty($a['installable']) || in_array((string) ($a['install_method'] ?? ''), ['inf_zip', 'msi', 'exe_silent', 'exe_ui', 'updater_app'], true),
            ];
        }

        $queue = [];
        foreach ((array) ($drivers['install_queue'] ?? []) as $step) {
            if (!is_array($step)) {
                continue;
            }
            $step = $this->matcher->enrich([
                'category' => (string) ($step['id'] ?? ''),
                'match_confidence' => (string) ($step['match_confidence'] ?? ''),
                'primary_link' => $step['primary_link'] ?? null,
                'links' => $step['links'] ?? [],
            ] + $step, $board, $system);
            $queue[] = [
                'id' => (string) ($step['id'] ?? ''),
                'label' => (string) ($step['label'] ?? ''),
                'why' => (string) ($step['why'] ?? ''),
                'status' => (string) ($step['status'] ?? 'ok'),
                'action_count' => count((array) ($step['actions'] ?? [])),
                'match_confidence' => (string) ($step['match_confidence'] ?? ''),
                'primary_link' => $this->linkOne((array) ($step['primary_link'] ?? [])),
                'links' => $this->links((array) ($step['links'] ?? [])),
                'install_method' => (string) ($step['install_method'] ?? ($step['primary_link']['install_method'] ?? 'open_url')),
                'package_version' => (string) ($step['package_version'] ?? ($step['primary_link']['version'] ?? '')),
                'package_url' => (string) ($step['package_url'] ?? ($step['primary_link']['package_url'] ?? '')),
                'installable' => !empty($step['installable']) || in_array((string) ($step['install_method'] ?? ''), ['inf_zip', 'msi', 'exe_silent', 'exe_ui', 'updater_app'], true),
            ];
        }

        $gpus = [];
        foreach ((array) ($drivers['gpus'] ?? []) as $g) {
            if (!is_array($g)) {
                continue;
            }
            $g = $this->matcher->enrich($g + ['category' => 'gpu', 'device' => $g['name'] ?? ''], $board, $system);
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
                'instance_id' => (string) ($g['instance_id'] ?? $g['pnp_device_id'] ?? ''),
                'vendor_id' => (string) ($g['vendor_id'] ?? ''),
                'device_id' => (string) ($g['device_id'] ?? ''),
                'match_confidence' => (string) ($g['match_confidence'] ?? ''),
                'primary_link' => $this->linkOne((array) ($g['primary_link'] ?? [])),
                'links' => $this->links((array) ($g['links'] ?? [])),
            ];
        }

        $driverless = [];
        foreach ((array) ($devices['driverless'] ?? []) as $d) {
            if (!is_array($d)) {
                continue;
            }
            $d = $this->matcher->enrich($d + ['device' => $d['name'] ?? ''], $board, $system);
            $driverless[] = [
                'name' => (string) ($d['name'] ?? ''),
                'category' => (string) ($d['category'] ?? ''),
                'problem_message' => (string) ($d['problem_message'] ?? ''),
                'vendor_name' => (string) ($d['vendor_name'] ?? ''),
                'instance_id' => (string) ($d['instance_id'] ?? ''),
                'vendor_id' => (string) ($d['vendor_id'] ?? ''),
                'device_id' => (string) ($d['device_id'] ?? ''),
                'bus' => (string) ($d['bus'] ?? ''),
                'match_confidence' => (string) ($d['match_confidence'] ?? ''),
                'primary_link' => $this->linkOne((array) ($d['primary_link'] ?? [])),
                'links' => $this->links((array) ($d['links'] ?? [])),
                'install_method' => (string) ($d['install_method'] ?? ($d['primary_link']['install_method'] ?? '')),
                'package_version' => (string) ($d['package_version'] ?? ($d['primary_link']['version'] ?? '')),
                'installable' => !empty($d['installable']) || in_array((string) ($d['install_method'] ?? ''), ['inf_zip', 'msi', 'exe_silent', 'exe_ui', 'updater_app'], true),
            ];
        }

        $wu = (array) ($drivers['windows_update'] ?? []);
        $wuCandidates = [];
        foreach ((array) ($wu['candidates'] ?? []) as $c) {
            if (!is_array($c)) {
                continue;
            }
            $wuCandidates[] = [
                'title' => (string) ($c['title'] ?? ''),
                'categories' => array_values(array_filter(array_map('strval', (array) ($c['categories'] ?? [])))),
                'kb' => (string) ($c['kb'] ?? ''),
            ];
        }

        $storeHints = [];
        foreach ((array) ($drivers['actions'] ?? []) as $a) {
            if (!is_array($a) || ($a['code'] ?? '') !== 'store_newer') {
                continue;
            }
            $storeHints[] = [
                'device' => (string) ($a['device'] ?? ''),
                'detail' => (string) ($a['detail'] ?? ''),
                'instance_id' => (string) ($a['instance_id'] ?? ''),
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
                'driverless_devices' => (int) ($deviceSummary['driverless'] ?? $deviceSummary['driverless_count'] ?? count($driverless)),
                'problem_devices' => (int) ($deviceSummary['problem_devices'] ?? $deviceSummary['problem_count'] ?? 0),
                'total_devices' => (int) ($deviceSummary['total_devices'] ?? $deviceSummary['total'] ?? 0),
                'store_packages' => (int) ($summary['store_packages'] ?? 0),
                'wu_candidates' => (int) ($summary['wu_candidates'] ?? count($wuCandidates)),
            ],
            'install_queue' => $queue,
            'actions' => $actions,
            'gpus' => $gpus,
            'driverless' => $driverless,
            'windows_update' => [
                'available' => !empty($wu['available']),
                'scanned' => !empty($wu['scanned']),
                'note' => (string) ($wu['note'] ?? ''),
                'candidates' => $wuCandidates,
                'problem_devices' => array_values(array_filter(array_map(function ($d) {
                    if (!is_array($d)) {
                        return null;
                    }

                    return [
                        'name' => (string) ($d['name'] ?? ''),
                        'instance_id' => (string) ($d['instance_id'] ?? ''),
                        'problem' => (string) ($d['problem'] ?? ''),
                        'code' => (string) ($d['code'] ?? ''),
                        'vendor_id' => (string) ($d['vendor_id'] ?? ''),
                        'device_id' => (string) ($d['device_id'] ?? ''),
                    ];
                }, (array) ($wu['problem_devices'] ?? [])))),
            ],
            'store_hints' => $storeHints,
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
     * @param array<string, mixed> $link
     * @return array{label: string, url: string, note: ?string}|null
     */
    private function linkOne(array $link): ?array
    {
        $url = (string) ($link['url'] ?? '');
        if ($url === '') {
            return null;
        }

        return [
            'label' => (string) ($link['label'] ?? $url),
            'url' => $url,
            'note' => isset($link['note']) ? (string) $link['note'] : null,
        ];
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
            $one = $this->linkOne($l);
            if ($one !== null) {
                $out[] = $one;
            }
        }

        return $out;
    }
}
