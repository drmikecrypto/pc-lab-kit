<?php

declare(strict_types=1);

namespace App\Services;

/**
 * SVG-friendly topology layout from hardware knowledge graph.
 */
class TopologyViewService
{
    /**
     * @param array{nodes?: list<array<string, mixed>>, edges?: list<array<string, mixed>>, summary?: array<string, mixed>} $graph
     * @return array<string, mixed>
     */
    public function fromGraph(array $graph): array
    {
        $nodes = is_array($graph['nodes'] ?? null) ? $graph['nodes'] : [];
        $edges = is_array($graph['edges'] ?? null) ? $graph['edges'] : [];

        // Normalize associative node maps
        if ($nodes !== [] && !array_is_list($nodes)) {
            $nodes = array_values($nodes);
        }

        $slots = [
            'system' => [400, 40],
            'cpu' => [200, 160],
            'chipset' => [400, 160],
            'motherboard' => [400, 100],
            'bios' => [520, 100],
            'tpm' => [280, 100],
            'gpu' => [600, 160],
            'ram' => [120, 300],
            'storage' => [280, 300],
            'psu' => [520, 300],
            'network' => [680, 300],
            'cooler' => [200, 40],
            'thermal' => [600, 40],
            'battery' => [80, 160],
            'monitor' => [680, 40],
        ];

        $typeSlots = [
            'dimm' => [40, 360],
            'fan' => [200, 80],
            'usb' => [40, 440],
            'pci' => [400, 440],
            'device' => [600, 440],
            'storage' => [280, 360],
            'monitor' => [680, 80],
        ];

        $placed = [];
        $typeCounts = [];
        $i = 0;
        foreach ($nodes as $n) {
            if (!is_array($n)) {
                continue;
            }
            $id = (string) ($n['id'] ?? '');
            $type = strtolower((string) ($n['type'] ?? 'component'));
            if ($id === '') {
                continue;
            }
            $xy = $slots[$id] ?? null;
            if ($xy === null && isset($slots[$type])) {
                $xy = $slots[$type];
            }
            if ($xy === null && isset($typeSlots[$type])) {
                $base = $typeSlots[$type];
                $count = $typeCounts[$type] ?? 0;
                $typeCounts[$type] = $count + 1;
                $xy = [$base[0] + ($count % 4) * 100, $base[1] + intdiv($count, 4) * 56];
            }
            if ($xy === null) {
                $xy = [80 + ($i % 6) * 120, 400 + intdiv($i, 6) * 70];
                $i++;
            }
            $placed[] = [
                'id' => $id,
                'type' => $type,
                'label' => (string) ($n['label'] ?? $id),
                'x' => $xy[0],
                'y' => $xy[1],
                'attrs' => array_diff_key($n, array_flip(['id', 'type', 'label'])),
            ];
        }

        $links = [];
        foreach ($edges as $e) {
            if (!is_array($e)) {
                continue;
            }
            $links[] = [
                'source' => (string) ($e['source'] ?? ''),
                'target' => (string) ($e['target'] ?? ''),
                'relation' => (string) ($e['relation'] ?? 'link'),
            ];
        }

        return [
            'width' => 800,
            'height' => 480,
            'nodes' => $placed,
            'links' => $links,
            'summary' => $graph['summary'] ?? [],
        ];
    }
}
