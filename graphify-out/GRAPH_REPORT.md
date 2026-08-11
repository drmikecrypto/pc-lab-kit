# Graph Report - pc-lab-kit  (2026-08-11)

## Corpus Check
- 178 files · ~1,034,082 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1219 nodes · 2074 edges · 135 communities (90 shown, 45 thin omitted)
- Extraction: 91% EXTRACTED · 9% INFERRED · 0% AMBIGUOUS · INFERRED: 189 edges (avg confidence: 0.78)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `8dd38c09`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Native Core CLI Sensors
- Benchmark Dataset Service
- Database & History
- Docs Product Concepts
- Flutter Device Packages
- Diagnostic Agent Services
- Flutter PC Test Page
- Telemetry & Games Commands
- Web Diagnostic Controllers
- Mobile Diagnostic API
- Flutter Brand & Routes
- Diagnostic AI Service
- Native Probe Client
- Toolkit Coverage Page
- Flutter Page Routes
- Benchmark Pricing
- Native Main Window
- Diagnostic Core Service
- Native Sensor Client
- Telemetry Panel Builder
- Probe RGB OpenRGB
- Linux Sensor Collector
- Windows Setup Form UI
- Native Monitor Page
- Probe Device Inventory
- Native Scan Page
- Probe Common Utils
- Diagnostic Import Service
- Live Diagnostic JS
- App Update Service
- Diagnostic RGB Service
- RGB Diagnostic JS
- Bootstrap PHP Tools
- Tool Catalog Service
- Native Settings Page
- Native Settings Store
- Pulse Diagnostic JS
- Composer Manifest Meta
- Flutter Brand Tokens
- Lab Diagnostic JS
- Probe Drivers Lib
- Probe GPU NVIDIA
- Flutter Lab Pages
- Telemetry Charts JS
- Vakhsh Lighting Service
- Probe Overclock Lib
- Composer PHP Deps
- Linux Setup UI
- Bootstrap Build Tools
- Frametime PresentMon
- Main Window Styling
- Probe Benchmark Lib
- gpu.ps1
- Windows Setup Installer
- Linux Native Setup UI
- OC Diagnostic JS
- Settings Diagnostic JS
- RAM SPD Probe
- Probe Stress Lib
- PcVerseHwMon C#
- ProbeServe Helpers
- Composer Plugin Config
- Composer Autoload
- App Update JS
- Bootstrap Qt Shell
- Windows Native Installer
- Probe CIM Helpers
- Admin Settings Service
- Composer Dev Autoload
- Setup Project File
- Compare Diagnostic JS
- Linux Installer Script
- Linux Native Installer
- Deploy Qt Linux
- stage-app-payload.sh
- bundle
- Install Shell Script
- package.json
- Start Shell Script
- compilerOptions
- Contributor Hasti
- Contributor Taha
- DiagnosticHistoryCompareService
- stress.ps1
- default.json
- main.ts
- build-desktop-linux.sh
- stage-desktop-payload.sh script
- DiagnosticApiController.php
- web.php
- DiagnosticIntelligencePulseService
- DiagnosticConsultantService
- Get-RamSpdTelemetry
- .__invoke
- diagnostic-sensor-deck.js
- HardwareKnowledgeGraphService.php
- LabFeaturesTest.php
- AmbitiousUpgradeTest
- SensorDeckService
- Contributing to PC Lab Kit
- INTEGRATION.md
- diagnostic-launchers.js
- PC Lab Kit Desktop
- Executive vision
- diagnostic-topology.js
- How it fits together
- suite-smoke.spec.js

## God Nodes (most connected - your core abstractions)
1. `DiagnosticApiController` - 41 edges
2. `BenchmarkDatasetService` - 36 edges
3. `json_response()` - 36 edges
4. `DiagnosticService` - 33 edges
5. `DiagnosticHistoryService` - 27 edges
6. `Database` - 25 edges
7. `DiagnosticTelemetryService` - 23 edges
8. `DiagnosticGameCatalogService` - 22 edges
9. `decode_json_body_limited()` - 22 edges
10. `Get-CimSafe()` - 20 edges

## Surprising Connections (you probably didn't know these)
- `diagnostic_reports_cleanup_test_rows()` --calls--> `Database`  [INFERRED]
  tests/Unit/DiagnosticHistoryServiceTest.php → app/Database.php
- `diagnostic_reports_ensure_sqlite_table()` --calls--> `Database`  [INFERRED]
  tests/Unit/DiagnosticHistoryServiceTest.php → app/Database.php
- `runTest()` --indirect_call--> `e()`  [INFERRED]
  public/assets/js/diagnostic-toolkit.js → app/helpers.php
- `Get-ProbeCpuCacheDetail()` --calls--> `Get-CimSafe()`  [INFERRED]
  agent/pclab_probe/ProbeLib/cpu.ps1 → agent/pclab_probe/ProbeLib/common.ps1
- `Get-ProbeCpuTelemetry()` --calls--> `Get-CimSafe()`  [INFERRED]
  agent/pclab_probe/ProbeLib/cpu.ps1 → agent/pclab_probe/ProbeLib/common.ps1

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Native CMake build graph (root → core → apps)** — native_cmakelists_pcverse_native, native_core_cmakelists_pcverse_core, native_apps_pcverse_cli_cmakelists_pcverse_cli, native_apps_pcverse_cmakelists_pcverse_desktop [EXTRACTED 1.00]
- **Cross-platform installer release pipeline** — github_workflows_release_bundles_release_installers, readme_windows_installer, readme_linux_installer [EXTRACTED 1.00]

## Communities (135 total, 45 thin omitted)

### Community 0 - "Native Core CLI Sensors"
Cohesion: 0.21
Nodes (13): Get-AmdSoftwareInfo(), Get-ProbeAmdGpuTelemetry(), Get-CounterSafe(), Get-ProbeCstateTelemetry(), Get-ProbeMotherboardTelemetry(), Get-ProbeRamTelemetry(), Get-ProbeStorageTelemetry(), Get-ProbeDeepTelemetry() (+5 more)

### Community 1 - "Benchmark Dataset Service"
Cohesion: 0.08
Nodes (3): BenchmarkDatasetService, BenchmarkService, self

### Community 2 - "Database & History"
Cohesion: 0.07
Nodes (8): AppUpdateController, Database, DiagnosticHistoryService, DiagnosticIntelligencePulseService, PDO, PDOException, diagnostic_reports_cleanup_test_rows(), diagnostic_reports_ensure_sqlite_table()

### Community 3 - "Docs Product Concepts"
Cohesion: 0.83
Nodes (4): pcverse_cli executable, pcverse Qt desktop executable, pcverse_native CMake project, pcverse_core static library target

### Community 4 - "Flutter Device Packages"
Cohesion: 0.22
Nodes (7): Build desktop installers, Docs, Download (end users), License, Optional AI advisor (BYOK), Quick start (developers), Tests

### Community 5 - "Diagnostic Agent Services"
Cohesion: 0.09
Nodes (5): DiagnosticInventoryService, HardwareKnowledgeGraphService, LabReportExportService, StressCertificateService, ToonSerializer

### Community 6 - "Flutter PC Test Page"
Cohesion: 0.20
Nodes (23): Compare-ProbeDriverVersion(), ConvertFrom-ProbeHardwareId(), Get-ProbeDeviceDrivers(), Get-ProbeDriverAdvice(), Get-ProbeDriverAgeDays(), Get-ProbeDriverCacheDir(), Get-ProbeDriverCatalog(), Get-ProbeDriverInstallStatus() (+15 more)

### Community 7 - "Telemetry & Games Commands"
Cohesion: 0.11
Nodes (8): TrackUserEventAction, DiagnosticGamesRefreshCommand, DiagnosticGameCatalogService, Log, Client, Command, InputInterface, OutputInterface

### Community 8 - "Web Diagnostic Controllers"
Cohesion: 0.14
Nodes (33): Arc, Child, copy_dir_recursive(), ensure_lab_ready(), http_get_ok(), LabRuntime, pick_free_port(), prepare_work_dir() (+25 more)

### Community 9 - "Mobile Diagnostic API"
Cohesion: 0.12
Nodes (4): DiagnosticApiController, SettingsApiController, decode_json_body_limited(), json_response()

### Community 10 - "Flutter Brand & Routes"
Cohesion: 0.20
Nodes (19): Export-ProbeFanCurves(), Get-ProbeDataDir(), Invoke-ProbeOrchestrate(), Invoke-ProbeRgbAuto(), Map-RgbZonesFromPlan(), Write-ProbeLcdDashboard(), Get-OpenRgbDeviceList(), Get-OpenRgbExecutable() (+11 more)

### Community 11 - "Diagnostic AI Service"
Cohesion: 0.08
Nodes (4): DownloadController, DiagnosticAiService, LlmService, SettingsService

### Community 12 - "Native Probe Client"
Cohesion: 0.17
Nodes (12): Assumptions, Critical gap, Immediate next steps, Module map: 80 tools → PC Lab Kit modules, PC Lab Kit → The Unified Local PC Laboratory, Recommended start, Replace strategy by category, Shipped vs planned (2026-08) (+4 more)

### Community 13 - "Toolkit Coverage Page"
Cohesion: 0.33
Nodes (11): Get-ProbeOcSample(), Get-ProbeOcState(), Get-ProbeOcStorePath(), Get-ProbeOcWatchPath(), Invoke-ProbeOcPreflight(), Invoke-ProbeOcWatch(), Invoke-ProbeOverclockApply(), Invoke-ProbeOverclockRollback() (+3 more)

### Community 14 - "Flutter Page Routes"
Cohesion: 0.18
Nodes (11): AIO LCD Screens, Sensor Panels & GIF Displays, CPU Benchmarks & Stress Tests, Enterprise / OEM validation (common stacks), Full-System Benchmarks, GPU Benchmarks & Stress Tests, Honest scope: replacing 80 tools, RAM & Memory Testing, Reference: 80-tool categories (+3 more)

### Community 15 - "Benchmark Pricing"
Cohesion: 0.67
Nodes (3): Added, Removed, [Unreleased]

### Community 21 - "Linux Sensor Collector"
Cohesion: 0.14
Nodes (23): Find-ProbeDiskSpd(), Invoke-ProbeBenchmark(), Invoke-ProbeCpuBenchmark(), Invoke-ProbeGpuBenchmark(), Invoke-ProbeMemoryBenchmark(), Invoke-ProbeStorageBenchmark(), Get-ProbeExternalLaunchers(), Invoke-ProbeExternalLauncher() (+15 more)

### Community 22 - "Windows Setup Form UI"
Cohesion: 0.25
Nodes (8): Phase 0 — Foundation (2–3 weeks), Phase 1 — Desktop shell (3–4 weeks), Phase 2 — Native benchmarks (4–6 weeks), Phase 3 — Stress orchestration (3–4 weeks), Phase 4 — AI + Knowledge Graph (3–4 weeks), Phase 5 — RGB + Sensor Deck (3–4 weeks), Phase 6 — Enterprise mode (optional), Phased roadmap

### Community 23 - "Native Monitor Page"
Cohesion: 0.29
Nodes (6): agent/, backend (PHP), downloads (built, gitignored), launchers, Not in this repository, scripts/

### Community 24 - "Probe Device Inventory"
Cohesion: 0.33
Nodes (6): Advisor outputs (specialist-grade), AI advisor architecture (the differentiator), Existing AI integration, Pipeline, Principles, Supported AI providers (target)

### Community 25 - "Native Scan Page"
Cohesion: 0.33
Nodes (6): PHP migration path, Recommended architecture (standalone + GitHub-friendly), Target stack, Three surfaces, one stack (current → target), Why keep the agent separate, Why Tauri over pure Flutter for v1 OSS launch

### Community 27 - "Probe Common Utils"
Cohesion: 0.50
Nodes (4): Agent endpoints (`PcLabProbeServe.ps1`), API routes (to extract), Appendix: existing kit inventory, Benchmark datasets (19 JSON files)

### Community 28 - "Diagnostic Import Service"
Cohesion: 0.24
Nodes (19): Get-CimSafe(), ConvertFrom-PnpDeviceId(), ConvertFrom-ProbeEdidBytes(), Get-ProbeAudioDevices(), Get-ProbeBatteryDetail(), Get-ProbeBluetoothDevices(), Get-ProbeConfigManagerMessage(), Get-ProbeDeviceCategory() (+11 more)

### Community 29 - "Live Diagnostic JS"
Cohesion: 0.25
Nodes (18): animateNum(), esc(), fetchLive(), formatSample(), fpQuery(), installDriver(), loadReport(), pollAgentSensors() (+10 more)

### Community 31 - "Diagnostic RGB Service"
Cohesion: 0.10
Nodes (19): DiagnosticController, e(), view(), Router, View, esc(), issueCertificate(), loadCatalog() (+11 more)

### Community 32 - "RGB Diagnostic JS"
Cohesion: 0.27
Nodes (14): applyZones(), effectOptions(), esc(), getContext(), getTelemetry(), jsonHeadersWithCsrf(), orchestratorProSetup(), parseGifDimensions() (+6 more)

### Community 33 - "Bootstrap PHP Tools"
Cohesion: 0.30
Nodes (12): Copy-BundledPhpToStage(), Get-BuildDepsConfig(), Get-BuildDepsRoot(), Get-BuildPhpExe(), Get-BundledWindowsPhpDir(), Initialize-BuildCacheDir(), Initialize-BuildTools(), Initialize-BundledComposer() (+4 more)

### Community 35 - "Native Settings Page"
Cohesion: 0.50
Nodes (4): Brand evolution, Design system: from dull sketch to engineering showcase, Motion principles, UI pillars

### Community 36 - "Native Settings Store"
Cohesion: 0.50
Nodes (4): Launch checklist for GitHub impact, Naming, Open-source & GitHub growth strategy, Target repo structure (monorepo)

### Community 37 - "Pulse Diagnostic JS"
Cohesion: 0.26
Nodes (10): Get-ProbeCoreTopology(), Get-ProbeProcessorFeatures(), Guess-InstructionSets(), Initialize-ProbeNativeInterop(), KelvinToC(), Parse-FeatureSet(), Get-ProbeCpuCacheDetail(), Get-ProbeCpuCodename() (+2 more)

### Community 39 - "Composer Manifest Meta"
Cohesion: 0.06
Nodes (31): pestphp/pest-plugin, autoload, autoload-dev, psr-4, files, psr-4, config, allow-plugins (+23 more)

### Community 41 - "Lab Diagnostic JS"
Cohesion: 0.36
Nodes (10): esc(), escAttr(), jsonHeadersWithCsrf(), loadGames(), parseApiResponse(), renderStep(), runFullScan(), selectOption() (+2 more)

### Community 42 - "Probe Drivers Lib"
Cohesion: 0.67
Nodes (3): Already implemented philosophy, Enhancements for v1 launch, One-click OC (safe, real, bounded)

### Community 43 - "Probe GPU NVIDIA"
Cohesion: 0.67
Nodes (3): Release installers workflow, PCVerse-Setup-Linux-x64.run, PCVerse-Setup-Windows-x64.exe

### Community 45 - "Telemetry Charts JS"
Cohesion: 0.12
Nodes (15): DiagnosticDriverAdvisorService, DriverPackageMatcherService, animateNum(), delay(), el(), ensureFp(), esc(), gpuScoreBucket() (+7 more)

### Community 52 - "Bootstrap Build Tools"
Cohesion: 0.32
Nodes (4): ensure_build_tools(), ensure_cache(), ensure_composer_phar(), bootstrap-build-tools.sh script

### Community 56 - "gpu.ps1"
Cohesion: 0.32
Nodes (12): New-ProbeField(), ConvertTo-NvNumber(), ConvertTo-NvText(), Get-GpuRegistryStatic(), Get-GpuVramFromRegistry(), Get-NvidiaGpuList(), Get-NvidiaSmiTemperatureDetail(), Get-NvidiaThrottleReasons() (+4 more)

### Community 59 - "OC Diagnostic JS"
Cohesion: 0.38
Nodes (10): applyOc(), countdown(), esc(), exportOcReport(), onScanComplete(), renderOcPanel(), rollbackOc(), runPreflight() (+2 more)

### Community 60 - "Settings Diagnostic JS"
Cohesion: 0.38
Nodes (4): csrfHeaders(), load(), open(), save()

### Community 63 - "PcVerseHwMon C#"
Cohesion: 0.50
Nodes (3): net8.0-windows, LibreHardwareMonitorLib (0.9.4), Microsoft.NET.Sdk

### Community 67 - "App Update JS"
Cohesion: 0.42
Nodes (9): applyUpdateUi(), checkUpdate(), clearDismiss(), esc(), focusUpdateUi(), hideUpdateUi(), isDismissed(), platformDownload() (+1 more)

### Community 83 - "bundle"
Cohesion: 0.07
Nodes (29): app, security, windows, withGlobalTauri, bundleMediaFramework, build, beforeBuildCommand, beforeDevCommand (+21 more)

### Community 85 - "package.json"
Cohesion: 0.12
Nodes (16): dependencies, @tauri-apps/api, @tauri-apps/plugin-opener, devDependencies, @tauri-apps/cli, typescript, vite, name (+8 more)

### Community 87 - "compilerOptions"
Cohesion: 0.12
Nodes (16): compilerOptions, allowImportingTsExtensions, isolatedModules, lib, module, moduleResolution, noEmit, noFallthroughCasesInSwitch (+8 more)

### Community 101 - "stress.ps1"
Cohesion: 0.15
Nodes (12): [1.0.0] - 2026-06-14, [3.0.0] - 2026-07-30, [3.1.0] - 2026-08-01, [3.1.1] - 2026-08-04, Added, Added, Added, Added (+4 more)

### Community 102 - "default.json"
Cohesion: 0.33
Nodes (5): description, identifier, permissions, $schema, windows

### Community 116 - "DiagnosticApiController.php"
Cohesion: 0.38
Nodes (12): Find-ProbeGpuSensorNode(), Get-ProbeCpuTjMax(), Get-ProbeGpuThermalFindings(), Get-ProbeGpuThermalHealth(), Get-ProbeGpuThermalLimits(), Get-ProbeSensorValue(), Get-ProbeVendorTag(), New-ProbeHeadroom() (+4 more)

### Community 118 - "DiagnosticIntelligencePulseService"
Cohesion: 0.42
Nodes (11): boot(), cancelSuite(), csrfHeaders(), el(), esc(), fp(), pollProbeSuite(), renderCards() (+3 more)

### Community 119 - "DiagnosticConsultantService"
Cohesion: 0.42
Nodes (12): activeFilters(), bind(), el(), esc(), exportJson(), loadTopology(), matchesFilters(), refreshInventory() (+4 more)

### Community 120 - "Get-RamSpdTelemetry"
Cohesion: 0.05
Nodes (8): DiagnosticAgentService, DiagnosticConsultantService, DiagnosticOcService, DiagnosticRgbService, SensorDeckService, TopologyViewService, TestCase, AmbitiousUpgradeTest

### Community 121 - ".__invoke"
Cohesion: 0.22
Nodes (9): Does anything leave my PC?, Does the lab open in my browser?, FAQ — PC Lab Kit, How do I get CPU temperatures?, License, What is this?, What is this product?, Where do I download the app? (+1 more)

### Community 122 - "diagnostic-sensor-deck.js"
Cohesion: 0.44
Nodes (8): boot(), csrfHeaders(), exportLayout(), loadLayout(), pick(), render(), saveLayout(), tick()

### Community 123 - "HardwareKnowledgeGraphService.php"
Cohesion: 0.36
Nodes (12): drawCstateBars(), drawSparklines(), drawSpikeMap(), driverSectionsFromPresent(), esc(), fetchDriversAndPresent(), fetchHistory(), fetchTelemetry() (+4 more)

### Community 124 - "LabFeaturesTest.php"
Cohesion: 0.48
Nodes (5): Build-FrametimeSpikeMap(), Find-CapFrameXExports(), Get-FrametimeTelemetry(), Parse-CapFrameXFrametimes(), Get-ProbePresentMonTelemetry()

### Community 125 - "AmbitiousUpgradeTest"
Cohesion: 0.57
Nodes (6): Find-CpuZExports(), Get-RamFormFactorName(), Get-RamMemoryTypeName(), Get-RamSpdTelemetry(), Parse-CpuZMemoryBlock(), Resolve-RamDieType()

### Community 126 - "SensorDeckService"
Cohesion: 0.60
Nodes (4): Test-ProbeElevated(), Find-Sensors(), Find-SensorValue(), Get-ProbeHwMonTelemetry()

### Community 127 - "Contributing to PC Lab Kit"
Cohesion: 0.33
Nodes (5): Before you start, Contributing to PC Lab Kit, Development setup, Pull requests, Reporting bugs

### Community 128 - "INTEGRATION.md"
Cohesion: 0.29
Nodes (6): Lab suite API (PHP), Layout, Probe HTTP API (localhost:18765), Product identity, Standalone flow, Web routes

### Community 130 - "diagnostic-launchers.js"
Cohesion: 0.70
Nodes (4): boot(), esc(), refresh(), run()

### Community 132 - "PC Lab Kit Desktop"
Cohesion: 0.50
Nodes (3): Build installers, Develop, PC Lab Kit Desktop

### Community 133 - "Executive vision"
Cohesion: 0.67
Nodes (3): Core principles, Executive vision, Positioning for GitHub

### Community 135 - "How it fits together"
Cohesion: 0.67
Nodes (3): Driver matching, How it fits together, In-app updates

## Knowledge Gaps
- **202 isolated node(s):** `net8.0-windows`, `LibreHardwareMonitorLib (0.9.4)`, `Microsoft.NET.Sdk`, `name`, `description` (+197 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **45 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `DiagnosticService` connect `Diagnostic Core Service` to `Get-RamSpdTelemetry`, `Benchmark Dataset Service`, `Diagnostic AI Service`, `Diagnostic RGB Service`?**
  _High betweenness centrality (0.045) - this node is a cross-community bridge._
- **Why does `DiagnosticImportService` connect `Native Main Window` to `Get-RamSpdTelemetry`?**
  _High betweenness centrality (0.026) - this node is a cross-community bridge._
- **Why does `DiagnosticApiController` connect `Mobile Diagnostic API` to `Get-RamSpdTelemetry`?**
  _High betweenness centrality (0.025) - this node is a cross-community bridge._
- **Are the 35 inferred relationships involving `json_response()` (e.g. with `.check()` and `.diagnosticAgent()`) actually correct?**
  _`json_response()` has 35 INFERRED edges - model-reasoned connections that need verification._
- **What connects `net8.0-windows`, `LibreHardwareMonitorLib (0.9.4)`, `Microsoft.NET.Sdk` to the rest of the system?**
  _206 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Benchmark Dataset Service` be split into smaller, more focused modules?**
  _Cohesion score 0.07591836734693877 - nodes in this community are weakly interconnected._
- **Should `Database & History` be split into smaller, more focused modules?**
  _Cohesion score 0.06896551724137931 - nodes in this community are weakly interconnected._