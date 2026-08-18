<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Normalizes PC Lab Kit Windows Probe JSON (v2) into DiagnosticService report shape.
 */
class DiagnosticAgentService
{
    /** @param array<string, mixed> $agent */
    public function normalize(array $agent): array
    {
        if (($agent['probe_version'] ?? 0) < 2 && empty($agent['agent'])) {
            return $agent;
        }

        $device = (array) ($agent['device'] ?? []);
        $cpu = (array) ($agent['cpu'] ?? []);
        $gpu = (array) ($agent['gpu'] ?? []);
        $nvidia = (array) ($agent['nvidia_smi'] ?? []);
        $ram = (array) ($agent['ram'] ?? []);
        $battery = (array) ($agent['battery'] ?? []);
        $sensors = (array) ($agent['sensors'] ?? []);
        $gaming = (array) ($agent['gaming'] ?? []);
        $network = $agent['network'] ?? [];
        $storage = $agent['storage'] ?? [];
        $telemetry = (array) ($agent['telemetry'] ?? []);
        $thermal = (array) ($agent['thermal'] ?? ($telemetry['thermal'] ?? []));
        $drivers = (array) ($agent['drivers'] ?? []);
        $devices = (array) ($agent['devices'] ?? []);

        if ($telemetry !== []) {
            $telRam = (array) ($telemetry['ram'] ?? []);
            if ($telRam !== []) {
                $ram = array_merge($ram, $telRam);
            }
            $telGaming = (array) ($telemetry['gaming'] ?? []);
            if ($telGaming !== []) {
                $gaming = array_merge($gaming, $telGaming);
            }
            $telGpu = (array) ($telemetry['gpu'] ?? []);
            if ($telGpu !== []) {
                $gpuThermal = (array) ($telGpu['thermal'] ?? []);
                if ($gpuThermal !== []) {
                    $sensors['gpu_temp_max'] = $gpuThermal['core_c'] ?? ($sensors['gpu_temp_max'] ?? null);
                    $sensors['gpu_hotspot_max'] = $gpuThermal['hot_spot_c'] ?? ($sensors['gpu_hotspot_max'] ?? null);
                    $sensors['gpu_hotspot_delta'] = $gpuThermal['hotspot_delta_c'] ?? ($sensors['gpu_hotspot_delta'] ?? null);
                    $sensors['gpu_hotspot_source'] = $gpuThermal['hotspot_source'] ?? ($sensors['gpu_hotspot_source'] ?? null);
                    $sensors['gpu_therm_spread'] = $gpuThermal['therm_spread_c'] ?? ($sensors['gpu_therm_spread'] ?? null);
                    $sensors['gpu_vram_temp'] = $gpuThermal['memory_c'] ?? ($sensors['gpu_vram_temp'] ?? null);
                }
            }
            $telCpu = (array) ($telemetry['cpu'] ?? []);
            if ($telCpu !== []) {
                $cpuThermal = (array) ($telCpu['thermal'] ?? []);
                if (!empty($cpuThermal['package_c'])) {
                    $sensors['cpu_temp_max'] = $cpuThermal['package_c'];
                }
                if (!empty($cpuThermal['hotspot_c'])) {
                    $sensors['cpu_hotspot_max'] = $cpuThermal['hotspot_c'];
                }
            }
        }

        $lanMbps = 0;
        if (is_array($network)) {
            foreach ($network as $nic) {
                if (!is_array($nic)) {
                    continue;
                }
                $lanMbps = max($lanMbps, (int) ($nic['link_speed_mbps'] ?? 0));
            }
        }

        $storageList = is_array($storage) ? $storage : [];
        $primaryStorage = $storageList[0] ?? [];

        $gpuHotspot = $sensors['gpu_hotspot_max']
            ?? $nvidia['temp_hotspot_c']
            ?? null;
        $gpuCore = $sensors['gpu_temp_max']
            ?? $nvidia['temp_c']
            ?? null;

        $out = [
            'device' => array_merge($device, [
                'form_factor' => $device['form_factor'] ?? 'desktop',
                'platform' => 'windows',
                'probe_agent' => 'pclab-probe',
                'elevated' => !empty($agent['elevated']),
            ]),
            'cpu' => array_merge($cpu, [
                'model' => trim((string) ($cpu['model'] ?? '')),
                'cores' => (int) ($cpu['cores'] ?? 0),
                'threads' => (int) ($cpu['threads'] ?? 0),
                'codename' => $cpu['codename'] ?? null,
                'hybrid' => !empty($cpu['hybrid']),
                'performance_cores' => $cpu['performance_cores'] ?? null,
                'efficiency_cores' => $cpu['efficiency_cores'] ?? null,
                'temp_max' => $sensors['cpu_temp_max'] ?? ($cpu['package_c'] ?? null),
                'hotspot_max' => $sensors['cpu_hotspot_max'] ?? ($cpu['hotspot_c'] ?? null),
                'tjmax_c' => $cpu['tjmax_c'] ?? null,
            ]),
            'gpu' => array_merge($gpu, [
                'model' => (string) ($nvidia['name'] ?? $gpu['model'] ?? ''),
                'vram_gb' => (float) ($gpu['vram_gb'] ?? 0),
                // Hot spot is a distinct sensor. Never fall back to core temp —
                // that is exactly the bug that hid NVIDIA junction readings.
                'core_temp' => $gpuCore,
                'hotspot_max' => $gpuHotspot,
                'hotspot_delta' => $sensors['gpu_hotspot_delta'] ?? null,
                'vram_temp' => $sensors['gpu_vram_temp'] ?? null,
                'power_w' => $nvidia['power_w'] ?? $nvidia['power_draw_w'] ?? null,
                'pcie_gen' => $nvidia['pcie_gen'] ?? null,
                'pcie_width' => $nvidia['pcie_width'] ?? null,
                'cuda_note' => !empty($nvidia) ? 'See nvidia-smi in report' : null,
            ]),
            'ram' => [
                'total_gb' => (int) round((float) ($ram['total_gb'] ?? 0)),
                'modules' => $ram['modules'] ?? [],
                'speed_mhz' => $ram['modules'][0]['configured_mhz'] ?? $ram['modules'][0]['speed_mhz'] ?? null,
                'primary_timings' => $ram['primary_timings'] ?? ($ram['modules'][0]['timings'] ?? null),
                'primary_die' => $ram['primary_die'] ?? ($ram['modules'][0]['die_type'] ?? null),
                'spd_source' => $ram['spd_source'] ?? $ram['source'] ?? null,
                'spd_direct_read' => !empty($ram['spd_direct_read']),
                'channels' => $ram['channels'] ?? null,
                'die_type' => $ram['primary_die'] ?? ($ram['modules'][0]['die_type'] ?? null),
            ],
            'storage' => [
                'disks' => $storageList,
                'primary' => $primaryStorage,
                'type' => $primaryStorage['interface'] ?? $primaryStorage['media_type'] ?? null,
            ],
            'motherboard' => (array) ($agent['motherboard'] ?? $devices['motherboard'] ?? []),
            'psu' => (array) ($agent['psu'] ?? []),
            'network' => [
                'adapters' => $network,
                'lan_speed_mbps' => $lanMbps,
                'wifi_standard' => $this->detectWifiStandard($network),
            ],
            'battery' => $battery !== [] ? $battery : (array) ($devices['battery'] ?? []),
            'sensors' => array_merge($sensors, [
                'throttle_count' => (int) ($sensors['throttle_count'] ?? 0),
                'fans' => $sensors['fans'] ?? ($agent['hwmon']['fans'] ?? ($telemetry['hwmon']['fans'] ?? [])),
            ]),
            'hwmon' => (array) ($agent['hwmon'] ?? $telemetry['hwmon'] ?? []),
            'thermal' => $thermal,
            'devices' => $devices,
            'drivers' => $drivers,
            'gaming' => $gaming,
            'peripherals' => (array) ($agent['peripherals'] ?? []),
            'bios' => (array) ($agent['bios'] ?? $devices['bios'] ?? []),
            'tpm' => (array) ($devices['tpm'] ?? $agent['tpm'] ?? []),
            'nvidia_smi' => $nvidia,
            'telemetry' => $telemetry,
            'collected_at' => $agent['collected_at'] ?? date('c'),
            'probe_version' => (int) ($agent['probe_version'] ?? 2),
            'elevated' => !empty($agent['elevated']),
        ];

        // GPU-Z-class static fields from telemetry primary GPU when present
        $telGpus = (array) ($telemetry['gpu']['gpus'] ?? []);
        if ($telGpus !== [] && is_array($telGpus[0] ?? null)) {
            $g0 = $telGpus[0];
            $out['gpu'] = array_merge($out['gpu'], array_filter([
                'vbios' => $g0['vbios'] ?? null,
                'driver_branch' => $g0['driver_branch'] ?? null,
                'pci_location' => $g0['pci_location'] ?? null,
                'memory_bus_width' => $g0['memory_bus_width'] ?? null,
                'memory_vendor' => $g0['memory_vendor'] ?? null,
                'vendor_id' => $g0['vendor_id'] ?? null,
                'device_id' => $g0['device_id'] ?? null,
                'fields' => $g0['fields'] ?? null,
            ], static fn ($v) => $v !== null && $v !== ''));
        }

        return $out;
    }

    /** @param mixed $network */
    private function detectWifiStandard($network): ?string
    {
        if (!is_array($network)) {
            return null;
        }
        foreach ($network as $nic) {
            if (!is_array($nic)) {
                continue;
            }
            $desc = strtolower((string) ($nic['interface'] ?? $nic['name'] ?? ''));
            if (!str_contains($desc, 'wi-fi') && !str_contains($desc, 'wireless') && !str_contains($desc, 'wlan')) {
                continue;
            }
            if (str_contains($desc, '6e') || str_contains($desc, 'ax')) {
                return 'Wi‑Fi 6/6E';
            }
            if (str_contains($desc, 'ac')) {
                return 'Wi‑Fi 5 (ac)';
            }

            return 'Wi‑Fi';
        }

        return null;
    }
}
