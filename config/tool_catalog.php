<?php

/**
 * PC Lab Kit unified toolkit — maps 80 enthusiast/OEM tools to local lab modules.
 *
 * coverage: live | beta | import | orchestrate | planned
 * module: monitor | stress | bench | storage | rgb | lcd | system | enterprise
 */
return [
    'meta' => [
        'version' => 1,
        'total' => 80,
        'tagline' => 'One local lab instead of 80 separate apps.',
    ],
    'categories' => [
        'cpu' => 'CPU benchmarks & stress',
        'gpu' => 'GPU benchmarks & stress',
        'ram' => 'RAM & memory testing',
        'system' => 'Full-system benchmarks',
        'monitor' => 'Temperature, power & sensors',
        'storage' => 'SSD, HDD & storage',
        'rgb' => 'RGB, ARGB & lighting',
        'lcd' => 'AIO LCD & sensor panels',
    ],
    'tools' => [
        // CPU benchmarks & stress (10)
        ['id' => 'cinebench', 'name' => 'Cinebench', 'category' => 'cpu', 'module' => 'bench', 'coverage' => 'beta', 'coverage_note' => 'Native CPU render score + import Maxon exports'],
        ['id' => 'geekbench', 'name' => 'Geekbench', 'category' => 'cpu', 'module' => 'bench', 'coverage' => 'import', 'coverage_note' => 'Import Geekbench JSON; native compute suite in Toolkit'],
        ['id' => 'passmark_cpu', 'name' => 'PassMark PerformanceTest', 'category' => 'cpu', 'module' => 'bench', 'coverage' => 'import', 'coverage_note' => 'Composite score from PC Lab Kit bench modules + import'],
        ['id' => 'prime95', 'name' => 'Prime95', 'category' => 'cpu', 'module' => 'stress', 'coverage' => 'orchestrate', 'coverage_note' => 'Built-in AVX CPU stress + optional Prime95 launcher'],
        ['id' => 'occt', 'name' => 'OCCT', 'category' => 'cpu', 'module' => 'stress', 'coverage' => 'beta', 'coverage_note' => 'Unified CPU/GPU/PSU stress with live telemetry overlay'],
        ['id' => 'ycruncher', 'name' => 'y-cruncher', 'category' => 'cpu', 'module' => 'bench', 'coverage' => 'orchestrate', 'coverage_note' => 'Pi/AVX stress orchestration + import logs'],
        ['id' => 'aida64', 'name' => 'AIDA64', 'category' => 'cpu', 'module' => 'stress', 'coverage' => 'beta', 'coverage_note' => 'Sensor + stress panels; import AIDA64 reports'],
        ['id' => 'intel_xtu', 'name' => 'Intel Extreme Tuning Utility', 'category' => 'cpu', 'module' => 'stress', 'coverage' => 'planned', 'coverage_note' => 'Safe OC advisor + telemetry (Intel-only tuning advisory)'],
        ['id' => 'linpack', 'name' => 'Linpack Xtreme', 'category' => 'cpu', 'module' => 'bench', 'coverage' => 'beta', 'coverage_note' => 'Linpack-style CPU benchmark in Toolkit'],
        ['id' => 'cpuz_bench', 'name' => 'CPU-Z Benchmark', 'category' => 'cpu', 'module' => 'bench', 'coverage' => 'import', 'coverage_note' => 'CPU-Z TXT import + native single/multi score'],

        // GPU benchmarks & stress (10)
        ['id' => '3dmark', 'name' => '3DMark', 'category' => 'gpu', 'module' => 'bench', 'coverage' => 'import', 'coverage_note' => 'Import 3DMark XML; native Vulkan compute bench (beta)'],
        ['id' => 'superposition', 'name' => 'Unigine Superposition', 'category' => 'gpu', 'module' => 'bench', 'coverage' => 'import', 'coverage_note' => 'Import Unigine logs + GPU compute stress'],
        ['id' => 'heaven', 'name' => 'Unigine Heaven', 'category' => 'gpu', 'module' => 'bench', 'coverage' => 'import', 'coverage_note' => 'Import benchmark logs'],
        ['id' => 'valley', 'name' => 'Unigine Valley', 'category' => 'gpu', 'module' => 'bench', 'coverage' => 'import', 'coverage_note' => 'Import benchmark logs'],
        ['id' => 'furmark', 'name' => 'FurMark', 'category' => 'gpu', 'module' => 'stress', 'coverage' => 'orchestrate', 'coverage_note' => 'GPU thermal soak stress + optional FurMark launcher'],
        ['id' => 'kombustor', 'name' => 'MSI Kombustor', 'category' => 'gpu', 'module' => 'stress', 'coverage' => 'orchestrate', 'coverage_note' => 'GPU stress orchestration with telemetry'],
        ['id' => 'basemark_gpu', 'name' => 'Basemark GPU', 'category' => 'gpu', 'module' => 'bench', 'coverage' => 'planned', 'coverage_note' => 'Native Vulkan bench module'],
        ['id' => 'specviewperf', 'name' => 'SPECviewperf', 'category' => 'gpu', 'module' => 'bench', 'coverage' => 'import', 'coverage_note' => 'Enterprise import + workstation profile'],
        ['id' => 'octanebench', 'name' => 'OctaneBench', 'category' => 'gpu', 'module' => 'bench', 'coverage' => 'import', 'coverage_note' => 'Import OctaneBench results'],
        ['id' => 'vray', 'name' => 'V-Ray Benchmark', 'category' => 'gpu', 'module' => 'bench', 'coverage' => 'import', 'coverage_note' => 'Import V-Ray exports'],

        // RAM & memory (10)
        ['id' => 'memtest86', 'name' => 'MemTest86', 'category' => 'ram', 'module' => 'stress', 'coverage' => 'orchestrate', 'coverage_note' => 'Bootable USB guide + in-OS memory stress'],
        ['id' => 'testmem5', 'name' => 'TestMem5', 'category' => 'ram', 'module' => 'stress', 'coverage' => 'orchestrate', 'coverage_note' => 'Profile runner + telemetry during RAM test'],
        ['id' => 'karhu', 'name' => 'Karhu RAM Test', 'category' => 'ram', 'module' => 'stress', 'coverage' => 'beta', 'coverage_note' => 'Built-in memory stress with error detection'],
        ['id' => 'hci_memtest', 'name' => 'HCI MemTest', 'category' => 'ram', 'module' => 'stress', 'coverage' => 'beta', 'coverage_note' => 'Coverage-based RAM stress in Toolkit'],
        ['id' => 'memtest64', 'name' => 'MemTest64', 'category' => 'ram', 'module' => 'stress', 'coverage' => 'beta', 'coverage_note' => 'Quick in-OS memory test'],
        ['id' => 'aida64_mem', 'name' => 'AIDA64 Cache & Memory', 'category' => 'ram', 'module' => 'bench', 'coverage' => 'beta', 'coverage_note' => 'RAM latency/bandwidth bench in Telemetry'],
        ['id' => 'gsat', 'name' => 'GSAT', 'category' => 'ram', 'module' => 'stress', 'coverage' => 'orchestrate', 'coverage_note' => 'GSAT profile orchestration'],
        ['id' => 'passmark_ram', 'name' => 'PassMark RAM Benchmark', 'category' => 'ram', 'module' => 'bench', 'coverage' => 'beta', 'coverage_note' => 'Native memory bandwidth score'],
        ['id' => 'sandra_mem', 'name' => 'SiSoftware Sandra Memory', 'category' => 'ram', 'module' => 'bench', 'coverage' => 'import', 'coverage_note' => 'Import Sandra exports'],
        ['id' => 'linpack_mem', 'name' => 'Linpack Memory Stress', 'category' => 'ram', 'module' => 'stress', 'coverage' => 'beta', 'coverage_note' => 'Memory bandwidth stress module'],

        // Full-system (10)
        ['id' => 'pcmark10', 'name' => 'PCMark 10', 'category' => 'system', 'module' => 'bench', 'coverage' => 'import', 'coverage_note' => 'Composite PC Lab Kit system score + import'],
        ['id' => 'userbenchmark', 'name' => 'UserBenchmark', 'category' => 'system', 'module' => 'bench', 'coverage' => 'beta', 'coverage_note' => 'Local comparative scoring vs reference DB'],
        ['id' => 'novabench', 'name' => 'Novabench', 'category' => 'system', 'module' => 'bench', 'coverage' => 'beta', 'coverage_note' => 'Run all PC Lab Kit bench modules as one report'],
        ['id' => 'sandra', 'name' => 'SiSoftware Sandra', 'category' => 'system', 'module' => 'bench', 'coverage' => 'import', 'coverage_note' => 'Import Sandra suite exports'],
        ['id' => 'aida64_eng', 'name' => 'AIDA64 Engineer', 'category' => 'system', 'module' => 'system', 'coverage' => 'beta', 'coverage_note' => 'Deep telemetry + burn-in orchestration'],
        ['id' => 'burnintest', 'name' => 'BurnInTest', 'category' => 'system', 'module' => 'stress', 'coverage' => 'beta', 'coverage_note' => 'Multi-hour burn-in mode with unified log'],
        ['id' => 'crystalmark_retro', 'name' => 'CrystalMark Retro', 'category' => 'system', 'module' => 'bench', 'coverage' => 'planned', 'coverage_note' => 'Retro composite bench module'],
        ['id' => 'specworkstation', 'name' => 'SPECworkstation', 'category' => 'system', 'module' => 'bench', 'coverage' => 'import', 'coverage_note' => 'Enterprise workstation import'],
        ['id' => 'phoronix', 'name' => 'Phoronix Test Suite', 'category' => 'system', 'module' => 'bench', 'coverage' => 'orchestrate', 'coverage_note' => 'PTS profile runner (Linux) + import'],
        ['id' => 'anvil_storage', 'name' => "Anvil's Storage Utilities", 'category' => 'system', 'module' => 'storage', 'coverage' => 'import', 'coverage_note' => 'Storage score via DiskSpd + import'],

        // Monitoring (10)
        ['id' => 'hwinfo', 'name' => 'HWiNFO64', 'category' => 'monitor', 'module' => 'monitor', 'coverage' => 'live', 'coverage_note' => 'LibreHardwareMonitor + deep telemetry console'],
        ['id' => 'hwmonitor', 'name' => 'HWMonitor', 'category' => 'monitor', 'module' => 'monitor', 'coverage' => 'live', 'coverage_note' => 'Live sensor strip + telemetry gauges'],
        ['id' => 'ohm', 'name' => 'Open Hardware Monitor', 'category' => 'monitor', 'module' => 'monitor', 'coverage' => 'live', 'coverage_note' => 'Same LHM engine as PcLab Probe'],
        ['id' => 'lhm', 'name' => 'Libre Hardware Monitor', 'category' => 'monitor', 'module' => 'monitor', 'coverage' => 'live', 'coverage_note' => 'Bundled PcLabHwMon collector'],
        ['id' => 'gpuz', 'name' => 'GPU-Z', 'category' => 'monitor', 'module' => 'monitor', 'coverage' => 'live', 'coverage_note' => 'GPU inventory, VRAM, clocks, power sensors'],
        ['id' => 'cpuz', 'name' => 'CPU-Z', 'category' => 'monitor', 'module' => 'monitor', 'coverage' => 'live', 'coverage_note' => 'CPU/RAM/board inventory + TXT import'],
        ['id' => 'coretemp', 'name' => 'Core Temp', 'category' => 'monitor', 'module' => 'monitor', 'coverage' => 'live', 'coverage_note' => 'Per-core temperature in telemetry'],
        ['id' => 'realtemp', 'name' => 'Real Temp', 'category' => 'monitor', 'module' => 'monitor', 'coverage' => 'live', 'coverage_note' => 'Intel CPU thermal sensors via LHM'],
        ['id' => 'nzxt_cam', 'name' => 'NZXT CAM', 'category' => 'monitor', 'module' => 'monitor', 'coverage' => 'live', 'coverage_note' => 'Unified dashboard + OpenRGB device control'],
        ['id' => 'argus', 'name' => 'Argus Monitor', 'category' => 'monitor', 'module' => 'monitor', 'coverage' => 'live', 'coverage_note' => 'SMART, fan, and thermal alerts in lab report'],

        // Storage (10)
        ['id' => 'crystaldiskmark', 'name' => 'CrystalDiskMark', 'category' => 'storage', 'module' => 'storage', 'coverage' => 'beta', 'coverage_note' => 'DiskSpd / WinSAT seq & random bench'],
        ['id' => 'crystaldiskinfo', 'name' => 'CrystalDiskInfo', 'category' => 'storage', 'module' => 'storage', 'coverage' => 'live', 'coverage_note' => 'SMART health in telemetry + probe scan'],
        ['id' => 'atto', 'name' => 'ATTO Disk Benchmark', 'category' => 'storage', 'module' => 'storage', 'coverage' => 'beta', 'coverage_note' => 'Block-size sweep via DiskSpd profiles'],
        ['id' => 'as_ssd', 'name' => 'AS SSD Benchmark', 'category' => 'storage', 'module' => 'storage', 'coverage' => 'beta', 'coverage_note' => 'Seq/4K storage bench module'],
        ['id' => 'hdtune', 'name' => 'HD Tune Pro', 'category' => 'storage', 'module' => 'storage', 'coverage' => 'import', 'coverage_note' => 'SMART + benchmark import'],
        ['id' => 'fio', 'name' => 'fio', 'category' => 'storage', 'module' => 'storage', 'coverage' => 'orchestrate', 'coverage_note' => 'fio job runner + parse output (Linux/Windows)'],
        ['id' => 'diskspd', 'name' => 'DiskSpd', 'category' => 'storage', 'module' => 'storage', 'coverage' => 'beta', 'coverage_note' => 'Bundled storage benchmark orchestration'],
        ['id' => 'iometer', 'name' => 'Iometer', 'category' => 'storage', 'module' => 'storage', 'coverage' => 'orchestrate', 'coverage_note' => 'I/O workload profiles via DiskSpd/fio'],
        ['id' => 'blackmagic', 'name' => 'Blackmagic Disk Speed Test', 'category' => 'storage', 'module' => 'storage', 'coverage' => 'beta', 'coverage_note' => 'Large sequential read/write test'],
        ['id' => 'samsung_magician', 'name' => 'Samsung Magician', 'category' => 'storage', 'module' => 'storage', 'coverage' => 'live', 'coverage_note' => 'NVMe SMART + health via probe (vendor-agnostic)'],

        // RGB (10)
        ['id' => 'signalrgb', 'name' => 'SignalRGB', 'category' => 'rgb', 'module' => 'rgb', 'coverage' => 'live', 'coverage_note' => 'OpenRGB unified control + Orchestrator auto setup'],
        ['id' => 'openrgb', 'name' => 'OpenRGB', 'category' => 'rgb', 'module' => 'rgb', 'coverage' => 'live', 'coverage_note' => 'Bundled OpenRGB in PcLab Probe'],
        ['id' => 'icue', 'name' => 'iCUE', 'category' => 'rgb', 'module' => 'rgb', 'coverage' => 'live', 'coverage_note' => 'Corsair via OpenRGB (when supported)'],
        ['id' => 'synapse', 'name' => 'Razer Synapse', 'category' => 'rgb', 'module' => 'rgb', 'coverage' => 'live', 'coverage_note' => 'Razer devices via OpenRGB'],
        ['id' => 'armoury_crate', 'name' => 'ASUS Armoury Crate', 'category' => 'rgb', 'module' => 'rgb', 'coverage' => 'live', 'coverage_note' => 'ASUS ARGB via OpenRGB'],
        ['id' => 'mystic_light', 'name' => 'MSI Center Mystic Light', 'category' => 'rgb', 'module' => 'rgb', 'coverage' => 'live', 'coverage_note' => 'MSI boards/devices via OpenRGB'],
        ['id' => 'rgb_fusion', 'name' => 'Gigabyte RGB Fusion', 'category' => 'rgb', 'module' => 'rgb', 'coverage' => 'live', 'coverage_note' => 'Gigabyte via OpenRGB'],
        ['id' => 'polychrome', 'name' => 'ASRock Polychrome Sync', 'category' => 'rgb', 'module' => 'rgb', 'coverage' => 'live', 'coverage_note' => 'ASRock via OpenRGB'],
        ['id' => 'tt_rgb', 'name' => 'Thermaltake TT RGB Plus', 'category' => 'rgb', 'module' => 'rgb', 'coverage' => 'live', 'coverage_note' => 'TT devices via OpenRGB'],
        ['id' => 'lconnect', 'name' => 'L-Connect 3', 'category' => 'rgb', 'module' => 'rgb', 'coverage' => 'live', 'coverage_note' => 'Lian Li fans/pumps via OpenRGB + LCD upload'],

        // AIO LCD & sensor panels (10)
        ['id' => 'nzxt_lcd', 'name' => 'NZXT CAM LCD', 'category' => 'lcd', 'module' => 'lcd', 'coverage' => 'live', 'coverage_note' => 'Pump LCD GIF upload (local only)'],
        ['id' => 'icue_lcd', 'name' => 'Corsair iCUE LCD', 'category' => 'lcd', 'module' => 'lcd', 'coverage' => 'live', 'coverage_note' => 'AIO LCD via Probe RGB/LCD API'],
        ['id' => 'lconnect_lcd', 'name' => 'L-Connect 3 LCD', 'category' => 'lcd', 'module' => 'lcd', 'coverage' => 'live', 'coverage_note' => 'Lian Li screen GIF + sensor layout'],
        ['id' => 'aida64_panel', 'name' => 'AIDA64 SensorPanel', 'category' => 'lcd', 'module' => 'lcd', 'coverage' => 'beta', 'coverage_note' => 'Telemetry console + Sensor Deck (beta)'],
        ['id' => 'rainmeter', 'name' => 'Rainmeter', 'category' => 'lcd', 'module' => 'lcd', 'coverage' => 'live', 'coverage_note' => 'Export sensor skins from Sensor Deck'],
        ['id' => 'hwinfo_sm', 'name' => 'HWiNFO Shared Memory', 'category' => 'lcd', 'module' => 'lcd', 'coverage' => 'live', 'coverage_note' => 'Shared-memory sensor JSON writer GET /integrations/hwinfo-sm'],
        ['id' => 'wallpaper_engine', 'name' => 'Wallpaper Engine', 'category' => 'lcd', 'module' => 'lcd', 'coverage' => 'planned', 'coverage_note' => 'Sensor-linked wallpaper hooks'],
        ['id' => 'stream_deck', 'name' => 'Stream Deck', 'category' => 'lcd', 'module' => 'lcd', 'coverage' => 'planned', 'coverage_note' => 'Live sensor tiles plugin'],
        ['id' => 'aquasuite', 'name' => 'Aquasuite', 'category' => 'lcd', 'module' => 'lcd', 'coverage' => 'beta', 'coverage_note' => 'Custom loop telemetry + LCD layouts'],
        ['id' => 'turing_smart', 'name' => 'Turing Smart Screen', 'category' => 'lcd', 'module' => 'lcd', 'coverage' => 'planned', 'coverage_note' => 'USB mini-panel driver integration'],
    ],
];
