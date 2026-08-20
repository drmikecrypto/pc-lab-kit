<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Database;
use App\Services\JobQueueService;
use App\Services\LabSessionService;
use App\Services\LabSuiteService;
use App\Services\SettingsService;
use PHPUnit\Framework\TestCase;

final class EnterpriseMasterpieceTest extends TestCase
{
    private string $root;

    protected function setUp(): void
    {
        $this->root = sys_get_temp_dir() . '/pclab-ent-' . bin2hex(random_bytes(4));
        mkdir($this->root . '/storage/suite', 0777, true);
        mkdir($this->root . '/storage/sessions', 0777, true);
        mkdir($this->root . '/storage/settings', 0777, true);
        mkdir($this->root . '/storage/database', 0777, true);
        putenv('PCLAB_SQLITE=' . $this->root . '/storage/database/test.sqlite');
    }

    protected function tearDown(): void
    {
        Database::resetConnection();
    }

    public function testFinalizeAfterSoftCancelKeepsProbeWork(): void
    {
        $svc = new LabSuiteService($this->root);
        $job = $svc->start(['profile' => 'quick', 'fp' => 'deadbeef']);
        $id = (string) $job['id'];
        $svc->patch($id, [
            'status' => 'running',
            'progress' => 80,
            'probe_job' => [
                'status' => 'completed',
                'benches' => [
                    [
                        'id' => 'storage',
                        'engine' => 'diskspd_cdm',
                        'diskspd_available' => true,
                        'score' => 1200,
                        'seq_read_mbps' => 3100,
                        'profiles' => [
                            'SEQ1M_Q8T1' => [
                                'read_mbps' => 3100,
                                'write_mbps' => 2800,
                                'read_iops' => 12000,
                                'write_iops' => 11000,
                                'read_latency_us' => 80,
                            ],
                        ],
                    ],
                ],
                'stress' => ['id' => 'combined', 'status' => 'ok'],
                'samples' => [['t' => gmdate('c'), 'cpu_temp' => 55.0, 'gpu_temp' => 60.0]],
                'probe' => ['cpu' => ['name' => 'Test CPU'], 'gpu' => [], 'ram' => [], 'sensors' => []],
            ],
        ]);
        $cancelled = $svc->cancel($id);
        self::assertSame('awaiting_finalize', $cancelled['status']);

        $final = $svc->finalize($id, []);
        self::assertSame('completed', $final['status']);
        self::assertNotEmpty($final['result']['analysis']['suite']['benches']);
        $storage = $final['result']['analysis']['suite']['benches'][0];
        self::assertSame('diskspd_cdm', $storage['engine']);
        self::assertArrayHasKey('profiles', $storage);
        self::assertArrayHasKey('read_iops', $storage['profiles']['SEQ1M_Q8T1']);
    }

    public function testListResumableSurfacesAwaitingFinalize(): void
    {
        $svc = new LabSuiteService($this->root);
        $job = $svc->start(['profile' => 'quick', 'fp' => 'abc']);
        $svc->patch((string) $job['id'], [
            'probe_job' => ['status' => 'completed', 'benches' => [['id' => 'cpu', 'score' => 1]]],
        ]);
        $svc->cancel((string) $job['id']);
        $list = $svc->listResumable();
        self::assertNotEmpty($list);
        self::assertTrue($list[0]['resumable']);
    }

    public function testSessionHmacRoundTrip(): void
    {
        $settings = new SettingsService($this->root);
        $key = $settings->shopSigningKey();
        self::assertNotSame('', $key);
        self::assertTrue($settings->shopKeyConfigured());

        $svc = new LabSessionService($this->root);
        $export = $svc->export([
            'health_score' => 90,
            'metrics' => ['cpu_score' => 100],
            'stress_certificate' => ['verdict' => 'pass', 'timeline' => []],
            'silicon_dossier' => ['open_book' => ['sensors' => []]],
            'hardware_graph' => ['summary' => ['nodes' => 3]],
            'suite' => ['profile' => 'quick'],
        ], ['fingerprint' => 'fp1', 'profile' => 'quick']);

        $imported = $svc->import(json_encode($export['session'], JSON_UNESCAPED_UNICODE) ?: '{}');
        self::assertTrue($imported['verified']);
        self::assertTrue($svc->verifyPayload($imported));

        $tampered = $export['session'];
        $tampered['health_score'] = 1;
        self::assertFalse($svc->verifyPayload($tampered));
    }

    public function testJobQueueLeaseAndComplete(): void
    {
        // Point Database at temp sqlite via config override is hard; use migrate on default if available.
        $configPath = dirname(__DIR__, 2) . '/config/app.php';
        if (!is_file($configPath)) {
            self::markTestSkipped('app config missing');
        }
        Database::migrate();
        $q = new JobQueueService();
        $id = $q->enqueue('burn_in_24h', ['duration_seconds' => 30, 'profile' => 'quick'], 'local');
        $leased = $q->leaseNext('test-owner', 60, 'burn_in_24h');
        self::assertNotNull($leased);
        self::assertSame($id, $leased['id']);
        self::assertSame('running', $leased['status']);
        $q->complete($id, ['ok' => true]);
        $done = $q->get($id);
        self::assertSame('complete', $done['status']);
    }

    public function testSoakProfilesExist(): void
    {
        $svc = new LabSuiteService($this->root);
        $profiles = $svc->profiles();
        self::assertArrayHasKey('soak_15', $profiles);
        self::assertSame(900, $profiles['soak_15']['stress_seconds']);
        self::assertArrayHasKey('soak_60', $profiles);
    }
}
