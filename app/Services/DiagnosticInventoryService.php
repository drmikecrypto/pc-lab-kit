<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Presents probe device inventory for the Hardware Reference UI.
 * Preserves fields; never silently drops known keys.
 */
class DiagnosticInventoryService
{
    /**
     * @param array<string, mixed> $probe Probe /devices payload or full probe with devices key
     * @return array<string, mixed>
     */
    public function present(array $probe): array
    {
        $devices = (array) ($probe['devices'] ?? $probe);
        $summary = (array) ($devices['summary'] ?? []);
        $all = array_values(array_filter((array) ($devices['all_devices'] ?? []), 'is_array'));

        $filters = [
            'present' => 0,
            'hidden' => 0,
            'problem' => 0,
            'driverless' => 0,
            'ghost' => 0,
        ];
        $tree = [];
        foreach ($all as $d) {
            $present = array_key_exists('present', $d) ? !empty($d['present']) : true;
            $hidden = !empty($d['hidden']) || !$present;
            $ghost = !empty($d['ghost']);
            $problem = !empty($d['has_problem']) || ((int) ($d['problem_code'] ?? 0) !== 0 && (int) ($d['problem_code'] ?? 0) !== 22);
            $driverless = !empty($d['needs_driver']);

            if ($present) {
                $filters['present']++;
            }
            if ($hidden) {
                $filters['hidden']++;
            }
            if ($problem) {
                $filters['problem']++;
            }
            if ($driverless) {
                $filters['driverless']++;
            }
            if ($ghost) {
                $filters['ghost']++;
            }

            $bus = (string) ($d['bus'] ?? 'other');
            $cat = (string) ($d['category'] ?? 'other');
            if (!isset($tree[$bus])) {
                $tree[$bus] = [];
            }
            if (!isset($tree[$bus][$cat])) {
                $tree[$bus][$cat] = [];
            }
            $tree[$bus][$cat][] = $this->deviceRow($d);
        }

        $monitors = [];
        foreach ((array) (($devices['monitors']['displays'] ?? [])) as $m) {
            if (!is_array($m)) {
                continue;
            }
            $edid = is_array($m['edid'] ?? null) ? $m['edid'] : null;
            $monitors[] = [
                'name' => (string) ($m['name'] ?? 'Display'),
                'manufacturer' => (string) ($m['manufacturer'] ?? ''),
                'serial' => (string) ($m['serial'] ?? ''),
                'year' => $m['year'] ?? null,
                'week' => $m['week'] ?? null,
                'active' => !empty($m['active']),
                'edid' => $edid,
                'confidence' => (string) ($m['confidence'] ?? 'measured'),
                'source' => (string) ($m['source'] ?? 'wmi'),
                'fields' => $this->flattenFields([
                    'name' => $m['name'] ?? null,
                    'manufacturer' => $m['manufacturer'] ?? null,
                    'edid_version' => $edid['edid_version'] ?? null,
                    'hdr_capable' => $edid['hdr_capable'] ?? null,
                    'preferred_timing' => $edid['preferred_timing'] ?? null,
                    'size_cm' => $edid['size_cm'] ?? null,
                ], (string) ($m['confidence'] ?? 'measured'), (string) ($m['source'] ?? 'wmi')),
            ];
        }

        $modes = array_values(array_filter((array) ($devices['monitors']['modes'] ?? []), 'is_array'));

        return [
            'summary' => [
                'total_devices' => (int) ($summary['total_devices'] ?? count($all)),
                'present_devices' => (int) ($summary['present_devices'] ?? $filters['present']),
                'hidden_devices' => (int) ($summary['hidden_devices'] ?? $filters['hidden']),
                'problem_devices' => (int) ($summary['problem_devices'] ?? $filters['problem']),
                'driverless' => (int) ($summary['driverless'] ?? $filters['driverless']),
                'pci_devices' => (int) ($summary['pci_devices'] ?? count((array) ($devices['pci'] ?? []))),
                'usb_devices' => (int) ($summary['usb_devices'] ?? 0),
                'monitors' => (int) ($summary['monitors'] ?? count($monitors)),
                'categories' => (array) ($summary['categories'] ?? []),
            ],
            'filters' => $filters,
            'tree' => $tree,
            'all_devices' => array_map(fn ($d) => $this->deviceRow($d), $all),
            'problem' => array_map(fn ($d) => $this->deviceRow($d), array_values(array_filter((array) ($devices['problem'] ?? []), 'is_array'))),
            'driverless' => array_map(fn ($d) => $this->deviceRow($d), array_values(array_filter((array) ($devices['driverless'] ?? []), 'is_array'))),
            'hidden' => array_map(fn ($d) => $this->deviceRow($d), array_values(array_filter((array) ($devices['hidden'] ?? []), 'is_array'))),
            'pci' => array_values(array_filter((array) ($devices['pci'] ?? []), 'is_array')),
            'usb' => (array) ($devices['usb'] ?? []),
            'monitors' => $monitors,
            'modes' => $modes,
            'firmware' => (array) ($devices['firmware'] ?? []),
            'motherboard' => (array) ($devices['motherboard'] ?? []),
            'bios' => (array) ($devices['bios'] ?? []),
            'tpm' => (array) ($devices['tpm'] ?? []),
            'secure_boot' => $devices['secure_boot'] ?? null,
            'system_slots' => array_values(array_filter((array) ($devices['system_slots'] ?? []), 'is_array')),
            'ports' => array_values(array_filter((array) ($devices['ports'] ?? []), 'is_array')),
            'battery' => array_values(array_filter((array) ($devices['battery'] ?? []), 'is_array')),
            'audio' => array_values(array_filter((array) ($devices['audio'] ?? []), 'is_array')),
            'bluetooth' => array_values(array_filter((array) ($devices['bluetooth'] ?? []), 'is_array')),
            'findings' => array_values(array_filter((array) ($devices['findings'] ?? []), 'is_array')),
            'schema' => (array) ($devices['schema'] ?? ['version' => 2]),
        ];
    }

    /** @param array<string, mixed> $d */
    private function deviceRow(array $d): array
    {
        $row = [
            'name' => (string) ($d['name'] ?? ''),
            'class' => (string) ($d['class'] ?? ''),
            'category' => (string) ($d['category'] ?? ''),
            'status' => (string) ($d['status'] ?? ''),
            'problem_code' => (int) ($d['problem_code'] ?? 0),
            'problem_message' => (string) ($d['problem_message'] ?? ''),
            'instance_id' => (string) ($d['instance_id'] ?? ''),
            'manufacturer' => (string) ($d['manufacturer'] ?? ''),
            'bus' => (string) ($d['bus'] ?? ''),
            'vendor_id' => (string) ($d['vendor_id'] ?? ''),
            'device_id' => (string) ($d['device_id'] ?? ''),
            'subsystem_id' => (string) ($d['subsystem_id'] ?? ''),
            'revision' => (string) ($d['revision'] ?? ''),
            'vendor_name' => (string) ($d['vendor_name'] ?? ''),
            'service' => (string) ($d['service'] ?? ''),
            'present' => array_key_exists('present', $d) ? !empty($d['present']) : true,
            'hidden' => !empty($d['hidden']),
            'ghost' => !empty($d['ghost']),
            'needs_driver' => !empty($d['needs_driver']),
            'has_problem' => !empty($d['has_problem']),
            'parent_instance_id' => (string) ($d['parent_instance_id'] ?? ''),
            'location_paths' => array_values(array_filter(array_map('strval', (array) ($d['location_paths'] ?? [])))),
            'confidence' => (string) ($d['confidence'] ?? 'measured'),
            'source' => (string) ($d['source'] ?? 'pnp'),
        ];
        // Preserve any extra keys the probe added (accuracy gate: no silent nulling).
        foreach ($d as $k => $v) {
            if (!array_key_exists($k, $row)) {
                $row[$k] = $v;
            }
        }
        $row['fields'] = $this->flattenFields([
            'vendor_id' => $row['vendor_id'] ?: null,
            'device_id' => $row['device_id'] ?: null,
            'subsystem_id' => $row['subsystem_id'] ?: null,
            'status' => $row['status'] ?: null,
            'problem_code' => $row['problem_code'] ?: null,
            'service' => $row['service'] ?: null,
            'parent_instance_id' => $row['parent_instance_id'] ?: null,
        ], $row['confidence'], $row['source']);

        return $row;
    }

    /**
     * @param array<string, mixed> $map
     * @return array<string, array{value: mixed, confidence: string, source: string}>
     */
    private function flattenFields(array $map, string $confidence, string $source): array
    {
        $out = [];
        foreach ($map as $k => $v) {
            if ($v === null || $v === '') {
                $out[$k] = ['value' => null, 'confidence' => 'unavailable', 'source' => $source];
            } else {
                $out[$k] = ['value' => $v, 'confidence' => $confidence, 'source' => $source];
            }
        }

        return $out;
    }
}
