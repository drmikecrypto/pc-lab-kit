<?php

declare(strict_types=1);

use App\Services\DiagnosticAiService;
use App\Services\DiagnosticImportService;
use App\Services\LabSuiteService;
use App\Services\SensorDeckService;
use App\Services\TopologyViewService;
use PHPUnit\Framework\TestCase;

final class AmbitiousUpgradeTest extends TestCase
{
    public function testSuiteProfilesAndStartCancel(): void
    {
        $dir = sys_get_temp_dir() . '/pclab_suite_' . bin2hex(random_bytes(4));
        mkdir($dir . '/storage/suite', 0777, true);
        // LabSuiteService uses project root; exercise via reflection-free temp by constructing normally
        $svc = new LabSuiteService(dirname(__DIR__, 2));
        $profiles = $svc->profiles();
        $this->assertArrayHasKey('standard', $profiles);
        $this->assertContains('gpu', $profiles['standard']['benches']);
        $this->assertContains('cpu_cache', $profiles['standard']['benches']);
        $this->assertContains('gpu', $profiles['deep']['benches']);
        $job = $svc->start(['profile' => 'quick', 'fp' => 'testfp']);
        $this->assertSame('pending', $job['status']);
        $this->assertNotEmpty($job['id']);
        $again = $svc->status($job['id']);
        $this->assertNotNull($again);
        $cancelled = $svc->cancel($job['id']);
        $this->assertSame('cancelled', $cancelled['status'] ?? null);
    }

    public function testAdvisorCardsFallback(): void
    {
        $cards = (new DiagnosticAiService())->advisorCards([
            'health_grade' => 'B',
            'health_score' => 82,
            'bottleneck' => ['type' => 'gpu', 'message' => 'GPU bound in 1440p'],
            'risks' => [['message' => 'VRAM tight']],
            'hardware_graph' => ['nodes' => [['id' => 'cpu']], 'edges' => [], 'summary' => []],
        ]);
        $this->assertNotEmpty($cards);
        $this->assertLessThanOrEqual(5, count($cards));
        $this->assertArrayHasKey('title', $cards[0]);
        $this->assertArrayHasKey('severity', $cards[0]);
    }

    public function testSensorDeckSaveAndExport(): void
    {
        $root = sys_get_temp_dir() . '/pclab_deck_' . bin2hex(random_bytes(4));
        mkdir($root . '/storage/settings', 0777, true);
        $svc = new SensorDeckService($root);
        $layout = $svc->save([
            'widgets' => [
                ['id' => 'cpu_temp', 'type' => 'gauge', 'source' => 'cpu_temp', 'label' => 'CPU'],
            ],
            'alert_thresholds' => [
                'cpu_temp_c' => 88,
                'gpu_temp_c' => 82,
            ],
        ]);
        $this->assertCount(1, $layout['widgets']);
        $this->assertSame(88.0, $layout['alert_thresholds']['cpu_temp_c']);
        $loaded = $svc->get();
        $this->assertSame(88.0, $loaded['alert_thresholds']['cpu_temp_c']);
        $defaults = $svc->defaultLayout();
        $this->assertArrayHasKey('alert_thresholds', $defaults);
        $sources = array_column($defaults['widgets'], 'source');
        $this->assertContains('gpu_hotspot', $sources);
        $this->assertContains('gpu_vram_temp', $sources);
        $json = $svc->export('json');
        $this->assertSame('json', $json['format']);
        $rain = $svc->export('rainmeter');
        $this->assertStringContainsString('[Rainmeter]', (string) $rain['content']);
    }

    public function testTopologyFromGraph(): void
    {
        $graph = [
            'nodes' => [
                ['id' => 'cpu', 'type' => 'cpu', 'label' => 'Ryzen'],
                ['id' => 'gpu', 'type' => 'gpu', 'label' => 'RTX'],
            ],
            'edges' => [
                ['source' => 'cpu', 'target' => 'gpu', 'relation' => 'pcie'],
            ],
            'summary' => ['ok' => true],
        ];
        $topo = (new TopologyViewService())->fromGraph($graph);
        $this->assertCount(2, $topo['nodes']);
        $this->assertCount(1, $topo['links']);
        $this->assertArrayHasKey('x', $topo['nodes'][0]);

        $topo3d = (new TopologyViewService())->fromGraph3d($graph);
        $this->assertSame('3d', $topo3d['mode']);
        $this->assertCount(2, $topo3d['nodes']);
        $this->assertArrayHasKey('position', $topo3d['nodes'][0]);
    }

    public function testImportCinebenchGeekbench3dmark(): void
    {
        $imp = new DiagnosticImportService();
        $cb = $imp->parse('cinebench', "CPU (Multi Core): 18234\nCPU (Single Core): 1980\n");
        $this->assertSame('cinebench', $cb['source']);
        $this->assertNotEmpty($cb['geek'] ?? $cb['imported_scores'] ?? []);

        $gb = $imp->parse('geekbench', json_encode([
            'single_core_score' => 2100,
            'multi_core_score' => 12000,
            'version' => '6.2',
        ], JSON_THROW_ON_ERROR));
        $this->assertSame('geekbench_json', $gb['source']);

        $xml = $imp->parse('3dmark_xml', '<result><Score>12500</Score><GraphicsScore>13000</GraphicsScore><PhysicsScore>9000</PhysicsScore></result>');
        $this->assertSame('3dmark_xml', $xml['source']);
        $this->assertArrayHasKey('3dmark_score', $xml['geek']);
    }
}
