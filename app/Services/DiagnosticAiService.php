<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Optional BYOK AI advisor — expert hardware analysis when API key is set.
 */
class DiagnosticAiService
{
    private const SYSTEM_PROMPT = <<<'PROMPT'
You are PC Lab Kit Lead Hardware Engineer — 20+ years diagnosing gaming PCs, workstations, and thermals.

Write ONLY valid JSON (English). Be specific: cite numbers from the data (temps, scores, frametime, RAM GB). No generic fluff.

Required keys:
- headline (string, max 90 chars — the single most important finding)
- summary (string, 3-5 sentences — diagnosis + what to do first)
- changes_since_last (string — compare to previous test if provided; else "First saved test — no prior run to compare.")
- priority_actions (array of 3 strings — ordered steps the user should take today)
- upgrade_plan (array of exactly 3 objects: {priority: 1|2|3, component: string, recommendation: string, rationale: string})
- burn_risk (array of 2 strings — thermal/stability/PSU risks if any; say "None critical" if clean)
- swap_pairs (array of up to 3 objects: {from: string, to: string, reason: string} — only if a swap makes sense)

Rules:
- Tie every recommendation to bottleneck, metrics, or comparison deltas.
- For lite/quiz-only scans, say what Probe/full scan would confirm.
- Never mention stores, prices, affiliate links, or that you are an AI.
- Never invent sensor values not present in the input.
PROMPT;

    public function __construct(
        private ?LlmService $llm = null,
        private ?DiagnosticService $diagnostic = null,
    ) {
        $this->llm = $llm ?? new LlmService();
        $this->diagnostic = $diagnostic ?? new DiagnosticService();
    }

    /** @param array<string, mixed> $analysis @param array<string, mixed> $context */
    public function enrich(array $analysis, array $context = []): array
    {
        $analysis['ai_available'] = $this->llm->isConfigured();
        $previousBlock = $this->buildPreviousTestsBlock($context);

        if (!$this->llm->isConfigured()) {
            $analysis['ai_narrative'] = $this->fallbackNarrative($analysis);
            $analysis['ai_hint'] = 'Open Settings (header or AI advisor button) and paste your API key for expert analysis.';
            if ($previousBlock !== '') {
                $analysis['ai_hint'] .= ' Retest comparison is ready once AI is enabled.';
            }

            return $analysis;
        }

        $benchCtx = '';
        $metrics = (array) ($analysis['metrics'] ?? []);
        if ($metrics !== []) {
            $benchCtx = (new BenchmarkDatasetService())->buildAiContext(
                [
                    ['category_slug' => 'cpu', 'model' => $metrics['cpu_model'] ?? '', 'name' => $metrics['cpu_model'] ?? ''],
                    ['category_slug' => 'gpu', 'model' => $metrics['gpu_model'] ?? '', 'name' => $metrics['gpu_model'] ?? ''],
                ],
                $analysis
            );
        }

        $comparison = is_array($context['comparison'] ?? null) ? $context['comparison'] : null;
        $toon = new ToonSerializer();
        $graphSvc = new HardwareKnowledgeGraphService();

        $graph = is_array($analysis['hardware_graph'] ?? null)
            ? $analysis['hardware_graph']
            : $graphSvc->fromProbe(
                [
                    'cpu' => ['model' => $metrics['cpu_model'] ?? ''],
                    'gpu' => ['model' => $metrics['gpu_model'] ?? '', 'vram_gb' => $metrics['vram_gb'] ?? null],
                    'ram' => ['total_gb' => $metrics['ram_gb'] ?? null],
                    'sensors' => [
                        'cpu_temp_max' => $metrics['cpu_temp_max'] ?? null,
                        'gpu_temp_max' => $metrics['gpu_temp_max'] ?? null,
                    ],
                    'report_summary' => $analysis['report_summary'] ?? [],
                ],
                $analysis
            );
        $analysis['hardware_graph'] = $graph;

        $payload = $this->buildAnalysisPayload($analysis);
        $payload['percentiles'] = $analysis['percentiles'] ?? [];
        $compactCtx = [
            'previous' => $previousBlock !== '' ? $previousBlock : null,
            'comparison' => $comparison ? $this->compactComparison($comparison) : null,
            'benchmark_notes' => $benchCtx !== '' ? $benchCtx : null,
            'hw_graph' => $graphSvc->compact($graph),
            'diagnostic' => $payload,
        ];
        $userPrompt = "PC Lab Kit TOON context (facts only — do not invent sensors):\n"
            . $toon->encode(array_filter($compactCtx, static fn ($v) => $v !== null && $v !== '' && $v !== []));

        $json = $this->llm->generateJson(self::SYSTEM_PROMPT, $userPrompt, 2200, 0.35);

        if (is_array($json)) {
            $analysis['ai'] = $this->normalizeAiResponse($json);
            $headline = (string) ($analysis['ai']['headline'] ?? '');
            $summary = (string) ($analysis['ai']['summary'] ?? '');
            $analysis['ai_narrative'] = $headline !== '' ? $headline . ' — ' . $summary : $summary;
            if (!empty($analysis['ai']['changes_since_last'])) {
                $analysis['ai_changes_since_last'] = (string) $analysis['ai']['changes_since_last'];
            }

            return $analysis;
        }

        $err = $this->llm->lastError();
        $analysis['ai_error'] = $err !== ''
            ? 'AI analysis failed: ' . $err . ' Check Settings (API key, base URL, model).'
            : 'AI analysis failed. Check your API key and model in Settings.';
        $analysis['ai_narrative'] = $this->fallbackNarrative($analysis);
        $analysis['ai_hint'] = $analysis['ai_error'];

        return $analysis;
    }

    /** @param array<string, mixed> $analysis @return array<string, mixed> */
    private function buildAnalysisPayload(array $analysis): array
    {
        $metrics = (array) ($analysis['metrics'] ?? []);
        $keyMetrics = array_filter([
            'cpu_model' => $metrics['cpu_model'] ?? null,
            'gpu_model' => $metrics['gpu_model'] ?? null,
            'cpu_score' => $metrics['cpu_score'] ?? null,
            'gpu_score' => $metrics['gpu_score'] ?? null,
            'ram_gb' => $metrics['ram_gb'] ?? null,
            'vram_gb' => $metrics['vram_gb'] ?? null,
            'cpu_temp_max' => $metrics['cpu_temp_max'] ?? null,
            'gpu_temp_max' => $metrics['gpu_temp_max'] ?? null,
            'gpu_hotspot_max' => $metrics['gpu_hotspot_max'] ?? null,
            'gpu_util_avg' => $metrics['gpu_util_avg'] ?? null,
            'frametime_p99_ms' => $metrics['frametime_p99_ms'] ?? null,
            'battery_health_pct' => $metrics['battery_health_pct'] ?? null,
            'throttle_detected' => $metrics['throttle_detected'] ?? null,
            'storage_type' => $metrics['storage_type'] ?? null,
        ], static fn ($v) => $v !== null && $v !== '');

        $risks = array_slice((array) ($analysis['risks'] ?? []), 0, 6);
        $issues = array_slice((array) ($analysis['issues'] ?? []), 0, 6);
        $upgrades = array_slice((array) ($analysis['upgrade_suggestions'] ?? []), 0, 4);
        $games = array_slice((array) ($analysis['game_settings'] ?? []), 0, 5);

        $oc = (array) ($analysis['oc_plan'] ?? []);
        $ocSummary = $oc !== [] ? [
            'profile' => $oc['profile'] ?? null,
            'safe' => $oc['safe'] ?? null,
            'headline' => $oc['headline'] ?? $oc['headline_fa'] ?? null,
        ] : null;

        return [
            'mode' => $analysis['mode'] ?? 'lite',
            'health_score' => $analysis['health_score'] ?? null,
            'health_grade' => $analysis['health_grade'] ?? null,
            'bottleneck' => $analysis['bottleneck'] ?? null,
            'needs_full_scan' => $analysis['needs_full_scan'] ?? false,
            'full_scan_reason' => $analysis['full_scan_reason'] ?? null,
            'metrics' => $keyMetrics,
            'risks' => $risks,
            'issues' => $issues,
            'rule_based_upgrades' => $upgrades,
            'game_settings_sample' => $games,
            'oc_plan' => $ocSummary,
            'report_summary' => $analysis['report_summary'] ?? null,
        ];
    }

    /** @param array<string, mixed> $comparison @return array<string, mixed> */
    private function compactComparison(array $comparison): array
    {
        return [
            'score_delta' => ($comparison['delta']['health_score'] ?? null),
            'grade_before' => $comparison['previous']['grade'] ?? null,
            'grade_after' => $comparison['current']['grade'] ?? null,
            'bottleneck_shift' => [
                'from' => $comparison['previous']['bottleneck_type'] ?? null,
                'to' => $comparison['current']['bottleneck_type'] ?? null,
            ],
            'summary' => $comparison['summary'] ?? '',
            'metrics_changed' => array_slice((array) ($comparison['metrics'] ?? []), 0, 8),
        ];
    }

    /** @param array<string, mixed> $json @return array<string, mixed> */
    private function normalizeAiResponse(array $json): array
    {
        $plan = [];
        foreach ((array) ($json['upgrade_plan'] ?? []) as $i => $row) {
            if (is_string($row)) {
                $plan[] = ['priority' => $i + 1, 'component' => 'Upgrade', 'recommendation' => $row, 'rationale' => ''];
                continue;
            }
            if (is_array($row)) {
                $plan[] = [
                    'priority' => (int) ($row['priority'] ?? $i + 1),
                    'component' => (string) ($row['component'] ?? 'Upgrade'),
                    'recommendation' => (string) ($row['recommendation'] ?? $row['suggestion'] ?? ''),
                    'rationale' => (string) ($row['rationale'] ?? $row['why'] ?? ''),
                ];
            }
        }
        $json['upgrade_plan'] = $plan;
        $json['priority_actions'] = array_values(array_filter((array) ($json['priority_actions'] ?? [])));

        return $json;
    }

    /** @param array<string, mixed> $context */
    private function buildPreviousTestsBlock(array $context): string
    {
        $previous = $context['previous_snapshot'] ?? null;
        if (!is_array($previous)) {
            return '';
        }

        $bn = $previous['bottleneck']['type'] ?? $previous['bottleneck_type'] ?? 'unknown';

        return 'Previous saved test (' . ($previous['ago'] ?? '') . '): score '
            . ($previous['health_score'] ?? 0) . ', grade ' . ($previous['health_grade'] ?? '')
            . ', mode ' . ($previous['mode'] ?? '') . ", bottleneck {$bn}. Metrics: "
            . json_encode($previous['metrics'] ?? [], JSON_UNESCAPED_UNICODE);
    }

    private function fallbackNarrative(array $analysis): string
    {
        $bn = $analysis['bottleneck']['message'] ?? $analysis['bottleneck']['message_fa'] ?? 'Run a full Probe scan for sensor-level detail.';
        $grade = $analysis['health_grade'] ?? '?';

        return "Health grade {$grade}. {$bn}";
    }

    /**
     * Schema-validated advisor cards (3–5) from AI payload or rule fallback.
     *
     * @param array<string, mixed> $analysis
     * @return list<array{id: string, title: string, body: string, severity: string, source: string}>
     */
    public function advisorCards(array $analysis): array
    {
        $cards = [];
        $ai = is_array($analysis['ai'] ?? null) ? $analysis['ai'] : null;

        if ($ai !== null) {
            $headline = trim((string) ($ai['headline'] ?? ''));
            $summary = trim((string) ($ai['summary'] ?? ''));
            if ($headline !== '' || $summary !== '') {
                $cards[] = $this->card('finding', $headline !== '' ? $headline : 'Primary finding', $summary !== '' ? $summary : $headline, 'info', 'ai');
            }
            foreach (array_slice((array) ($ai['priority_actions'] ?? []), 0, 3) as $i => $action) {
                $text = is_string($action) ? $action : (string) ($action['text'] ?? '');
                if ($text === '') {
                    continue;
                }
                $cards[] = $this->card('action_' . ($i + 1), 'Action ' . ($i + 1), $text, 'action', 'ai');
            }
            foreach (array_slice((array) ($ai['burn_risk'] ?? []), 0, 2) as $i => $risk) {
                $text = is_string($risk) ? $risk : (string) ($risk['text'] ?? '');
                if ($text === '' || stripos($text, 'none critical') !== false) {
                    continue;
                }
                $cards[] = $this->card('risk_' . ($i + 1), 'Risk', $text, 'warn', 'ai');
            }
        }

        if ($cards === []) {
            $grade = (string) ($analysis['health_grade'] ?? '?');
            $score = $analysis['health_score'] ?? '—';
            $bn = is_array($analysis['bottleneck'] ?? null)
                ? (string) ($analysis['bottleneck']['message'] ?? $analysis['bottleneck']['type'] ?? 'Unknown bottleneck')
                : 'Run Full Lab for bottleneck detail';
            $cards[] = $this->card('health', "Health {$grade} ({$score})", $bn, 'info', 'rules');

            $cert = is_array($analysis['stress_certificate'] ?? null) ? $analysis['stress_certificate'] : null;
            if ($cert !== null) {
                $cards[] = $this->card(
                    'stress',
                    'Stress ' . ($cert['verdict'] ?? '—'),
                    (string) ($cert['summary'] ?? ''),
                    !empty($cert['passed']) ? 'ok' : 'warn',
                    'rules'
                );
            }

            foreach (array_slice((array) ($analysis['risks'] ?? []), 0, 2) as $i => $risk) {
                $text = is_string($risk) ? $risk : (string) ($risk['message'] ?? $risk['title'] ?? '');
                if ($text === '') {
                    continue;
                }
                $cards[] = $this->card('rule_risk_' . $i, 'Watch item', $text, 'warn', 'rules');
            }

            $graph = is_array($analysis['hardware_graph'] ?? null) ? $analysis['hardware_graph'] : null;
            if ($graph !== null) {
                $summary = is_array($graph['summary'] ?? null) ? $graph['summary'] : [];
                $edgeHint = (string) ($summary['primary_bottleneck'] ?? $summary['bottleneck'] ?? '');
                if ($edgeHint !== '') {
                    $cards[] = $this->card('graph', 'Graph bottleneck', $edgeHint, 'info', 'graph');
                } else {
                    $nodeCount = is_array($graph['nodes'] ?? null) ? count($graph['nodes']) : 0;
                    $edgeCount = is_array($graph['edges'] ?? null) ? count($graph['edges']) : 0;
                    $cards[] = $this->card('graph', 'Hardware graph', "{$nodeCount} nodes · {$edgeCount} edges captured for this run.", 'info', 'graph');
                }
            }
        }

        $cards = array_slice($cards, 0, 5);
        foreach ($cards as &$c) {
            $c = $this->validateCard($c);
        }
        unset($c);

        return array_values(array_filter($cards));
    }

    /** @return array{id: string, title: string, body: string, severity: string, source: string} */
    private function card(string $id, string $title, string $body, string $severity, string $source): array
    {
        return [
            'id' => substr($id, 0, 32),
            'title' => substr(trim($title), 0, 90),
            'body' => substr(trim($body), 0, 400),
            'severity' => in_array($severity, ['info', 'action', 'warn', 'ok'], true) ? $severity : 'info',
            'source' => in_array($source, ['ai', 'rules', 'graph'], true) ? $source : 'rules',
        ];
    }

    /** @param array<string, mixed> $card @return array{id: string, title: string, body: string, severity: string, source: string}|null */
    private function validateCard(array $card): ?array
    {
        $id = preg_replace('/[^a-z0-9_\-]/i', '', (string) ($card['id'] ?? '')) ?: null;
        $title = trim((string) ($card['title'] ?? ''));
        $body = trim((string) ($card['body'] ?? ''));
        if ($id === null || $title === '' || $body === '') {
            return null;
        }

        return $this->card($id, $title, $body, (string) ($card['severity'] ?? 'info'), (string) ($card['source'] ?? 'rules'));
    }
}
