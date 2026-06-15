# Integration guide — spinning off PC Lab Kit

## HTTP routes (from `app/bootstrap.php`)

### Pages

| Method | Path | Handler |
|--------|------|---------|
| GET | `/diagnostic` | `DiagnosticController::index()` → currently `lab/legacy-redirect` |
| GET | `/lab/pc-test` | `LabPitchController::pcTest()` |
| GET | `/lab/rgb-sync` | `LabPitchController::rgbSync()` |
| GET | `/download` | `DownloadController::index()` — two installers |
| GET | `/download/pcverse-windows-x64` | `DownloadController::windowsInstaller()` |
| GET | `/download/pcverse-linux-x64` | `DownloadController::linuxInstaller()` |

### API (`/api` prefix in production)

| Method | Path | ApiController method |
|--------|------|----------------------|
| GET | `/diagnostic/games` | `diagnosticGames()` |
| GET | `/diagnostic/config` | `diagnosticConfig()` |
| GET | `/diagnostic/live` | `diagnosticLive()` |
| GET | `/diagnostic/history` | `diagnosticHistory()` |
| GET | `/diagnostic/report/{token}` | `diagnosticReport($token)` |
| POST | `/diagnostic/lite` | `diagnosticLite()` |
| POST | `/diagnostic/full` | `diagnosticFull()` |
| POST | `/diagnostic/agent` | `diagnosticAgent()` |
| POST | `/diagnostic/import` | `diagnosticImport()` |
| POST | `/diagnostic/telemetry/present` | `diagnosticTelemetryPresent()` |
| POST | `/diagnostic/oc/plan` | `diagnosticOcPlan()` |
| GET | `/diagnostic/rgb/catalog` | `diagnosticRgbCatalog()` |
| POST | `/diagnostic/vakhsh/orchestrate` | `diagnosticVakhshOrchestrate()` |
| POST | `/diagnostic/vakhsh/narrate` | `diagnosticVakhshNarrate()` |
| POST | `/diagnostic/game-settings` | `diagnosticGameSettings()` |

Admin: `POST /system/diagnostic-games/refresh` → `AdminController::refreshDiagnosticGames()`

**Source location:** `app/Controllers/ApiController.php` approximately lines **2720–3199** (including private helpers `enrichDiagnosticConsultant`, `labMetaFromAnalysis`, `persistDiagnostic`, `diagnosticFingerprint`).

Recommended extraction: move those methods into `DiagnosticApiController` and register the routes above against it.

## Config

`config/diagnostic.php` keys:

- `windows_agent.local_host` / `local_port` — must match Flutter `PcverseAppConfig.windowsAgentBase` and probe server
- `rgb.openrgb_bundle_path` — relative path to portable OpenRGB
- `games_catalog` — cron refresh interval for `diagnostic_games.json`

## Database

```sql
-- Required for history/live pulse
database/migrations/20260529_diagnostic_reports.sql

-- Optional catalog taxonomy (RGB parts category)
database/migrations/20260612_rgb_lighting_category.sql
```

## Cron

```bash
php cron/refresh_diagnostic_games.php
# or
php artisan diagnostic-games:refresh  # DiagnosticGamesRefreshCommand
```

## Flutter ↔ backend contract

Documented in [API_MOBILE_ROUTES.md](API_MOBILE_ROUTES.md) (included in kit).

Client: `pcverse_app/lib/core/diagnostic_service.dart`

- Fingerprint cookie/key: `_pcverse_fp` (SharedPreferences + query `?fp=`)
- Agent base: `PcverseAppConfig.windowsAgentBase` → `http://127.0.0.1:18765`
- API base: `PcverseAppConfig.apiBase` + `/diagnostic/...`

Header for suppressing web download pitch when already in app:

```
X-PCVERSE-Client: pcverse-flutter
```

## Web frontend assets

Load order in `diagnostic.php`:

1. `diagnostic-pulse.css`, `diagnostic-lab.css`, `diagnostic-live.css`, `diagnostic-telemetry.css`, `diagnostic-rgb.css`
2. Matching JS: `diagnostic-lab.js`, `diagnostic-live.js`, `diagnostic-pulse.js`, `diagnostic-telemetry.js`, `diagnostic-oc.js`, `diagnostic-rgb.js`

Lab pitch pages: `lab-pitch.css` only.

## Probe agent endpoints (local)

| Path | Role |
|------|------|
| `GET /health` | Agent alive check |
| `GET /probe` | Full hardware JSON (v2+) |
| `GET /rgb/scan` | RGB/LCD device discovery |
| RGB apply routes | See `PCVerseProbeServe.ps1` + `ProbeLib/rgb.ps1` |

Default port **18765** — change in `config/diagnostic.php`, `pcverse_app_config.dart`, and `PCVerseProbeServe.ps1` together.

## Decoupling checklist

- [x] Extract `DiagnosticApiController` from `ApiController`
- [x] Wire `BenchmarkDatasetService` + `benchmark_datasets.php`
- [x] Stub `CatalogService` (empty parts catalog; benchmark scoring works)
- [x] Make `LlmService` optional (BYOK via `.env`; rule-based fallback)
- [x] Replace `TrackUserEventAction` with local SQLite activity log
- [x] Restore full web lab at `/diagnostic`
- [x] Add `composer.json`, `.env.example`, SQLite migrations, `scripts/install.ps1`
- [ ] Tauri desktop shell (Phase 1)
- [ ] Point branding fully to PC Lab Kit (English UI pass)
