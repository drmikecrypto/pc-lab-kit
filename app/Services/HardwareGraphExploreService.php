<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Interactive hardware graph explorer — filterable views for UI.
 */
class HardwareGraphExploreService
{
    /** @param array<string, mixed> $graph */
    public function buildExploreView(array $graph): array
    {
        $nodes = is_array($graph['nodes'] ?? null) ? $graph['nodes'] : [];
        $edges = is_array($graph['edges'] ?? null) ? $graph['edges'] : [];

        $byType = [];
        foreach ($nodes as $n) {
            if (!is_array($n)) {
                continue;
            }
            $type = (string) ($n['type'] ?? 'other');
            $byType[$type][] = $n;
        }

        $paths = [
            'power' => $this->filterPath($nodes, $edges, ['psu', 'motherboard', 'cpu', 'gpu']),
            'thermal' => $this->filterPath($nodes, $edges, ['cpu', 'gpu', 'cooler', 'sensor']),
            'storage' => $this->filterPath($nodes, $edges, ['storage', 'nvme', 'sata']),
            'drivers' => array_values(array_filter($nodes, static fn ($n) => is_array($n) && ($n['type'] ?? '') === 'driver')),
        ];

        return [
            'summary' => $graph['summary'] ?? [],
            'node_count' => count($nodes),
            'edge_count' => count($edges),
            'by_type' => $byType,
            'paths' => $paths,
            'nodes' => $nodes,
            'edges' => $edges,
        ];
    }

    /**
     * @param list<array<string, mixed>> $nodes
     * @param list<array<string, mixed>> $edges
     * @param list<string> $types
     * @return list<array<string, mixed>>
     */
    private function filterPath(array $nodes, array $edges, array $types): array
    {
        $typeSet = array_flip($types);
        $ids = [];
        foreach ($nodes as $n) {
            if (!is_array($n)) {
                continue;
            }
            $t = (string) ($n['type'] ?? '');
            if (isset($typeSet[$t])) {
                $ids[(string) ($n['id'] ?? '')] = true;
            }
        }
        $pathEdges = array_values(array_filter($edges, static function ($e) use ($ids) {
            if (!is_array($e)) {
                return false;
            }

            return isset($ids[(string) ($e['source'] ?? '')]) || isset($ids[(string) ($e['target'] ?? '')]);
        }));

        return [
            'nodes' => array_values(array_filter($nodes, static fn ($n) => is_array($n) && isset($ids[(string) ($n['id'] ?? '')]))),
            'edges' => $pathEdges,
        ];
    }
}
