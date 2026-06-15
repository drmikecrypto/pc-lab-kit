<?php

declare(strict_types=1);

namespace App\Services;

/**
 * Optional BYOK AI advisor — expert hardware analysis when API key is set.
 */
class DiagnosticAiService
{
    private const SYSTEM_PROMPT = <<<'PROMPT'
You are PCVerse Lead Hardware Engineer — 20+ years diagnosing gaming PCs, workstations, and thermals.

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
        $comparisonBlock = $comparison
            ? "Comparison vs previous test:\n" . json_encode($this->compactComparison($comparison), JSON_UNESCAPED_UNICODE) . "\n\n"
            : '';

        $payload = $this->buildAnalysisPayload($analysis);
        $userPrompt = implode("\n\n", array_filter([
            $previousBlock,
            $comparisonBlock,
            $benchCtx,
            'Current diagnostic payload (use these facts only):',
            json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT),
        ]));

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

        $oc = (array) ($analysis['vakhsh_oc'] ?? []);
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
            'vakhsh_oc' => $ocSummary,
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
}
