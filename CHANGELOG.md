# Changelog

All notable releases of PC Lab Kit are documented here.

Format based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

## [4.0.0] - 2026-08-18

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
