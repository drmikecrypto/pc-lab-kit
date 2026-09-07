<?php

declare(strict_types=1);

use App\Database;
use App\Services\BenchmarkArenaService;
use App\Services\BenchmarkDatasetService;
use PHPUnit\Framework\TestCase;

final class BenchmarkArenaTest extends TestCase
{
    protected function setUp(): void
    {
        Database::resetConnection();
        Database::migrate();
    }

    public function testArenaPayloadHasComponentsAndGlobalStats(): void
    {
        $root = dirname(__DIR__, 2);
        $svc = new BenchmarkArenaService(new BenchmarkDatasetService($root));
        $payload = $svc->buildPayload('test-fp');
        $this->assertArrayHasKey('global', $payload);
        $this->assertArrayHasKey('components', $payload);
        $this->assertGreaterThan(0, count($payload['components']));
        $this->assertArrayHasKey('datasets', $payload);
        $this->assertArrayHasKey('percentile_method', $payload);
        $this->assertArrayHasKey('dataset_version', $payload);
        $this->assertStringContainsString('Empirical CDF', (string) $payload['percentile_method']);
        $this->assertStringContainsString('not UserBenchmark', (string) $payload['percentile_method']);
        $first = $payload['components'][0];
        $this->assertArrayHasKey('dataset_version', $first);
        $this->assertSame($payload['dataset_version'], $first['dataset_version']);
    }

    public function testScorePercentileInRange(): void
    {
        $ds = new BenchmarkDatasetService(dirname(__DIR__, 2));
        $pct = $ds->scorePercentile('cpu', 25000);
        $this->assertGreaterThanOrEqual(0, $pct);
        $this->assertLessThanOrEqual(100, $pct);
    }
}
