# Changelog

All notable releases of PC Lab Kit are documented here.

Format based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

## [4.1.6] - 2026-08-23

### Added — Rival gap completion
- Sensor trust path + Ring0 conflict banner; tray vs Windows Service docs truth
- Adaptive / variable / switch GPU stress modes; stress certificate handoff from Overview
- SMART panel + PresentMon 1%/0.1% capture; Sensor Deck live alert thresholds
- RGB kill-vendor + preset packs; shop fleet UI; OS maintenance panel (SFC/DISM/pnputil)
- Scorecard honesty (`percentile_method` + `dataset_version` on Arena/Lab reports)
- Linux sensor density on `/health`; honest JSON sensor feed (not binary HWiNFO SM)

## [4.1.5] - 2026-08-22

### Security
- Probe token kept in memory only (no `localStorage`); legacy key cleared on load
- Broader per-session rate limits on suite/OC/orchestrate/session/fleet discover paths
- Fleet job worker uses `ProbeAuthService` and ignores payload `probe_token`

### Changed
- Open Book Platform Console: assembly checklist + plane chips + calm offline empty
- Linux probe honesty flags (no Stability Oracle / OC / RGB / Ring0 parity messaging)

## [4.1.4] - 2026-08-22

### Security
- Probe `/health` no longer returns `auth_token`; UI bootstraps via `GET /api/diagnostic/probe-auth` (session)
- Linux probe auth parity (token file/env, header gate, loopback CORS); Windows drops `?token=` and tightens SSE CORS
- Server-side CSRF verification on all PHP mutating routes; fleet `probe_base` allowlist + per-session rate limits
- Tauri CSP enabled (self + loopback probe)

### Changed
- Calm cancel/discard and Probe SLA down states; Capabilities soft-hide for Linux-missing Advanced actions

## [4.1.3] - 2026-08-21

### Changed — Detect → decide → execute lab UI
- **Overview** replaces Command Center as the home module: Probe instrument, detected hardware cards, and per-component Drivers / Test this actions
- **Tabs are exclusive workspaces** — suite chrome and Live twin no longer stay on screen when opening Drivers, Test, or other modules
- **Test** tab (was Stress): choose CPU / GPU / Memory targets, duration presets, and a precise Start label
- **Drivers** tab: full-panel offline/empty states; `Rescan devices` / `Install driver` copy
- **Programmed suite** demoted to a collapsed optional batch; CTA label matches the selected profile (e.g. Start Adaptive Lab)
- Calm Probe-not-ready guidance instead of a loud “Full Lab could not start” banner
- Primary nav: Overview · Drivers · Test · Open Book · History (Arena and the rest under Advanced)

## [4.1.2] - 2026-08-21

### Added — Enterprise masterpiece wedge
- **Full Lab resume:** probe step checkpoints, soft-cancel that keeps completed work, Resume/Discard in Command Center
- **Forever-on probe:** hardened Windows Service install/repair with failure recovery; Tauri skips second spawn when service/external probe is healthy
- **Probe SLA strip** + `/health` fields (`uptime_s`, `pid`, `service_mode`, `auth_token`)
- **Job queue worker** (`bin/job-worker.php`) with lease/heartbeat; fleet burn-in enqueue API
- **Command Center OEM path:** Run → Progress → Verdict → Cert; Advanced collapsed; Intelligence Pulse demoted
- **CDM-class storage:** DiskSpd matrix with IOPS + latency; refuses silent CDM claims if `diskspd.exe` missing
- **Soak profiles** 15/30/60 min; Stability Oracle card on Verdict
- **HMAC shop signing** for `.pclab` (AES-wrapped key at rest); offline verify; probe auth token on mutating routes
- Sensor Deck **CSV timeline** export; CI workflow (Pest + Playwright smoke)
- Linux probe Platform Intelligence / Adaptive / Drivers / Audit / Open Book (sysfs) parity modules

### Changed
- README rewritten for operators/engineers; `.gitignore` blocks sessions, settings keys, PHPUnit caches, `__pycache__`

## [4.1.1] - 2026-08-20

### Fixed
- Desktop upgrades kept a stale `%LOCALAPPDATA%/PC Lab Kit/.env` `APP_VERSION` (e.g. 3.1.0) so the UI lied about the installed build and showed a false update to an older release
- Stale GitHub release cache after upgrades; update check now refreshes when the app version changes
- **Update** button / Download links did nothing inside the Tauri webview — open the installer in the system browser via the opener plugin

## [4.1.0] - 2026-08-20

### Added
- **Drivers** tab — per-device Install/Update for problem/driverless/outdated hardware
- **Stress** tab — profiles plus custom hours/minutes (enterprise soaks up to 24h)
- Open Book **firmware truth cards** (UEFI/BIOS, microcode, VBIOS hash, TPM/Secure Boot, ACPI, storage firmware)

### Changed
- GitHub Releases ship **Windows EXE + Linux AppImage only** (probe bundled inside Windows app; no standalone probe zip)
- Command Center Full Lab shows a loud error banner when Probe is offline
- Probe stress duration clamp raised from 5 minutes to **24 hours**

### Fixed
- Full Lab “click does nothing” when Probe was unreachable (silent muted status)
- Advisor notes overlapping sticky left nav; denser readable scroll panels

## [4.0.5] - 2026-08-20

### Changed
- **Command Center:** denser lab shell — compact status bar, Run Full Lab first, module marks on left nav, brand tokens (orange/cyan)

### Fixed
- Sticky left nav no longer covered by Advisor notes when scrolling (rail stays in the main column; nav has an opaque layer)
- Desktop splash uses brand colors, a short human error, and Retry instead of a raw HTTP dump
- Desktop app hides “Download Probe” and leads Full scan with Connect Probe
- Advisor rail empty state, suite score, history copy, and certificate verify page

## [4.0.4] - 2026-08-20

### Fixed
- **Windows/Linux desktop:** bundled PHP no longer inherits host PHP config (Scoop, Chocolatey, etc.) — fixes `Lab did not become ready … HTTP 500` when `pdo_sqlite` / `mbstring` failed to load

## [4.0.3] - 2026-08-20

### Fixed
- **Windows/Linux desktop:** bundled lab payload was placed at `$RESOURCE/resources/lab/` but the app looked for `$RESOURCE/lab/` — installer now maps payload to `lab/` and resolves both paths
- Build scripts fail fast if staging did not produce `resources/lab/public/index.php`

## [4.0.2] - 2026-08-20

### Added — Command Center 2.0 & platform expansion
- **Command Center 2.0:** left nav, live topology canvas twin, advisor rail mirror, Benchmark Arena tab
- **Intelligence Pulse** visible by default; **Benchmark Arena** percentile UI + `GET /api/diagnostic/arena`
- **SSE telemetry stream** (probe → PHP proxy → browser); **Silicon Aging** dashboard
- **Interactive hardware graph** explorer; **certificate verify** page at `/verify/{hash}`
- **OpenAPI** spec (`docs/openapi.yaml`); root **Playwright** config + 13 E2E scenarios (all passing)
- **SQLite job queue** (`lab_jobs`); **Driver Outcome Learner**; **Federated Benchmark** opt-in
- **Shop fleet** discovery; **batch CLI** (`scripts/pclab-batch.ps1`); **Linux probe MVP**
- **HWiNFO shared-memory writer**; **Windows Service** probe installer; **Vulkan raster** bench MVP
- **Rust R2 MMIO** stub in `pclab_core`; **Three.js** bundled locally for 3D topology

### Fixed
- Database migration skipped `CREATE TABLE` when SQL files started with `--` comments (fixes `lab_jobs` on fresh install)
- Restored missing `SettingsApiController` import in routes; live API `toolkit` payload uses catalog `payload()`
- Stability Oracle profiles API returns a JSON array; E2E specs updated for Command Center nav + probe mocks

### Changed
- `APP_VERSION`, desktop package, and Tauri/Cargo aligned to **v4.0.2**
- Thin orchestration layer (`Container`, `LabOrchestration`) started for API controllers

## [4.0.1] - 2026-08-20

### Added — Hardware Reality Engine (Truth Protocol)
- **Stability Oracle:** 30s idle baseline, adaptive CPU/GPU/combined ramp, margin grade on Deep Lab certificate and advisor cards
- **`.pclab` sessions:** signed export/import in Command Center with silicon aging index and drift notes
- **Open Book 2.0:** register catalog runtime on `/openbook` with ≥12 provenance tags; WHEA + PCIe truth on assembly certificate
- **3D digital twin:** WebGL topology fed by `/telemetry/history` ring buffer; Blackwell Therm S1–S6 overlay dots; Hardware Reference 3D toggle
- **Driver Oracle v2 UI:** `match_confidence_pct` and local `success_rate` on live driver cards
- **Rust sidecar R1:** optional `pclab_core.exe` pipe merges into telemetry history when bundled
- **E2E:** 10+ Playwright scenarios with mock probe fixtures (session, oracle, openbook, topology, drivers)

### Changed
- History compare includes `open_book_delta` (sensor count + therm spread drift)
- `APP_VERSION`, desktop package, and probe banner aligned to v4.0.1
- MASTER_PLAN status row for v4.0.1 shipped


### Added
- **Open-Book Catalog (3.5):** Blackwell VRAM junction MMIO, NVAPI raw / ADL / Intel provenance tags, probe `GET /openbook`, Hardware Reference sensor table
- **Silicon Dossier (3.6):** PCI config dump, CPUID + microcode, SMBIOS SPD, NVMe SMART, EDID hex — `SiliconDossierService` + export `.pclab-dossier.json`
- **Assembly Certificate (3.7):** client one-page HTML/PDF after Full Lab; native `PcLabVkBench --stress-seconds` GPU soak in combined stress
- **Open Book Lab tab (4.0):** dossier | live gauges | certificate layout; tray tooltip shows elevated + open-book channel count
- Shop name in Settings for certificate branding

### Changed
- Probe `/health` reports `open_book_count`; Full Lab combined stress includes GPU compute soak
- MASTER_PLAN Pillar E catalog + assembly distinction marked shipped for 4.0.0
- Desktop / `APP_VERSION` aligned to 4.0.0

## [3.4.0] - 2026-08-17

### Added
- **Pillar E — Open-Book Sensors**: Blackwell GPU Hot Spot via BAR0 THERM MMIO in `PcLabHwMon` (Q8.8 + validity; S1–S6 + Therm Spread)
- Docs: [OPEN_BOOK_SENSORS.md](docs/OPEN_BOOK_SENSORS.md) — MODS out; register path in; decode rules
- Sensor Deck **Therm spread** gauge; live note when hotspot is `blackwell_therm_mmio`
- `BlackwellThermDecode` PHP helper + unit tests mirroring HwMon decode

### Changed
- Probe prefers open-book Hot Spot; rejects NVAPI lock (255) and RTX 50 core-clone fakes; T.Limit remains last-resort estimate
- MASTER_PLAN Pillar E marked shipped for 3.4.0
- Desktop / `APP_VERSION` aligned to 3.4.0

## [3.3.0] - 2026-08-17

### Added
- **Pillar D — Native Benchmark Arena**: `PcLabVkBench` GPU compute helper (D3D11 CS + Vulkan ICD detect); probe primary path for `/bench/gpu`
- Native **CPU cache/latency** bench (`cpu_cache`) with L1/L2/L3/DRAM pointer-chase composite
- DiskSpd **CDM-like** storage profiles (SEQ1M Q8T1/Q1T1, RND4K Q32T1/Q1T1) when `tools/DiskSpd/diskspd.exe` is present
- Full Lab **standard/deep** profiles run GPU + `cpu_cache` alongside CPU/memory/storage
- Toolkit catalog **Native** labels for benches; probe `/health` reports `vkbench`
- Build/bundle scripts publish `PcLabVkBench.exe` with the probe zip and desktop payload

### Changed
- MASTER_PLAN doctrine: **capability-first** replacement via open engines (imports are bonus, not the strategy)
- GPU NVML/`nvidia-smi` / host proxy retained only as **fallback** when the native helper is missing
- Desktop / `APP_VERSION` aligned to 3.3.0

## [3.2.2] - 2026-08-17

### Fixed
- Auto setup narrate is English-first (`headline` / `did` / `next_steps`) while keeping FA keys
- LCD GIF upload no longer claims “Applied to device” after OpenRGB Custom/Direct attempts — `pushed` vs `attempted`
- RGB conflict detection uses real process names (CAM, L-Connect*, ArmouryCrate*, TtRgb*)
- In-app `APP_VERSION` / `.env.example` aligned with desktop package (was stale 3.2.0 / 3.1.1)

### Added
- Tray Probe Status dialog + live tooltip (`PC Lab Kit · Probe: …`)
- RGB Apply / Stop blink status feedback (zone counts, errors)
- Sensor Deck gauges: GPU hotspot, VRAM %, package power, fan RPM

### Changed
- MASTER_PLAN Pillar C marked shipped; INTEGRATION documents `/rgb/stop` and LCD push shape
- Desktop package version aligned to 3.2.2

## [3.2.1] - 2026-08-16

### Added
- **RGB Lab blink**: per-zone Blink effect with custom on/off duration (ms); OpenRGB flashing when available, otherwise detached software timer
- **Stop blink** control + probe `POST /rgb/stop`
- **LCD Studio push path**: GIF still cached locally; OpenRGB Custom/Direct attempt + staged copy; clear pushed vs local-only status and next steps
- Soft-accept GIF dimension mismatch (letterbox/crop note) instead of hard-fail
- Expanded cooler/case LCD fingerprints (Corsair, NZXT, Lian Li, DeepCool, Thermaltake, Cooler Master, generic USB panel)
- English-first RGB catalog, enable guide, and zone labels

### Changed
- MASTER_PLAN status aligned with shipped Phases 0–5 / Pillars A–B; Pillar C shipping in 3.2.1
- Desktop package version aligned to 3.2.1

## [3.2.0] - 2026-08-11

### Added
- **Hardware Reference** tab: full PnP inventory including hidden/ghost devices, searchable tree, confidence-tagged fields, JSON export
- Raw EDID parsing for monitors (preferred timing, HDR hint, manufacturer codes)
- Deeper RAM SPD/SMBIOS fields with measured vs heuristic confidence
- GPU-Z-class static fields (VBIOS, PCI location, driver branch, memory hints)
- Expanded hardware knowledge graph (motherboard, chipset, BIOS/TPM, DIMMs, monitors, cooler/fans, full storage list)
- Always-on Advanced system topology from probe inventory
- Driver catalog v2 with `install_method` / `package_url` / version metadata
- One-click **Install** on driver queue (probe `POST /drivers/install` — updater app, package download, or open vendor URL)
- Command Center Full Lab suite, Sensor Deck, external stress launchers, suite smoke e2e
- `DiagnosticInventoryService` + inventory present API

### Changed
- Probe PnP inventory no longer PresentOnly — Device Manager “show hidden” parity
- LibreHardwareMonitor sensors tagged with source / confidence / plausible
- Lab reports include a Hardware Reference section; history stores inventory summary
- In-app Update button CSS hardened for Tauri WebView `[hidden]` behavior
- Desktop package version aligned to 3.2.0

### Removed
- Store/builder leftovers: affiliate pricing (`BenchmarkPricingService`), Wallex USDT exchange, toman value scoring
- Unused `AppReleaseService` (superseded by `AppUpdateService`)

## [3.1.1] - 2026-08-04

### Added
- Hidden Update control in the shell nav; shows only when a newer GitHub Release exists
- Settings “Check for updates” (force refresh) with clearer up-to-date / available messaging
- Driver package catalog (`agent/pclab_probe/data/driver-catalog.json`) with PCI/USB and board-model matching
- PHP `DriverPackageMatcherService` to enrich missing/generic/stale advice with confident package links
- Optional Windows Update driver scan via probe `/drivers?wu=1`
- Hardware knowledge graph nodes for notable PnP / driver issues

### Changed
- Driver advisor surfaces VEN/DEV IDs, match confidence, install queue, and Rescan / WU actions in the lab UI
- In-app update banner hardened (shared UI state for banner + nav button)
- Version bumped to 3.1.1

## [3.1.0] - 2026-08-01

### Added
- Installable desktop apps via Tauri 2 shell (`desktop/`): lab UI runs inside the app window
- Windows NSIS installer `PcLabKit-Setup-Windows-x64.exe` and Linux `PcLabKit-Linux-x64.AppImage`
- Desktop runtime auto-starts bundled PHP lab; Windows also starts the probe sidecar
- Build scripts: `scripts/build-desktop-windows.ps1`, `scripts/build-desktop-linux.sh`

### Changed
- GitHub Releases primary assets are installers (not zip/tarball quick-start)
- App update checker prefers Setup.exe / AppImage download URLs
- Version bumped to 3.1.0

## [3.0.0] - 2026-07-30

### Added
- Portable GitHub release apps: `pc-lab-kit-windows-x64.zip` and `pc-lab-kit-linux-x64.tar.gz` (bundled PHP)
- CI publishes Windows app, Linux app, and Windows probe on `v*` tags
- Local download routes: `/download/windows`, `/download/linux`, `/download/probe-windows`

### Changed
- Standalone rebrand: product identity is **PC Lab Kit** (probe `pclab-probe`, HwMon `PcLabHwMon`)
- Removed PCVerse-attached shells: native Qt app, installers, Flutter stub, pitch/download marketing pages
- Neutralized Orchestrator (was Vakhsh) and Advisor (was Amin) naming
- App update checker prefers `pc-lab-kit-windows-x64.zip` / `pc-lab-kit-linux-x64.tar.gz` assets

## [1.0.0] - 2026-06-14

### Added
- Local PC diagnostic lab (quick quiz + full Probe scan on Windows)
- Test history with before/after comparison
- Optional AI advisor (BYOK, stored locally)
- GitHub release update checker
- Elastic License 2.0
