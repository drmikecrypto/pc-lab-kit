<?php

declare(strict_types=1);

use App\Services\DiagnosticDriverAdvisorService;
use App\Services\HardwareKnowledgeGraphService;

test('driver advisor presents identity confidence and install queue', function () {
    $presented = (new DiagnosticDriverAdvisorService())->present([
        'drivers' => [
            'score' => 55,
            'grade' => 'D',
            'is_laptop' => false,
            'board' => ['manufacturer' => 'ASUS', 'product' => 'ROG STRIX B550-F'],
            'system' => ['manufacturer' => 'ASUS', 'model' => 'System Product Name'],
            'summary' => [
                'critical_actions' => 1,
                'warn_actions' => 1,
                'info_actions' => 0,
                'store_packages' => 12,
                'wu_candidates' => 0,
            ],
            'actions' => [
                [
                    'severity' => 'critical',
                    'code' => 'missing_driver',
                    'title' => 'No driver: PCI Simple Communications Controller',
                    'detail' => 'Code 28',
                    'category' => 'chipset',
                    'device' => 'PCI Simple Communications Controller',
                    'priority' => 10,
                    'instance_id' => 'PCI\\VEN_8086&DEV_43E8&SUBSYS_87D01043',
                    'vendor_id' => '8086',
                    'device_id' => '43e8',
                    'bus' => 'pci',
                    'match_confidence' => 'exact',
                    'primary_link' => [
                        'label' => 'Intel Chipset INF Utility',
                        'url' => 'https://www.intel.com/content/www/us/en/download/19347/chipset-inf-utility.html',
                    ],
                    'links' => [
                        [
                            'label' => 'Intel Chipset INF Utility',
                            'url' => 'https://www.intel.com/content/www/us/en/download/19347/chipset-inf-utility.html',
                        ],
                    ],
                ],
                [
                    'severity' => 'warn',
                    'code' => 'store_newer',
                    'title' => 'Newer driver in store for Realtek',
                    'detail' => 'Active 1.0; store has 2.0',
                    'category' => 'network',
                    'device' => 'Realtek PCIe GbE',
                    'match_confidence' => 'vendor',
                    'links' => [],
                ],
            ],
            'install_queue' => [
                [
                    'id' => 'chipset',
                    'label' => 'Chipset / ME / PSP',
                    'why' => 'Unlocks PCIe',
                    'status' => 'action_required',
                    'actions' => [['code' => 'missing_driver']],
                    'match_confidence' => 'board',
                    'primary_link' => [
                        'label' => 'ASUS Support',
                        'url' => 'https://www.asus.com/support/',
                    ],
                    'links' => [
                        ['label' => 'ASUS Support', 'url' => 'https://www.asus.com/support/'],
                    ],
                ],
            ],
            'gpus' => [
                [
                    'name' => 'NVIDIA GeForce RTX 4070',
                    'vendor' => 'nvidia',
                    'driver' => '560.94',
                    'driver_date' => '2024-08-01',
                    'age_days' => 40,
                    'is_stale' => false,
                    'is_generic' => false,
                    'vendor_id' => '10de',
                    'device_id' => '2786',
                    'match_confidence' => 'exact',
                    'links' => [],
                ],
            ],
            'windows_update' => [
                'available' => true,
                'scanned' => false,
                'note' => 'optional',
                'candidates' => [],
                'problem_devices' => [
                    [
                        'name' => 'PCI Simple Communications Controller',
                        'instance_id' => 'PCI\\VEN_8086&DEV_43E8',
                        'vendor_id' => '8086',
                        'device_id' => '43e8',
                    ],
                ],
            ],
        ],
        'devices' => [
            'summary' => ['driverless' => 1, 'problem_devices' => 1, 'total_devices' => 120],
            'driverless' => [
                [
                    'name' => 'PCI Simple Communications Controller',
                    'category' => 'chipset',
                    'problem_message' => 'The drivers for this device are not installed. (Code 28)',
                    'vendor_name' => 'Intel',
                    'instance_id' => 'PCI\\VEN_8086&DEV_43E8',
                    'vendor_id' => '8086',
                    'device_id' => '43e8',
                    'bus' => 'pci',
                ],
            ],
        ],
    ]);

    expect($presented['score'])->toBe(55)
        ->and($presented['grade'])->toBe('D')
        ->and($presented['actions'][0]['match_confidence'])->toBe('exact')
        ->and($presented['actions'][0]['vendor_id'])->toBe('8086')
        ->and($presented['actions'][0]['primary_link']['url'])->toContain('intel.com')
        ->and($presented['install_queue'][0]['match_confidence'])->toBe('board')
        ->and($presented['driverless'][0]['vendor_id'])->toBe('8086')
        ->and($presented['store_hints'])->not->toBeEmpty()
        ->and($presented['windows_update']['problem_devices'])->not->toBeEmpty();
});

test('hardware knowledge graph includes driver device nodes', function () {
    $graph = (new HardwareKnowledgeGraphService())->fromProbe([
        'cpu' => ['model' => 'Ryzen 7 5800X', 'cores' => 8],
        'gpu' => ['model' => 'RTX 4070', 'vram_gb' => 12],
        'ram' => ['total_gb' => 32],
        'device' => ['form_factor' => 'desktop'],
        'drivers' => [
            'gpus' => [
                [
                    'name' => 'Microsoft Basic Display Adapter',
                    'is_generic' => true,
                    'vendor_id' => '10de',
                    'device_id' => '2786',
                    'instance_id' => 'PCI\\VEN_10DE&DEV_2786',
                ],
            ],
            'actions' => [
                [
                    'severity' => 'critical',
                    'code' => 'missing_driver',
                    'title' => 'No driver: SMBus',
                    'device' => 'SM Bus Controller',
                    'category' => 'chipset',
                    'vendor_id' => '1022',
                    'device_id' => '790b',
                    'instance_id' => 'PCI\\VEN_1022&DEV_790B',
                    'match_confidence' => 'exact',
                ],
            ],
        ],
        'devices' => [
            'driverless' => [
                [
                    'name' => 'SM Bus Controller',
                    'category' => 'chipset',
                    'vendor_id' => '1022',
                    'device_id' => '790b',
                    'instance_id' => 'PCI\\VEN_1022&DEV_790B',
                ],
            ],
        ],
    ], [
        'metrics' => ['cpu_score' => 28000, 'gpu_score' => 22000],
        'percentiles' => ['cpu' => 85, 'gpu' => 70],
        'bottleneck' => ['type' => 'gpu', 'message' => 'GPU limited'],
        'risks' => [],
    ]);

    $types = array_column($graph['nodes'], 'type');
    expect($types)->toContain('device')
        ->and($graph['summary']['driver_device_nodes'])->toBeGreaterThan(0);

    $rels = array_column($graph['edges'], 'relation');
    expect($rels)->toContain('needs_driver')
        ->and($rels)->toContain('generic_driver');
});

test('driver catalog json has required keys', function () {
    $path = dirname(__DIR__, 2) . '/agent/pclab_probe/data/driver-catalog.json';
    expect(is_file($path))->toBeTrue();
    $json = json_decode((string) file_get_contents($path), true);
    expect($json)->toBeArray()
        ->and($json['version'] ?? null)->toBe(1)
        ->and($json['pci'])->toBeArray()->not->toBeEmpty()
        ->and($json['usb'])->toBeArray()->not->toBeEmpty()
        ->and($json['board_patterns'])->toBeArray()->not->toBeEmpty();

    foreach ($json['pci'] as $row) {
        expect($row)->toHaveKeys(['ven', 'category', 'label', 'url']);
    }
});

test('driver package matcher resolves pci and board model links', function () {
    $matcher = new \App\Services\DriverPackageMatcherService();

    expect($matcher->parseHardwareId('PCI\\VEN_10EC&DEV_8168'))->toMatchArray([
        'bus' => 'pci',
        'vendor_id' => '10ec',
        'device_id' => '8168',
    ]);

    $intelMe = $matcher->resolve([
        'category' => 'pci',
        'device' => 'PCI Simple Communications Controller',
        'vendor_id' => '8086',
        'device_id' => '43e8',
        'instance_id' => 'PCI\\VEN_8086&DEV_43E8&SUBSYS_87D01043',
        'board' => ['manufacturer' => 'ASUSTeK', 'product' => 'ROG STRIX B550-F GAMING'],
        'system' => ['manufacturer' => 'ASUS', 'model' => 'System Product Name'],
    ]);
    expect($intelMe['vendor_id'])->toBe('8086')
        ->and($intelMe['device_id'])->toBe('43e8')
        ->and($intelMe['category'])->toBe('chipset')
        ->and($intelMe['match_confidence'])->toBeIn(['exact', 'vendor', 'board'])
        ->and($intelMe['primary_link']['url'] ?? '')->not->toBe('');

    $nvidia = $matcher->resolve([
        'category' => 'gpu',
        'device' => 'NVIDIA GeForce RTX 4070',
        'vendor_id' => '10de',
        'device_id' => '2786',
    ]);
    expect($nvidia['match_confidence'])->toBe('vendor')
        ->and($nvidia['primary_link']['url'] ?? '')->toContain('nvidia.com');

    $enriched = $matcher->enrich([
        'name' => 'Realtek PCIe GbE Family Controller',
        'category' => 'network',
        'vendor_id' => '10ec',
        'device_id' => '8168',
        'instance_id' => 'PCI\\VEN_10EC&DEV_8168',
    ], ['manufacturer' => 'MSI', 'product' => 'MAG B550 TOMAHAWK'], []);
    expect($enriched['vendor_id'])->toBe('10ec')
        ->and($enriched['device_id'])->toBe('8168')
        ->and($enriched['match_confidence'])->toBe('vendor')
        ->and($enriched['primary_link']['url'] ?? '')->toContain('realtek.com');
});

test('driver advisor enriches driverless rows with package links', function () {
    $presented = (new \App\Services\DiagnosticDriverAdvisorService())->present([
        'drivers' => [
            'score' => 40,
            'grade' => 'F',
            'board' => ['manufacturer' => 'Gigabyte', 'product' => 'B650 AORUS ELITE'],
            'system' => ['manufacturer' => 'Gigabyte', 'model' => 'B650 AORUS ELITE'],
            'actions' => [],
            'install_queue' => [],
            'gpus' => [],
            'summary' => [],
        ],
        'devices' => [
            'driverless' => [
                [
                    'name' => 'SM Bus Controller',
                    'category' => 'motherboard',
                    'problem_message' => 'Code 28',
                    'vendor_id' => '1022',
                    'device_id' => '790b',
                    'instance_id' => 'PCI\\VEN_1022&DEV_790B',
                ],
            ],
        ],
    ]);

    expect($presented['driverless'][0]['vendor_id'])->toBe('1022')
        ->and($presented['driverless'][0]['device_id'])->toBe('790b')
        ->and($presented['driverless'][0]['match_confidence'])->not->toBe('')
        ->and($presented['driverless'][0]['primary_link']['url'] ?? '')->not->toBe('')
        ->and($presented['driverless'][0]['category'])->toBe('chipset');
});
