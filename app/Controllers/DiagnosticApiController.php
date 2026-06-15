<?php

declare(strict_types=1);

namespace App\Controllers;

use App\Actions\TrackUserEventAction;
use App\Services\DiagnosticAgentService;
use App\Services\DiagnosticAiService;
use App\Services\DiagnosticConsultantService;
use App\Services\DiagnosticHistoryCompareService;
use App\Services\DiagnosticHistoryService;
use App\Services\DiagnosticImportService;
use App\Services\DiagnosticOcService;
use App\Services\DiagnosticRgbService;
use App\Services\DiagnosticService;
use App\Services\DiagnosticTelemetryService;
use App\Services\DiagnosticToolCatalogService;
use App\Services\SettingsService;

class DiagnosticApiController
{
    public function diagnosticGames(): string
    {
        $path = dirname(__DIR__, 2) . '/config/diagnostic_games.json';
        $meta = is_file($path) ? \App\json_decode_assoc((string) file_get_contents($path), '{}') : [];

        $svc = new DiagnosticService();
        $q = trim((string) ($_GET['q'] ?? ''));
        $payload = $svc->searchGames($q, max(1, (int) ($_GET['page'] ?? 1)), min(80, (int) ($_GET['per_page'] ?? 40)));
        $payload['count'] = (int) ($meta['count'] ?? $payload['total']);
        $payload['updated_at'] = $meta['updated_at'] ?? null;
        $payload['sources'] = $meta['sources'] ?? [];
        $payload['version'] = (int) ($meta['version'] ?? 1);

        return json_response($payload);
    }

    public function diagnosticConfig(): string
    {
        $appCfg = require dirname(__DIR__, 2) . '/config/app.php';

        return json_response([
            'config' => (new DiagnosticService())->getConfig(),
            'settings' => (new SettingsService())->publicSettings(),
            'app' => [
                'version' => (string) ($appCfg['version'] ?? '1.0.0'),
                'github' => $appCfg['github'] ?? [],
            ],
        ]);
    }

    /** @param array<string, mixed> $analysis */
    private function enrichDiagnosticConsultant(array $analysis): array
    {
        $analysis['consultant'] = (new DiagnosticConsultantService())->plan($analysis);

        return $analysis;
    }

    /** @return array<string, mixed> */
    private function labMetaFromAnalysis(array $result, array $raw = [], string $mode = ''): array
    {
        $bn = $result['bottleneck'] ?? [];
        $bnArr = is_array($bn) ? $bn : [];
        $metrics = is_array($result['metrics'] ?? null) ? $result['metrics'] : [];
        $gpuScore = isset($metrics['gpu_score']) ? (int) $metrics['gpu_score'] : null;

        return array_filter([
            'mode' => $mode ?: ($raw['mode'] ?? ''),
            'health_grade' => $result['health_grade'] ?? '',
            'health_score' => isset($result['health_score']) ? (int) $result['health_score'] : null,
            'bottleneck' => is_array($bn) ? ($bn['type'] ?? '') : (string) $bn,
            'bottleneck_component' => $bnArr['component'] ?? null,
            'profile' => ($result['vakhsh_oc']['profile'] ?? null),
            'ram_gb' => $metrics['ram_gb'] ?? null,
            'vram_gb' => $metrics['vram_gb'] ?? null,
            'form_factor' => $raw['form_factor'] ?? ($result['form_factor'] ?? ''),
            'consultant_stance' => is_array($result['consultant'] ?? null) ? ($result['consultant']['stance'] ?? null) : null,
            'gpu_temp_max' => $metrics['gpu_temp_max'] ?? null,
            'cpu_temp_max' => $metrics['cpu_temp_max'] ?? null,
            'gpu_score_bucket' => $this->diagnosticGpuScoreBucket($gpuScore),
            'thermal_band' => $this->diagnosticThermalBand(
                isset($metrics['gpu_temp_max']) ? (float) $metrics['gpu_temp_max'] : null,
                isset($metrics['cpu_temp_max']) ? (float) $metrics['cpu_temp_max'] : null,
            ),
            'upgrade_top_category' => $this->diagnosticUpgradeTopCategory($result),
            'catalog_pick_ids' => $this->diagnosticLabCatalogPickIds($result),
        ], static fn ($v) => $v !== null && $v !== '');
    }

    /** @param array<string, mixed> $result @return list<int> */
    private function diagnosticLabCatalogPickIds(array $result): array
    {
        $c = $result['consultant'] ?? null;
        if (!is_array($c)) {
            return [];
        }
        $picks = $c['catalog_picks'] ?? [];
        if (!is_array($picks)) {
            return [];
        }
        $ids = [];
        foreach (array_slice($picks, 0, 8) as $row) {
            if (!is_array($row) || empty($row['part_id'])) {
                continue;
            }
            $ids[] = (int) $row['part_id'];
        }

        return $ids;
    }

    /** @param array<string, mixed> $result */
    private function diagnosticUpgradeTopCategory(array $result): ?string
    {
        $sugs = $result['upgrade_suggestions'] ?? null;
        if (!is_array($sugs) || $sugs === []) {
            return null;
        }
        $first = $sugs[0];
        if (!is_array($first)) {
            return null;
        }
        $cat = (string) ($first['category_slug'] ?? '');

        return $cat !== '' ? $cat : null;
    }

    private function diagnosticGpuScoreBucket(?int $score): string
    {
        if ($score === null || $score <= 0) {
            return 'unknown';
        }
        if ($score < 4000) {
            return 'entry';
        }
        if ($score < 9000) {
            return 'mid';
        }
        if ($score < 15000) {
            return 'upper_mid';
        }
        if ($score < 22000) {
            return 'high';
        }

        return 'enthusiast';
    }

    private function diagnosticThermalBand(?float $gpuT, ?float $cpuT): string
    {
        $g = (float) ($gpuT ?? 0);
        $c = (float) ($cpuT ?? 0);
        if ($g <= 0 && $c <= 0) {
            return 'unknown';
        }
        $max = max($g, $c);
        if ($max >= 95) {
            return 'hot';
        }
        if ($max >= 85) {
            return 'warm';
        }

        return 'cool';
    }

    public function diagnosticLite(): string
    {
        set_time_limit(120);
        $input = decode_json_body_limited(524288);
        if ($input === null) {
            return json_response(['ok' => false, 'message' => 'Request too large. Try again with less data.'], 413);
        }
        try {
            $input['user_agent'] = $_SERVER['HTTP_USER_AGENT'] ?? '';

            $result = (new DiagnosticService())->analyzeLite($input);
            $out = $this->finalizeDiagnostic('lite', $input, $result);

            $fp = $this->diagnosticFingerprint($input);
            (new TrackUserEventAction())([
                'fingerprint' => $fp,
                'event_type' => 'diagnostic_lite',
                'target_type' => 'health',
                'target_id' => (string) ($out['health_score'] ?? 0),
                'metadata' => $this->labMetaFromAnalysis($out, $input, 'lite'),
            ]);

            return json_response(array_merge($out, [
                'skip_app_download_pitch' => strtolower(trim((string) ($_SERVER['HTTP_X_PCVERSE_CLIENT'] ?? ''))) === 'pcverse-flutter',
            ]));
        } catch (\Throwable $e) {
            error_log('diagnosticLite: ' . $e->getMessage());

            return json_response(['ok' => false, 'message' => 'Analysis failed. Please try again.'], 500);
        }
    }

    public function diagnosticFull(): string
    {
        $input = decode_json_body_limited(6_291_456);
        if ($input === null) {
            return json_response(['ok' => false, 'message' => 'Report too large.'], 413);
        }
        if ($input === []) {
            return json_response(['error' => 'Empty report'], 400);
        }

        $payload = $input;
        if (($input['probe_version'] ?? 0) >= 2 || ($input['agent'] ?? '') === 'pcverse-probe') {
            $payload = (new DiagnosticAgentService())->normalize($input);
            $payload = array_merge($payload, [
                'import_format' => $input['import_format'] ?? null,
                'import_content' => $input['import_content'] ?? null,
                'selected_games' => array_slice((array) ($input['selected_games'] ?? []), 0, 20),
            ]);
        }

        $result = (new DiagnosticService())->analyzeFull($payload);
        $out = $this->finalizeDiagnostic('full', $payload, $result);

        $fp = $this->diagnosticFingerprint($payload);
        (new TrackUserEventAction())([
            'fingerprint' => $fp,
            'event_type' => 'diagnostic_full',
            'target_type' => 'health',
            'target_id' => (string) ($out['health_score'] ?? 0),
            'metadata' => $this->labMetaFromAnalysis($out, $payload, 'full'),
        ]);

        return json_response($out);
    }

    public function diagnosticAgent(): string
    {
        $input = decode_json_body_limited(6_291_456);
        if ($input === null) {
            return json_response(['ok' => false, 'message' => 'Report too large.'], 413);
        }
        if ($input === []) {
            return json_response(['error' => 'Empty agent payload'], 400);
        }

        $normalized = (new DiagnosticAgentService())->normalize($input);
        $payload = array_merge($normalized, [
            'selected_games' => array_slice((array) ($input['selected_games'] ?? []), 0, 20),
            'imports' => $input['imports'] ?? [],
            'import_format' => $input['import_format'] ?? null,
            'import_content' => $input['import_content'] ?? null,
            'telemetry' => $input['telemetry'] ?? ($normalized['telemetry'] ?? []),
        ]);

        $result = (new DiagnosticService())->analyzeFull($payload);
        $out = $this->finalizeDiagnostic('agent', $payload, $result);

        $fp = $this->diagnosticFingerprint($payload);
        (new TrackUserEventAction())([
            'fingerprint' => $fp,
            'event_type' => 'diagnostic_agent',
            'target_type' => 'health',
            'target_id' => (string) ($out['health_score'] ?? 0),
            'metadata' => $this->labMetaFromAnalysis($out, $payload, 'agent'),
        ]);

        return json_response($out);
    }

    public function diagnosticImport(): string
    {
        $input = decode_json_body_limited(8_388_608);
        if ($input === null) {
            return json_response(['ok' => false, 'message' => 'Import file too large.'], 413);
        }
        $format = (string) ($input['format'] ?? '');
        $content = (string) ($input['content'] ?? '');
        if ($format === '' || $content === '') {
            return json_response(['error' => 'format and content required'], 400);
        }

        $parsed = (new DiagnosticImportService())->parse($format, $content);
        $base = (array) ($input['report'] ?? []);
        if ($base !== []) {
            $base['import_format'] = $format;
            $base['import_content'] = $content;
            $full = (new DiagnosticService())->analyzeFull($base);
            $analysis = $this->finalizeDiagnostic('agent', $base, $full);

            return json_response([
                'import' => $parsed,
                'analysis' => $analysis,
                'saved' => $analysis['saved'] ?? [],
                'comparison' => $analysis['comparison'] ?? null,
            ]);
        }

        return json_response(['import' => $parsed]);
    }

    public function diagnosticGameSettings(): string
    {
        $input = decode_json_body_limited(2_097_152);
        if ($input === null) {
            return json_response(['error' => 'payload_too_large'], 413);
        }
        $gameIds = array_slice((array) ($input['game_ids'] ?? []), 0, 20);
        $payload = array_merge((array) ($input['report'] ?? $input), ['selected_games' => $gameIds]);
        $full = (new DiagnosticService())->analyzeFull($payload);

        return json_response([
            'game_settings' => $full['game_settings'] ?? [],
            'metrics' => $full['metrics'] ?? [],
        ]);
    }

    public function diagnosticLive(): string
    {
        $fp = $this->diagnosticFingerprint([]);

        return json_response((new DiagnosticHistoryService())->livePayload($fp, null));
    }

    public function diagnosticToolkit(): string
    {
        return json_response((new DiagnosticToolCatalogService())->payload());
    }

    public function diagnosticHistory(): string
    {
        $fp = $this->diagnosticFingerprint([]);
        $limit = min(50, max(1, (int) ($_GET['limit'] ?? 20)));

        return json_response([
            'history' => (new DiagnosticHistoryService())->userHistoryWithDeltas($fp, null, $limit),
        ]);
    }

    public function diagnosticReport(string $token): string
    {
        $fp = $this->diagnosticFingerprint([]);
        $report = (new DiagnosticHistoryService())->getByToken($token, $fp, null);
        if (!$report) {
            return json_response(['error' => 'Not found'], 404);
        }

        return json_response(['report' => $report]);
    }

    public function diagnosticTelemetryPresent(): string
    {
        $input = decode_json_body_limited(6_291_456);
        if ($input === null) {
            return json_response(['error' => 'payload_too_large'], 413);
        }
        if ($input === []) {
            return json_response(['error' => 'Empty probe payload'], 400);
        }

        return json_response((new DiagnosticTelemetryService())->present($input));
    }

    public function diagnosticOcPlan(): string
    {
        $input = decode_json_body_limited(6_291_456);
        if ($input === null) {
            return json_response(['error' => 'payload_too_large'], 413);
        }
        if ($input === []) {
            return json_response(['error' => 'Empty payload'], 400);
        }

        $svc = new DiagnosticService();
        $agent = new DiagnosticAgentService();
        $report = ($input['probe_version'] ?? 0) >= 2 || ($input['agent'] ?? '') === 'pcverse-probe'
            ? $agent->normalize($input)
            : $input;

        if (!empty($input['import_format']) && !empty($input['import_content'])) {
            $report['import_format'] = $input['import_format'];
            $report['import_content'] = $input['import_content'];
        }

        $analysis = $svc->analyzeFull($report);

        return json_response([
            'vakhsh_oc' => $analysis['vakhsh_oc'] ?? (new DiagnosticOcService())->buildPlan($report, $analysis),
        ]);
    }

    public function diagnosticRgbCatalog(): string
    {
        return json_response((new DiagnosticRgbService())->catalog());
    }

    public function diagnosticVakhshOrchestrate(): string
    {
        $input = decode_json_body_limited(2_097_152);
        if ($input === null) {
            return json_response(['error' => 'payload_too_large'], 413);
        }
        $tel = (array) ($input['telemetry'] ?? []);
        $ctx = (array) ($input['context'] ?? []);

        $result = (new DiagnosticRgbService())->orchestrate($tel, $ctx);

        $fp = $this->diagnosticFingerprint($input);
        (new TrackUserEventAction())([
            'fingerprint' => $fp,
            'event_type' => 'vakhsh_orchestrate',
            'target_type' => 'rgb_lab',
            'metadata' => array_filter([
                'device_count' => $ctx['device_count'] ?? count($tel['rgb']['devices'] ?? []),
                'profile' => ($result['plan']['profile'] ?? null),
            ]),
        ]);

        return json_response($result);
    }

    public function diagnosticVakhshNarrate(): string
    {
        $input = decode_json_body_limited(262144);
        if ($input === null) {
            return json_response(['error' => 'payload_too_large'], 413);
        }
        $plan = (array) ($input['plan'] ?? []);
        $apply = (array) ($input['apply'] ?? []);

        if ($plan === []) {
            return json_response(['error' => 'plan required'], 400);
        }

        return json_response([
            'narrative' => (new DiagnosticRgbService())->narrateApply($plan, $apply),
        ]);
    }

    public function trackEvent(): string
    {
        $input = decode_json_body_limited(20000);
        if ($input === null) {
            return json_response(['success' => false], 413);
        }
        if ($input === []) {
            return json_response(['success' => false]);
        }

        $ok = (new TrackUserEventAction())($input);

        return json_response(['success' => $ok]);
    }

    /** @param array<string, mixed> $raw @param array<string, mixed> $analysis @return array<string, mixed> */
    private function finalizeDiagnostic(string $mode, array $raw, array $analysis): array
    {
        $history = new DiagnosticHistoryService();
        $fp = $this->diagnosticFingerprint($raw);
        $previous = $history->latestSnapshot($fp);
        $comparison = $previous
            ? (new DiagnosticHistoryCompareService())->compare($analysis, $previous)
            : null;

        $analysis = (new DiagnosticAiService())->enrich($analysis, [
            'previous_snapshot' => $previous,
            'comparison' => $comparison,
        ]);
        $analysis = $this->enrichDiagnosticConsultant($analysis);
        if ($comparison !== null) {
            $analysis['comparison'] = $comparison;
        }

        $saved = $this->persistDiagnostic($mode, $analysis, $raw);

        return array_merge($analysis, ['saved' => $saved]);
    }

    /** @param array<string, mixed> $analysis @param array<string, mixed> $raw */
    private function persistDiagnostic(string $mode, array $analysis, array $raw): array
    {
        try {
            $fp = $this->diagnosticFingerprint($raw);

            return (new DiagnosticHistoryService())->save($fp, null, $mode, $analysis, $raw);
        } catch (\Throwable $e) {
            error_log('diagnostic save: ' . $e->getMessage());

            return ['saved' => false];
        }
    }

    /** @param array<string, mixed> $input */
    private function diagnosticFingerprint(array $input): string
    {
        $q = trim((string) ($_GET['fp'] ?? ''));
        if ($q !== '') {
            return substr($q, 0, 64);
        }
        $body = trim((string) ($input['fp'] ?? $input['fingerprint'] ?? ''));
        if ($body !== '') {
            return substr($body, 0, 64);
        }
        $c = trim((string) ($_COOKIE['_pcverse_fp'] ?? ''));
        if ($c !== '') {
            return substr($c, 0, 64);
        }
        $s = trim((string) ($_SESSION['fingerprint'] ?? ''));
        if ($s !== '') {
            return substr($s, 0, 64);
        }

        return 'unknown';
    }
}
