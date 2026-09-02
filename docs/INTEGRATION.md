# PC Lab Kit — integration guide

Standalone local lab: **PHP web UI** + **Windows or Linux probe agent**. No mobile SaaS, Flutter app, or desktop Qt shell ships in this repository.

## Layout

| Path | Role |
|------|------|
| `public/` | Web root (`index.php` front controller) |
| `routes/web.php` | HTTP routes |
| `app/` | Controllers, services, support |
| `config/` | App + diagnostic config |
| `resources/views/` | PHP templates |
| `agent/pclab_probe/` | Windows probe (PowerShell HTTP server) |
| `agent/pclab_probe_linux/` | Linux probe (Python HTTP server — Platform Intelligence parity) |
| `scripts/` | Install, start, probe build helpers |
| `storage/` | SQLite DB, settings, cache |

## Web routes

| Method | Path | Handler |
|--------|------|---------|
| GET | `/`, `/diagnostic` | Diagnostic lab UI |
| GET | `/download/windows` | Windows desktop installer (`PcLabKit-Setup-Windows-x64.exe`) |
| GET | `/download/linux` | Linux AppImage (`PcLabKit-Linux-x64.AppImage`) |
| GET | `/download/probe-windows` | Windows probe ZIP |
| GET | `/download/probe-linux` | Linux probe ZIP (`agent/pclab_probe_linux`) |
| GET/POST | `/api/diagnostic/*` | Diagnostic JSON API |
| GET/POST | `/api/settings` | Local BYOK settings |
| GET | `/api/app/update` | GitHub release check |

## Probe HTTP API (localhost:18765)

Identity: Windows `"agent":"pclab-probe"` / Linux `"agent":"pclab-probe-linux"`, collector `"pclab-hwmon"` (Windows).

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/` | Status page |
| GET | `/health` | Liveness + capability flags (`platform`, `oc`, `rgb`, …) |
| GET | `/probe` | Full hardware scan |
| GET | `/telemetry`, `/telemetry/history` | Live counters |
| GET | `/devices`, `/drivers`, `/thermal` | Inventory / advisors |
| GET | `/openbook` | Open Book sensors + platform fingerprint |
| GET | `/suite/plan` | Adaptive Lab plan preview |
| GET | `/audit` | Platform audit JSON (+ HTML on Linux) |
| GET/POST | `/oc/*` | Safe OC (Windows only) |
| GET/POST | `/rgb/*` | RGB scan / apply / LCD (Windows only) |
| POST | `/rgb/stop` | Stop blink timers; set OpenRGB zones off |
| POST | `/rgb/lcd` | Upload GIF (local cache; `pushed` / `attempted` in response) |
| POST | `/orchestrate` | RGB + fan + LCD orchestration |
| GET/POST | `/bench/*`, `/stress/*` | Native benchmarks and stress |
| POST/GET | `/suite/start\|status\|cancel` | Full Lab async suite |
| GET/POST | `/launchers`, `/launchers/run` | Optional third-party stress tools (Windows) |
| GET | `/integrations/hwinfo-sm` | Write **JSON sensor feed** (see below) |
| GET/POST | `/repair/*` | OS maintenance catalog / run (Windows; confirm required) |

### Sensor JSON feed (not binary HWiNFO Shared Memory)

`GET /integrations/hwinfo-sm` refreshes `%LOCALAPPDATA%\PcLabKit\Probe\hwinfo-shared.json` and returns metadata. This is a **JSON file feed** with HWiNFO-style sensor names — it is **not** the proprietary HWiNFO Shared Memory binary segment. Use it with Rainmeter WebParser, scripts, or overlays that can read a local file / HTTP JSON.

Example payload:

```json
{
  "schema_version": 2,
  "feed_kind": "json_file",
  "source": "pc-lab-kit",
  "sensor_count": 12,
  "path": "C:\\\\Users\\\\…\\\\AppData\\\\Local\\\\PcLabKit\\\\Probe\\\\hwinfo-shared.json",
  "sensors": [
    { "name": "CPU Package", "value": 58.2, "unit": "°C" },
    { "name": "GPU Core", "value": 61.0, "unit": "°C" },
    { "name": "GPU Hot Spot", "value": 72.0, "unit": "°C" },
    { "name": "CPU Package Power", "value": 42.5, "unit": "W" },
    { "name": "GPU Board Power", "value": 180.0, "unit": "W" },
    { "name": "CPU Load", "value": 34.0, "unit": "%" },
    { "name": "GPU Load", "value": 88.0, "unit": "%" },
    { "name": "RAM Used %", "value": 61.0, "unit": "%" }
  ]
}
```

Dense channel map (when Probe/HwMon elevated) includes CPU/GPU temps, hotspot, VRAM junction, package + board power, loads, RAM %, fans, Vcore, FPS / 1% low when PresentMon has samples.

Rainmeter can also poll `http://127.0.0.1:18765/telemetry` directly (Sensor Deck Rainmeter export). Afterburner/RTSS still expect their own injectors — this feed is for local overlays that accept JSON, not a drop-in HWiNFO SM replacement.

### Linux probe

```bash
chmod +x agent/pclab_probe_linux/pclab-probe-linux.sh
./agent/pclab_probe_linux/pclab-probe-linux.sh
```

Honest limits: no Ring0 MMIO Open Book, no one-click driver install, no OC/RGB. Inventory / Adaptive / Drivers / Audit / Open Book (hwmon) match Windows JSON shapes.

### Lab suite API (PHP)

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/diagnostic/suite/profiles` | Quick / Full / Deep profiles |
| POST | `/api/diagnostic/suite/start` | Create suite job |
| GET | `/api/diagnostic/suite/status/{id}` | Job progress |
| POST | `/api/diagnostic/suite/cancel/{id}` | Cancel |
| POST | `/api/diagnostic/suite/finalize/{id}` | Analyze probe suite → report + cards |
| GET/POST | `/api/diagnostic/sensor-deck` | Sensor Deck layout |
| GET | `/api/diagnostic/sensor-deck/export` | JSON or Rainmeter export |
| POST | `/api/diagnostic/topology` | SVG topology from graph/probe |

## Standalone flow

1. `.\scripts\install.ps1` then `.\scripts\start.ps1`
2. Build probe: `.\scripts\build-agent-bundle.ps1`
3. Run `agent/pclab_probe/Start-PcLabProbe.bat`
4. Use **Command Center → Run Full Lab**, or Connect from the Full scan tab

## Product identity

| Concept | Value |
|---------|-------|
| Product | PC Lab Kit |
| Probe | PcLab Probe / `pclab-probe` |
| HwMon | `PcLabHwMon.exe` / `pclab-hwmon` |
| AppData | `%LOCALAPPDATA%\PcLabKit\Probe` |
| SQLite | `storage/database/pclab.sqlite` |
