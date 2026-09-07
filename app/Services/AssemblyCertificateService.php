<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Client-facing one-page Assembly Certificate (HTML → print PDF).
 */
class AssemblyCertificateService
{
    /**
     * @param array<string, mixed> $analysis Suite/full analysis
     * @param array<string, mixed> $meta shop_name, token
     * @return array{title: string, html: string, document: array<string, mixed>}
     */
    public function build(array $analysis, array $meta = []): array
    {
        $summary = (array) ($analysis['report_summary'] ?? []);
        $metrics = (array) ($analysis['metrics'] ?? []);
        $cert = is_array($analysis['stress_certificate'] ?? null) ? $analysis['stress_certificate'] : [];
        $dossier = is_array($analysis['silicon_dossier'] ?? null) ? $analysis['silicon_dossier'] : [];
        $open = (array) ($dossier['open_book'] ?? []);
        $suite = (array) ($analysis['suite'] ?? []);
        $plan = is_array($suite['plan'] ?? null) ? $suite['plan'] : (is_array($analysis['adaptive_plan'] ?? null) ? $analysis['adaptive_plan'] : []);
        $fingerprint = (array) ($dossier['fingerprint'] ?? $analysis['fingerprint'] ?? []);
        $platform = (array) ($dossier['platform'] ?? $analysis['platform'] ?? []);
        $shop = trim((string) ($meta['shop_name'] ?? $analysis['shop_name'] ?? 'PC Lab Kit'));
        $passed = (bool) ($cert['passed'] ?? false);
        $verdict = (string) ($cert['verdict'] ?? ($passed ? 'PASS' : 'INCOMPLETE'));
        $sessionHash = (string) ($meta['session_hash'] ?? $analysis['session_hash'] ?? '');
        $wheaCount = (int) (($cert['peaks']['whea_errors'] ?? null) ?? ($cert['whea_timeline']['count'] ?? 0));
        $pcieWarnings = is_array($cert['pcie_warnings'] ?? null) ? $cert['pcie_warnings'] : [];
        $stabilityMargin = $cert['stability_margin_pct'] ?? null;

        $planSteps = [];
        foreach (array_slice((array) ($plan['steps'] ?? []), 0, 16) as $s) {
            if (!is_array($s)) {
                continue;
            }
            $planSteps[] = [
                'id' => (string) ($s['id'] ?? ''),
                'label' => (string) ($s['label'] ?? $s['id'] ?? ''),
                'reason' => (string) ($s['reason'] ?? ''),
            ];
        }

        $doc = [
            'product' => 'PC Lab Kit Assembly Certificate',
            'shop_name' => $shop,
            'generated_at' => gmdate('c'),
            'verdict' => $verdict,
            'passed' => $passed,
            'cpu' => $summary['cpu'] ?? ($dossier['cpu']['model'] ?? null),
            'gpu' => $summary['gpu'] ?? ($dossier['gpu']['name'] ?? null),
            'ram_gb' => $summary['ram_gb'] ?? null,
            'gpu_core_c' => $metrics['gpu_temp_max'] ?? null,
            'gpu_hotspot_c' => $metrics['gpu_hotspot_max'] ?? null,
            'gpu_hotspot_source' => $metrics['gpu_hotspot_source'] ?? ($dossier['gpu']['hotspot_source'] ?? null),
            'gpu_therm_spread' => $metrics['gpu_therm_spread'] ?? null,
            'gpu_vram_c' => $metrics['gpu_vram_temp'] ?? null,
            'open_book_count' => (int) ($open['count'] ?? 0),
            'open_book_sources' => array_values(array_unique(array_filter(array_map(
                static fn ($s) => is_array($s) ? (string) ($s['source'] ?? '') : '',
                (array) ($open['sensors'] ?? [])
            )))),
            'coverage_score' => $fingerprint['coverage_score'] ?? ($dossier['firmware_inventory']['coverage_score'] ?? null),
            'fingerprint_id' => $fingerprint['id'] ?? null,
            'form_factor' => $fingerprint['form_factor'] ?? null,
            'secure_boot' => $platform['uefi']['secure_boot'] ?? ($dossier['firmware_inventory']['secure_boot'] ?? null),
            'tpm_present' => !empty($platform['tpm']['present'] ?? $dossier['firmware_inventory']['tpm']['present'] ?? false),
            'adaptive_plan' => [
                'label' => $plan['label'] ?? ($suite['profile'] ?? null),
                'gated' => !empty($plan['gated']),
                'steps' => $planSteps,
                'benches' => array_values((array) ($plan['benches'] ?? $suite['benches'] ?? [])),
            ],
            'whea_errors' => $wheaCount > 0 ? $wheaCount : null,
            'pcie_warnings' => $pcieWarnings,
            'stability_margin_pct' => $stabilityMargin,
            'session_hash' => $sessionHash !== '' ? $sessionHash : null,
            'verification_qr' => $sessionHash !== '' ? ('pclab://verify/' . $sessionHash) : null,
            'stress_certificate' => $cert,
            'token' => $meta['token'] ?? null,
        ];

        $title = sprintf('Assembly Certificate — %s — %s', $verdict, $doc['cpu'] ?: 'PC');

        return [
            'title' => $title,
            'html' => $this->render($doc),
            'document' => $doc,
        ];
    }

    /** @param array<string, mixed> $d */
    private function render(array $d): string
    {
        $esc = static fn ($v) => htmlspecialchars((string) ($v ?? '—'), ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        $sources = implode(', ', array_map($esc, (array) $d['open_book_sources']));
        $verdictClass = !empty($d['passed']) ? 'pass' : 'fail';
        $pcie = implode('; ', array_map($esc, (array) ($d['pcie_warnings'] ?? [])));
        $whea = $d['whea_errors'] ?? null;
        $margin = $d['stability_margin_pct'] ?? null;
        $qr = $d['verification_qr'] ?? null;
        $plan = (array) ($d['adaptive_plan'] ?? []);
        $stepHtml = '';
        foreach ((array) ($plan['steps'] ?? []) as $s) {
            if (!is_array($s)) {
                continue;
            }
            $stepHtml .= '<li><strong>' . $esc($s['label'] ?? '') . '</strong>'
                . (($s['reason'] ?? '') !== '' ? ' — <span class="meta">' . $esc($s['reason']) . '</span>' : '')
                . '</li>';
        }

        return '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><title>'
            . $esc($d['product']) . '</title><style>
            body{font-family:Segoe UI,system-ui,sans-serif;background:#0d1117;color:#e6edf3;margin:2rem;max-width:720px}
            h1{font-size:1.4rem;margin:0 0 .25rem}
            .shop{color:#8b98a5;margin-bottom:1.25rem}
            .verdict{display:inline-block;padding:.35rem .8rem;font-weight:700;letter-spacing:.06em}
            .verdict.pass{background:#1a7f37;color:#fff}
            .verdict.fail{background:#da3633;color:#fff}
            table{width:100%;border-collapse:collapse;margin:1rem 0}
            th,td{text-align:left;padding:.4rem .5rem;border-bottom:1px solid #30363d;font-size:.9rem}
            th{color:#8b98a5;font-weight:500}
            .meta{font-size:.8rem;color:#8b98a5}
            .qr{font-family:ui-monospace,monospace;font-size:.75rem;word-break:break-all}
            ol{margin:.4rem 0 0 1.1rem;padding:0;font-size:.85rem}
            @media print{body{background:#fff;color:#111}}
            </style></head><body>
            <p class="shop">' . $esc($d['shop_name']) . '</p>
            <h1>Assembly Certificate</h1>
            <p><span class="verdict ' . $verdictClass . '">' . $esc($d['verdict']) . '</span></p>
            <table>
            <tr><th>CPU</th><td>' . $esc($d['cpu']) . '</td></tr>
            <tr><th>GPU</th><td>' . $esc($d['gpu']) . '</td></tr>
            <tr><th>RAM</th><td>' . $esc($d['ram_gb']) . ' GB</td></tr>
            <tr><th>Platform coverage</th><td>' . $esc($d['coverage_score'] ?? '—') . '% · fp <code>' . $esc($d['fingerprint_id'] ?? '—') . '</code> · ' . $esc($d['form_factor'] ?? '') . '</td></tr>
            <tr><th>TPM / Secure Boot</th><td>' . (!empty($d['tpm_present']) ? 'TPM present' : 'TPM n/a') . ' · Secure Boot ' . $esc($d['secure_boot'] === null ? '—' : ($d['secure_boot'] ? 'on' : 'off')) . '</td></tr>
            <tr><th>GPU core peak</th><td>' . $esc($d['gpu_core_c']) . ' °C</td></tr>
            <tr><th>GPU hotspot peak</th><td>' . $esc($d['gpu_hotspot_c']) . ' °C <span class="meta">' . $esc($d['gpu_hotspot_source']) . '</span></td></tr>
            <tr><th>Therm spread</th><td>' . $esc($d['gpu_therm_spread']) . ' °C</td></tr>
            <tr><th>VRAM junction</th><td>' . $esc($d['gpu_vram_c']) . ' °C</td></tr>
            <tr><th>Open-book sensors</th><td>' . $esc($d['open_book_count']) . ' (' . $sources . ')</td></tr>
            <tr><th>WHEA errors</th><td>' . $esc($whea ?? '0') . '</td></tr>
            <tr><th>Stability margin</th><td>' . ($margin !== null ? $esc($margin) . ' %' : '—') . '</td></tr>
            <tr><th>PCIe warnings</th><td>' . ($pcie !== '' ? $pcie : '—') . '</td></tr>
            <tr><th>Lab plan</th><td>' . $esc($plan['label'] ?? '—') . (!empty($plan['gated']) ? ' (gated)' : '') . '</td></tr>
            </table>'
            . ($stepHtml !== '' ? '<p class="meta">Adaptive steps</p><ol>' . $stepHtml . '</ol>' : '')
            . ($qr ? '<p class="meta qr">Verify offline: ' . $esc($qr) . '</p>' : '')
            . '<p class="meta">Generated ' . $esc($d['generated_at']) . ' · token ' . $esc($d['token']) . ' · Print → Save as PDF</p>
            </body></html>';
    }
}
