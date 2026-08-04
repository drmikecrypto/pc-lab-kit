<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Resolves vendor/driver package links from PCI/USB IDs + board model using the
 * shared probe catalog (agent/pclab_probe/data/driver-catalog.json).
 */
class DriverPackageMatcherService
{
    /** @var array<string, mixed>|null */
    private static ?array $catalog = null;

    /**
     * @param array{
     *   category?: string,
     *   device?: string,
     *   name?: string,
     *   instance_id?: string,
     *   vendor_id?: string,
     *   device_id?: string,
     *   bus?: string,
     *   board?: array{manufacturer?: string, product?: string},
     *   system?: array{manufacturer?: string, model?: string}
     * } $ctx
     * @return array{
     *   match_confidence: string,
     *   primary_link: ?array{label: string, url: string, note: ?string},
     *   links: list<array{label: string, url: string, note: ?string}>,
     *   vendor_id: string,
     *   device_id: string,
     *   bus: string,
     *   category: string
     * }
     */
    public function resolve(array $ctx): array
    {
        $catalog = $this->catalog();
        $instanceId = (string) ($ctx['instance_id'] ?? '');
        $parsed = $this->parseHardwareId($instanceId);
        $ven = strtolower((string) ($ctx['vendor_id'] ?? $parsed['vendor_id'] ?? ''));
        $dev = strtolower((string) ($ctx['device_id'] ?? $parsed['device_id'] ?? ''));
        $bus = (string) ($ctx['bus'] ?? $parsed['bus'] ?? '');
        if ($bus === '' && $instanceId !== '') {
            $bus = str_starts_with(strtoupper($instanceId), 'USB\\') ? 'usb' : 'pci';
        }
        $name = (string) ($ctx['device'] ?? $ctx['name'] ?? '');
        $category = $this->normalizeCategory((string) ($ctx['category'] ?? ''), $name, $ven);
        $board = (array) ($ctx['board'] ?? []);
        $system = (array) ($ctx['system'] ?? []);
        $boardMfr = (string) ($board['manufacturer'] ?? '');
        $boardProduct = (string) ($board['product'] ?? '');
        $sysMfr = (string) ($system['manufacturer'] ?? '');
        $sysModel = (string) ($system['model'] ?? '');

        $links = [];
        $confidence = 'generic';
        $primary = null;

        if ($bus === 'usb') {
            foreach ((array) ($catalog['usb'] ?? []) as $row) {
                if (!is_array($row)) {
                    continue;
                }
                $vid = strtolower((string) ($row['vid'] ?? ''));
                $pid = strtolower((string) ($row['pid'] ?? '*'));
                if ($vid === '' || $ven === '' || $vid !== $ven) {
                    continue;
                }
                if ($pid !== '*' && $dev !== '' && $pid !== $dev) {
                    continue;
                }
                $rowCat = (string) ($row['category'] ?? '');
                if ($rowCat !== '' && $category !== '' && $rowCat !== $category && $category !== 'peripherals') {
                    continue;
                }
                $hit = $this->hit($row, 'catalog');
                $links[] = $hit;
                if ($primary === null) {
                    $primary = $hit;
                    $confidence = ($pid !== '*' && $dev !== '') ? 'exact' : 'vendor';
                }
            }
        } else {
            $bestScore = -1;
            foreach ((array) ($catalog['pci'] ?? []) as $row) {
                if (!is_array($row)) {
                    continue;
                }
                $rowVen = strtolower((string) ($row['ven'] ?? ''));
                $rowDev = strtolower((string) ($row['dev'] ?? '*'));
                if ($rowVen === '' || $ven === '' || $rowVen !== $ven) {
                    continue;
                }
                if ($rowDev !== '*' && $dev !== '' && $rowDev !== $dev) {
                    continue;
                }
                $rowCat = (string) ($row['category'] ?? '');
                $nameMatch = (string) ($row['name_match'] ?? '');
                $nameHit = $nameMatch !== '' && $name !== '' && (bool) preg_match('/' . $nameMatch . '/i', $name);
                // name_match is a boost, not a hard filter when ven+category already align
                if ($nameMatch !== '' && $name !== '' && !$nameHit) {
                    $venCatOk = ($rowVen !== '' && $rowVen === $ven && $rowCat !== '' && $rowCat === $category);
                    $exactDev = ($rowDev !== '*' && $dev !== '' && $rowDev === $dev);
                    if (!$venCatOk && !$exactDev) {
                        continue;
                    }
                }
                if ($rowCat !== '' && $category !== '' && $rowCat !== $category) {
                    if (!$nameHit && $rowDev === '*') {
                        continue;
                    }
                }
                $score = 0;
                if ($rowDev !== '*' && $dev !== '' && $rowDev === $dev) {
                    $score += 40;
                }
                if ($nameHit) {
                    $score += 20;
                }
                if ($rowCat !== '' && $rowCat === $category) {
                    $score += 10;
                }
                if ($rowVen !== '' && $rowVen === $ven) {
                    $score += 5;
                }
                // Prefer any ven match over nothing
                if ($score === 0 && $rowVen !== '' && $rowVen === $ven) {
                    $score = 1;
                }
                if ($score <= 0) {
                    continue;
                }
                $hit = $this->hit($row, 'catalog');
                $links[] = $hit;
                if ($score > $bestScore) {
                    $bestScore = $score;
                    $primary = $hit;
                    $confidence = ($rowDev !== '*' && $dev !== '' && $rowDev === $dev) ? 'exact' : 'vendor';
                }
            }
        }

        $hay = strtolower(trim($boardMfr . ' ' . $boardProduct . ' ' . $sysMfr));
        $product = $boardProduct !== '' ? $boardProduct : $sysModel;
        $enc = rawurlencode($product);
        if ($hay !== '' && in_array($category, ['chipset', 'audio', 'network', 'usb', 'storage', ''], true)) {
            foreach ((array) ($catalog['board_patterns'] ?? []) as $row) {
                if (!is_array($row)) {
                    continue;
                }
                $match = (string) ($row['match'] ?? '');
                if ($match === '' || !preg_match('/' . $match . '/i', $hay)) {
                    continue;
                }
                $url = str_replace('{product}', $enc, (string) ($row['url_template'] ?? $row['url'] ?? ''));
                if ($url === '') {
                    continue;
                }
                $hit = [
                    'label' => (string) ($row['label'] ?? 'Board support'),
                    'url' => $url,
                    'note' => $product !== '' ? ('Matched board/OEM pattern for ' . $product) : null,
                ];
                $links[] = $hit;
                if ($confidence === 'generic' || $primary === null) {
                    $primary = $hit;
                    $confidence = 'board';
                }
            }
        }

        if ($category === 'laptop_oem') {
            foreach ((array) ($catalog['oem_patterns'] ?? []) as $row) {
                if (!is_array($row)) {
                    continue;
                }
                $match = (string) ($row['match'] ?? '');
                if ($match === '' || !preg_match('/' . $match . '/i', strtolower($sysMfr))) {
                    continue;
                }
                $hit = $this->hit($row, 'oem');
                $links[] = $hit;
                if ($primary === null) {
                    $primary = $hit;
                    $confidence = 'board';
                }
            }
        }

        $links = $this->dedupeLinks($links);
        if ($primary === null && $links !== []) {
            $primary = $links[0];
        }
        if ($links === []) {
            $confidence = 'generic';
            $primary = [
                'label' => 'Windows Update drivers',
                'url' => 'ms-settings:windowsupdate',
                'note' => 'Optional updates often hide OEM drivers.',
            ];
            $links = [$primary];
        }

        return [
            'match_confidence' => $confidence,
            'primary_link' => $primary,
            'links' => $links,
            'vendor_id' => $ven,
            'device_id' => $dev,
            'bus' => $bus,
            'category' => $category,
        ];
    }

    /**
     * Fill missing match_confidence / links on an action or driverless row.
     *
     * @param array<string, mixed> $row
     * @param array<string, mixed> $board
     * @param array<string, mixed> $system
     * @return array<string, mixed>
     */
    public function enrich(array $row, array $board = [], array $system = []): array
    {
        $hasPrimary = is_array($row['primary_link'] ?? null) && !empty($row['primary_link']['url']);
        $hasLinks = is_array($row['links'] ?? null) && $row['links'] !== [];
        $hasConfidence = (string) ($row['match_confidence'] ?? '') !== '';
        $needsIds = (string) ($row['vendor_id'] ?? '') === '' && (string) ($row['instance_id'] ?? '') !== '';

        if ($hasPrimary && $hasLinks && $hasConfidence && !$needsIds) {
            return $row;
        }

        $resolved = $this->resolve([
            'category' => (string) ($row['category'] ?? ''),
            'device' => (string) ($row['device'] ?? $row['name'] ?? ''),
            'name' => (string) ($row['name'] ?? $row['device'] ?? ''),
            'instance_id' => (string) ($row['instance_id'] ?? ''),
            'vendor_id' => (string) ($row['vendor_id'] ?? ''),
            'device_id' => (string) ($row['device_id'] ?? ''),
            'bus' => (string) ($row['bus'] ?? ''),
            'board' => $board,
            'system' => $system,
        ]);

        $row['vendor_id'] = $resolved['vendor_id'] !== ''
            ? $resolved['vendor_id']
            : (string) ($row['vendor_id'] ?? '');
        $row['device_id'] = $resolved['device_id'] !== ''
            ? $resolved['device_id']
            : (string) ($row['device_id'] ?? '');
        $row['bus'] = $resolved['bus'] !== ''
            ? $resolved['bus']
            : (string) ($row['bus'] ?? '');
        if ((string) ($row['category'] ?? '') === '' || (string) ($row['category'] ?? '') === 'other' || (string) ($row['category'] ?? '') === 'motherboard' || (string) ($row['category'] ?? '') === 'pci') {
            $row['category'] = $resolved['category'];
        }
        if (!$hasConfidence || (string) ($row['match_confidence'] ?? '') === '') {
            $row['match_confidence'] = $resolved['match_confidence'];
        }
        if (!$hasPrimary) {
            $row['primary_link'] = $resolved['primary_link'];
        }
        if (!$hasLinks) {
            $row['links'] = $resolved['links'];
        }

        return $row;
    }

    /** @return array{bus: string, vendor_id: string, device_id: string} */
    public function parseHardwareId(string $instanceId): array
    {
        $info = ['bus' => '', 'vendor_id' => '', 'device_id' => ''];
        // Normalize doubled backslashes from JSON / test literals.
        $id = strtoupper(str_replace(['/', '\\\\'], ['\\', '\\'], $instanceId));
        if (preg_match('/VEN_([0-9A-F]{4}).{0,24}DEV_([0-9A-F]{4})/', $id, $m)) {
            $info['bus'] = 'pci';
            $info['vendor_id'] = strtolower($m[1]);
            $info['device_id'] = strtolower($m[2]);
        } elseif (preg_match('/VID_([0-9A-F]{4}).{0,24}PID_([0-9A-F]{4})/', $id, $m)) {
            $info['bus'] = 'usb';
            $info['vendor_id'] = strtolower($m[1]);
            $info['device_id'] = strtolower($m[2]);
        }

        return $info;
    }

    public function normalizeCategory(string $category, string $name = '', string $ven = ''): string
    {
        $c = strtolower(trim($category));
        $map = [
            'motherboard' => 'chipset',
            'pci' => 'chipset',
            'firmware' => 'chipset',
            'wireless' => 'network',
            'thunderbolt' => 'usb',
            'input' => 'peripherals',
            'other' => '',
            'unknown' => '',
        ];
        if (isset($map[$c])) {
            $c = $map[$c];
        }
        if ($c !== '') {
            return $c;
        }
        $n = strtolower($name);
        if (preg_match('/geforce|radeon|arc |uhd|iris|vga|3d|display|gpu/', $n) || in_array($ven, ['10de', '1002'], true)) {
            return 'gpu';
        }
        if (preg_match('/ethernet|wi-?fi|wireless|bluetooth|wlan|lan /', $n)) {
            return 'network';
        }
        if (preg_match('/audio|sound|hd audio/', $n)) {
            return 'audio';
        }
        if (preg_match('/sm ?bus|management engine|mei|pch|chipset|lpc|serial io|pci simple/', $n) || in_array($ven, ['8086', '1022'], true)) {
            return 'chipset';
        }
        if (preg_match('/usb|thunderbolt|usb4/', $n)) {
            return 'usb';
        }
        if (preg_match('/nvme|ahci|sata|raid|storage/', $n)) {
            return 'storage';
        }

        return 'chipset';
    }

    /** @return array<string, mixed> */
    private function catalog(): array
    {
        if (self::$catalog !== null) {
            return self::$catalog;
        }
        $path = dirname(__DIR__, 2) . '/agent/pclab_probe/data/driver-catalog.json';
        if (!is_file($path)) {
            self::$catalog = ['pci' => [], 'usb' => [], 'board_patterns' => [], 'oem_patterns' => []];

            return self::$catalog;
        }
        $json = json_decode((string) file_get_contents($path), true);
        self::$catalog = is_array($json) ? $json : ['pci' => [], 'usb' => [], 'board_patterns' => [], 'oem_patterns' => []];

        return self::$catalog;
    }

    /**
     * @param array<string, mixed> $row
     * @return array{label: string, url: string, note: ?string}
     */
    private function hit(array $row, string $source): array
    {
        return [
            'label' => (string) ($row['label'] ?? 'Driver package'),
            'url' => (string) ($row['url'] ?? ''),
            'note' => isset($row['note']) ? (string) $row['note'] : ($source !== '' ? 'source:' . $source : null),
        ];
    }

    /**
     * @param list<array{label: string, url: string, note: ?string}> $links
     * @return list<array{label: string, url: string, note: ?string}>
     */
    private function dedupeLinks(array $links): array
    {
        $seen = [];
        $out = [];
        foreach ($links as $l) {
            $url = (string) ($l['url'] ?? '');
            if ($url === '' || isset($seen[$url])) {
                continue;
            }
            $seen[$url] = true;
            $out[] = $l;
        }

        return $out;
    }
}
