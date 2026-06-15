<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Normalizes PCVerse Windows Probe JSON (v2) into DiagnosticService report shape.
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

        if ($telemetry !== []) {
            $telRam = (array) ($telemetry['ram'] ?? []);
            if ($telRam !== []) {
                $ram = array_merge($ram, $telRam);
            }
            $telGaming = (array) ($telemetry['gaming'] ?? []);
            if ($telGaming !== []) {
                $gaming = array_merge($gaming, $telGaming);
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

        return [
            'device' => array_merge($device, [
                'form_factor' => $device['form_factor'] ?? 'desktop',
                'platform' => 'windows',
                'probe_agent' => 'pcverse-probe',
            ]),
            'cpu' => array_merge($cpu, [
                'model' => trim((string) ($cpu['model'] ?? '')),
                'cores' => (int) ($cpu['cores'] ?? 0),
                'threads' => (int) ($cpu['threads'] ?? 0),
                'temp_max' => $sensors['cpu_temp_max'] ?? null,
            ]),
            'gpu' => array_merge($gpu, [
                'model' => (string) ($nvidia['name'] ?? $gpu['model'] ?? ''),
                'vram_gb' => (float) ($gpu['vram_gb'] ?? 0),
                'hotspot_max' => $nvidia['temp_c'] ?? $sensors['gpu_temp_max'] ?? null,
                'power_w' => $nvidia['power_w'] ?? null,
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
                'spd_source' => $ram['spd_source'] ?? null,
            ],
            'storage' => [
                'disks' => $storageList,
                'primary' => $primaryStorage,
                'type' => $primaryStorage['interface'] ?? $primaryStorage['media_type'] ?? null,
            ],
            'motherboard' => (array) ($agent['motherboard'] ?? []),
            'psu' => (array) ($agent['psu'] ?? []),
            'network' => [
                'adapters' => $network,
                'lan_speed_mbps' => $lanMbps,
                'wifi_standard' => $this->detectWifiStandard($network),
            ],
            'battery' => $battery,
            'sensors' => array_merge($sensors, [
                'throttle_count' => (int) ($sensors['throttle_count'] ?? 0),
            ]),
            'gaming' => $gaming,
            'peripherals' => (array) ($agent['peripherals'] ?? []),
            'bios' => (array) ($agent['bios'] ?? []),
            'nvidia_smi' => $nvidia,
            'telemetry' => $telemetry,
            'collected_at' => $agent['collected_at'] ?? date('c'),
            'probe_version' => (int) ($agent['probe_version'] ?? 2),
        ];
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
