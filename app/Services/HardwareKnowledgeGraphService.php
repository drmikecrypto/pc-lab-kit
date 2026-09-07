<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Builds a hardware knowledge graph from a normalized probe/report payload.
 * Full inventory graph for UI/topology; use compact() for AI/TOON.
 */
class HardwareKnowledgeGraphService
{
    /**
     * @param array<string, mixed> $report Normalized probe or analysis report_summary+metrics
     * @param array<string, mixed> $analysis Optional analysis (bottleneck, risks, percentiles)
     * @return array{nodes: list<array<string, mixed>>, edges: list<array<string, mixed>>, summary: array<string, mixed>}
     */
    public function fromProbe(array $report, array $analysis = []): array
    {
        $nodes = [];
        $edges = [];
        $addNode = function (string $id, string $type, string $label, array $attrs = []) use (&$nodes): void {
            if ($id === '' || isset($nodes[$id])) {
                return;
            }
            $nodes[$id] = array_filter([
                'id' => $id,
                'type' => $type,
                'label' => $label,
            ] + $attrs, static fn ($v) => $v !== null && $v !== '');
        };
        $addEdge = function (string $src, string $tgt, string $rel, array $attrs = []) use (&$edges): void {
            if ($src === '' || $tgt === '') {
                return;
            }
            $edges[] = array_filter([
                'source' => $src,
                'target' => $tgt,
                'relation' => $rel,
            ] + $attrs, static fn ($v) => $v !== null && $v !== '');
        };

        $cpu = (array) ($report['cpu'] ?? []);
        $gpu = (array) ($report['gpu'] ?? []);
        $ram = (array) ($report['ram'] ?? []);
        $device = (array) ($report['device'] ?? []);
        $psu = (array) ($report['psu'] ?? []);
        $storage = (array) ($report['storage'] ?? $report['disks'] ?? []);
        $sensors = (array) ($report['sensors'] ?? []);
        $network = (array) ($report['network'] ?? []);
        $devices = (array) ($report['devices'] ?? []);
        $board = (array) ($report['motherboard'] ?? $devices['motherboard'] ?? []);
        $bios = (array) ($report['bios'] ?? $devices['bios'] ?? []);
        $tpm = (array) ($devices['tpm'] ?? $report['tpm'] ?? []);
        $metrics = (array) ($analysis['metrics'] ?? []);
        $summary = (array) ($analysis['report_summary'] ?? []);

        $cpuModel = (string) ($cpu['model'] ?? $metrics['cpu_model'] ?? $summary['cpu'] ?? '');
        $gpuModel = (string) ($gpu['model'] ?? $metrics['gpu_model'] ?? $summary['gpu'] ?? '');
        $form = (string) ($device['form_factor'] ?? (($summary['is_laptop'] ?? false) ? 'laptop' : 'desktop'));

        $addNode('system', 'system', 'PC', [
            'form_factor' => $form,
            'hostname' => $device['hostname'] ?? $device['computer_name'] ?? null,
            'elevated' => !empty($report['elevated']) || !empty($device['elevated']),
        ]);

        $boardLabel = trim((string) ($board['manufacturer'] ?? '') . ' ' . (string) ($board['product'] ?? ''));
        if ($boardLabel !== '') {
            $addNode('motherboard', 'motherboard', $boardLabel, [
                'version' => $board['version'] ?? null,
                'serial' => $board['serial'] ?? null,
            ]);
            $addEdge('motherboard', 'system', 'installed_in');
        }

        if (!empty($bios['version']) || !empty($bios['vendor'])) {
            $addNode('bios', 'firmware', trim((string) ($bios['vendor'] ?? 'BIOS') . ' ' . (string) ($bios['version'] ?? '')), [
                'date' => $bios['date'] ?? null,
                'smbios' => isset($bios['smbios_major'])
                    ? ($bios['smbios_major'] . '.' . ($bios['smbios_minor'] ?? ''))
                    : null,
            ]);
            $parent = isset($nodes['motherboard']) ? 'motherboard' : 'system';
            $addEdge('bios', $parent, 'firmware_of');
        }

        if (!empty($tpm['present'])) {
            $addNode('tpm', 'security', 'TPM ' . (string) ($tpm['spec_version'] ?? ''), [
                'enabled' => $tpm['enabled'] ?? null,
                'activated' => $tpm['activated'] ?? null,
            ]);
            $addEdge('tpm', 'system', 'installed_in');
        }

        // Chipset heuristic from PCI / category inventory
        $chipsetName = $this->findChipsetLabel($devices);
        if ($chipsetName !== '') {
            $addNode('chipset', 'chipset', $chipsetName);
            $addEdge('chipset', isset($nodes['motherboard']) ? 'motherboard' : 'system', 'on_board');
            if ($cpuModel !== '') {
                $addEdge('cpu', 'chipset', 'connected_to');
            }
        }

        if ($cpuModel !== '') {
            $addNode('cpu', 'cpu', $cpuModel, [
                'cores' => $cpu['cores'] ?? $cpu['logical_processors'] ?? null,
                'score' => $metrics['cpu_score'] ?? $cpu['benchmark_score'] ?? null,
                'percentile' => $analysis['percentiles']['cpu'] ?? null,
                'temp_max' => $metrics['cpu_temp_max'] ?? $sensors['cpu_temp_max'] ?? null,
            ]);
            $addEdge('cpu', 'system', 'installed_in');
            if (isset($nodes['motherboard'])) {
                $addEdge('cpu', 'motherboard', 'socketed_in');
            }
        }

        if ($gpuModel !== '') {
            $addNode('gpu', 'gpu', $gpuModel, [
                'vram_gb' => $metrics['vram_gb'] ?? $gpu['vram_gb'] ?? null,
                'score' => $metrics['gpu_score'] ?? $gpu['benchmark_score'] ?? null,
                'percentile' => $analysis['percentiles']['gpu'] ?? null,
                'temp_max' => $metrics['gpu_temp_max'] ?? $sensors['gpu_temp_max'] ?? null,
                'hotspot_max' => $metrics['gpu_hotspot_max'] ?? null,
                'vbios' => $gpu['vbios'] ?? null,
                'pcie_gen' => $gpu['pcie_gen'] ?? null,
                'pcie_width' => $gpu['pcie_width'] ?? null,
            ]);
            $addEdge('gpu', 'system', 'installed_in');
            $addEdge('gpu', 'cpu', 'pcie_attached_to');
        }

        $ramGb = (int) ($metrics['ram_gb'] ?? $ram['total_gb'] ?? $ram['capacity_gb'] ?? $summary['ram_gb'] ?? 0);
        if ($ramGb > 0) {
            $addNode('ram', 'memory', $ramGb . ' GB RAM', [
                'channels' => $ram['channels'] ?? null,
                'speed_mhz' => $ram['speed_mhz'] ?? $ram['configured_mhz'] ?? null,
                'die_type' => $ram['die_type'] ?? $ram['primary_die'] ?? null,
                'spd_source' => $ram['spd_source'] ?? null,
            ]);
            $addEdge('ram', 'cpu', 'served_by');
            $addEdge('ram', 'system', 'installed_in');
        }

        foreach (array_values((array) ($ram['modules'] ?? [])) as $i => $mod) {
            if (!is_array($mod)) {
                continue;
            }
            $id = 'dimm_' . $i;
            $cap = $mod['capacity_gb'] ?? null;
            $label = trim((string) ($mod['manufacturer'] ?? '') . ' ' . (string) ($mod['part_number'] ?? ('DIMM ' . ($i + 1))));
            if ($label === '') {
                $label = 'DIMM ' . ($i + 1);
            }
            $addNode($id, 'dimm', $label, [
                'capacity_gb' => $cap,
                'speed_mhz' => $mod['configured_mhz'] ?? $mod['speed_mhz'] ?? null,
                'bank' => $mod['bank_label'] ?? $mod['device_locator'] ?? null,
                'die_type' => $mod['die_type'] ?? null,
                'die_confidence' => $mod['die_confidence'] ?? null,
                'timings_confidence' => $mod['timings_confidence'] ?? null,
                'memory_type' => $mod['memory_type'] ?? null,
            ]);
            $addEdge($id, isset($nodes['ram']) ? 'ram' : 'system', 'module_of');
        }

        $watt = (int) ($psu['wattage'] ?? 0);
        if ($watt > 0) {
            $addNode('psu', 'psu', $watt . ' W PSU', [
                'efficiency' => $psu['efficiency'] ?? null,
            ]);
            $addEdge('psu', 'system', 'powers');
            if (isset($nodes['gpu'])) {
                $addEdge('psu', 'gpu', 'powers');
            }
            if (isset($nodes['cpu'])) {
                $addEdge('psu', 'cpu', 'powers');
            }
        }

        $disks = is_array($storage) && isset($storage[0]) ? $storage : (isset($storage['disks']) ? (array) $storage['disks'] : (isset($storage['drives']) ? (array) $storage['drives'] : []));
        foreach (array_values($disks) as $i => $disk) {
            if (!is_array($disk)) {
                continue;
            }
            $label = (string) ($disk['model'] ?? $disk['name'] ?? ('Disk ' . ($i + 1)));
            $id = 'storage_' . $i;
            $addNode($id, 'storage', $label, [
                'type' => $disk['type'] ?? $disk['media_type'] ?? $disk['interface'] ?? null,
                'size_gb' => $disk['size_gb'] ?? $disk['capacity_gb'] ?? null,
                'health' => $disk['health'] ?? $disk['smart_status'] ?? null,
            ]);
            $addEdge($id, 'system', 'installed_in');
        }

        if (!empty($network['lan_speed_mbps']) || !empty($network['wifi_standard'])) {
            $addNode('network', 'network', 'Network', [
                'lan_mbps' => $network['lan_speed_mbps'] ?? null,
                'wifi' => $network['wifi_standard'] ?? null,
            ]);
            $addEdge('network', 'system', 'connected_to');
        }

        foreach (array_slice((array) (($devices['monitors']['displays'] ?? $devices['monitors'] ?? [])), 0, 8) as $i => $mon) {
            if (!is_array($mon)) {
                continue;
            }
            $id = 'monitor_' . $i;
            $edid = is_array($mon['edid'] ?? null) ? $mon['edid'] : [];
            $pref = is_array($edid['preferred_timing'] ?? null) ? $edid['preferred_timing'] : [];
            $addNode($id, 'monitor', (string) ($mon['name'] ?? 'Display'), [
                'manufacturer' => $mon['manufacturer'] ?? ($edid['manufacturer_code'] ?? null),
                'serial' => $mon['serial'] ?? null,
                'hdr' => $edid['hdr_capable'] ?? null,
                'preferred' => isset($pref['width']) ? ($pref['width'] . 'x' . $pref['height'] . '@' . ($pref['refresh_hz'] ?? '?')) : null,
                'confidence' => $mon['confidence'] ?? ($edid['confidence'] ?? null),
            ]);
            $addEdge($id, 'system', 'connected_to');
        }

        $batteryList = (array) ($report['battery'] ?? $devices['battery'] ?? []);
        if ($batteryList !== [] && isset($batteryList[0]) && is_array($batteryList[0])) {
            $b = $batteryList[0];
            $addNode('battery', 'battery', (string) ($b['name'] ?? 'Battery'), [
                'health_percent' => $b['health_percent'] ?? null,
                'design_capacity' => $b['design_capacity'] ?? $b['designed_capacity_mwh'] ?? null,
            ]);
            $addEdge('battery', 'system', 'powers');
        } elseif (is_array($batteryList) && isset($batteryList['health_percent'])) {
            $addNode('battery', 'battery', 'Battery', [
                'health_percent' => $batteryList['health_percent'] ?? null,
            ]);
            $addEdge('battery', 'system', 'powers');
        }

        // Cooler / fans from sensor deck
        $fans = (array) ($sensors['fans'] ?? $report['hwmon']['fans'] ?? []);
        if ($fans !== []) {
            $addNode('cooler', 'cooler', 'Cooling', [
                'fan_count' => count($fans),
            ]);
            $addEdge('cooler', 'cpu', 'cools');
            $addEdge('cooler', 'system', 'installed_in');
            foreach (array_slice($fans, 0, 6) as $fi => $fan) {
                if (!is_array($fan)) {
                    continue;
                }
                $fid = 'fan_' . $fi;
                $addNode($fid, 'fan', (string) ($fan['name'] ?? ('Fan ' . ($fi + 1))), [
                    'rpm' => $fan['value'] ?? $fan['rpm'] ?? null,
                    'confidence' => $fan['confidence'] ?? 'measured',
                ]);
                $addEdge($fid, 'cooler', 'part_of');
            }
        }

        foreach (array_slice((array) ($devices['usb']['devices'] ?? []), 0, 24) as $i => $u) {
            if (!is_array($u)) {
                continue;
            }
            $id = 'usb_' . $i;
            $addNode($id, 'usb', (string) ($u['name'] ?? 'USB device'), [
                'vendor_id' => $u['vendor_id'] ?? null,
                'product_id' => $u['product_id'] ?? null,
                'present' => $u['present'] ?? null,
                'parent' => $u['parent_instance_id'] ?? null,
            ]);
            $addEdge($id, 'system', 'usb_attached');
        }

        foreach (array_slice((array) ($devices['pci'] ?? []), 0, 40) as $i => $p) {
            if (!is_array($p)) {
                continue;
            }
            // Skip if already represented as GPU/chipset primary
            $name = (string) ($p['name'] ?? '');
            if ($name === '' || stripos($name, 'Host bridge') !== false) {
                continue;
            }
            $id = 'pci_' . $i;
            $addNode($id, 'pci', $name, [
                'vendor_id' => $p['vendor_id'] ?? null,
                'device_id' => $p['device_id'] ?? null,
                'present' => $p['present'] ?? null,
                'problem_code' => $p['problem_code'] ?? null,
            ]);
            $addEdge($id, isset($nodes['chipset']) ? 'chipset' : 'system', 'pcie_endpoint');
        }

        $this->addDriverDeviceNodes($report, $addNode, $addEdge, $nodes);

        $platform = (array) ($report['platform'] ?? $devices['platform'] ?? []);
        $fingerprint = (array) ($report['fingerprint'] ?? $devices['fingerprint'] ?? []);
        if ($fingerprint !== [] || $platform !== []) {
            $cov = $fingerprint['coverage_score'] ?? $devices['summary']['coverage_score'] ?? null;
            $addNode('platform', 'platform', 'Platform Intelligence', [
                'coverage_score' => $cov,
                'form_factor' => $fingerprint['form_factor'] ?? null,
                'elevated' => $fingerprint['elevated'] ?? $platform['elevated'] ?? null,
                'hash' => isset($fingerprint['id']) ? (string) $fingerprint['id'] : null,
            ]);
            $addEdge('platform', 'system', 'profiles');
            if (!empty($platform['tpm']['present'])) {
                $addNode('tpm_detail', 'security', 'TPM ' . (string) ($platform['tpm']['spec_version'] ?? ''), [
                    'manufacturer' => $platform['tpm']['manufacturer_id'] ?? null,
                    'firmware' => $platform['tpm']['manufacturer_version'] ?? null,
                ]);
                $addEdge('tpm_detail', 'platform', 'attests');
            }
            if (!empty($platform['me_psp']['present'])) {
                $addNode('me_psp', 'firmware', strtoupper((string) ($platform['me_psp']['vendor'] ?? 'me/psp')), [
                    'generic_driver' => $platform['me_psp']['generic_driver'] ?? null,
                ]);
                $addEdge('me_psp', 'platform', 'management_engine');
            }
            if (!empty($platform['uefi']['firmware_type'])) {
                $addNode('uefi', 'firmware', strtoupper((string) $platform['uefi']['firmware_type']), [
                    'secure_boot' => $platform['uefi']['secure_boot'] ?? null,
                ]);
                $addEdge('uefi', 'platform', 'firmware_of');
            }
        }

        $bn = (array) ($analysis['bottleneck'] ?? []);
        $bnType = (string) ($bn['type'] ?? $bn['component'] ?? '');
        if ($bnType !== '' && $bnType !== 'balanced') {
            $target = match (true) {
                str_contains($bnType, 'gpu'), str_contains($bnType, 'vram') => 'gpu',
                str_contains($bnType, 'cpu') => 'cpu',
                str_contains($bnType, 'memory'), str_contains($bnType, 'frametime'), str_contains($bnType, 'ram') => 'ram',
                default => 'system',
            };
            if (isset($nodes[$target])) {
                $addEdge('system', $target, 'bottleneck', [
                    'confidence' => $bn['confidence'] ?? null,
                    'message' => $bn['message'] ?? null,
                ]);
            }
        }

        foreach (array_slice((array) ($analysis['risks'] ?? []), 0, 6) as $risk) {
            if (!is_array($risk)) {
                continue;
            }
            $code = (string) ($risk['code'] ?? '');
            $tgt = match (true) {
                str_starts_with($code, 'cpu') => 'cpu',
                str_starts_with($code, 'gpu') => 'gpu',
                str_starts_with($code, 'psu') => 'psu',
                default => 'system',
            };
            if (isset($nodes[$tgt])) {
                $addEdge($tgt, 'system', 'risk', [
                    'code' => $code,
                    'severity' => $risk['severity'] ?? null,
                    'message' => $risk['message'] ?? null,
                ]);
            }
        }

        $nodeList = array_values($nodes);
        $driverNodes = count(array_filter($nodeList, static fn ($n) => ($n['type'] ?? '') === 'device'));

        return [
            'nodes' => $nodeList,
            'edges' => $edges,
            'summary' => [
                'node_count' => count($nodeList),
                'edge_count' => count($edges),
                'bottleneck' => $bnType !== '' ? $bnType : null,
                'form_factor' => $form,
                'driver_device_nodes' => $driverNodes,
                'hidden_devices' => (int) ($devices['summary']['hidden_devices'] ?? 0),
                'total_devices' => (int) ($devices['summary']['total_devices'] ?? 0),
                'coverage_score' => $fingerprint['coverage_score'] ?? $devices['summary']['coverage_score'] ?? null,
                'platform_fingerprint' => $fingerprint['id'] ?? null,
            ],
        ];
    }

    /** @param array<string, mixed> $devices */
    private function findChipsetLabel(array $devices): string
    {
        foreach ((array) ($devices['by_category']['chipset'] ?? []) as $d) {
            if (is_array($d) && !empty($d['name'])) {
                return (string) $d['name'];
            }
        }
        foreach ((array) ($devices['pci'] ?? []) as $d) {
            if (!is_array($d)) {
                continue;
            }
            $n = (string) ($d['name'] ?? '');
            if (preg_match('/chipset|pch|LPC|SMBus|Host Bridge|Root Complex/i', $n)) {
                return $n;
            }
        }

        return '';
    }

    /**
     * @param array<string, mixed> $report
     * @param callable $addNode
     * @param callable $addEdge
     * @param array<string, array<string, mixed>> $nodes
     */
    private function addDriverDeviceNodes(array $report, callable $addNode, callable $addEdge, array &$nodes): void
    {
        $drivers = (array) ($report['drivers'] ?? []);
        $devices = (array) ($report['devices'] ?? []);
        $candidates = [];

        foreach ((array) ($devices['driverless'] ?? []) as $d) {
            if (!is_array($d)) {
                continue;
            }
            $candidates[] = [
                'severity' => 0,
                'label' => (string) ($d['name'] ?? 'Unknown device'),
                'relation' => 'needs_driver',
                'attrs' => [
                    'category' => $d['category'] ?? null,
                    'vendor_id' => $d['vendor_id'] ?? null,
                    'device_id' => $d['device_id'] ?? null,
                    'instance_id' => $d['instance_id'] ?? null,
                    'present' => $d['present'] ?? null,
                    'hidden' => $d['hidden'] ?? null,
                    'severity' => 'critical',
                ],
            ];
        }

        foreach ((array) ($drivers['gpus'] ?? []) as $g) {
            if (!is_array($g)) {
                continue;
            }
            if (empty($g['is_generic']) && empty($g['is_stale'])) {
                continue;
            }
            $rel = !empty($g['is_generic']) ? 'generic_driver' : 'uses_driver';
            $candidates[] = [
                'severity' => !empty($g['is_generic']) ? 1 : 2,
                'label' => (string) ($g['name'] ?? 'GPU'),
                'relation' => $rel,
                'attrs' => [
                    'category' => 'gpu',
                    'vendor_id' => $g['vendor_id'] ?? null,
                    'device_id' => $g['device_id'] ?? null,
                    'instance_id' => $g['instance_id'] ?? $g['pnp_device_id'] ?? null,
                    'severity' => !empty($g['is_generic']) ? 'critical' : 'warn',
                    'driver' => $g['driver'] ?? null,
                ],
            ];
        }

        foreach ((array) ($drivers['actions'] ?? []) as $a) {
            if (!is_array($a)) {
                continue;
            }
            $sev = (string) ($a['severity'] ?? 'info');
            if ($sev === 'info') {
                continue;
            }
            $code = (string) ($a['code'] ?? '');
            if (!in_array($code, ['missing_driver', 'generic_driver', 'gpu_generic', 'store_newer', 'gpu_stale'], true)) {
                continue;
            }
            $rel = match ($code) {
                'missing_driver' => 'needs_driver',
                'generic_driver', 'gpu_generic' => 'generic_driver',
                default => 'uses_driver',
            };
            $candidates[] = [
                'severity' => $sev === 'critical' ? 0 : 2,
                'label' => (string) ($a['device'] ?? $a['title'] ?? 'Device'),
                'relation' => $rel,
                'attrs' => [
                    'category' => $a['category'] ?? null,
                    'vendor_id' => $a['vendor_id'] ?? null,
                    'device_id' => $a['device_id'] ?? null,
                    'instance_id' => $a['instance_id'] ?? null,
                    'severity' => $sev,
                    'code' => $code,
                    'match_confidence' => $a['match_confidence'] ?? null,
                ],
            ];
        }

        usort($candidates, static fn ($x, $y) => ($x['severity'] <=> $y['severity']));
        $seen = [];
        $added = 0;
        foreach ($candidates as $c) {
            if ($added >= 12) {
                break;
            }
            $label = $c['label'];
            if ($label === '') {
                continue;
            }
            $key = strtolower($label . '|' . ($c['attrs']['instance_id'] ?? ''));
            if (isset($seen[$key])) {
                continue;
            }
            $seen[$key] = true;
            $id = 'dev_' . $added;
            $parent = (isset($nodes['gpu']) && (($c['attrs']['category'] ?? '') === 'gpu')) ? 'gpu' : 'system';
            $addNode($id, 'device', $label, $c['attrs']);
            $addEdge($id, $parent, $c['relation'], [
                'severity' => $c['attrs']['severity'] ?? null,
            ]);
            $added++;
        }
    }

    /**
     * Compact graph for AI / TOON (strip long free text).
     *
     * @param array{nodes: list<array>, edges: list<array>, summary: array} $graph
     * @return array<string, mixed>
     */
    public function compact(array $graph): array
    {
        $nodes = [];
        foreach ($graph['nodes'] as $n) {
            $type = (string) ($n['type'] ?? '');
            // Prefer core topology + driver issues for AI token budget
            if (!in_array($type, ['system', 'cpu', 'gpu', 'memory', 'dimm', 'motherboard', 'chipset', 'firmware', 'storage', 'psu', 'network', 'cooler', 'monitor', 'device', 'battery', 'security'], true)) {
                continue;
            }
            $row = [
                'id' => $n['id'] ?? '',
                'type' => $type,
                'label' => $n['label'] ?? '',
            ];
            foreach (['score', 'percentile', 'temp_max', 'vram_gb', 'cores', 'speed_mhz', 'vendor_id', 'device_id', 'severity', 'category', 'confidence', 'present', 'hidden'] as $k) {
                if (isset($n[$k]) && $n[$k] !== '' && $n[$k] !== null) {
                    $row[$k] = $n[$k];
                }
            }
            $nodes[] = $row;
        }
        $edges = [];
        foreach ($graph['edges'] as $e) {
            $edges[] = array_filter([
                's' => $e['source'] ?? '',
                't' => $e['target'] ?? '',
                'r' => $e['relation'] ?? '',
                'sev' => $e['severity'] ?? null,
            ], static fn ($v) => $v !== null && $v !== '');
        }

        return [
            'summary' => $graph['summary'] ?? [],
            'nodes' => $nodes,
            'edges' => $edges,
        ];
    }
}
