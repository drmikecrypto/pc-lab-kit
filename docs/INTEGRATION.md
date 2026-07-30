# PC Lab Kit — integration guide

Standalone local lab: **PHP web UI** + **Windows probe agent**. No mobile SaaS, Flutter app, or desktop Qt shell ships in this repository.

## Layout

| Path | Role |
|------|------|
| `public/` | Web root (`index.php` front controller) |
| `routes/web.php` | HTTP routes |
| `app/` | Controllers, services, support |
| `config/` | App + diagnostic config |
| `resources/views/` | PHP templates |
| `agent/pclab_probe/` | Windows probe (PowerShell HTTP server) |
| `scripts/` | Install, start, probe build helpers |
| `storage/` | SQLite DB, settings, cache |

## Web routes

| Method | Path | Handler |
|--------|------|---------|
| GET | `/`, `/diagnostic` | Diagnostic lab UI |
| GET | `/download/windows` | Windows desktop installer (`PcLabKit-Setup-Windows-x64.exe`) |
| GET | `/download/linux` | Linux AppImage (`PcLabKit-Linux-x64.AppImage`) |
| GET | `/download/probe-windows` | Windows probe ZIP |
| GET/POST | `/api/diagnostic/*` | Diagnostic JSON API |
| GET/POST | `/api/settings` | Local BYOK settings |
| GET | `/api/app/update` | GitHub release check |

## Probe HTTP API (localhost:18765)

Identity: `"agent":"pclab-probe"`, collector `"pclab-hwmon"`.

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/` | Status page |
| GET | `/health` | Liveness + capability flags |
| GET | `/probe` | Full hardware scan |
| GET | `/telemetry`, `/telemetry/history` | Live counters |
| GET | `/devices`, `/drivers`, `/thermal` | Inventory / advisors |
| GET/POST | `/oc/*` | Safe OC status / preflight / apply / watch / rollback |
| GET/POST | `/rgb/*` | RGB scan / apply / LCD / auto |
| POST | `/orchestrate` | RGB + fan + LCD orchestration |
| GET/POST | `/bench/*`, `/stress/*` | Native benchmarks and stress |

## Standalone flow

1. `.\scripts\install.ps1` then `.\scripts\start.ps1`
2. Build probe: `.\scripts\build-agent-bundle.ps1`
3. Run `agent/pclab_probe/Start-PcLabProbe.bat`
4. Connect from the lab Full scan tab

## Product identity

| Concept | Value |
|---------|-------|
| Product | PC Lab Kit |
| Probe | PcLab Probe / `pclab-probe` |
| HwMon | `PcLabHwMon.exe` / `pclab-hwmon` |
| AppData | `%LOCALAPPDATA%\PcLabKit\Probe` |
| SQLite | `storage/database/pclab.sqlite` |
