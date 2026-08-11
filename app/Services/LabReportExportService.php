<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Unified Lab Report — shareable HTML (print → PDF) with scores, percentiles, history delta.
 */
class LabReportExportService
{
    /**
     * @param array<string, mixed> $analysis Finalized analysis (may include comparison, percentiles, ai)
     * @param array<string, mixed> $meta Token / created_at / mode
     * @return array{title: string, html: string, document: array<string, mixed>}
     */
    public function buildDocument(array $analysis, array $meta = []): array
    {
        $comparison = is_array($analysis['comparison'] ?? null) ? $analysis['comparison'] : null;
        $percentiles = is_array($analysis['percentiles'] ?? null) ? $analysis['percentiles'] : [];
        $metrics = (array) ($analysis['metrics'] ?? []);
        $summary = (array) ($analysis['report_summary'] ?? []);
        $certificate = is_array($analysis['stress_certificate'] ?? null) ? $analysis['stress_certificate'] : null;

        $doc = [
            'product' => 'PC Lab Kit Report',
            'generated_at' => gmdate('c'),
            'token' => $meta['token'] ?? ($analysis['saved']['token'] ?? null),
            'mode' => $analysis['mode'] ?? ($meta['mode'] ?? 'full'),
            'health_score' => $analysis['health_score'] ?? null,
            'health_grade' => $analysis['health_grade'] ?? null,
            'cpu' => $summary['cpu'] ?? ($metrics['cpu_model'] ?? null),
            'gpu' => $summary['gpu'] ?? ($metrics['gpu_model'] ?? null),
            'ram_gb' => $summary['ram_gb'] ?? ($metrics['ram_gb'] ?? null),
            'bottleneck' => $analysis['bottleneck'] ?? null,
            'metrics' => $metrics,
            'percentiles' => $percentiles,
            'risks' => array_slice((array) ($analysis['risks'] ?? []), 0, 8),
            'comparison' => $comparison,
            'ai' => is_array($analysis['ai'] ?? null) ? [
                'headline' => $analysis['ai']['headline'] ?? null,
                'summary' => $analysis['ai']['summary'] ?? null,
                'priority_actions' => array_slice((array) ($analysis['ai']['priority_actions'] ?? []), 0, 5),
            ] : null,
            'consultant' => is_array($analysis['consultant'] ?? null) ? [
                'headline' => $analysis['consultant']['headline'] ?? ($analysis['consultant']['headline_fa'] ?? null),
            ] : null,
            'stress_certificate' => $certificate,
            'advisor_cards' => is_array($analysis['advisor_cards'] ?? null) ? $analysis['advisor_cards'] : null,
            'hardware_graph' => is_array($analysis['hardware_graph'] ?? null)
                ? (($analysis['hardware_graph']['summary'] ?? []) + [
                    'node_count' => count($analysis['hardware_graph']['nodes'] ?? []),
                ])
                : null,
            'hardware_reference' => $this->hardwareReferenceSection($analysis),
        ];

        $title = sprintf(
            'PC Lab Kit Report — %s / %s',
            $doc['health_grade'] ?? '?',
            $doc['health_score'] ?? '—'
        );

        return [
            'title' => $title,
            'html' => $this->renderHtml($doc, $title),
            'document' => $doc,
        ];
    }

    /**
     * OC apply report (plan + result + optional thermal samples).
     *
     * @param array<string, mixed> $plan
     * @param array<string, mixed> $applyResult
     * @param list<array<string, mixed>> $samples
     */
    public function buildOcReport(array $plan, array $applyResult, array $samples = [], array $meta = []): array
    {
        $doc = [
            'product' => 'PC Lab Kit OC Safety Report',
            'generated_at' => gmdate('c'),
            'profile' => $plan['profile'] ?? null,
            'safety_score' => $plan['safety_score'] ?? null,
            'eligible' => $plan['eligible'] ?? null,
            'applied' => $applyResult['applied'] ?? [],
            'skipped' => $applyResult['skipped'] ?? [],
            'rolled_back' => $applyResult['rolled_back'] ?? ($meta['rolled_back'] ?? false),
            'preflight' => $meta['preflight'] ?? null,
            'watch' => $meta['watch'] ?? null,
            'samples' => array_slice($samples, 0, 60),
            'disclaimer' => $plan['disclaimer'] ?? 'Reversible OS/GPU tuning only. BIOS/voltage/XMP are advisory.',
        ];
        $title = 'PC Lab Kit OC Report — ' . ($doc['profile'] ?? 'safe');

        return [
            'title' => $title,
            'html' => $this->renderOcHtml($doc, $title),
            'document' => $doc,
        ];
    }

    /** @param array<string, mixed> $analysis @return array<string, mixed>|null */
    private function hardwareReferenceSection(array $analysis): ?array
    {
        $devices = (array) ($analysis['devices'] ?? []);
        $graph = (array) ($analysis['hardware_graph'] ?? []);
        $summary = (array) ($devices['summary'] ?? $graph['summary'] ?? []);
        if ($summary === [] && empty($graph['nodes']) && empty($devices['all_devices'])) {
            return null;
        }
        $rows = [];
        foreach (array_slice((array) ($devices['all_devices'] ?? $devices['problem'] ?? []), 0, 40) as $d) {
            if (!is_array($d)) {
                continue;
            }
            $rows[] = [
                'name' => (string) ($d['name'] ?? ''),
                'bus' => (string) ($d['bus'] ?? ''),
                'status' => (string) ($d['status'] ?? ''),
                'present' => array_key_exists('present', $d) ? !empty($d['present']) : true,
                'confidence' => (string) ($d['confidence'] ?? 'measured'),
                'problem_code' => (int) ($d['problem_code'] ?? 0),
            ];
        }

        return [
            'summary' => [
                'total' => (int) ($summary['total_devices'] ?? $summary['node_count'] ?? count($rows)),
                'hidden' => (int) ($summary['hidden_devices'] ?? 0),
                'driverless' => (int) ($summary['driverless'] ?? 0),
                'problem' => (int) ($summary['problem_devices'] ?? 0),
            ],
            'devices' => $rows,
            'elevated' => !empty($analysis['elevated']),
        ];
    }

    /** @param array<string, mixed> $doc */
    private function renderHtml(array $doc, string $title): string
    {
        $esc = static fn ($v) => htmlspecialchars((string) ($v ?? ''), ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        $pct = (array) ($doc['percentiles'] ?? []);
        $m = (array) ($doc['metrics'] ?? []);
        $cmp = is_array($doc['comparison'] ?? null) ? $doc['comparison'] : null;
        $bn = is_array($doc['bottleneck'] ?? null) ? $doc['bottleneck'] : [];

        $pctRows = '';
        foreach (['cpu' => 'CPU', 'gpu' => 'GPU', 'ram' => 'RAM', 'storage' => 'Storage', 'gaming' => 'Gaming', 'workstation' => 'Workstation'] as $k => $label) {
            $v = $pct[$k] ?? null;
            if ($v === null || $v === '' || (int) $v <= 0) {
                continue;
            }
            $pctRows .= '<tr><td>' . $esc($label) . '</td><td>' . $esc((string) $v) . 'th</td></tr>';
        }

        $metricRows = '';
        foreach ([
            'cpu_score' => 'CPU score',
            'gpu_score' => 'GPU score',
            'ram_gb' => 'RAM (GB)',
            'vram_gb' => 'VRAM (GB)',
            'cpu_temp_max' => 'CPU temp max °C',
            'gpu_temp_max' => 'GPU temp max °C',
            'gpu_hotspot_max' => 'GPU hotspot °C',
            'frametime_p99_ms' => 'Frametime p99 ms',
        ] as $k => $label) {
            if (!isset($m[$k]) || $m[$k] === '' || $m[$k] === null || (float) $m[$k] === 0.0) {
                continue;
            }
            $metricRows .= '<tr><td>' . $esc($label) . '</td><td>' . $esc((string) $m[$k]) . '</td></tr>';
        }

        $deltaHtml = '';
        if ($cmp && !empty($cmp['has_previous'])) {
            $delta = (array) ($cmp['delta'] ?? []);
            $scoreDelta = $delta['health_score'] ?? null;
            $overall = $esc((string) ($cmp['overall'] ?? ''));
            $summary = $esc((string) ($cmp['summary'] ?? ''));
            $deltaHtml = '<section><h2>History delta</h2>'
                . '<p><strong>' . $overall . '</strong> — ' . $summary . '</p>'
                . '<p>Score change: ' . $esc((string) $scoreDelta) . '</p></section>';
        }

        $riskHtml = '';
        foreach ((array) ($doc['risks'] ?? []) as $r) {
            if (!is_array($r)) {
                continue;
            }
            $riskHtml .= '<li><strong>' . $esc((string) ($r['severity'] ?? '')) . '</strong> '
                . $esc((string) ($r['message'] ?? '')) . '</li>';
        }

        $ai = is_array($doc['ai'] ?? null) ? $doc['ai'] : null;
        $aiHtml = '';
        if ($ai) {
            $aiHtml = '<section><h2>AI advisor</h2>'
                . '<p><strong>' . $esc((string) ($ai['headline'] ?? '')) . '</strong></p>'
                . '<p>' . $esc((string) ($ai['summary'] ?? '')) . '</p>';
            $actions = (array) ($ai['priority_actions'] ?? []);
            if ($actions !== []) {
                $aiHtml .= '<ol>';
                foreach ($actions as $a) {
                    $aiHtml .= '<li>' . $esc((string) $a) . '</li>';
                }
                $aiHtml .= '</ol>';
            }
            $aiHtml .= '</section>';
        }

        $cert = is_array($doc['stress_certificate'] ?? null) ? $doc['stress_certificate'] : null;
        $certHtml = '';
        if ($cert) {
            $timelineRows = '';
            foreach (array_slice((array) ($cert['timeline'] ?? []), 0, 80) as $row) {
                if (!is_array($row)) {
                    continue;
                }
                $timelineRows .= '<tr><td>' . $esc((string) ($row['t'] ?? '')) . '</td>'
                    . '<td>' . $esc((string) ($row['cpu_temp'] ?? '—')) . '</td>'
                    . '<td>' . $esc((string) ($row['gpu_temp'] ?? '—')) . '</td></tr>';
            }
            $certHtml = '<section class="cert"><h2>Stress certificate</h2>'
                . '<p class="verdict">' . $esc((string) ($cert['verdict'] ?? '')) . '</p>'
                . '<p>' . $esc((string) ($cert['summary'] ?? '')) . '</p>';
            if ($timelineRows !== '') {
                $certHtml .= '<h3>Thermal timeline</h3><table><thead><tr><th>t</th><th>CPU</th><th>GPU</th></tr></thead><tbody>'
                    . $timelineRows . '</tbody></table>';
            }
            $certHtml .= '</section>';
        }

        $cardsHtml = '';
        $cards = is_array($doc['advisor_cards'] ?? null) ? $doc['advisor_cards'] : [];
        if ($cards !== []) {
            $cardsHtml = '<section><h2>Advisor cards</h2><ul>';
            foreach ($cards as $c) {
                if (!is_array($c)) {
                    continue;
                }
                $cardsHtml .= '<li><strong>' . $esc((string) ($c['title'] ?? '')) . '</strong> — '
                    . $esc((string) ($c['body'] ?? '')) . '</li>';
            }
            $cardsHtml .= '</ul></section>';
        }

        $hwHtml = '';
        $hw = is_array($doc['hardware_reference'] ?? null) ? $doc['hardware_reference'] : null;
        if ($hw) {
            $hs = (array) ($hw['summary'] ?? []);
            $hwHtml = '<section><h2>Hardware Reference</h2><p class="meta">'
                . $esc((string) ($hs['total'] ?? 0)) . ' devices · '
                . $esc((string) ($hs['hidden'] ?? 0)) . ' hidden · '
                . $esc((string) ($hs['driverless'] ?? 0)) . ' driverless · '
                . $esc((string) ($hs['problem'] ?? 0)) . ' problem'
                . (!empty($hw['elevated']) ? '' : ' · sensors may be degraded (not elevated)')
                . '</p><table><tr><th>Name</th><th>Bus</th><th>Status</th><th>Confidence</th></tr>';
            foreach ((array) ($hw['devices'] ?? []) as $row) {
                if (!is_array($row)) {
                    continue;
                }
                $hwHtml .= '<tr><td>' . $esc((string) ($row['name'] ?? '')) . '</td>'
                    . '<td>' . $esc((string) ($row['bus'] ?? '')) . '</td>'
                    . '<td>' . $esc((string) ($row['status'] ?? '')) . (empty($row['present']) ? ' (hidden)' : '') . '</td>'
                    . '<td>' . $esc((string) ($row['confidence'] ?? '')) . '</td></tr>';
            }
            $hwHtml .= '</table></section>';
        }

        return <<<HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>{$esc($title)}</title>
<style>
  :root { color-scheme: light; }
  body { font-family: "Segoe UI", system-ui, sans-serif; max-width: 820px; margin: 2rem auto; padding: 0 1.25rem; color: #111; line-height: 1.45; }
  h1 { font-size: 1.6rem; margin-bottom: 0.25rem; }
  h2 { font-size: 1.1rem; margin-top: 1.75rem; border-bottom: 1px solid #ddd; padding-bottom: 0.35rem; }
  .meta { color: #555; font-size: 0.9rem; }
  .score { font-size: 2.4rem; font-weight: 700; }
  table { width: 100%; border-collapse: collapse; margin: 0.75rem 0; }
  td, th { text-align: left; padding: 0.4rem 0.5rem; border-bottom: 1px solid #eee; }
  .cert .verdict { font-size: 1.4rem; font-weight: 700; text-transform: uppercase; }
  .actions { margin: 1.5rem 0; display: flex; gap: 0.75rem; flex-wrap: wrap; }
  .actions button, .actions a { padding: 0.55rem 1rem; border-radius: 8px; border: 1px solid #333; background: #111; color: #fff; text-decoration: none; cursor: pointer; font: inherit; }
  @media print { .actions { display: none; } body { margin: 0; } }
</style>
</head>
<body>
  <div class="actions">
    <button type="button" onclick="window.print()">Print / Save as PDF</button>
  </div>
  <h1>PC Lab Kit Report</h1>
  <p class="meta">Generated {$esc($doc['generated_at'] ?? '')}
 · mode {$esc($doc['mode'] ?? '')}
 · token {$esc($doc['token'] ?? '—')}</p>
  <p class="score">{$esc((string) ($doc['health_score'] ?? '—'))} <span style="font-size:1rem">{$esc((string) ($doc['health_grade'] ?? ''))}</span></p>
  <p><strong>CPU</strong> {$esc((string) ($doc['cpu'] ?? '—'))}<br>
     <strong>GPU</strong> {$esc((string) ($doc['gpu'] ?? '—'))}<br>
     <strong>RAM</strong> {$esc((string) ($doc['ram_gb'] ?? '—'))} GB</p>
  <section><h2>Bottleneck</h2><p>{$esc((string) ($bn['message'] ?? $bn['type'] ?? '—'))}</p></section>
  <section><h2>Scores &amp; metrics</h2><table>{$metricRows}</table></section>
  <section><h2>Dataset percentiles</h2><table>{$pctRows}</table></section>
  {$deltaHtml}
  <section><h2>Risks</h2><ul>{$riskHtml}</ul></section>
  {$aiHtml}
  {$cardsHtml}
  {$hwHtml}
  {$certHtml}
  <p class="meta">Local-first · data stays on your machine · print this page to PDF</p>
</body>
</html>
HTML;
    }

    /** @param array<string, mixed> $doc */
    private function renderOcHtml(array $doc, string $title): string
    {
        $esc = static fn ($v) => htmlspecialchars((string) ($v ?? ''), ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        $applied = '';
        foreach ((array) ($doc['applied'] ?? []) as $row) {
            if (!is_array($row)) {
                continue;
            }
            $applied .= '<li>' . $esc(json_encode($row, JSON_UNESCAPED_UNICODE)) . '</li>';
        }
        $samples = '';
        foreach ((array) ($doc['samples'] ?? []) as $s) {
            if (!is_array($s)) {
                continue;
            }
            $samples .= '<tr><td>' . $esc((string) ($s['t'] ?? $s['at'] ?? '')) . '</td>'
                . '<td>' . $esc((string) ($s['cpu_temp'] ?? $s['cpu'] ?? '—')) . '</td>'
                . '<td>' . $esc((string) ($s['gpu_temp'] ?? $s['gpu'] ?? '—')) . '</td></tr>';
        }

        return <<<HTML
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><title>{$esc($title)}</title>
<style>
body{font-family:Segoe UI,system-ui,sans-serif;max-width:800px;margin:2rem auto;padding:0 1rem}
.actions button{padding:.55rem 1rem;border-radius:8px;border:0;background:#111;color:#fff;cursor:pointer}
@media print{.actions{display:none}}
table{width:100%;border-collapse:collapse} td,th{border-bottom:1px solid #eee;padding:.35rem;text-align:left}
</style></head><body>
<div class="actions"><button type="button" onclick="window.print()">Print / Save as PDF</button></div>
<h1>PC Lab Kit OC Safety Report</h1>
<p>Profile: <strong>{$esc((string) ($doc['profile'] ?? ''))}</strong> · Safety {$esc((string) ($doc['safety_score'] ?? ''))}
 · {$esc($doc['generated_at'] ?? '')}</p>
<p>{$esc((string) ($doc['disclaimer'] ?? ''))}</p>
<h2>Applied</h2><ul>{$applied}</ul>
<h2>Thermal samples</h2>
<table><thead><tr><th>Time</th><th>CPU °C</th><th>GPU °C</th></tr></thead><tbody>{$samples}</tbody></table>
<p>Rolled back: {$esc($doc['rolled_back'] ? 'yes' : 'no')}</p>
</body></html>
HTML;
    }
}
