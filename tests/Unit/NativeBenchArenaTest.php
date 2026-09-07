<?php

declare(strict_types=1);

use App\Services\DiagnosticToolCatalogService;
use App\Services\LabSuiteService;
use PHPUnit\Framework\TestCase;

final class NativeBenchArenaTest extends TestCase
{
    public function testSuiteProfilesIncludeNativeGpuAndCpuCache(): void
    {
        $profiles = (new LabSuiteService(dirname(__DIR__, 2)))->profiles();
        foreach (['standard', 'deep'] as $id) {
            $this->assertContains('gpu', $profiles[$id]['benches']);
            $this->assertContains('cpu_cache', $profiles[$id]['benches']);
            $this->assertContains('storage', $profiles[$id]['benches']);
        }
    }

    public function testCatalogLabelsAreNativeFirst(): void
    {
        $bench = (new DiagnosticToolCatalogService())->runnableBench();
        $byId = [];
        foreach ($bench as $row) {
            $byId[$row['id']] = $row;
        }
        $this->assertArrayHasKey('cpu_cache', $byId);
        $this->assertStringContainsString('Native', $byId['gpu']['label']);
        $this->assertStringContainsString('CDM', $byId['storage']['label']);
    }

    public function testMergeBenchMetricsAcceptsProbeGpuShape(): void
    {
        $svc = new LabSuiteService(dirname(__DIR__, 2));
        $ref = new ReflectionClass($svc);
        $m = $ref->getMethod('mergeBenchMetrics');
        $normalized = ['metrics' => []];
        $m->invokeArgs($svc, [&$normalized, [
            [
                'id' => 'gpu',
                'score' => 340544.5,
                'engine' => 'vulkan_d3d11_compute',
                'gflops' => 3405.4,
                'primary' => true,
            ],
            [
                'id' => 'cpu_cache',
                'score' => 128.5,
            ],
            [
                'id' => 'storage',
                'seq_read_mbps' => 3200.1,
                'seq_write_mbps' => 2800.2,
                'score' => 9000,
            ],
            [
                'id' => 'memory',
                'score' => 18500.5,
            ],
        ]]);
        $this->assertSame(340544, $normalized['metrics']['gpu_score']);
        $this->assertSame('vulkan_d3d11_compute', $normalized['metrics']['gpu_engine']);
        $this->assertSame(128, $normalized['metrics']['cpu_cache_score']);
        $this->assertSame(3200.1, $normalized['metrics']['storage_read_mb_s']);
        $this->assertSame(18500.5, $normalized['metrics']['mem_bandwidth_mb_s']);
    }
}
