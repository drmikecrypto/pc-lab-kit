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

    /**
     * Three.js-friendly 3D board layout (normalized -1..1 plane + elevation by type).
     *
     * @param array{nodes?: list<array<string, mixed>>, edges?: list<array<string, mixed>>, summary?: array<string, mixed>} $graph
     * @return array<string, mixed>
     */
    public function fromGraph3d(array $graph): array
    {
        $flat = $this->fromGraph($graph);
        $slots3d = [
            'cpu' => ['x' => -0.35, 'y' => 0.08, 'z' => 0.05],
            'gpu' => ['x' => 0.35, 'y' => 0.08, 'z' => 0.12],
            'ram' => ['x' => -0.55, 'y' => -0.05, 'z' => 0.02],
            'storage' => ['x' => 0.0, 'y' => -0.25, 'z' => 0.0],
            'psu' => ['x' => 0.55, 'y' => -0.35, 'z' => 0.0],
            'motherboard' => ['x' => 0.0, 'y' => 0.0, 'z' => 0.0],
            'chipset' => ['x' => 0.05, 'y' => 0.02, 'z' => 0.03],
            'network' => ['x' => 0.65, 'y' => -0.1, 'z' => 0.0],
            'cooler' => ['x' => -0.35, 'y' => 0.22, 'z' => 0.15],
            'system' => ['x' => 0.0, 'y' => 0.35, 'z' => 0.0],
        ];
        $nodes3d = [];
        foreach ((array) ($flat['nodes'] ?? []) as $n) {
            if (!is_array($n)) {
                continue;
            }
            $id = (string) ($n['id'] ?? '');
            $type = (string) ($n['type'] ?? 'component');
            $pos = $slots3d[$id] ?? $slots3d[$type] ?? [
                'x' => (($n['x'] ?? 400) / 800) - 0.5,
                'y' => 0.15 - (($n['y'] ?? 240) / 480) * 0.5,
                'z' => 0.02,
            ];
            $nodes3d[] = [
                'id' => $id,
                'type' => $type,
                'label' => (string) ($n['label'] ?? $id),
                'position' => $pos,
                'size' => $this->nodeSize3d($type),
                'attrs' => (array) ($n['attrs'] ?? []),
            ];
        }

        return [
            'mode' => '3d',
            'nodes' => $nodes3d,
            'links' => $flat['links'] ?? [],
            'summary' => $flat['summary'] ?? [],
            'board' => ['width' => 1.4, 'depth' => 1.0, 'thickness' => 0.02],
        ];
    }

    private function nodeSize3d(string $type): array
    {
        return match ($type) {
            'cpu' => ['w' => 0.18, 'h' => 0.04, 'd' => 0.18],
            'gpu' => ['w' => 0.28, 'h' => 0.06, 'd' => 0.12],
            'ram', 'dimm' => ['w' => 0.08, 'h' => 0.03, 'd' => 0.22],
            'storage' => ['w' => 0.14, 'h' => 0.02, 'd' => 0.06],
            'psu' => ['w' => 0.2, 'h' => 0.08, 'd' => 0.14],
            default => ['w' => 0.1, 'h' => 0.03, 'd' => 0.1],
        };
    }
}
