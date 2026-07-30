# Changelog

All notable releases of PC Lab Kit are documented here.

Format based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

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
