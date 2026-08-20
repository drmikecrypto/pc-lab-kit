<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Saved Sensor Deck layouts + Rainmeter/JSON export.
 */
class SensorDeckService
{
    private string $path;

    public function __construct(?string $projectRoot = null)
    {
        $root = $projectRoot ?? dirname(__DIR__, 2);
        $dir = $root . '/storage/settings';
        if (!is_dir($dir)) {
            mkdir($dir, 0755, true);
        }
        $this->path = $dir . '/sensor_deck.json';
    }

    /** @return array<string, mixed> */
    public function defaultLayout(): array
    {
        return [
            'version' => 1,
            'updated_at' => null,
            'widgets' => [
                ['id' => 'cpu_temp', 'type' => 'gauge', 'source' => 'cpu_temp', 'label' => 'CPU °C', 'min' => 20, 'max' => 100],
                ['id' => 'gpu_temp', 'type' => 'gauge', 'source' => 'gpu_temp', 'label' => 'GPU °C', 'min' => 20, 'max' => 100],
                ['id' => 'gpu_hotspot', 'type' => 'gauge', 'source' => 'gpu_hotspot', 'label' => 'Hotspot °C', 'min' => 20, 'max' => 110],
                ['id' => 'gpu_therm_spread', 'type' => 'gauge', 'source' => 'gpu_therm_spread', 'label' => 'Therm spread °C', 'min' => 0, 'max' => 40],
                ['id' => 'gpu_vram_temp', 'type' => 'gauge', 'source' => 'gpu_vram_temp', 'label' => 'VRAM junction °C', 'min' => 20, 'max' => 110],
                ['id' => 'gpu_therm_s1', 'type' => 'gauge', 'source' => 'gpu_therm_s1', 'label' => 'Therm S1 °C', 'min' => 20, 'max' => 120],
                ['id' => 'cpu_load', 'type' => 'gauge', 'source' => 'cpu_load', 'label' => 'CPU %', 'min' => 0, 'max' => 100],
                ['id' => 'gpu_load', 'type' => 'gauge', 'source' => 'gpu_load', 'label' => 'GPU %', 'min' => 0, 'max' => 100],
                ['id' => 'vram_used', 'type' => 'gauge', 'source' => 'vram_used_pct', 'label' => 'VRAM %', 'min' => 0, 'max' => 100],
                ['id' => 'pkg_power', 'type' => 'gauge', 'source' => 'package_power_w', 'label' => 'CPU W', 'min' => 0, 'max' => 250],
                ['id' => 'fan_rpm', 'type' => 'gauge', 'source' => 'fan_rpm', 'label' => 'Fan RPM', 'min' => 0, 'max' => 3000],
                ['id' => 'ram_used', 'type' => 'gauge', 'source' => 'ram_used_pct', 'label' => 'RAM %', 'min' => 0, 'max' => 100],
                ['id' => 'temps_spark', 'type' => 'sparkline', 'source' => 'history_temps', 'label' => 'Temp history'],
            ],
        ];
    }

    /** @return array<string, mixed> */
    public function get(): array
    {
        if (!is_file($this->path)) {
            return $this->defaultLayout();
        }
        $data = json_decode((string) file_get_contents($this->path), true);

        return is_array($data) ? array_merge($this->defaultLayout(), $data) : $this->defaultLayout();
    }

    /** @param array<string, mixed> $input @return array<string, mixed> */
    public function save(array $input): array
    {
        $widgets = $input['widgets'] ?? null;
        if (!is_array($widgets) || $widgets === []) {
            throw new \InvalidArgumentException('widgets array required');
        }
        $clean = [];
        foreach (array_slice($widgets, 0, 24) as $w) {
            if (!is_array($w)) {
                continue;
            }
            $id = preg_replace('/[^a-z0-9_\-]/i', '', (string) ($w['id'] ?? '')) ?: ('w' . count($clean));
            $clean[] = [
                'id' => $id,
                'type' => in_array(($w['type'] ?? ''), ['gauge', 'sparkline', 'number'], true) ? $w['type'] : 'gauge',
                'source' => substr((string) ($w['source'] ?? 'cpu_temp'), 0, 64),
                'label' => substr((string) ($w['label'] ?? $id), 0, 48),
                'min' => isset($w['min']) ? (float) $w['min'] : 0,
                'max' => isset($w['max']) ? (float) $w['max'] : 100,
            ];
        }
        if ($clean === []) {
            throw new \InvalidArgumentException('no valid widgets');
        }
        $layout = [
            'version' => 1,
            'updated_at' => gmdate('c'),
            'widgets' => $clean,
        ];
        file_put_contents($this->path, json_encode($layout, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT), LOCK_EX);

        return $layout;
    }

    /** @return array<string, mixed> */
    public function export(string $format = 'json'): array
    {
        $layout = $this->get();
        if ($format === 'csv' || $format === 'timeline') {
            $historyUrl = 'http://127.0.0.1:18765/telemetry/history';
            $raw = @file_get_contents($historyUrl, false, stream_context_create([
                'http' => ['timeout' => 3],
            ]));
            $rows = is_string($raw) ? json_decode($raw, true) : null;
            if (!is_array($rows)) {
                $rows = [];
            }
            $csv = "ts,cpu_temp,gpu_temp,gpu_hotspot,cpu_power,gpu_power,fan_rpm\n";
            foreach ($rows as $r) {
                if (!is_array($r)) {
                    continue;
                }
                $csv .= sprintf(
                    "%s,%s,%s,%s,%s,%s,%s\n",
                    $r['ts'] ?? $r['t'] ?? '',
                    $r['cpu_temp'] ?? $r['cpu_temp_max'] ?? '',
                    $r['gpu_temp'] ?? $r['gpu_temp_max'] ?? '',
                    $r['gpu_hotspot'] ?? '',
                    $r['cpu_power'] ?? '',
                    $r['gpu_power'] ?? '',
                    $r['fan_rpm'] ?? ''
                );
            }

            return [
                'format' => 'csv',
                'filename' => 'PCLabKit-SensorTimeline.csv',
                'content' => $csv,
                'alert_thresholds' => [
                    'cpu_temp_c' => 90,
                    'gpu_temp_c' => 85,
                    'gpu_hotspot_c' => 95,
                ],
            ];
        }

        if ($format === 'rainmeter') {
            $ini = "; PC Lab Kit Sensor Deck export — map these measures to your Probe telemetry JSON/HTTP source.\r\n";
            $ini .= "; Honest export: placeholders only; wire to http://127.0.0.1:18765/telemetry\r\n\r\n";
            $ini .= "[Rainmeter]\r\nUpdate=1000\r\n\r\n";
            foreach ((array) ($layout['widgets'] ?? []) as $i => $w) {
                if (!is_array($w)) {
                    continue;
                }
                $name = preg_replace('/[^A-Za-z0-9]/', '', (string) ($w['id'] ?? ('W' . $i))) ?: ('W' . $i);
                $ini .= "[Measure{$name}]\r\n";
                $ini .= "Measure=WebParser\r\n";
                $ini .= "URL=http://127.0.0.1:18765/telemetry\r\n";
                $ini .= "RegExp=(?s)\"{$w['source']}\":\\s*([0-9.]+)\r\n";
                $ini .= "StringIndex=1\r\n";
                $ini .= "UpdateRate=2\r\n\r\n";
                $ini .= "[Meter{$name}]\r\n";
                $ini .= "Meter=String\r\n";
                $ini .= "MeasureName=Measure{$name}\r\n";
                $ini .= "Text=" . ($w['label'] ?? $name) . ": %1\r\n";
                $ini .= "FontSize=12\r\n";
                $ini .= "FontColor=230,237,243\r\n\r\n";
            }

            return [
                'format' => 'rainmeter',
                'filename' => 'PCLabKit-SensorDeck.ini',
                'content' => $ini,
            ];
        }

        return [
            'format' => 'json',
            'filename' => 'PCLabKit-SensorDeck.json',
            'content' => $layout,
            'agent_endpoints' => [
                'telemetry' => 'http://127.0.0.1:18765/telemetry',
                'history' => 'http://127.0.0.1:18765/telemetry/history',
            ],
        ];
    }
}
