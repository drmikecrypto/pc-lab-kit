<?php

declare(strict_types=1);

use App\Database;
use App\Services\DiagnosticHistoryService;

function diagnostic_reports_ensure_sqlite_table(): void
{
    $pdo = Database::connection();
    if (Database::usesMysqlDialect()) {
        return;
    }
    $pdo->exec(
        'CREATE TABLE IF NOT EXISTS diagnostic_reports (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            fingerprint TEXT NOT NULL,
            user_id INTEGER,
            mode TEXT NOT NULL DEFAULT \'lite\',
            health_score INTEGER DEFAULT 0,
            health_grade TEXT DEFAULT \'C\',
            bottleneck_type TEXT,
            bottleneck_fa TEXT,
            cpu_model TEXT,
            gpu_model TEXT,
            ram_gb INTEGER DEFAULT 0,
            form_factor TEXT DEFAULT \'desktop\',
            metrics_json TEXT,
            summary_json TEXT,
            report_json TEXT,
            report_token TEXT NOT NULL,
            is_public INTEGER DEFAULT 1,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        )'
    );
}

function diagnostic_reports_cleanup_test_rows(): void
{
    try {
        $pdo = Database::connection();
        $pdo->exec("DELETE FROM diagnostic_reports WHERE fingerprint LIKE 'pest-diag-%'");
    } catch (\Throwable) {
    }
}

beforeEach(function () {
    diagnostic_reports_ensure_sqlite_table();
});

afterEach(function () {
    diagnostic_reports_cleanup_test_rows();
});

it('save persists row and returns id token and public label', function () {
    $svc = new DiagnosticHistoryService();
    $analysis = [
        'health_score' => 82,
        'health_grade' => 'B',
        'report_summary' => ['cpu' => 'R7', 'gpu' => 'RTX 4060', 'ram_gb' => 32, 'is_laptop' => false],
        'metrics' => ['ram_gb' => 32, 'gpu_temp_max' => 72],
        'bottleneck' => ['type' => 'gpu', 'message' => 'GPU limit'],
    ];
    $out = $svc->save('pest-diag-fp-1', null, 'lite', $analysis, ['cpu' => ['model' => 'R7']]);
    expect($out)->toHaveKeys(['id', 'token', 'public_label']);
    expect($out['id'])->toBeInt()->toBeGreaterThan(0);
    expect(strlen($out['token']))->toBeGreaterThan(4);
});

it('getByToken returns report for matching fingerprint', function () {
    $svc = new DiagnosticHistoryService();
    $fp = 'pest-diag-owner';
    $saved = $svc->save($fp, null, 'full', [
        'health_score' => 90,
        'health_grade' => 'A',
        'report_summary' => ['cpu' => 'X', 'gpu' => 'Y', 'ram_gb' => 16, 'is_laptop' => false],
        'metrics' => ['cpu_temp_max' => 60],
        'bottleneck' => ['type' => '', 'message' => ''],
    ], []);
    $row = $svc->getByToken($saved['token'], $fp, null);
    expect($row)->not->toBeNull();
    expect($row['report'] ?? null)->toBeArray();
});

it('getByToken denies report payload for wrong fingerprint', function () {
    $svc = new DiagnosticHistoryService();
    $fp = 'pest-diag-a';
    $saved = $svc->save($fp, null, 'lite', [
        'health_score' => 50,
        'health_grade' => 'C',
        'report_summary' => ['cpu' => 'c', 'gpu' => 'g', 'ram_gb' => 8, 'is_laptop' => false],
        'metrics' => [],
        'bottleneck' => ['type' => 'cpu', 'message' => 'CPU'],
    ], []);
    $row = $svc->getByToken($saved['token'], 'other-fp', null);
    expect($row)->not->toBeNull();
    expect($row)->not->toHaveKey('report');
});

it('userHistory lists rows for fingerprint', function () {
    $svc = new DiagnosticHistoryService();
    $fp = 'pest-diag-hist';
    $svc->save($fp, null, 'lite', [
        'health_score' => 40,
        'health_grade' => 'D',
        'report_summary' => ['cpu' => 'c', 'gpu' => 'g', 'ram_gb' => 8, 'is_laptop' => false],
        'metrics' => [],
        'bottleneck' => ['type' => '', 'message' => ''],
    ], []);
    $hist = $svc->userHistory($fp, null, 5);
    expect($hist)->toBeArray()->not->toBeEmpty();
});

it('stats returns aggregate keys', function () {
    $svc = new DiagnosticHistoryService();
    $s = $svc->stats();
    expect($s)->toHaveKeys(['scans_today', 'scans_hour', 'avg_health_24h', 'total_scans', 'full_scans']);
    expect($s['total_scans'])->toBeInt();
});

it('communityBenchmark returns expected structure', function () {
    $svc = new DiagnosticHistoryService();
    $b = $svc->communityBenchmark();
    expect($b)->toHaveKeys(['grades', 'top_gpus', 'bottlenecks', 'thermal_lab_24h', 'gpu_temp_rows']);
});

it('lastPublicMetricsForFingerprint returns null for unknown fingerprint', function () {
    $svc = new DiagnosticHistoryService();
    expect($svc->lastPublicMetricsForFingerprint('pest-diag-unknown-' . bin2hex(random_bytes(4))))->toBeNull();
});

it('lastPublicMetricsForFingerprint returns null for empty fingerprint', function () {
    $svc = new DiagnosticHistoryService();
    expect($svc->lastPublicMetricsForFingerprint(''))->toBeNull();
});

it('anonymousBottleneckMixLastDays returns list of type count', function () {
    $svc = new DiagnosticHistoryService();
    $mix = $svc->anonymousBottleneckMixLastDays(14);
    expect($mix)->toBeArray();
});
