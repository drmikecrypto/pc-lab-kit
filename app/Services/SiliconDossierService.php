<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Merge probe silicon dossier into Hardware Reference / reports.
 */
class SiliconDossierService
{
    /**
     * @param array<string, mixed> $probe Full probe or telemetry
     * @return array<string, mixed>
     */
    public function present(array $probe): array
    {
        $tel = (array) ($probe['telemetry'] ?? $probe);
        $dossier = (array) ($tel['dossier'] ?? $probe['dossier'] ?? []);
        $open = (array) ($tel['open_book'] ?? $probe['open_book'] ?? []);

        $cpu = (array) ($dossier['cpu'] ?? []);
        $gpu = (array) ($dossier['gpu'] ?? []);
        $ram = (array) ($dossier['ram'] ?? []);
        $board = (array) ($dossier['board'] ?? []);
        $monitors = array_values(array_filter((array) ($dossier['monitors'] ?? []), 'is_array'));
        $storage = array_values(array_filter((array) ($dossier['storage'] ?? []), 'is_array'));
        $pci = array_values(array_filter((array) ($gpu['pci_config'] ?? []), 'is_array'));

        return [
            'collected_at' => $dossier['collected_at'] ?? null,
            'cpu' => $cpu,
            'gpu' => $gpu,
            'ram' => [
                'modules' => array_values(array_filter((array) ($ram['modules'] ?? []), 'is_array')),
                'source' => $ram['source'] ?? null,
                'note' => $ram['note'] ?? null,
            ],
            'storage' => $storage,
            'monitors' => $monitors,
            'board' => $board,
            'pci_config' => $pci,
            'open_book' => [
                'count' => (int) ($open['count'] ?? $dossier['open_book_count'] ?? 0),
                'sensors' => array_values(array_filter((array) ($open['sensors'] ?? []), 'is_array')),
                'open_book_therm' => (bool) ($open['open_book_therm'] ?? false),
                'open_book_vram' => (bool) ($open['open_book_vram'] ?? false),
                'note' => $open['note'] ?? null,
            ],
        ];
    }
}
