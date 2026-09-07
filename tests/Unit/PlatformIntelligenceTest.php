<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Services\AssemblyCertificateService;
use App\Services\LabSuiteService;
use App\Services\PlatformAuditService;
use PHPUnit\Framework\TestCase;

final class PlatformIntelligenceTest extends TestCase
{
    public function testAdaptivePlanPreviewSkipsGpuWithoutDiscreteFlag(): void
    {
        $svc = new LabSuiteService(sys_get_temp_dir() . '/pclab-suite-test-' . bin2hex(random_bytes(4)));
        $plan = $svc->planPreview([
            'profile' => 'adaptive',
            'fingerprint' => [
                'id' => 'abc123',
                'coverage_score' => 70,
                'form_factor' => 'desktop',
                'has_discrete_gpu' => false,
                'nvme_count' => 1,
                'disk_count' => 1,
            ],
            'devices' => [
                'summary' => ['driverless' => 0],
                'driverless' => [],
                'battery' => [],
            ],
        ]);

        self::assertTrue($plan['ok']);
        self::assertSame('adaptive', $plan['profile']);
        self::assertFalse($plan['gated']);
        self::assertNotContains('gpu', $plan['benches']);
        $ids = array_column($plan['steps'], 'id');
        self::assertContains('bench:cpu', $ids);
        self::assertNotContains('bench:gpu', $ids);
    }

    public function testAdaptivePlanGatesOnChipsetDriverless(): void
    {
        $svc = new LabSuiteService(sys_get_temp_dir() . '/pclab-suite-test-' . bin2hex(random_bytes(4)));
        $plan = $svc->planPreview([
            'profile' => 'adaptive',
            'fingerprint' => ['coverage_score' => 40, 'form_factor' => 'desktop'],
            'devices' => [
                'summary' => ['driverless' => 1],
                'driverless' => [
                    ['name' => 'Intel Chipset SMBus Controller', 'category' => 'chipset', 'instance_id' => 'PCI\\VEN_8086'],
                ],
            ],
        ]);

        self::assertTrue($plan['gated']);
        self::assertSame([], $plan['benches']);
        self::assertNotEmpty($plan['gate_reason']);
    }

    public function testPlatformAuditBuildsHtmlDocument(): void
    {
        $audit = (new PlatformAuditService())->build([
            'fingerprint' => [
                'id' => 'deadbeef',
                'coverage_score' => 80,
                'form_factor' => 'desktop',
                'elevated' => true,
                'gaps' => [
                    ['plane' => 'pci_config', 'reason' => 'needs_elevation', 'detail' => 'test gap'],
                ],
                'capabilities' => ['inventory', 'adaptive_lab'],
            ],
            'platform' => [
                'bios' => ['vendor' => 'AMI', 'version' => '1.0'],
                'acpi' => ['signature_count' => 12],
                'storage' => [['friendly_name' => 'NVMe']],
                'pci_config' => [],
                'ec_board' => ['count' => 0],
            ],
            'plan' => [
                'id' => 'adaptive',
                'label' => 'Adaptive Lab',
                'steps' => [
                    ['id' => 'inventory', 'label' => 'Platform inventory', 'reason' => 'baseline'],
                ],
                'benches' => ['cpu'],
            ],
            'drivers' => [
                'action_plan' => [
                    'count' => 1,
                    'installable_count' => 1,
                    'items' => [
                        ['action' => 'install', 'device' => 'GPU', 'category' => 'gpu'],
                    ],
                ],
            ],
            'stress' => ['verdict' => 'PASS', 'id' => 'combined'],
        ]);

        self::assertSame('pclab-platform-audit-v1', $audit['document']['schema']);
        self::assertSame(80, $audit['document']['fingerprint']['coverage_score']);
        self::assertStringContainsString('Platform Audit', $audit['html']);
        self::assertStringContainsString('deadbeef', $audit['html']);
        self::assertStringContainsString('PASS', $audit['html']);
    }

    public function testAssemblyCertificateIncludesCoverageAndPlan(): void
    {
        $cert = (new AssemblyCertificateService())->build([
            'report_summary' => ['cpu' => 'Test CPU', 'gpu' => 'Test GPU', 'ram_gb' => 32],
            'metrics' => [],
            'stress_certificate' => ['passed' => true, 'verdict' => 'PASS'],
            'silicon_dossier' => [
                'fingerprint' => ['id' => 'fpdeadbeef', 'coverage_score' => 72, 'form_factor' => 'desktop'],
                'platform' => ['uefi' => ['secure_boot' => true], 'tpm' => ['present' => true]],
                'open_book' => ['count' => 2, 'sensors' => [['source' => 'blackwell_therm_mmio']]],
            ],
            'suite' => [
                'plan' => [
                    'label' => 'Adaptive Lab',
                    'steps' => [
                        ['id' => 'inventory', 'label' => 'Platform inventory', 'reason' => 'baseline'],
                        ['id' => 'bench:cpu', 'label' => 'CPU', 'reason' => 'baseline ST'],
                    ],
                    'benches' => ['cpu'],
                ],
            ],
        ], ['shop_name' => 'Test Shop', 'token' => 'tok']);

        self::assertSame(72, $cert['document']['coverage_score']);
        self::assertSame('fpdeadbeef', $cert['document']['fingerprint_id']);
        self::assertStringContainsString('Platform coverage', $cert['html']);
        self::assertStringContainsString('Adaptive Lab', $cert['html']);
        self::assertStringContainsString('baseline ST', $cert['html']);
    }

    public function testProfilesIncludeAdaptive(): void
    {
        $profiles = (new LabSuiteService())->profiles();
        self::assertArrayHasKey('adaptive', $profiles);
        self::assertTrue($profiles['adaptive']['adaptive']);
    }
}
