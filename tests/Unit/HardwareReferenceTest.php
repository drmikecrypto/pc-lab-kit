<?php

declare(strict_types=1);

use App\Services\DiagnosticInventoryService;
use App\Services\HardwareKnowledgeGraphService;
use App\Services\DiagnosticDriverAdvisorService;
use App\Services\LabReportExportService;

test('inventory presenter preserves hidden devices and confidence fields', function () {
    $probe = [
        'devices' => [
            'summary' => [
                'total_devices' => 2,
                'present_devices' => 1,
                'hidden_devices' => 1,
                'driverless' => 1,
                'problem_devices' => 1,
            ],
            'all_devices' => [
                [
                    'name' => 'NVIDIA GeForce',
                    'bus' => 'pci',
                    'category' => 'gpu',
                    'status' => 'OK',
                    'present' => true,
                    'hidden' => false,
                    'vendor_id' => '10de',
                    'device_id' => '2684',
                    'instance_id' => 'PCI\\VEN_10DE&DEV_2684\\0',
                    'confidence' => 'measured',
                    'source' => 'pnp',
                    'problem_code' => 0,
                ],
                [
                    'name' => 'Ghost USB Device',
                    'bus' => 'usb',
                    'category' => 'usb',
                    'status' => 'Error',
                    'present' => false,
                    'hidden' => true,
                    'ghost' => true,
                    'needs_driver' => true,
                    'has_problem' => true,
                    'vendor_id' => '046d',
                    'device_id' => 'c52b',
                    'instance_id' => 'USB\\VID_046D&PID_C52B\\GHOST',
                    'confidence' => 'measured',
                    'problem_code' => 28,
                    'problem_message' => 'Drivers for this device are not installed',
                ],
            ],
            'driverless' => [],
            'problem' => [],
            'hidden' => [],
            'monitors' => [
                'displays' => [
                    [
                        'name' => 'DELL U2720Q',
                        'manufacturer' => 'DEL',
                        'confidence' => 'measured',
                        'source' => 'wmi+edid',
                        'edid' => [
                            'manufacturer_code' => 'DEL',
                            'edid_version' => '1.4',
                            'hdr_capable' => false,
                            'preferred_timing' => ['width' => 3840, 'height' => 2160, 'refresh_hz' => 60],
                            'confidence' => 'measured',
                        ],
                    ],
                ],
                'modes' => [],
            ],
            'schema' => ['version' => 2],
        ],
    ];

    $presented = (new DiagnosticInventoryService())->present($probe);

    expect($presented['summary']['total_devices'])->toBe(2)
        ->and($presented['filters']['hidden'])->toBe(1)
        ->and($presented['filters']['driverless'])->toBe(1)
        ->and($presented['all_devices'][1]['hidden'])->toBeTrue()
        ->and($presented['all_devices'][0]['fields']['vendor_id']['confidence'])->toBe('measured')
        ->and($presented['monitors'][0]['edid']['preferred_timing']['width'])->toBe(3840);
});

test('hardware graph emits motherboard chipset dimm and monitor nodes', function () {
    $report = [
        'device' => ['form_factor' => 'desktop', 'hostname' => 'LAB'],
        'cpu' => ['model' => 'Ryzen 7 7800X3D', 'cores' => 8],
        'gpu' => ['model' => 'RTX 4080', 'vram_gb' => 16, 'vbios' => '95.02.3C'],
        'ram' => [
            'total_gb' => 32,
            'speed_mhz' => 6000,
            'modules' => [
                ['manufacturer' => 'G.Skill', 'part_number' => 'F5-6000', 'capacity_gb' => 16, 'die_type' => 'Hynix', 'die_confidence' => 'heuristic'],
                ['manufacturer' => 'G.Skill', 'part_number' => 'F5-6000', 'capacity_gb' => 16],
            ],
        ],
        'motherboard' => ['manufacturer' => 'ASUS', 'product' => 'ROG STRIX'],
        'bios' => ['vendor' => 'American Megatrends', 'version' => '2001'],
        'devices' => [
            'summary' => ['total_devices' => 10, 'hidden_devices' => 2],
            'by_category' => [
                'chipset' => [['name' => 'AMD SMBus']],
            ],
            'monitors' => [
                'displays' => [['name' => 'Monitor A', 'edid' => ['hdr_capable' => true, 'preferred_timing' => ['width' => 2560, 'height' => 1440]]]],
            ],
            'pci' => [],
            'usb' => ['devices' => []],
            'driverless' => [],
        ],
        'storage' => [
            'disks' => [
                ['model' => 'SSD1', 'size_gb' => 1000],
                ['model' => 'SSD2', 'size_gb' => 2000],
                ['model' => 'SSD3', 'size_gb' => 500],
                ['model' => 'SSD4', 'size_gb' => 500],
                ['model' => 'SSD5', 'size_gb' => 500],
            ],
        ],
        'sensors' => [
            'fans' => [['name' => 'CPU Fan', 'value' => 1200, 'confidence' => 'measured']],
        ],
    ];

    $graph = (new HardwareKnowledgeGraphService())->fromProbe($report, []);
    $types = array_column($graph['nodes'], 'type');

    expect($types)->toContain('motherboard')
        ->and($types)->toContain('chipset')
        ->and($types)->toContain('dimm')
        ->and($types)->toContain('monitor')
        ->and($types)->toContain('cooler')
        ->and($types)->toContain('firmware')
        ->and(count(array_filter($types, fn ($t) => $t === 'storage')))->toBe(5);
});

test('driver advisor exposes installable queue metadata', function () {
    $presented = (new DiagnosticDriverAdvisorService())->present([
        'drivers' => [
            'score' => 70,
            'grade' => 'C',
            'board' => ['manufacturer' => 'ASUS', 'product' => 'ROG'],
            'system' => ['manufacturer' => 'ASUS', 'model' => 'ROG'],
            'summary' => ['critical_actions' => 1],
            'install_queue' => [
                [
                    'id' => 'chipset',
                    'label' => 'Chipset',
                    'why' => 'First',
                    'status' => 'action_required',
                    'match_confidence' => 'vendor',
                    'install_method' => 'exe_ui',
                    'package_version' => '10.1.19628.8586',
                    'installable' => true,
                    'primary_link' => [
                        'label' => 'Intel Chipset',
                        'url' => 'https://www.intel.com/',
                        'install_method' => 'exe_ui',
                        'version' => '10.1.19628.8586',
                    ],
                    'links' => [],
                    'actions' => [['severity' => 'critical']],
                ],
            ],
            'actions' => [],
            'gpus' => [],
        ],
        'devices' => [
            'summary' => ['driverless' => 0],
            'driverless' => [],
        ],
    ]);

    expect($presented['install_queue'][0]['installable'])->toBeTrue()
        ->and($presented['install_queue'][0]['install_method'])->toBe('exe_ui')
        ->and($presented['install_queue'][0]['package_version'])->toBe('10.1.19628.8586');
});

test('lab report includes hardware reference section when devices present', function () {
    $built = (new LabReportExportService())->buildDocument([
        'health_score' => 88,
        'health_grade' => 'B',
        'metrics' => ['cpu_model' => 'Test CPU'],
        'report_summary' => ['cpu' => 'Test CPU', 'gpu' => 'Test GPU', 'ram_gb' => 32],
        'elevated' => false,
        'devices' => [
            'summary' => [
                'total_devices' => 1,
                'hidden_devices' => 0,
                'driverless' => 0,
                'problem_devices' => 0,
            ],
            'all_devices' => [
                [
                    'name' => 'Test Device',
                    'bus' => 'pci',
                    'status' => 'OK',
                    'present' => true,
                    'confidence' => 'measured',
                ],
            ],
        ],
        'hardware_graph' => ['summary' => ['node_count' => 3], 'nodes' => []],
    ]);

    expect($built['document']['hardware_reference']['summary']['total'])->toBe(1)
        ->and($built['html'])->toContain('Hardware Reference')
        ->and($built['html'])->toContain('Test Device');
});
