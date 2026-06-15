<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Formats probe v3 telemetry into UI panels (HWiNFO-class presentation).
 */
class DiagnosticTelemetryService
{
    /** @param array<string, mixed> $probe Raw agent JSON */
    public function present(array $probe): array
    {
        if (!isset($probe['telemetry']) && isset($probe['cpu']['architecture'])) {
            $probe = [
                'telemetry' => $probe,
                'probe_version' => (int) ($probe['probe_version'] ?? 3),
                'collected_at' => $probe['collected_at'] ?? null,
            ];
        }

        $tel = (array) ($probe['telemetry'] ?? []);
        if ($tel === [] && ($probe['probe_version'] ?? 0) >= 2) {
            $tel = $this->legacyShim($probe);
        }

        return [
            'probe_version' => (int) ($probe['probe_version'] ?? 0),
            'collected_at' => $probe['collected_at'] ?? null,
            'tabs' => [
                ['id' => 'cpu', 'label_fa' => 'CPU', 'icon' => 'cpu', 'sections' => $this->cpuPanels($tel)],
                ['id' => 'gpu', 'label_fa' => 'GPU', 'icon' => 'gpu', 'sections' => $this->gpuPanels($tel)],
                ['id' => 'power', 'label_fa' => 'Power / VRM', 'icon' => 'power', 'sections' => $this->powerPanels($tel)],
                ['id' => 'ram', 'label_fa' => 'RAM', 'icon' => 'ram', 'sections' => $this->ramPanels($tel)],
                ['id' => 'storage', 'label_fa' => 'Storage', 'icon' => 'ssd', 'sections' => $this->storagePanels($tel)],
                ['id' => 'gaming', 'label_fa' => 'Render / Game', 'icon' => 'game', 'sections' => $this->gamingPanels($tel)],
                ['id' => 'sensors', 'label_fa' => 'All Sensors', 'icon' => 'sensor', 'sections' => $this->sensorPanels($tel)],
                ['id' => 'board', 'label_fa' => 'Motherboard', 'icon' => 'board', 'sections' => $this->boardPanels($tel)],
                ['id' => 'os', 'label_fa' => 'OS / Kernel', 'icon' => 'kernel', 'sections' => $this->osPanels($tel)],
                ['id' => 'network', 'label_fa' => 'Network', 'icon' => 'net', 'sections' => $this->networkPanels($tel)],
                ['id' => 'geek', 'label_fa' => 'Deep / Geek', 'icon' => 'geek', 'sections' => $this->geekPanels($tel)],
            ],
            'highlights' => $this->highlights($tel, $probe),
            'charts' => [
                'spike_map' => $this->spikeMapChart($tel),
                'cstate_bars' => $this->cstateBars($tel),
            ],
            'hwmon_available' => !empty($tel['hwmon']['available']),
        ];
    }

    /** @return list<array{id: string, label_fa: string, value: mixed, unit?: string, severity?: string}> */
    private function highlights(array $tel, array $probe): array
    {
        $cpu = (array) ($tel['cpu'] ?? []);
        $gpu = (array) ($tel['gpu'] ?? []);
        $out = [];

        $pkg = $cpu['thermal']['package_c'] ?? null;
        if ($pkg) {
            $out[] = ['id' => 'cpu_temp', 'label_fa' => 'CPU Package', 'value' => $pkg, 'unit' => '°C', 'severity' => $pkg > 90 ? 'critical' : ($pkg > 80 ? 'warn' : 'ok')];
        }
        $gt = $gpu['thermal']['core_c'] ?? null;
        if ($gt) {
            $out[] = ['id' => 'gpu_temp', 'label_fa' => 'GPU Core', 'value' => $gt, 'unit' => '°C', 'severity' => $gt > 88 ? 'critical' : ($gt > 75 ? 'warn' : 'ok')];
        }
        $pw = $gpu['power']['draw_w'] ?? null;
        if ($pw) {
            $out[] = ['id' => 'gpu_power', 'label_fa' => 'GPU Power', 'value' => $pw, 'unit' => 'W', 'severity' => 'ok'];
        }
        $util = $gpu['render']['gpu_util_pct'] ?? null;
        if ($util !== null) {
            $out[] = ['id' => 'gpu_util', 'label_fa' => 'GPU Util', 'value' => $util, 'unit' => '%', 'severity' => $util > 95 ? 'warn' : 'ok'];
        }
        $dpc = $cpu['scheduler']['dpc_pct'] ?? null;
        if ($dpc !== null && $dpc > 5) {
            $out[] = ['id' => 'dpc', 'label_fa' => 'DPC Load', 'value' => $dpc, 'unit' => '%', 'severity' => 'warn'];
        }
        $cores = $cpu['architecture']['cores'] ?? null;
        if ($cores) {
            $out[] = ['id' => 'cores', 'label_fa' => 'Cores / Threads', 'value' => ($cpu['architecture']['cores'] ?? '?') . 'C / ' . ($cpu['architecture']['threads'] ?? '?') . 'T', 'severity' => 'ok'];
        }
        $vcore = $tel['power']['vcore'] ?? ($cpu['power']['vcore'] ?? null);
        if ($vcore) {
            $out[] = ['id' => 'vcore', 'label_fa' => 'Vcore', 'value' => $vcore, 'unit' => 'V', 'severity' => 'ok'];
        }
        $gaming = (array) ($tel['gaming'] ?? []);
        if (!empty($gaming['fps_avg'])) {
            $out[] = ['id' => 'fps', 'label_fa' => 'FPS (PresentMon)', 'value' => $gaming['fps_avg'], 'unit' => '', 'severity' => 'ok'];
        }
        if (!empty($gaming['frametime_p99_ms'])) {
            $out[] = ['id' => 'ft_p99', 'label_fa' => 'FT P99', 'value' => $gaming['frametime_p99_ms'], 'unit' => 'ms', 'severity' => ($gaming['frametime_p99_ms'] > 20 ? 'warn' : 'ok')];
        }
        if (!empty($gaming['spike_count'])) {
            $sc = (int) $gaming['spike_count'];
            $out[] = ['id' => 'spikes', 'label_fa' => 'Frametime Spikes', 'value' => $sc, 'unit' => '', 'severity' => ($sc > 10 ? 'warn' : 'ok')];
        }
        $ram = (array) ($tel['ram'] ?? []);
        if (!empty($ram['primary_timings']['cl'])) {
            $t = $ram['primary_timings'];
            $out[] = ['id' => 'ram_cl', 'label_fa' => 'RAM CL', 'value' => ($t['cl'] ?? '?') . '-' . ($t['trcd'] ?? '?') . '-' . ($t['trp'] ?? '?'), 'unit' => '', 'severity' => 'ok'];
        }
        if (!empty($ram['primary_die']) && $ram['primary_die'] !== 'Unknown') {
            $out[] = ['id' => 'ram_die', 'label_fa' => 'RAM Die', 'value' => (string) $ram['primary_die'], 'severity' => 'ok'];
        }

        return $out;
    }

    /** @return list<array{title_fa: string, rows: list<array{key: string, value: string}>}> */
    private function powerPanels(array $tel): array
    {
        $power = (array) ($tel['power'] ?? []);
        $hwmon = (array) ($tel['hwmon'] ?? []);
        $panels = [
            $this->panel('Package Power', [
                ['key' => 'Vcore', 'value' => (string) ($power['vcore'] ?? $tel['cpu']['power']['vcore'] ?? '—') . ' V'],
            ]),
        ];

        foreach (['Voltage' => 'Rail Voltages', 'Power' => 'Power Draw', 'Current' => 'Amperage'] as $type => $title) {
            $byType = (array) ($hwmon['by_type'] ?? []);
            $items = (array) ($byType[$type] ?? []);
            if ($items === [] && !empty($hwmon['sensors_flat'])) {
                $items = array_values(array_filter((array) $hwmon['sensors_flat'], fn ($s) => is_array($s) && ($s['type'] ?? '') === $type));
            }
            if ($items === []) {
                continue;
            }
            $rows = [];
            foreach (array_slice($items, 0, 24) as $s) {
                if (!is_array($s)) {
                    continue;
                }
                $rows[] = [
                    'key' => (string) ($s['name'] ?? $s['hardware'] ?? '?'),
                    'value' => ($s['value'] ?? '—') . ' ' . ($s['unit'] ?? ''),
                ];
            }
            if ($rows !== []) {
                $panels[] = $this->panel($title . ' (LHM)', $rows);
            }
        }

        return $panels;
    }

    private function gamingPanels(array $tel): array
    {
        $g = (array) ($tel['gaming'] ?? []);
        $pm = (array) ($tel['presentmon'] ?? []);
        $map = (array) ($g['spike_map'] ?? []);

        $panels = [
            $this->panel('PresentMon / Render', [
                ['key' => 'FPS avg', 'value' => (string) ($g['fps_avg'] ?? '—')],
                ['key' => 'Frametime mean', 'value' => (string) ($g['frametime_mean_ms'] ?? '—') . ' ms'],
                ['key' => 'Frametime P99', 'value' => (string) ($g['frametime_p99_ms'] ?? '—') . ' ms'],
                ['key' => 'Spike count', 'value' => (string) ($g['spike_count'] ?? ($map['stats']['spike_count'] ?? '—'))],
                ['key' => 'Samples', 'value' => (string) ($g['samples'] ?? $pm['sample_count'] ?? '—')],
                ['key' => 'Source', 'value' => (string) ($g['source'] ?? '—')],
                ['key' => 'PresentMon', 'value' => !empty($pm['available']) ? 'Active' : ($pm['note'] ?? 'Optional — add tools/PresentMon.exe')],
            ]),
        ];

        if (!empty($map['spikes'])) {
            $rows = [];
            foreach (array_slice($map['spikes'], 0, 12) as $s) {
                $rows[] = [
                    'key' => round((float) ($s['t_ms'] ?? 0)) . ' ms',
                    'value' => ($s['ft_ms'] ?? '—') . ' ms · ' . ($s['severity'] ?? '') . ' · ' . ($s['likely_cause'] ?? ''),
                ];
            }
            $panels[] = $this->panel('Top spikes', $rows);
        }

        return $panels;
    }

    /** @return list<array{title_fa: string, rows: list<array{key: string, value: string}>}> */
    private function sensorPanels(array $tel): array
    {
        $hwmon = (array) ($tel['hwmon'] ?? []);
        $flat = (array) ($hwmon['sensors_flat'] ?? []);
        if ($flat === []) {
            return [$this->panel('LibreHardwareMonitor', [['key' => 'Status', 'value' => 'PcVerseHwMon.exe not available — rebuild agent bundle']])];
        }

        $byHw = [];
        foreach ($flat as $s) {
            if (!is_array($s)) {
                continue;
            }
            $hw = (string) ($s['hardware'] ?? 'System');
            $byHw[$hw][] = $s;
        }

        $panels = [];
        foreach ($byHw as $hw => $sensors) {
            $rows = [];
            foreach ($sensors as $s) {
                $rows[] = [
                    'key' => ($s['type'] ?? '') . ' · ' . ($s['name'] ?? ''),
                    'value' => ($s['value'] ?? '—') . ' ' . ($s['unit'] ?? ''),
                ];
            }
            $panels[] = $this->panel($hw, $rows);
        }

        return $panels;
    }

    /** @return list<array{title_fa: string, rows: list<array{key: string, value: string}>}> */
    private function cpuPanels(array $tel): array
    {
        $cpu = (array) ($tel['cpu'] ?? []);
        $arch = (array) ($cpu['architecture'] ?? []);
        $clocks = (array) ($cpu['clocks'] ?? []);
        $sched = (array) ($cpu['scheduler'] ?? []);
        $thermal = (array) ($cpu['thermal'] ?? []);
        $cache = (array) ($cpu['cache'] ?? []);

        $panels = [
            $this->panel('معماری', [
                ['key' => 'Model', 'value' => $arch['model'] ?? '—'],
                ['key' => 'Cores / Threads', 'value' => ($arch['cores'] ?? '—') . ' / ' . ($arch['threads'] ?? '—')],
                ['key' => 'Stepping / Rev', 'value' => ($arch['stepping'] ?? '—') . ' / ' . ($arch['revision'] ?? '—')],
                ['key' => 'Socket', 'value' => $arch['socket'] ?? '—'],
                ['key' => 'Virtualization', 'value' => !empty($arch['virtualization']) ? 'Yes' : 'No'],
                ['key' => 'SMT/HT', 'value' => !empty($arch['smt_enabled']) ? 'Enabled' : 'Disabled'],
                ['key' => 'ISA', 'value' => implode(', ', (array) ($arch['instruction_sets'] ?? [])) ?: '—'],
            ]),
            $this->panel('فرکانس و کلاک', [
                ['key' => 'Base MHz', 'value' => (string) ($clocks['base_mhz'] ?? '—')],
                ['key' => 'Current MHz', 'value' => (string) ($clocks['current_mhz'] ?? '—')],
                ['key' => 'Effective MHz', 'value' => (string) ($clocks['effective_mhz'] ?? '—')],
                ['key' => 'Queue Length', 'value' => (string) ($clocks['queue_length'] ?? '—')],
            ]),
            $this->panel('Scheduler / Kernel', [
                ['key' => 'Context switches/s', 'value' => $this->fmtNum($sched['context_switches_per_sec'] ?? null)],
                ['key' => 'Interrupt %', 'value' => $this->fmtPct($sched['interrupt_pct'] ?? null)],
                ['key' => 'DPC %', 'value' => $this->fmtPct($sched['dpc_pct'] ?? null)],
                ['key' => 'Privileged %', 'value' => $this->fmtPct($sched['privileged_pct'] ?? null)],
                ['key' => 'User %', 'value' => $this->fmtPct($sched['user_pct'] ?? null)],
            ]),
            $this->panel('حرارت', [
                ['key' => 'Package °C', 'value' => (string) ($thermal['package_c'] ?? '—')],
                ['key' => 'Zones', 'value' => implode(', ', array_map('strval', (array) ($thermal['per_core_c'] ?? []))) ?: '—'],
            ]),
            $this->panel('Cache', [
                ['key' => 'L2 KB', 'value' => (string) ($cache['l2_kb'] ?? '—')],
                ['key' => 'L3 KB', 'value' => (string) ($cache['l3_kb'] ?? '—')],
            ]),
        ];

        $perCore = (array) ($clocks['per_core'] ?? []);
        if ($perCore !== []) {
            $rows = [];
            foreach (array_slice($perCore, 0, 32) as $c) {
                $rows[] = [
                    'key' => (string) ($c['core_id'] ?? '?'),
                    'value' => ($c['mhz'] ?? '—') . ' MHz · ' . ($c['util_pct'] ?? '—') . '% util · idle ' . ($c['idle_pct'] ?? '—') . '%',
                ];
            }
            $panels[] = $this->panel('Per-core (live)', $rows);
        }

        return $panels;
    }

    private function gpuPanels(array $tel): array
    {
        $gpu = (array) ($tel['gpu'] ?? []);
        $clocks = (array) ($gpu['clocks'] ?? []);
        $power = (array) ($gpu['power'] ?? []);
        $thermal = (array) ($gpu['thermal'] ?? []);
        $mem = (array) ($gpu['memory'] ?? []);
        $pcie = (array) ($gpu['pcie'] ?? []);
        $render = (array) ($gpu['render'] ?? []);

        $panels = [
            $this->panel('کلاک', [
                ['key' => 'Core MHz', 'value' => (string) ($clocks['core_mhz'] ?? '—')],
                ['key' => 'Memory MHz', 'value' => (string) ($clocks['mem_mhz'] ?? '—')],
                ['key' => 'SM MHz', 'value' => (string) ($clocks['sm_mhz'] ?? '—')],
                ['key' => 'Max Core', 'value' => (string) ($clocks['max_core'] ?? '—')],
            ]),
            $this->panel('توان', [
                ['key' => 'Draw W', 'value' => (string) ($power['draw_w'] ?? '—')],
                ['key' => 'Limit W', 'value' => (string) ($power['limit_w'] ?? '—')],
            ]),
            $this->panel('حرارت / فن', [
                ['key' => 'Core °C', 'value' => (string) ($thermal['core_c'] ?? '—')],
                ['key' => 'VRAM °C', 'value' => (string) ($thermal['vram_c'] ?? '—')],
                ['key' => 'Fan %', 'value' => (string) ($thermal['fan_pct'] ?? '—')],
            ]),
            $this->panel('VRAM', [
                ['key' => 'Total MB', 'value' => (string) ($mem['vram_total_mb'] ?? '—')],
                ['key' => 'Used MB', 'value' => (string) ($mem['vram_used_mb'] ?? '—')],
                ['key' => 'Util %', 'value' => (string) ($mem['util_pct'] ?? '—')],
            ]),
            $this->panel('PCIe', [
                ['key' => 'Gen', 'value' => ($pcie['gen_current'] ?? '—') . ' / max ' . ($pcie['gen_max'] ?? '—')],
                ['key' => 'Width', 'value' => 'x' . ($pcie['width'] ?? '—') . ' / max x' . ($pcie['width_max'] ?? '—')],
            ]),
            $this->panel('Render / Util', [
                ['key' => 'GPU Util %', 'value' => (string) ($render['gpu_util_pct'] ?? '—')],
                ['key' => 'Encoder %', 'value' => (string) ($render['encoder_util_pct'] ?? '—')],
                ['key' => 'Decoder %', 'value' => (string) ($render['decoder_util_pct'] ?? '—')],
            ]),
        ];

        $engines = (array) ($render['engines'] ?? []);
        if ($engines !== []) {
            $rows = [];
            foreach ($engines as $e) {
                $rows[] = ['key' => (string) ($e['engine'] ?? '?'), 'value' => ($e['util_pct'] ?? '—') . '%'];
            }
            $panels[] = $this->panel('GPU Engines', $rows);
        }

        return $panels;
    }

    private function ramPanels(array $tel): array
    {
        $ram = (array) ($tel['ram'] ?? []);
        $st = (array) ($ram['status'] ?? []);
        $pt = (array) ($ram['primary_timings'] ?? []);
        $rows = [
            ['key' => 'Total GB', 'value' => (string) ($ram['total_gb'] ?? '—')],
            ['key' => 'Slots used', 'value' => (string) ($ram['slots_used'] ?? '—')],
            ['key' => 'Available MB', 'value' => $this->fmtNum($st['available_mb'] ?? null)],
            ['key' => 'Pages/sec', 'value' => $this->fmtNum($st['pages_per_sec'] ?? null)],
            ['key' => 'Page faults/sec', 'value' => $this->fmtNum($st['page_faults_sec'] ?? null)],
        ];
        $panels = [$this->panel('وضعیت سیستم', $rows)];

        if ($pt !== []) {
            $panels[] = $this->panel('Timings (CL / tRP)', [
                ['key' => 'Frequency', 'value' => (string) ($pt['frequency_mhz'] ?? '—') . ' MHz'],
                ['key' => 'CL-tRCD-tRP-tRAS', 'value' => implode('-', array_filter([
                    $pt['cl'] ?? null,
                    $pt['trcd'] ?? null,
                    $pt['trp'] ?? null,
                    $pt['tras'] ?? null,
                ], static fn ($v) => $v !== null)) ?: '—'],
                ['key' => 'Voltage', 'value' => isset($pt['voltage']) ? ($pt['voltage'] . ' V') : '—'],
                ['key' => 'Die type', 'value' => (string) ($ram['primary_die'] ?? '—')],
                ['key' => 'Source', 'value' => (string) ($ram['spd_source'] ?? ($ram['cpuz_auto_import'] ? 'CPU-Z auto' : 'SMBIOS+heuristic'))],
            ]);
        }

        foreach ((array) ($ram['modules'] ?? []) as $i => $m) {
            $t = (array) ($m['timings'] ?? []);
            $timingStr = '—';
            if (!empty($t['cl'])) {
                $timingStr = ($t['cl'] ?? '?') . '-' . ($t['trcd'] ?? '?') . '-' . ($t['trp'] ?? '?') . '-' . ($t['tras'] ?? '?') . ' @ ' . ($t['frequency_mhz'] ?? '?') . ' MHz';
            }
            $panels[] = $this->panel('Module ' . ($i + 1), [
                ['key' => 'Capacity', 'value' => ($m['capacity_gb'] ?? '—') . ' GB'],
                ['key' => 'Speed', 'value' => ($m['configured_mhz'] ?? $m['speed_mhz'] ?? '—') . ' MHz'],
                ['key' => 'Timings', 'value' => $timingStr],
                ['key' => 'Die', 'value' => (string) ($m['die_type'] ?? '—')],
                ['key' => 'Manufacturer', 'value' => (string) ($m['manufacturer'] ?? '—')],
                ['key' => 'Part', 'value' => (string) ($m['part_number'] ?? '—')],
            ]);
        }

        return $panels;
    }

    private function storagePanels(array $tel): array
    {
        $st = (array) ($tel['storage'] ?? []);
        $perf = (array) ($st['performance'] ?? []);
        $panels = [
            $this->panel('Performance (live)', [
                ['key' => 'Read B/s', 'value' => $this->fmtNum($perf['read_bytes_sec'] ?? null)],
                ['key' => 'Write B/s', 'value' => $this->fmtNum($perf['write_bytes_sec'] ?? null)],
                ['key' => 'Avg read sec', 'value' => (string) ($perf['avg_read_sec'] ?? '—')],
                ['key' => 'Queue', 'value' => (string) ($perf['queue_length'] ?? '—')],
            ]),
        ];

        foreach ((array) ($st['smart'] ?? []) as $s) {
            $panels[] = $this->panel('SMART: ' . ($s['friendly_name'] ?? 'Disk'), [
                ['key' => 'Health', 'value' => (string) ($s['health_status'] ?? '—')],
                ['key' => 'Temp °C', 'value' => (string) ($s['temperature_c'] ?? '—')],
                ['key' => 'Wear %', 'value' => (string) ($s['wear_pct'] ?? '—')],
                ['key' => 'Power-on hrs', 'value' => (string) ($s['power_on_hours'] ?? '—')],
                ['key' => 'Read errors', 'value' => (string) ($s['read_errors'] ?? '—')],
            ]);
        }

        return $panels;
    }

    private function boardPanels(array $tel): array
    {
        $mb = (array) ($tel['motherboard'] ?? []);
        $bios = (array) ($mb['bios'] ?? []);

        return [
            $this->panel('Board', [
                ['key' => 'Manufacturer', 'value' => (string) ($mb['manufacturer'] ?? '—')],
                ['key' => 'Product', 'value' => (string) ($mb['product'] ?? '—')],
                ['key' => 'Version', 'value' => (string) ($mb['version'] ?? '—')],
            ]),
            $this->panel('BIOS', [
                ['key' => 'Vendor', 'value' => (string) ($bios['vendor'] ?? '—')],
                ['key' => 'Version', 'value' => (string) ($bios['version'] ?? '—')],
            ]),
        ];
    }

    private function osPanels(array $tel): array
    {
        $os = (array) ($tel['os_kernel'] ?? []);
        $proc = (array) ($os['processes'] ?? []);
        $io = (array) ($os['io'] ?? []);
        $panels = [
            $this->panel('Processes', [
                ['key' => 'Process count', 'value' => (string) ($proc['count'] ?? '—')],
                ['key' => 'Threads', 'value' => (string) ($proc['thread_count'] ?? '—')],
                ['key' => 'Uptime sec', 'value' => $this->fmtNum($os['uptime_sec'] ?? null)],
            ]),
            $this->panel('I/O', [
                ['key' => 'File read B/s', 'value' => $this->fmtNum($io['file_read_bytes_sec'] ?? null)],
                ['key' => 'File write B/s', 'value' => $this->fmtNum($io['file_write_bytes_sec'] ?? null)],
            ]),
        ];

        $whea = (array) ($os['whea_errors'] ?? []);
        if ($whea !== []) {
            $rows = [];
            foreach (array_slice($whea, 0, 8) as $w) {
                $rows[] = ['key' => (string) ($w['time'] ?? ''), 'value' => (string) ($w['message'] ?? '')];
            }
            $panels[] = $this->panel('WHEA Hardware Errors', $rows);
        }

        return $panels;
    }

    private function networkPanels(array $tel): array
    {
        $net = (array) ($tel['network'] ?? []);
        $sess = (array) ($net['sessions'] ?? []);
        $panels = [
            $this->panel('Sessions', [
                ['key' => 'TCP established', 'value' => (string) ($sess['tcp_established'] ?? '—')],
                ['key' => 'UDP endpoints', 'value' => (string) ($sess['udp_endpoints'] ?? '—')],
            ]),
        ];

        foreach ((array) ($net['adapters'] ?? []) as $a) {
            $panels[] = $this->panel((string) ($a['name'] ?? 'NIC'), [
                ['key' => 'Link Mbps', 'value' => (string) ($a['link_speed_mbps'] ?? '—')],
                ['key' => 'RX bytes', 'value' => $this->fmtNum($a['recv_bytes'] ?? null)],
                ['key' => 'TX bytes', 'value' => $this->fmtNum($a['sent_bytes'] ?? null)],
                ['key' => 'RX errors', 'value' => (string) ($a['recv_errors'] ?? '—')],
            ]);
        }

        return $panels;
    }

    private function geekPanels(array $tel): array
    {
        $g = (array) ($tel['geek'] ?? []);
        $summary = (array) ($g['residency_summary'] ?? []);
        $cstates = (array) ($g['cstates'] ?? $g['idle_states'] ?? []);

        $panels = [
            $this->panel('Residency / Idle', [
                ['key' => 'CPU idle %', 'value' => $this->fmtPct($g['cpu_idle_pct'] ?? null)],
                ['key' => 'Deep idle %', 'value' => $this->fmtPct($g['deep_idle_pct'] ?? null)],
                ['key' => 'C1 %', 'value' => $this->fmtPct($summary['C1_pct'] ?? null)],
                ['key' => 'Transition faults/s', 'value' => $this->fmtNum($g['transition_faults_sec'] ?? null)],
                ['key' => 'Demand zero faults/s', 'value' => $this->fmtNum($g['demand_zero_faults_sec'] ?? null)],
                ['key' => 'Source', 'value' => (string) ($g['cstate_source'] ?? 'perf_counters')],
            ]),
        ];

        if ($cstates !== []) {
            $rows = [];
            foreach ($cstates as $c) {
                $rows[] = [
                    'key' => (string) ($c['state'] ?? '?'),
                    'value' => $this->fmtPct($c['residency_pct'] ?? $c['residency'] ?? null),
                ];
            }
            $panels[] = $this->panel('C-State residency', $rows);
        }

        $pstates = (array) ($g['pstates'] ?? []);
        if ($pstates !== []) {
            $rows = [];
            foreach (array_slice($pstates, 0, 10) as $p) {
                $rows[] = ['key' => (string) ($p['metric'] ?? '?'), 'value' => (string) ($p['value'] ?? '—')];
            }
            $panels[] = $this->panel('Processor Power', $rows);
        }

        $acpi = (array) ($g['acpi_sleep'] ?? []);
        if ($acpi !== []) {
            $rows = [];
            foreach ($acpi as $a) {
                $rows[] = [
                    'key' => (string) ($a['state'] ?? '?'),
                    'value' => !empty($a['available']) ? 'Available' : 'Not available',
                ];
            }
            $panels[] = $this->panel('ACPI sleep states', $rows);
        }

        return $panels;
    }

    /** @return array<string, mixed>|null */
    private function spikeMapChart(array $tel): ?array
    {
        $g = (array) ($tel['gaming'] ?? []);
        $map = (array) ($g['spike_map'] ?? []);
        if (empty($map['available'])) {
            return null;
        }

        return [
            'type' => 'frametime_spike_map',
            'series' => $map['series'] ?? [],
            'spikes' => $map['spikes'] ?? [],
            'stats' => $map['stats'] ?? [],
        ];
    }

    /** @return list<array{state: string, pct: float}> */
    private function cstateBars(array $tel): array
    {
        $g = (array) ($tel['geek'] ?? []);
        $cstates = (array) ($g['cstates'] ?? $g['idle_states'] ?? []);
        $out = [];
        foreach ($cstates as $c) {
            $pct = $c['residency_pct'] ?? $c['residency'] ?? null;
            if ($pct === null) {
                continue;
            }
            $out[] = ['state' => (string) ($c['state'] ?? '?'), 'pct' => (float) $pct];
        }

        return $out;
    }

    /** @param array<string, mixed> $probe */
    private function legacyShim(array $probe): array
    {
        return [
            'cpu' => ['architecture' => $probe['cpu'] ?? [], 'thermal' => ['package_c' => $probe['sensors']['cpu_temp_max'] ?? null]],
            'gpu' => ['nvidia' => $probe['nvidia_smi'] ?? [], 'thermal' => ['core_c' => $probe['sensors']['gpu_temp_max'] ?? null]],
            'ram' => $probe['ram'] ?? [],
            'storage' => ['drives' => $probe['storage'] ?? []],
            'motherboard' => $probe['motherboard'] ?? [],
            'network' => ['adapters' => $probe['network'] ?? []],
        ];
    }

    /** @param list<array{key: string, value: string}> $rows */
    private function panel(string $title, array $rows): array
    {
        return ['title_fa' => $title, 'rows' => $rows];
    }

    private function fmtNum(mixed $v): string
    {
        if ($v === null || $v === '') {
            return '—';
        }

        return is_numeric($v) ? number_format((float) $v, 0) : (string) $v;
    }

    private function fmtPct(mixed $v): string
    {
        if ($v === null || $v === '') {
            return '—';
        }

        return is_numeric($v) ? round((float) $v, 1) . '%' : (string) $v;
    }
}
