# File manifest

Generated: 2026-06-14. **98+ files** — run `Get-ChildItem -Recurse -File` to refresh count after edits.

## benchmark/

```
benchmark/cpu/          # multithread, single-CPU, user-benchmark JSON
benchmark/gpu/            # tier lists + gpu-benchmark_all_pages
benchmark/ram/            # DDR5 datasets
benchmark/storage/        # SSD/HDD benchmarks
benchmark/flash-memory/   # flash benchmark pages
```

Referenced by `config/benchmark_datasets.php` in the monolith (not yet in kit — copy if you need `BenchmarkDatasetService` offline).

## agent/

```
agent/pcverse_probe/
  PCVerseProbe.ps1
  PCVerseProbeServe.ps1
  Start-PCVerseProbe.bat
  PcbHwMon.exe
  PcverseHwMon/Program.cs, PcverseHwMon.csproj
  ProbeLib/*.ps1 (cpu, gpu, rgb, memory, frametime, overclock, vakhsh-orchestrator, …)
  tools/OpenRGB/README.md
```

## backend (PHP)

```
app/Controllers/DiagnosticController.php
app/Controllers/LabPitchController.php
app/Controllers/DownloadController.php
app/Console/Commands/DiagnosticGamesRefreshCommand.php
app/Services/DiagnosticService.php
app/Services/DiagnosticAgentService.php
app/Services/DiagnosticAiService.php
app/Services/DiagnosticConsultantService.php
app/Services/DiagnosticGameCatalogService.php
app/Services/DiagnosticHistoryService.php
app/Services/DiagnosticImportService.php
app/Services/DiagnosticIntelligencePulseService.php
app/Services/DiagnosticOcService.php
app/Services/DiagnosticRgbService.php
app/Services/DiagnosticTelemetryService.php
app/Services/DiagnosticVakhshLightingService.php
```

## config

```
config/diagnostic.php
config/diagnostic_games.json
config/diagnostic_game_anchors.php
config/diagnostic_game_awards.php
```

## database

```
database/migrations/20260529_diagnostic_reports.sql
database/migrations/20260612_rgb_lighting_category.sql
```

## cron & scripts

```
cron/refresh_diagnostic_games.php
scripts/build-agent-bundle.ps1
scripts/build-installer-windows.ps1
scripts/build-installer-linux.sh
scripts/stage-payload-unix.sh
scripts/build-release.ps1
scripts/install.sh
scripts/start.sh
scripts/generate_diagnostic_games.php
```

## web views

```
resources/views/diagnostic.php
resources/views/lab/pitch.php
resources/views/lab/legacy-redirect.php
installer/PCVerse.Setup/          # WinForms Setup.exe (embedded payload)
installer/linux/setup-ui.sh       # Linux guided installer UI
PCVerse.bat                       # Windows launcher (desktop shortcut target)
PCVerse                           # Linux launcher script
```

## web assets

```
public/assets/css/diagnostic-lab.css
public/assets/css/diagnostic-live.css
public/assets/css/diagnostic-pulse.css
public/assets/css/diagnostic-rgb.css
public/assets/css/diagnostic-telemetry.css
public/assets/css/lab-pitch.css
public/assets/js/diagnostic-lab.js
public/assets/js/diagnostic-live.js
public/assets/js/diagnostic-oc.js
public/assets/js/diagnostic-pulse.js
public/assets/js/diagnostic-rgb.js
public/assets/css/download-pages.css
public/assets/js/diagnostic-settings.js
public/downloads/.gitkeep
public/downloads/PCVerse-Setup-Windows-x64.exe  (built; gitignored)
public/downloads/PCVerse-Setup-Linux-x64.run    (built; gitignored)
```

## Flutter (pcverse_app)

```
pcverse_app/lib/core/diagnostic_service.dart
pcverse_app/lib/core/pcverse_app_config.dart
pcverse_app/lib/core/pcverse_brand_tokens.dart
pcverse_app/lib/core/pcverse_page_routes.dart
pcverse_app/lib/presentation/pages/lab_hub_page.dart   # includes RgbLabPage
pcverse_app/lib/presentation/pages/pc_test_page.dart
pcverse_app/lib/presentation/pages/diagnostic_page.dart
```

## tests & docs

```
tests/Unit/DiagnosticConsultantServiceTest.php
tests/Unit/DiagnosticHistoryServiceTest.php
e2e/diagnostic-popup.spec.ts
doc/API_MOBILE_ROUTES.md
docs/INTEGRATION.md
docs/bootstrap.routes.snippet.php
README.md
```

## Not copied (stay in monolith)

| Item | Why |
|------|-----|
| `app/Controllers/ApiController.php` (diagnostic methods) | Large shared controller — see `docs/INTEGRATION.md` for line range |
| `CatalogService`, `Benchmark*`, `LlmService`, etc. | Shared platform services |
| `app/helpers.php`, `app/bootstrap.php` | App shell |
| `resources/views/layout.php`, header/footer | Site chrome for diagnostic.php |
| `user_home_page.dart` lab entry cards | Home integration only |
