<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Local driver install outcome learner — adjusts confidence from recorded results.
 */
class DriverOutcomeLearnerService
{
    private string $path;

    public function __construct(?string $projectRoot = null)
    {
        $root = $projectRoot ?? dirname(__DIR__, 2);
        $dir = $root . '/storage/settings';
        if (!is_dir($dir)) {
            mkdir($dir, 0755, true);
        }
        $this->path = $dir . '/driver_outcomes.json';
    }

    /** @param array<string, mixed> $outcome */
    public function record(array $outcome): void
    {
        $data = $this->load();
        $key = strtolower(trim((string) ($outcome['vendor_id'] ?? ''))) . ':'
            . strtolower(trim((string) ($outcome['device_id'] ?? '')));
        if ($key === ':') {
            $key = (string) ($outcome['instance_id'] ?? bin2hex(random_bytes(4)));
        }
        $prev = $data['devices'][$key] ?? ['success' => 0, 'fail' => 0];
        if (!empty($outcome['success'])) {
            ++$prev['success'];
        } else {
            ++$prev['fail'];
        }
        $data['devices'][$key] = $prev;
        $data['updated_at'] = gmdate('c');
        file_put_contents($this->path, json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE), LOCK_EX);
    }

    public function successRate(string $vendorDeviceKey): ?float
    {
        $data = $this->load();
        $row = $data['devices'][$vendorDeviceKey] ?? null;
        if (!$row) {
            return null;
        }
        $total = (int) ($row['success'] ?? 0) + (int) ($row['fail'] ?? 0);
        if ($total <= 0) {
            return null;
        }

        return round(((int) $row['success']) / $total * 100, 1);
    }

    /** @return array<string, mixed> */
    public function weights(): array
    {
        $data = $this->load();
        $rates = [];
        foreach ($data['devices'] ?? [] as $key => $row) {
            $total = (int) ($row['success'] ?? 0) + (int) ($row['fail'] ?? 0);
            if ($total >= 3) {
                $rates[$key] = round(((int) $row['success']) / $total, 3);
            }
        }

        return ['updated_at' => $data['updated_at'] ?? null, 'rates' => $rates];
    }

    /** @return array<string, mixed> */
    private function load(): array
    {
        if (!is_file($this->path)) {
            return ['devices' => []];
        }
        $data = json_decode((string) file_get_contents($this->path), true);

        return is_array($data) ? $data : ['devices' => []];
    }
}
