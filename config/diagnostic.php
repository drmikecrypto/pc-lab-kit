<?php

/**
 * PCVerse — local diagnostic lab configuration (English UI).
 */
return [
    'product' => [
        'name' => 'PCVerse',
        'tagline' => 'Local PC laboratory — probe, test, monitor, tune.',
        'lite_tagline' => 'Quick health quiz — full scan runs locally via PCVerse Probe.',
        'full_tagline' => 'One local lab for monitoring, benchmarks, stress tests, storage, RGB, and LCD — replaces 80 separate apps.',
        'engine_label' => 'Engine — depth · telemetry · RGB · safe OC',
        'advisor_label' => 'Advisor — insight · bottleneck · guidance',
    ],
    'rgb' => [
        'max_gif_mb' => 25,
        'openrgb_bundle_path' => 'agent/pcverse_probe/tools/OpenRGB/OpenRGB.exe',
    ],
    'app_download' => [
        'windows' => '/download/pcverse-windows-x64',
        'linux' => '/download/pcverse-linux-x64',
        'hub' => '/download',
        'fallback' => '/download',
    ],
    'downloads' => [
        'hub' => '/download',
        'windows' => '/download/pcverse-windows-x64',
        'linux' => '/download/pcverse-linux-x64',
    ],
    'windows_agent' => [
        'name' => 'PCVerse Probe',
        'download_url' => '/download/pcverse-windows-x64',
        'local_host' => '127.0.0.1',
        'local_port' => 18765,
        'health_path' => '/health',
        'probe_path' => '/probe',
    ],
    'games_catalog' => [
        'target_count' => 300,
        'refresh_days' => 7,
        'sources' => ['anchors', 'awards'],
    ],
    'import_formats' => [
        ['id' => 'hwinfo_csv', 'label' => 'Hardware sensor report (CSV)', 'extensions' => ['csv']],
        ['id' => 'capframex_json', 'label' => 'Game performance report (JSON)', 'extensions' => ['json']],
        ['id' => 'cpuz_txt', 'label' => 'CPU report (TXT)', 'extensions' => ['txt']],
        ['id' => 'frametime_csv', 'label' => 'Frametime log (CSV)', 'extensions' => ['csv', 'txt']],
    ],
    'pro_tools' => [
        ['id' => 'hwinfo', 'name' => 'HWiNFO', 'category' => 'monitoring', 'desc' => 'VRM sensors, CPU power, VRAM, throttling, WHEA'],
        ['id' => 'cpuz', 'name' => 'CPU-Z', 'category' => 'monitoring', 'desc' => 'Motherboard, RAM timings, CPU'],
        ['id' => 'gpuz', 'name' => 'GPU-Z', 'category' => 'monitoring', 'desc' => 'PCIe, GPU BIOS, power draw, clocks'],
        ['id' => 'afterburner', 'name' => 'MSI Afterburner', 'category' => 'monitoring', 'desc' => 'In-game OSD, fans, undervolt'],
        ['id' => 'rtss', 'name' => 'RivaTuner Statistics Server', 'category' => 'fps', 'desc' => 'FPS, frametime, 1% lows'],
        ['id' => 'capframex', 'name' => 'CapFrameX', 'category' => 'fps', 'desc' => 'Stutter and frametime analysis'],
        ['id' => 'presentmon', 'name' => 'PresentMon', 'category' => 'fps', 'desc' => 'Low-level render pipeline'],
        ['id' => 'occt', 'name' => 'OCCT', 'category' => 'stress', 'desc' => 'PSU, VRAM, CPU, GPU, AVX stress'],
        ['id' => 'prime95', 'name' => 'Prime95', 'category' => 'stress', 'desc' => 'CPU thermal and stability'],
        ['id' => 'aida64', 'name' => 'AIDA64', 'category' => 'stress', 'desc' => 'Stress, RAM latency, sensors'],
        ['id' => 'memtest86', 'name' => 'MemTest86', 'category' => 'stress', 'desc' => 'Professional RAM testing'],
        ['id' => '3dmark', 'name' => '3DMark', 'category' => 'gpu', 'desc' => 'Time Spy, Steel Nomad, Fire Strike'],
        ['id' => 'furmark', 'name' => 'FurMark', 'category' => 'gpu', 'desc' => 'GPU thermal torture test'],
    ],
    'lite_steps' => [
        [
            'id' => 'device',
            'title' => 'Device type',
            'questions' => [
                ['id' => 'form_factor', 'type' => 'choice', 'label' => 'What are you testing?', 'options' => [
                    ['value' => 'desktop', 'label' => 'Desktop PC', 'score' => []],
                    ['value' => 'laptop', 'label' => 'Laptop', 'score' => ['laptop' => 1]],
                    ['value' => 'aio', 'label' => 'All-in-one', 'score' => ['laptop' => 1]],
                ]],
            ],
        ],
        [
            'id' => 'usage',
            'title' => 'Primary use',
            'questions' => [
                ['id' => 'primary_use', 'type' => 'choice', 'label' => 'What do you use this PC for most?', 'options' => [
                    ['value' => 'gaming', 'label' => 'Gaming', 'score' => ['gpu_stress' => 2]],
                    ['value' => 'workstation', 'label' => 'Render / CAD / AI', 'score' => ['cpu_stress' => 2, 'ram_stress' => 1]],
                    ['value' => 'office', 'label' => 'Office / web', 'score' => []],
                    ['value' => 'mixed', 'label' => 'Mixed', 'score' => ['gpu_stress' => 1, 'cpu_stress' => 1]],
                ]],
            ],
        ],
        [
            'id' => 'symptoms',
            'title' => 'Symptoms',
            'questions' => [
                ['id' => 'symptoms', 'type' => 'multi', 'label' => 'What problems do you notice?', 'options' => [
                    ['value' => 'stutter', 'label' => 'Stutter in games', 'score' => ['frametime' => 3, 'bottleneck' => 2]],
                    ['value' => 'thermal', 'label' => 'High heat / loud fans', 'score' => ['thermal' => 3]],
                    ['value' => 'crash', 'label' => 'Crashes or BSOD', 'score' => ['stability' => 3, 'psu' => 2]],
                    ['value' => 'slow_boot', 'label' => 'Slow boot', 'score' => ['storage' => 2]],
                    ['value' => 'low_fps', 'label' => 'Lower FPS than expected', 'score' => ['bottleneck' => 3, 'gpu' => 2]],
                    ['value' => 'battery', 'label' => 'Weak battery (laptop)', 'score' => ['battery' => 3]],
                ]],
            ],
        ],
        [
            'id' => 'specs',
            'title' => 'Rough hardware',
            'questions' => [
                ['id' => 'ram_gb', 'type' => 'choice', 'label' => 'System RAM', 'options' => [
                    ['value' => '8', 'label' => '8 GB or less', 'score' => ['ram_stress' => 2]],
                    ['value' => '16', 'label' => '16 GB', 'score' => []],
                    ['value' => '32', 'label' => '32 GB+', 'score' => []],
                ]],
                ['id' => 'gpu_tier', 'type' => 'choice', 'label' => 'GPU class', 'options' => [
                    ['value' => 'igpu', 'label' => 'Integrated / weak', 'score' => ['gpu' => 3]],
                    ['value' => 'mid', 'label' => 'Mid-range', 'score' => []],
                    ['value' => 'high', 'label' => 'High-end', 'score' => []],
                    ['value' => 'flagship', 'label' => 'Flagship', 'score' => []],
                ]],
                ['id' => 'storage_type', 'type' => 'choice', 'label' => 'System drive', 'options' => [
                    ['value' => 'hdd', 'label' => 'HDD', 'score' => ['storage' => 3]],
                    ['value' => 'sata_ssd', 'label' => 'SATA SSD', 'score' => ['storage' => 1]],
                    ['value' => 'nvme', 'label' => 'NVMe', 'score' => []],
                ]],
            ],
        ],
    ],
    'ai' => [
        'enabled_hint' => 'Add your API key in Settings for personalized upgrade advice.',
    ],
];
