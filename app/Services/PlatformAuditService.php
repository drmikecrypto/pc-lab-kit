<?php

declare(strict_types=1);

namespace App\Services;

/**
 * One-page Platform Audit for shop/OEM bay — fingerprint, coverage, plan, drivers, stress.
 */
class PlatformAuditService
{
    /**
     * @param array<string, mixed> $input devices, fingerprint, platform, drivers, suite/plan, stress
     * @return array{document: array<string, mixed>, html: string, json: array<string, mixed>}
     */
    public function build(array $input): array
    {
        $devices = (array) ($input['devices'] ?? []);
        $fingerprint = (array) ($input['fingerprint'] ?? $devices['fingerprint'] ?? []);
        $platform = (array) ($input['platform'] ?? $devices['platform'] ?? []);
        $drivers = (array) ($input['drivers'] ?? []);
        $plan = (array) ($input['plan'] ?? $input['adaptive_plan'] ?? []);
        $stress = (array) ($input['stress'] ?? $input['stress_certificate'] ?? []);
        $actionPlan = (array) ($drivers['action_plan'] ?? []);

        $doc = [
            'schema' => 'pclab-platform-audit-v1',
            'generated_at' => gmdate('c'),
            'fingerprint' => [
                'id' => $fingerprint['id'] ?? null,
                'hash_sha256' => $fingerprint['hash_sha256'] ?? null,
                'coverage_score' => $fingerprint['coverage_score'] ?? null,
                'form_factor' => $fingerprint['form_factor'] ?? null,
                'elevated' => $fingerprint['elevated'] ?? $platform['elevated'] ?? null,
                'capabilities' => array_values((array) ($fingerprint['capabilities'] ?? [])),
            ],
            'gaps' => array_values(array_filter((array) ($fingerprint['gaps'] ?? []), 'is_array')),
            'platform_planes' => [
                'bios' => $platform['bios'] ?? null,
                'uefi' => [
                    'firmware_type' => $platform['uefi']['firmware_type'] ?? null,
                    'secure_boot' => $platform['uefi']['secure_boot'] ?? null,
                    'setup_mode' => $platform['uefi']['setup_mode'] ?? null,
                    'bitlocker' => $platform['uefi']['bitlocker'] ?? null,
                    'boot_entry_count' => count((array) ($platform['uefi']['boot_entries'] ?? [])),
                ],
                'tpm' => [
                    'present' => $platform['tpm']['present'] ?? null,
                    'spec_version' => $platform['tpm']['spec_version'] ?? null,
                    'pcr_banks' => $platform['tpm']['pcr_banks'] ?? null,
                    'pcr_bank_source' => $platform['tpm']['pcr_bank_source'] ?? null,
                    'ready' => $platform['tpm']['ready'] ?? null,
                ],
                'me_psp' => $platform['me_psp'] ?? null,
                'acpi_count' => $platform['acpi']['signature_count'] ?? null,
                'storage' => array_map(static function ($d) {
                    if (!is_array($d)) {
                        return $d;
                    }

                    return [
                        'name' => $d['friendly_name'] ?? $d['model'] ?? null,
                        'firmware' => $d['firmware'] ?? null,
                        'wear' => $d['wear'] ?? null,
                        'smart_depth' => $d['smart_depth'] ?? null,
                        'is_nvme' => $d['is_nvme'] ?? null,
                    ];
                }, array_slice((array) ($platform['storage'] ?? []), 0, 8)),
                'storage_count' => count((array) ($platform['storage'] ?? [])),
                'pci_config_count' => count((array) ($platform['pci_config'] ?? [])),
                'ec_board_count' => $platform['ec_board']['count'] ?? null,
            ],
            'adaptive_plan' => [
                'id' => $plan['id'] ?? $plan['profile'] ?? null,
                'label' => $plan['label'] ?? null,
                'gated' => !empty($plan['gated']),
                'gate_reason' => $plan['gate_reason'] ?? null,
                'steps' => array_values(array_filter((array) ($plan['steps'] ?? []), 'is_array')),
                'benches' => array_values((array) ($plan['benches'] ?? [])),
                'stress_id' => $plan['stress_id'] ?? null,
            ],
            'driver_actions' => [
                'count' => (int) ($actionPlan['count'] ?? count((array) ($drivers['actions'] ?? []))),
                'installable_count' => (int) ($actionPlan['installable_count'] ?? 0),
                'items' => array_slice(array_values(array_filter((array) ($actionPlan['items'] ?? $drivers['actions'] ?? []), 'is_array')), 0, 40),
            ],
            'stress' => [
                'verdict' => $stress['verdict'] ?? $stress['status'] ?? null,
                'id' => $stress['id'] ?? null,
                'label' => $stress['label'] ?? null,
            ],
            'inventory_summary' => (array) ($devices['summary'] ?? []),
            'note' => 'Read-only platform audit — no firmware flash, no NVRAM mutation',
        ];

        $html = $this->toHtml($doc);

        return [
            'document' => $doc,
            'html' => $html,
            'json' => $doc,
        ];
    }

    /** @param array<string, mixed> $doc */
    private function toHtml(array $doc): string
    {
        $fp = (array) ($doc['fingerprint'] ?? []);
        $gaps = (array) ($doc['gaps'] ?? []);
        $steps = (array) ($doc['adaptive_plan']['steps'] ?? []);
        $drivers = (array) ($doc['driver_actions']['items'] ?? []);
        $esc = static fn ($s) => htmlspecialchars((string) $s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');

        $gapLis = '';
        foreach (array_slice($gaps, 0, 12) as $g) {
            if (!is_array($g)) {
                continue;
            }
            $gapLis .= '<li><code>' . $esc($g['plane'] ?? '') . '</code> — ' . $esc($g['detail'] ?? $g['reason'] ?? '') . '</li>';
        }
        $stepLis = '';
        foreach ($steps as $s) {
            if (!is_array($s)) {
                continue;
            }
            $stepLis .= '<li><strong>' . $esc($s['label'] ?? $s['id'] ?? '') . '</strong>'
                . ($s['reason'] ?? '' ? ' — <span class="muted">' . $esc($s['reason']) . '</span>' : '')
                . '</li>';
        }
        $drvLis = '';
        foreach (array_slice($drivers, 0, 20) as $d) {
            if (!is_array($d)) {
                continue;
            }
            $drvLis .= '<li><strong>' . $esc($d['action'] ?? '') . '</strong> '
                . $esc($d['device'] ?? $d['title'] ?? '')
                . ' <span class="muted">(' . $esc($d['category'] ?? '') . ')</span></li>';
        }

        return '<!DOCTYPE html><html><head><meta charset="utf-8"><title>Platform Audit</title>
<style>
body{font-family:Segoe UI,system-ui,sans-serif;margin:2rem;color:#111;background:#f7f7f5}
h1{font-size:1.4rem;margin:0 0 .25rem}
.meta{color:#555;font-size:.85rem;margin-bottom:1.5rem}
.card{border:1px solid #ddd;border-radius:8px;padding:1rem 1.25rem;margin-bottom:1rem;background:#fff}
.bar{height:8px;background:#e5e5e5;border-radius:4px;overflow:hidden;margin:.5rem 0}
.bar>span{display:block;height:100%;background:#0d9488}
.muted{color:#666;font-size:.85rem}
ul{margin:.4rem 0 0 1.1rem;padding:0}
code{font-size:.8rem}
</style></head><body>
<h1>PC Lab Kit — Platform Audit</h1>
<p class="meta">Generated ' . $esc($doc['generated_at'] ?? '') . ' · schema ' . $esc($doc['schema'] ?? '') . '</p>
<div class="card">
  <h2>Fingerprint</h2>
  <p><code>' . $esc($fp['id'] ?? '—') . '</code> · ' . $esc($fp['form_factor'] ?? '—')
        . ' · elevated ' . $esc(!empty($fp['elevated']) ? 'yes' : 'no') . '</p>
  <div class="bar" role="meter"><span style="width:' . (int) ($fp['coverage_score'] ?? 0) . '%"></span></div>
  <p><strong>' . (int) ($fp['coverage_score'] ?? 0) . '%</strong> platform coverage</p>
  ' . ($gapLis !== '' ? '<ul>' . $gapLis . '</ul>' : '<p class="muted">No coverage gaps reported.</p>') . '
</div>
<div class="card">
  <h2>Adaptive plan</h2>
  <p>' . $esc($doc['adaptive_plan']['label'] ?? '—')
        . (!empty($doc['adaptive_plan']['gated']) ? ' · <strong>GATED</strong> ' . $esc($doc['adaptive_plan']['gate_reason'] ?? '') : '')
        . '</p>
  <ul>' . ($stepLis !== '' ? $stepLis : '<li class="muted">No steps</li>') . '</ul>
</div>
<div class="card">
  <h2>Driver actions</h2>
  <p class="muted">' . (int) ($doc['driver_actions']['count'] ?? 0) . ' items · '
        . (int) ($doc['driver_actions']['installable_count'] ?? 0) . ' installable</p>
  <ul>' . ($drvLis !== '' ? $drvLis : '<li class="muted">None</li>') . '</ul>
</div>
<div class="card">
  <h2>Stress</h2>
  <p>Verdict: <strong>' . $esc($doc['stress']['verdict'] ?? '—') . '</strong>
    · ' . $esc($doc['stress']['label'] ?? $doc['stress']['id'] ?? '') . '</p>
</div>
<p class="muted">' . $esc($doc['note'] ?? '') . '</p>
</body></html>';
    }
}
