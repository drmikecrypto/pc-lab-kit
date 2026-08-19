<?php

declare(strict_types=1);

namespace App\Controllers;

use App\Actions\TrackUserEventAction;
use App\Services\DiagnosticAgentService;
use App\Services\DiagnosticAiService;
use App\Services\DiagnosticConsultantService;
use App\Services\DiagnosticDriverAdvisorService;
use App\Services\DiagnosticHistoryCompareService;
use App\Services\DiagnosticHistoryService;
use App\Services\DiagnosticImportService;
use App\Services\DiagnosticOcService;
use App\Services\DiagnosticRgbService;
use App\Services\DiagnosticService;
use App\Services\DiagnosticTelemetryService;
use App\Services\DiagnosticToolCatalogService;
use App\Services\HardwareKnowledgeGraphService;
use App\Services\AssemblyCertificateService;
use App\Services\LabReportExportService;
use App\Services\LabSessionService;
use App\Services\LabSuiteService;
use App\Services\SensorDeckService;
use App\Services\SettingsService;
use App\Services\SiliconDossierService;
use App\Services\StabilityOracleService;
use App\Services\StressCertificateService;
use App\Services\TopologyViewService;

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
            'profile' => ($result['oc_plan']['profile'] ?? null),
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
        ], static fn ($v) => $v !== null && $v !== '');
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

            return json_response($out);
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
        if (($input['probe_version'] ?? 0) >= 2 || ($input['agent'] ?? '') === 'pclab-probe') {
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

    public function diagnosticArena(): string
    {
        return json_response((new \App\Services\BenchmarkArenaService())->buildPayload());
    }

    public function diagnosticSiliconAging(): string
    {
        $fp = trim((string) ($_GET['fp'] ?? ''));
        if ($fp === '') {
            $fp = trim((string) ($_COOKIE['pclab_fp'] ?? ''));
        }

        return json_response((new \App\Services\SiliconAgingService())->dashboard($fp !== '' ? substr($fp, 0, 64) : null));
    }

    public function diagnosticHardwareGraph(): string
    {
        $body = decode_json_body_limited(512_000);
        $probe = is_array($body['probe'] ?? null) ? $body['probe'] : [];
        if ($probe === [] && is_array($body['raw'] ?? null)) {
            $probe = $body['raw'];
        }
        $graphSvc = new HardwareKnowledgeGraphService();
        $graph = $graphSvc->fromProbe($probe);

        return json_response([
            'graph' => $graph,
            'compact' => $graphSvc->compact($graph),
            'explore' => (new \App\Services\HardwareGraphExploreService())->buildExploreView($graph),
        ]);
    }

    public function diagnosticTelemetryStream(): void
    {
        $cfg = require dirname(__DIR__, 2) . '/config/diagnostic.php';
        $wa = $cfg['windows_agent'] ?? [];
        $host = trim((string) ($wa['local_host'] ?? '127.0.0.1')) ?: '127.0.0.1';
        $port = max(1, min(65535, (int) ($wa['local_port'] ?? 18765)));
        $url = "http://{$host}:{$port}/telemetry/stream";

        header('Content-Type: text/event-stream');
        header('Cache-Control: no-cache');
        header('Connection: keep-alive');
        header('X-Accel-Buffering: no');

        $ctx = stream_context_create(['http' => ['timeout' => 120]]);
        $fp = @fopen($url, 'r', false, $ctx);
        if ($fp === false) {
            echo "event: error\ndata: {\"message\":\"probe unavailable\"}\n\n";
            if (function_exists('flush')) {
                flush();
            }

            return;
        }
        while (!feof($fp)) {
            $line = fgets($fp);
            if ($line === false) {
                break;
            }
            echo $line;
            if (function_exists('flush')) {
                flush();
            }
        }
        fclose($fp);
    }

    public function diagnosticFleetDiscover(): string
    {
        return json_response(['probes' => (new \App\Services\ShopFleetService())->discover()]);
    }

    public function diagnosticFederatedAggregates(): string
    {
        return json_response((new \App\Services\FederatedBenchmarkService())->localAggregates());
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

    /** Shareable HTML lab report (print → PDF). */
    public function diagnosticReportExport(string $token): string
    {
        $fp = $this->diagnosticFingerprint([]);
        $row = (new DiagnosticHistoryService())->getByToken($token, $fp, null);
        if (!$row) {
            return json_response(['error' => 'Not found'], 404);
        }

        $analysis = is_array($row['report']['analysis'] ?? null) ? $row['report']['analysis'] : [];
        if ($analysis === []) {
            $analysis = [
                'mode' => $row['mode'] ?? 'full',
                'health_score' => $row['health_score'] ?? null,
                'health_grade' => $row['health_grade'] ?? null,
                'metrics' => $row['metrics'] ?? [],
                'bottleneck' => [
                    'type' => $row['bottleneck_type'] ?? null,
                    'message' => $row['bottleneck'] ?? null,
                ],
                'report_summary' => $row['summary'] ?? [],
            ];
        }
        if (!empty($row['comparison'])) {
            $analysis['comparison'] = $row['comparison'];
        }

        $built = (new LabReportExportService())->buildDocument($analysis, [
            'token' => $token,
            'mode' => $row['mode'] ?? ($analysis['mode'] ?? 'full'),
        ]);

        $format = strtolower((string) ($_GET['format'] ?? 'html'));
        if ($format === 'json') {
            return json_response([
                'title' => $built['title'],
                'document' => $built['document'],
                'export_url' => '/api/diagnostic/report/' . rawurlencode($token) . '/export',
                'hint' => 'Open the HTML export and use Print → Save as PDF.',
            ]);
        }

        header('Content-Type: text/html; charset=utf-8');
        header('Content-Disposition: inline; filename="pclab-lab-report-' . preg_replace('/[^a-zA-Z0-9_-]/', '', $token) . '.html"');
        http_response_code(200);

        return $built['html'];
    }

    /** Issue a stress pass/fail certificate from Probe run JSON + optional samples. */
    public function diagnosticStressCertificate(): string
    {
        $input = decode_json_body_limited(2_097_152);
        if ($input === null) {
            return json_response(['error' => 'payload_too_large'], 413);
        }
        $run = (array) ($input['run'] ?? $input);
        $samples = (array) ($input['samples'] ?? []);
        $limits = (array) ($input['limits'] ?? []);

        $cert = (new StressCertificateService())->issue($run, $samples, $limits);

        return json_response(['certificate' => $cert]);
    }

    /** Merge probe silicon dossier for Hardware Reference / Open Book Lab. */
    public function diagnosticDossierPresent(): string
    {
        $input = decode_json_body_limited(12_582_912);
        if ($input === null) {
            return json_response(['error' => 'payload_too_large'], 413);
        }

        return json_response(['ok' => true, 'dossier' => (new SiliconDossierService())->present($input)]);
    }

    /** Client-facing Assembly Certificate HTML (print → PDF). */
    public function diagnosticAssemblyCertificate(): string
    {
        $input = decode_json_body_limited(6_291_456);
        if ($input === null) {
            return json_response(['error' => 'payload_too_large'], 413);
        }
        $analysis = (array) ($input['analysis'] ?? $input);
        if ($analysis === []) {
            return json_response(['error' => 'analysis required'], 400);
        }
        $shop = trim((string) ($input['shop_name'] ?? ''));
        if ($shop === '') {
            $shop = (new SettingsService())->shopName();
        }
        $built = (new AssemblyCertificateService())->build($analysis, [
            'shop_name' => $shop,
            'token' => $input['token'] ?? null,
        ]);

        $format = strtolower((string) ($input['format'] ?? $_GET['format'] ?? 'html'));
        if ($format === 'json') {
            return json_response([
                'title' => $built['title'],
                'document' => $built['document'],
                'hint' => 'Open the HTML and use Print → Save as PDF.',
            ]);
        }

        header('Content-Type: text/html; charset=utf-8');
        header('Content-Disposition: inline; filename="pclab-assembly-certificate.html"');
        http_response_code(200);

        return $built['html'];
    }

    /** OC safety report HTML (print → PDF). */
    public function diagnosticOcReportExport(): string
    {
        $input = decode_json_body_limited(2_097_152);
        if ($input === null) {
            return json_response(['error' => 'payload_too_large'], 413);
        }
        $plan = (array) ($input['plan'] ?? []);
        $apply = (array) ($input['apply'] ?? []);
        $samples = (array) ($input['samples'] ?? []);
        if ($plan === []) {
            return json_response(['error' => 'plan required'], 400);
        }

        $built = (new LabReportExportService())->buildOcReport($plan, $apply, $samples, [
            'preflight' => $input['preflight'] ?? null,
            'watch' => $input['watch'] ?? null,
            'rolled_back' => $input['rolled_back'] ?? false,
        ]);

        $format = strtolower((string) ($input['format'] ?? $_GET['format'] ?? 'html'));
        if ($format === 'json') {
            return json_response(['title' => $built['title'], 'document' => $built['document']]);
        }

        header('Content-Type: text/html; charset=utf-8');
        http_response_code(200);

        return $built['html'];
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

    public function diagnosticDriversPresent(): string
    {
        $input = decode_json_body_limited(6_291_456);
        if ($input === null) {
            return json_response(['error' => 'payload_too_large'], 413);
        }
        if ($input === []) {
            return json_response(['error' => 'Empty probe payload'], 400);
        }

        return json_response((new DiagnosticDriverAdvisorService())->present($input));
    }

    public function diagnosticInventoryPresent(): string
    {
        $input = decode_json_body_limited(12_582_912);
        if ($input === null) {
            return json_response(['error' => 'payload_too_large'], 413);
        }
        if ($input === []) {
            return json_response(['error' => 'Empty inventory payload'], 400);
        }

        return json_response((new DiagnosticInventoryService())->present($input));
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
        $report = ($input['probe_version'] ?? 0) >= 2 || ($input['agent'] ?? '') === 'pclab-probe'
            ? $agent->normalize($input)
            : $input;

        if (!empty($input['import_format']) && !empty($input['import_content'])) {
            $report['import_format'] = $input['import_format'];
            $report['import_content'] = $input['import_content'];
        }

        $analysis = $svc->analyzeFull($report);

        return json_response([
            'oc_plan' => $analysis['oc_plan'] ?? (new DiagnosticOcService())->buildPlan($report, $analysis),
        ]);
    }

    public function diagnosticRgbCatalog(): string
    {
        return json_response((new DiagnosticRgbService())->catalog());
    }

    public function diagnosticOrchestrate(): string
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
            'event_type' => 'orchestrate',
            'target_type' => 'rgb_lab',
            'metadata' => array_filter([
                'device_count' => $ctx['device_count'] ?? count($tel['rgb']['devices'] ?? []),
                'profile' => ($result['plan']['profile'] ?? null),
            ]),
        ]);

        return json_response($result);
    }

    public function diagnosticOrchestrateNarrate(): string
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

    public function diagnosticSuiteProfiles(): string
    {
        $svc = new LabSuiteService();

        return json_response([
            'ok' => true,
            'profiles' => array_values($svc->profiles()),
        ]);
    }

    public function diagnosticSuiteStart(): string
    {
        $input = decode_json_body_limited(65536) ?? [];
        $input['fp'] = $this->diagnosticFingerprint($input);
        $job = (new LabSuiteService())->start($input);
        (new TrackUserEventAction())([
            'fingerprint' => $input['fp'],
            'event_type' => 'diagnostic_suite_start',
            'target_type' => 'suite',
            'target_id' => (string) ($job['id'] ?? ''),
            'metadata' => ['profile' => $job['profile'] ?? 'standard'],
        ]);

        return json_response(['ok' => true, 'job' => $job]);
    }

    public function diagnosticSuiteStatus(string $id = ''): string
    {
        if ($id === '') {
            $id = (string) ($_GET['id'] ?? '');
        }
        $job = (new LabSuiteService())->status($id);
        if ($job === null) {
            return json_response(['ok' => false, 'error' => 'not_found'], 404);
        }

        return json_response(['ok' => true, 'job' => $job]);
    }

    public function diagnosticSuiteCancel(string $id = ''): string
    {
        $input = decode_json_body_limited(65536) ?? [];
        if ($id === '') {
            $id = (string) ($input['id'] ?? $_GET['id'] ?? '');
        }
        $job = (new LabSuiteService())->cancel($id);
        if ($job === null) {
            return json_response(['ok' => false, 'error' => 'not_found'], 404);
        }

        return json_response(['ok' => true, 'job' => $job]);
    }

    public function diagnosticSuitePatch(string $id = ''): string
    {
        $input = decode_json_body_limited(524288) ?? [];
        if ($id === '') {
            $id = (string) ($input['id'] ?? '');
        }
        $job = (new LabSuiteService())->patch($id, $input);
        if ($job === null) {
            return json_response(['ok' => false, 'error' => 'not_found'], 404);
        }

        return json_response(['ok' => true, 'job' => $job]);
    }

    public function diagnosticSuiteFinalize(string $id = ''): string
    {
        set_time_limit(180);
        $input = decode_json_body_limited(12_582_912);
        if ($input === null) {
            return json_response(['ok' => false, 'message' => 'Suite payload too large.'], 413);
        }
        if ($id === '') {
            $id = (string) ($input['id'] ?? '');
        }
        if ($id === '') {
            return json_response(['ok' => false, 'error' => 'id required'], 400);
        }
        try {
            $job = (new LabSuiteService())->finalize($id, $input);
        } catch (\InvalidArgumentException $e) {
            return json_response(['ok' => false, 'error' => $e->getMessage()], 404);
        } catch (\Throwable $e) {
            error_log('suite finalize: ' . $e->getMessage());

            return json_response(['ok' => false, 'error' => 'finalize_failed', 'message' => $e->getMessage()], 500);
        }

        $fp = $this->diagnosticFingerprint($input);
        (new TrackUserEventAction())([
            'fingerprint' => $fp,
            'event_type' => 'diagnostic_suite_complete',
            'target_type' => 'suite',
            'target_id' => $id,
            'metadata' => [
                'profile' => $job['profile'] ?? null,
                'health_score' => $job['result']['analysis']['health_score'] ?? null,
            ],
        ]);

        return json_response(['ok' => true, 'job' => $job]);
    }

    public function diagnosticSensorDeckGet(): string
    {
        return json_response(['ok' => true, 'layout' => (new SensorDeckService())->get()]);
    }

    public function diagnosticSensorDeckSave(): string
    {
        $input = decode_json_body_limited(131072) ?? [];
        try {
            $layout = (new SensorDeckService())->save($input);
        } catch (\InvalidArgumentException $e) {
            return json_response(['ok' => false, 'error' => $e->getMessage()], 400);
        }

        return json_response(['ok' => true, 'layout' => $layout]);
    }

    public function diagnosticSensorDeckExport(): string
    {
        $format = strtolower(trim((string) ($_GET['format'] ?? 'json')));
        $svc = new SensorDeckService();
        $export = $svc->export($format);

        if ($format === 'rainmeter') {
            header('Content-Type: text/plain; charset=utf-8');
            header('Content-Disposition: attachment; filename="PCLabKit-SensorDeck.ini"');

            return (string) ($export['content'] ?? '');
        }

        return json_response(['ok' => true, 'export' => $export]);
    }

    public function diagnosticTopology(): string
    {
        $input = decode_json_body_limited(12_582_912) ?? [];
        $graph = is_array($input['hardware_graph'] ?? null) ? $input['hardware_graph'] : null;
        if ($graph === null) {
            $probe = is_array($input['probe'] ?? null) ? (array) $input['probe'] : $input;
            if (($probe['devices'] ?? null) || ($probe['cpu'] ?? null) || ($probe['probe_version'] ?? null)) {
                $normalized = (new DiagnosticAgentService())->normalize($probe);
                // Prefer lightweight graph for always-on topology; full analyze when asked.
                if (!empty($input['analyze'])) {
                    $analysis = (new DiagnosticService())->analyzeFull($normalized);
                    $graph = (new HardwareKnowledgeGraphService())->fromProbe($normalized, $analysis);
                } else {
                    $graph = (new HardwareKnowledgeGraphService())->fromProbe($normalized, []);
                }
            }
        }
        if ($graph === null) {
            return json_response(['ok' => false, 'error' => 'graph_or_probe required'], 400);
        }

        return json_response([
            'ok' => true,
            'topology' => (new TopologyViewService())->fromGraph($graph),
            'topology_3d' => (new TopologyViewService())->fromGraph3d($graph),
            'graph' => $graph,
        ]);
    }

    public function diagnosticSessionExport(): string
    {
        $input = decode_json_body_limited(12_582_912) ?? [];
        $analysis = is_array($input['analysis'] ?? null) ? $input['analysis'] : $input;
        if ($analysis === []) {
            return json_response(['ok' => false, 'error' => 'analysis required'], 400);
        }
        $fp = $this->diagnosticFingerprint($input);
        $exported = (new LabSessionService())->export($analysis, [
            'fingerprint' => $fp,
            'profile' => (string) ($input['profile'] ?? 'standard'),
        ]);

        return json_response(['ok' => true, 'export' => $exported]);
    }

    public function diagnosticSessionImport(): string
    {
        $input = decode_json_body_limited(12_582_912) ?? [];
        $json = (string) ($input['json'] ?? $input['session'] ?? '');
        if ($json === '' && isset($input['format'])) {
            $json = json_encode($input, JSON_THROW_ON_ERROR);
        }
        if ($json === '') {
            return json_response(['ok' => false, 'error' => 'session json required'], 400);
        }
        try {
            $session = (new LabSessionService())->import($json);
        } catch (\InvalidArgumentException $e) {
            return json_response(['ok' => false, 'error' => $e->getMessage()], 400);
        }
        $drift = null;
        if (!empty($input['current_analysis']) && is_array($input['current_analysis'])) {
            $drift = (new LabSessionService())->driftScore($session, $input['current_analysis']);
        }

        return json_response(['ok' => true, 'session' => $session, 'drift' => $drift]);
    }

    public function diagnosticSessionVerify(): string
    {
        $hash = trim((string) ($_GET['hash'] ?? ''));
        if ($hash === '') {
            $input = decode_json_body_limited(65536) ?? [];
            $hash = trim((string) ($input['hash'] ?? ''));
        }
        if ($hash === '') {
            return json_response(['ok' => false, 'error' => 'hash required'], 400);
        }
        $hash = preg_replace('/^pclab:\/\/verify\//', '', $hash) ?? $hash;

        return json_response([
            'ok' => true,
            'verified' => (new LabSessionService())->verifyHash($hash),
            'hash' => $hash,
        ]);
    }

    public function diagnosticStabilityOracleProfiles(): string
    {
        return json_response(['ok' => true, 'profiles' => array_values((new StabilityOracleService())->profiles())]);
    }

    public function diagnosticStabilityOracleInterpret(): string
    {
        $input = decode_json_body_limited(4_194_304) ?? [];
        $run = is_array($input['run'] ?? null) ? $input['run'] : $input;
        if ($run === []) {
            return json_response(['ok' => false, 'error' => 'run required'], 400);
        }
        $svc = new StabilityOracleService();
        $cert = (new StressCertificateService())->issue($run, is_array($input['samples'] ?? null) ? $input['samples'] : []);

        return json_response([
            'ok' => true,
            'interpretation' => $svc->interpret($run),
            'certificate' => $svc->enrichCertificate($cert, $run),
        ]);
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
        $analysis['advisor_cards'] = (new DiagnosticAiService())->advisorCards($analysis);
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
        $c = trim((string) ($_COOKIE['pclab_fp'] ?? ''));
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
