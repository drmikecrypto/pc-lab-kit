# Changelog

All notable releases of PC Lab Kit are documented here.

Format based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

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
