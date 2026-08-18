# Graph Report - pc-lab-kit  (2026-08-18)

## Corpus Check
- 199 files · ~1,048,685 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1392 nodes · 2350 edges · 137 communities (82 shown, 55 thin omitted)
- Extraction: 91% EXTRACTED · 9% INFERRED · 0% AMBIGUOUS · INFERRED: 201 edges (avg confidence: 0.79)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `d255c994`
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
- diagnostic-telemetry.js
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
- Program
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
- Native Update Controller
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
- README.md
- diagnostic-sensor-deck.js
- HardwareKnowledgeGraphService.php
- LabFeaturesTest.php
- AmbitiousUpgradeTest
- SensorDeckService
- README.md
- SensorDeckService
- diagnostic-launchers.js
- diagnostic-openbook.js
- AssemblyCertificateService
- Executive vision
- diagnostic-topology.js
- How it fits together
- suite-smoke.spec.js

## God Nodes (most connected - your core abstractions)
1. `DiagnosticApiController` - 43 edges
2. `json_response()` - 38 edges
3. `BenchmarkDatasetService` - 36 edges
4. `DiagnosticService` - 33 edges
5. `DiagnosticHistoryService` - 27 edges
6. `Database` - 25 edges
7. `decode_json_body_limited()` - 24 edges
8. `DiagnosticTelemetryService` - 23 edges
9. `DiagnosticGameCatalogService` - 22 edges
10. `Get-CimSafe()` - 20 edges

## Surprising Connections (you probably didn't know these)
- `runTest()` --indirect_call--> `e()`  [INFERRED]
  public/assets/js/diagnostic-toolkit.js → app/helpers.php
- `diagnostic_reports_cleanup_test_rows()` --calls--> `Database`  [INFERRED]
  tests/Unit/DiagnosticHistoryServiceTest.php → app/Database.php
- `diagnostic_reports_ensure_sqlite_table()` --calls--> `Database`  [INFERRED]
  tests/Unit/DiagnosticHistoryServiceTest.php → app/Database.php
- `Get-ProbeCpuCacheDetail()` --calls--> `Get-CimSafe()`  [INFERRED]
  agent/pclab_probe/ProbeLib/cpu.ps1 → agent/pclab_probe/ProbeLib/common.ps1
- `Get-ProbeCpuTelemetry()` --calls--> `Get-CimSafe()`  [INFERRED]
  agent/pclab_probe/ProbeLib/cpu.ps1 → agent/pclab_probe/ProbeLib/common.ps1

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Native CMake build graph (root → core → apps)** — native_cmakelists_pcverse_native, native_core_cmakelists_pcverse_core, native_apps_pcverse_cli_cmakelists_pcverse_cli, native_apps_pcverse_cmakelists_pcverse_desktop [EXTRACTED 1.00]
- **Cross-platform installer release pipeline** — github_workflows_release_bundles_release_installers, readme_windows_installer, readme_linux_installer [EXTRACTED 1.00]

## Communities (137 total, 55 thin omitted)

### Community 0 - "Native Core CLI Sensors"
Cohesion: 0.05
Nodes (65): Get-AmdSoftwareInfo(), Get-ProbeAmdGpuTelemetry(), Get-CounterSafe(), Get-ProbeCoreTopology(), Get-ProbeProcessorFeatures(), Guess-InstructionSets(), Initialize-ProbeNativeInterop(), KelvinToC() (+57 more)

### Community 1 - "Benchmark Dataset Service"
Cohesion: 0.08
Nodes (3): BenchmarkDatasetService, BenchmarkService, self

### Community 2 - "Database & History"
Cohesion: 0.08
Nodes (7): Database, DiagnosticHistoryService, DiagnosticIntelligencePulseService, PDO, PDOException, diagnostic_reports_cleanup_test_rows(), diagnostic_reports_ensure_sqlite_table()

### Community 3 - "Docs Product Concepts"
Cohesion: 0.83
Nodes (4): pcverse_cli executable, pcverse Qt desktop executable, pcverse_native CMake project, pcverse_core static library target

### Community 4 - "Flutter Device Packages"
Cohesion: 0.05
Nodes (40): Before you start, Contributing to PC Lab Kit, Development setup, Pull requests, Reporting bugs, Build installers, Develop, PC Lab Kit Desktop (+32 more)

### Community 5 - "Diagnostic Agent Services"
Cohesion: 0.09
Nodes (5): DiagnosticInventoryService, HardwareKnowledgeGraphService, LabReportExportService, StressCertificateService, ToonSerializer

### Community 6 - "Flutter PC Test Page"
Cohesion: 0.11
Nodes (42): Get-CimSafe(), ConvertFrom-PnpDeviceId(), ConvertFrom-ProbeEdidBytes(), Get-ProbeAudioDevices(), Get-ProbeBatteryDetail(), Get-ProbeBluetoothDevices(), Get-ProbeConfigManagerMessage(), Get-ProbeDeviceCategory() (+34 more)

### Community 7 - "Telemetry & Games Commands"
Cohesion: 0.11
Nodes (8): TrackUserEventAction, DiagnosticGamesRefreshCommand, DiagnosticGameCatalogService, Log, Client, Command, InputInterface, OutputInterface

### Community 8 - "Web Diagnostic Controllers"
Cohesion: 0.12
Nodes (38): AppHandle, Arc, Child, copy_dir_recursive(), ensure_lab_ready(), http_get_ok(), LabRuntime, pick_free_port() (+30 more)

### Community 9 - "Mobile Diagnostic API"
Cohesion: 0.11
Nodes (4): DiagnosticApiController, SettingsApiController, decode_json_body_limited(), json_response()

### Community 10 - "Flutter Brand & Routes"
Cohesion: 0.16
Nodes (28): Export-ProbeFanCurves(), Get-ProbeDataDir(), Invoke-ProbeOrchestrate(), Invoke-ProbeRgbAuto(), Map-RgbZonesFromPlan(), Write-ProbeLcdDashboard(), Get-OpenRgbDeviceList(), Get-OpenRgbExecutable() (+20 more)

### Community 11 - "Diagnostic AI Service"
Cohesion: 0.10
Nodes (3): DiagnosticAiService, LlmService, SettingsService

### Community 12 - "Native Probe Client"
Cohesion: 0.17
Nodes (12): Assumptions, Critical gap (historical — resolved), Immediate next steps, Module map: 80 tools → PC Lab Kit modules, PC Lab Kit → The Unified Local PC Laboratory, Recommended focus, Replace strategy by category, Shipped vs planned (2026-08) (+4 more)

### Community 13 - "Toolkit Coverage Page"
Cohesion: 0.33
Nodes (11): Get-ProbeOcSample(), Get-ProbeOcState(), Get-ProbeOcStorePath(), Get-ProbeOcWatchPath(), Invoke-ProbeOcPreflight(), Invoke-ProbeOcWatch(), Invoke-ProbeOverclockApply(), Invoke-ProbeOverclockRollback() (+3 more)

### Community 14 - "Flutter Page Routes"
Cohesion: 0.18
Nodes (11): AIO LCD Screens, Sensor Panels & GIF Displays, Capability scope: replace the workflow (and exceed it), CPU Benchmarks & Stress Tests, Enterprise / OEM validation (common stacks), Full-System Benchmarks, GPU Benchmarks & Stress Tests, RAM & Memory Testing, Reference: 80-tool categories (+3 more)

### Community 15 - "diagnostic-telemetry.js"
Cohesion: 0.26
Nodes (13): animateNum(), delay(), el(), ensureFp(), esc(), gpuScoreBucket(), initSynapseCanvas(), metaFromScan() (+5 more)

### Community 21 - "Linux Sensor Collector"
Cohesion: 0.12
Nodes (27): Find-ProbeDiskSpd(), Find-ProbeVkBench(), Get-DiskSpdTotalMbps(), Invoke-ProbeBenchmark(), Invoke-ProbeCpuBenchmark(), Invoke-ProbeCpuCacheBenchmark(), Invoke-ProbeGpuBenchmark(), Invoke-ProbeGpuBenchmarkFallback() (+19 more)

### Community 22 - "Windows Setup Form UI"
Cohesion: 0.25
Nodes (8): Phase 0 — Foundation (2–3 weeks), Phase 1 — Desktop shell (3–4 weeks), Phase 2 — Native benchmarks (4–6 weeks), Phase 3 — Stress orchestration (3–4 weeks), Phase 4 — AI + Knowledge Graph (3–4 weeks), Phase 5 — RGB + Sensor Deck (3–4 weeks), Phase 6 — Enterprise mode (optional) — backlog, Phased roadmap

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
Cohesion: 0.30
Nodes (14): esc(), issueCertificate(), loadCatalog(), prettyResult(), probeHealth(), renderCatalog(), renderCertificate(), renderFilters() (+6 more)

### Community 29 - "Live Diagnostic JS"
Cohesion: 0.25
Nodes (18): animateNum(), esc(), fetchLive(), formatSample(), fpQuery(), installDriver(), loadReport(), pollAgentSensors() (+10 more)

### Community 30 - "App Update Service"
Cohesion: 0.06
Nodes (9): AppUpdateController, DiagnosticController, DownloadController, e(), view(), Router, AppUpdateService, Env (+1 more)

### Community 31 - "Program"
Cohesion: 0.27
Nodes (6): string, Program, PcLabVkBench, Dictionary, ID3D11Device, ID3D11DeviceContext

### Community 32 - "RGB Diagnostic JS"
Cohesion: 0.22
Nodes (18): applyZones(), blinkControlsHtml(), blinkDefaults(), conflictBanner(), effectOptions(), esc(), getContext(), getTelemetry() (+10 more)

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
Cohesion: 0.33
Nodes (5): net8.0-windows, Microsoft.NET.Sdk, Vortice.D3DCompiler (3.6.2), Vortice.Direct3D11 (3.6.2), Vortice.DXGI (3.6.2)

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
Cohesion: 0.14
Nodes (14): DiagnosticDriverAdvisorService, DriverPackageMatcherService, drawCstateBars(), drawSparklines(), drawSpikeMap(), driverSectionsFromPresent(), esc(), fetchDriversAndPresent() (+6 more)

### Community 47 - "Native Update Controller"
Cohesion: 0.05
Nodes (33): List, uint, BlackwellTherm, ChannelSet, List, uint, BlackwellVramTherm, VramSet (+25 more)

### Community 52 - "Bootstrap Build Tools"
Cohesion: 0.32
Nodes (4): ensure_build_tools(), ensure_cache(), ensure_composer_phar(), bootstrap-build-tools.sh script

### Community 59 - "OC Diagnostic JS"
Cohesion: 0.38
Nodes (10): applyOc(), countdown(), esc(), exportOcReport(), onScanComplete(), renderOcPanel(), rollbackOc(), runPreflight() (+2 more)

### Community 60 - "Settings Diagnostic JS"
Cohesion: 0.38
Nodes (4): csrfHeaders(), load(), open(), save()

### Community 63 - "PcVerseHwMon C#"
Cohesion: 0.50
Nodes (3): net8.0-windows, Microsoft.NET.Sdk, LibreHardwareMonitorLib (0.9.4)

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
Cohesion: 0.06
Nodes (33): [1.0.0] - 2026-06-14, [3.0.0] - 2026-07-30, [3.1.0] - 2026-08-01, [3.1.1] - 2026-08-04, [3.2.0] - 2026-08-11, [3.2.1] - 2026-08-16, [3.2.2] - 2026-08-17, [3.3.0] - 2026-08-17 (+25 more)

### Community 102 - "default.json"
Cohesion: 0.33
Nodes (5): description, identifier, permissions, $schema, windows

### Community 116 - "DiagnosticApiController.php"
Cohesion: 0.24
Nodes (3): BlackwellThermDecode, TestCase, BlackwellThermDecodeTest

### Community 118 - "DiagnosticIntelligencePulseService"
Cohesion: 0.42
Nodes (11): boot(), cancelSuite(), csrfHeaders(), el(), esc(), fp(), pollProbeSuite(), renderCards() (+3 more)

### Community 119 - "DiagnosticConsultantService"
Cohesion: 0.41
Nodes (13): activeFilters(), bind(), el(), esc(), exportJson(), loadOpenBook(), loadTopology(), matchesFilters() (+5 more)

### Community 122 - "diagnostic-sensor-deck.js"
Cohesion: 0.44
Nodes (8): boot(), csrfHeaders(), exportLayout(), loadLayout(), pick(), render(), saveLayout(), tick()

### Community 130 - "diagnostic-launchers.js"
Cohesion: 0.70
Nodes (4): boot(), esc(), refresh(), run()

### Community 131 - "diagnostic-openbook.js"
Cohesion: 0.44
Nodes (10): applySuiteCert(), bind(), downloadJson(), el(), esc(), refresh(), renderDossierHtml(), renderGauges() (+2 more)

### Community 133 - "Executive vision"
Cohesion: 0.67
Nodes (3): Core principles, Executive vision, Positioning for GitHub

## Knowledge Gaps
- **232 isolated node(s):** `ChannelSet`, `net8.0-windows`, `LibreHardwareMonitorLib (0.9.4)`, `Microsoft.NET.Sdk`, `Dump` (+227 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **55 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `DiagnosticService` connect `Diagnostic Core Service` to `Get-RamSpdTelemetry`, `Benchmark Dataset Service`, `Diagnostic AI Service`, `App Update Service`?**
  _High betweenness centrality (0.044) - this node is a cross-community bridge._
- **Why does `DiagnosticApiController` connect `Mobile Diagnostic API` to `Get-RamSpdTelemetry`?**
  _High betweenness centrality (0.037) - this node is a cross-community bridge._
- **Why does `SettingsService` connect `Diagnostic AI Service` to `App Update Service`, `Telemetry & Games Commands`?**
  _High betweenness centrality (0.017) - this node is a cross-community bridge._
- **Are the 37 inferred relationships involving `json_response()` (e.g. with `.check()` and `.diagnosticAgent()`) actually correct?**
  _`json_response()` has 37 INFERRED edges - model-reasoned connections that need verification._
- **What connects `ChannelSet`, `net8.0-windows`, `LibreHardwareMonitorLib (0.9.4)` to the rest of the system?**
  _236 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Native Core CLI Sensors` be split into smaller, more focused modules?**
  _Cohesion score 0.05221518987341772 - nodes in this community are weakly interconnected._
- **Should `Benchmark Dataset Service` be split into smaller, more focused modules?**
  _Cohesion score 0.07591836734693877 - nodes in this community are weakly interconnected._