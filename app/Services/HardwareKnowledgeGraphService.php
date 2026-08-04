<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Builds a small hardware knowledge graph from a normalized probe/report payload.
 * Nodes = components; edges = buses, thermal paths, bottlenecks, power.
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
        $metrics = (array) ($analysis['metrics'] ?? []);
        $summary = (array) ($analysis['report_summary'] ?? []);

        $cpuModel = (string) ($cpu['model'] ?? $metrics['cpu_model'] ?? $summary['cpu'] ?? '');
        $gpuModel = (string) ($gpu['model'] ?? $metrics['gpu_model'] ?? $summary['gpu'] ?? '');
        $form = (string) ($device['form_factor'] ?? (($summary['is_laptop'] ?? false) ? 'laptop' : 'desktop'));

        $addNode('system', 'system', 'PC', [
            'form_factor' => $form,
            'hostname' => $device['hostname'] ?? null,
        ]);

        if ($cpuModel !== '') {
            $addNode('cpu', 'cpu', $cpuModel, [
                'cores' => $cpu['cores'] ?? $cpu['logical_processors'] ?? null,
                'score' => $metrics['cpu_score'] ?? $cpu['benchmark_score'] ?? null,
                'percentile' => $analysis['percentiles']['cpu'] ?? null,
                'temp_max' => $metrics['cpu_temp_max'] ?? $sensors['cpu_temp_max'] ?? null,
            ]);
            $addEdge('cpu', 'system', 'installed_in');
        }

        if ($gpuModel !== '') {
            $addNode('gpu', 'gpu', $gpuModel, [
                'vram_gb' => $metrics['vram_gb'] ?? $gpu['vram_gb'] ?? null,
                'score' => $metrics['gpu_score'] ?? $gpu['benchmark_score'] ?? null,
                'percentile' => $analysis['percentiles']['gpu'] ?? null,
                'temp_max' => $metrics['gpu_temp_max'] ?? $sensors['gpu_temp_max'] ?? null,
                'hotspot_max' => $metrics['gpu_hotspot_max'] ?? null,
            ]);
            $addEdge('gpu', 'system', 'installed_in');
            $addEdge('gpu', 'cpu', 'pcie_attached_to');
        }

        $ramGb = (int) ($metrics['ram_gb'] ?? $ram['total_gb'] ?? $ram['capacity_gb'] ?? $summary['ram_gb'] ?? 0);
        if ($ramGb > 0) {
            $addNode('ram', 'memory', $ramGb . ' GB RAM', [
                'channels' => $ram['channels'] ?? null,
                'speed_mhz' => $ram['speed_mhz'] ?? $ram['configured_mhz'] ?? null,
                'die_type' => $ram['die_type'] ?? null,
            ]);
            $addEdge('ram', 'cpu', 'served_by');
            $addEdge('ram', 'system', 'installed_in');
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

        $disks = is_array($storage) && isset($storage[0]) ? $storage : (isset($storage['drives']) ? (array) $storage['drives'] : []);
        foreach (array_slice($disks, 0, 4) as $i => $disk) {
            if (!is_array($disk)) {
                continue;
            }
            $label = (string) ($disk['model'] ?? $disk['name'] ?? ('Disk ' . ($i + 1)));
            $id = 'storage_' . $i;
            $addNode($id, 'storage', $label, [
                'type' => $disk['type'] ?? $disk['media_type'] ?? null,
                'size_gb' => $disk['size_gb'] ?? $disk['capacity_gb'] ?? null,
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

        $this->addDriverDeviceNodes($report, $addNode, $addEdge, $nodes);

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
            ],
        ];
    }

    /**
     * Attach notable PnP / driver issues (capped) so AI and export see hardware identity.
     *
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
        foreach ($candidates as $i => $c) {
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
            // Prefer attaching GPU issues to the gpu node when present.
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
            $row = [
                'id' => $n['id'] ?? '',
                'type' => $n['type'] ?? '',
                'label' => $n['label'] ?? '',
            ];
            foreach (['score', 'percentile', 'temp_max', 'vram_gb', 'cores', 'speed_mhz', 'vendor_id', 'device_id', 'severity', 'category'] as $k) {
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
