# PCVerse Native — architecture (v2)

**Status:** Active rewrite direction  
**Replaces:** PHP web lab + browser UI (v1 — transitional ship only)

---

## Why v1 is not the product

The v1 stack (PHP + local HTTP + browser) was a **fast integration lab** to wire probe scripts, scoring, imports, and release flow. It was never capable of replacing HWiNFO, 3DMark, FurMark, or datacenter validation suites because:

| Limitation | Impact |
|------------|--------|
| Browser sandbox | No direct driver/GPU/ACPI/IPMI access |
| PHP runtime | Wrong layer for microsecond telemetry and AVX stress |
| Split process (browser ↔ PHP ↔ PowerShell probe) | Latency, fragility, “prototype” feel |
| No single native shell | Users expect **one app**, not localhost:8080 |

**v2 is a native desktop product:** C++ core, privileged probe service, Qt UI, same GitHub release/update channel.

---

## Product goal (unchanged ambition, honest delivery)

> One **local** app that unifies monitoring, stress, benchmarks, storage tests, RGB/LCD, enterprise/server inventory, optional BYOK AI — without pretending we cloned closed binaries (3DMark, iCUE, etc.).

The existing **`config/tool_catalog.php` (80 tools)** remains the **capability matrix**:

| Coverage | Meaning in v2 |
|----------|----------------|
| **live** | Native C++ module in core |
| **beta** | Native but incomplete vs commercial tool |
| **import** | Parse vendor export (HWiNFO CSV, 3DMark XML, …) |
| **orchestrate** | Launch external binary if installed, capture logs + telemetry overlay |
| **planned** | Roadmap slot with UI placeholder |

Replacing all 80 **names** is multi-year; replacing the **workflow** (one dashboard, one report, one history) is the v2 milestone.

---

## High-level stack

```
┌─────────────────────────────────────────────────────────────┐
│  PCVerse Desktop (Qt 6 · QML + C++)                         │
│  Dashboard · Toolkit · History · RGB · LCD · Server · AI    │
└───────────────────────────┬─────────────────────────────────┘
                            │ IPC (gRPC localhost / named pipe)
┌───────────────────────────▼─────────────────────────────────┐
│  pcverse_core (C++20 static/shared library)                 │
│  hw · bench · stress · storage · rgb · lcd · server · ai    │
│  report · history · update · tool_catalog                   │
└───────────────────────────┬─────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        ▼                   ▼                   ▼
┌───────────────┐  ┌───────────────┐  ┌───────────────────┐
│ pcverse_probe │  │ GPU backends  │  │ Enterprise        │
│ (elevated     │  │ NVML · ADL ·  │  │ IPMI · Redfish ·  │
│  service)     │  │ Vulkan compute│  │ SMBIOS · NUMA     │
└───────────────┘  └───────────────┘  └───────────────────┘
```

**UI:** Qt 6 (industry standard for cross-platform hardware tools — HWiNFO-class density, native menus, system tray, multi-monitor).

**Not:** Electron wrapping a website. Not PHP. Not “open browser to 127.0.0.1”.

---

## `pcverse_core` modules

| Module | Responsibility | Key deps / notes |
|--------|----------------|------------------|
| **hw** | Sensors, inventory, power, clocks | LHM port (already C# → rewrite/bind C++), WMI, sysfs, hwmon |
| **bench** | CPU/GPU/RAM/disk scores | AVX2/AVX-512 kernels, Vulkan compute, fio/DiskSpd wrappers |
| **stress** | Burn-in, thermal soak | CPU AVX loop, GPU power virus, RAM walking bits, combined profile |
| **storage** | NVMe/SAS/RAID | SMART, fio profiles, DiskSpd (Win), libaio (Linux) |
| **rgb** | Lighting | OpenRGB SDK (already orchestrated in v1 probe) |
| **lcd** | AIO / smart displays | NZXT/Corsair protocols where documented + GIF pipeline |
| **server** | Workstation & datacenter | Multi-socket, NUMA topology, GPU count, IPMI sensors, Redfish REST |
| **import** | Vendor files | Port PHP parsers to C++ (HWiNFO, CPU-Z, CapFrameX, 3DMark XML) |
| **report** | Health score, bottlenecks | Port `DiagnosticService` / consultant logic |
| **history** | SQLite local DB | Encrypted-at-rest optional; fingerprint per machine |
| **ai** | BYOK advisor | User **base URL** + **model name** + API key in OS keychain |
| **update** | GitHub Releases | Same contract as v1 (`drmikecrypto/pc-lab-kit`, semver tag) |
| **catalog** | 80-tool matrix | Load from embedded JSON (generated from `tool_catalog.php`) |

---

## Server & “monster rig” support

Beyond enthusiast PCs:

| Capability | Implementation |
|------------|----------------|
| Multi-CPU / NUMA | `libnuma`, ACPI/SMBIOS, Windows NUMA API |
| Many GPUs | NVML (NVIDIA), AMD ADL, PCIe tree enumeration |
| IPMI/BMC | `libipmimonitoring` / raw IPMI LAN |
| Redfish | HTTPS client for Dell/HPE/Supermicro OOB |
| Storage backplanes | SMART + SES; NVMe-MI where available |
| Network burn | Optional iperf3 orchestration |
| AI cluster smoke | NCCL/MLPerf = **orchestrate** + import, not reimplement |

Telemetry ring buffer (already in v1 probe design) moves into C++ with **1 Hz UI / 10 Hz log / 100 Hz stress** tiers.

---

## AI advisor (local config, user network)

Stored in OS credential store + local config:

```json
{
  "ai_base_url": "http://192.168.1.50:11434/v1",
  "ai_model": "llama3.1:70b",
  "ai_api_key": "<keychain>"
}
```

Core sends structured JSON report (same schema as v1 `DiagnosticAiService` payload). No PCVerse cloud. User picks IP/host and model name exactly as requested.

---

## Updates (GitHub)

Same as shipped v1.0.0:

- Poll `GET /repos/drmikecrypto/pc-lab-kit/releases/latest`
- Compare semver to embedded `PCVERSE_VERSION`
- Native notification + one-click download of `.exe` / `.run` or in-app updater (v2.1)

Implementation: `native/core/src/update/release_checker.cpp` (ported from PHP).

---

## What we salvage from v1

| Asset | v2 use |
|-------|--------|
| `agent/pcverse_probe/` logic | Spec for C++ probe; PowerShell → port |
| `PcVerseHwMon` / LHM | Sensor engine (rewrite or host CLR bridge temporarily) |
| `config/tool_catalog.php` | Generate `native/assets/tool_catalog.json` |
| `benchmark/*.json` | Reference scoring datasets |
| PHP diagnostic services | Port algorithms to C++ (tests become gtests) |
| Flutter `pcverse_app` | **Deprecate** in favor of Qt desktop (or Flutter desktop calling C++ via FFI later) |
| Installers / GitHub Releases | Keep channel; v2 ships `PCVerse-Setup-*` native binaries |

---

## Phased roadmap

### Phase 0 — Foundation (now)

- [x] Architecture doc (this file)
- [ ] CMake monorepo, `pcverse_core`, CI build Win/Linux
- [ ] GitHub release checker (C++)
- [ ] IPC skeleton probe ↔ core

### Phase 1 — Credible desktop MVP (8–12 weeks)

- Qt shell: **Monitor** + **Quick scan** + **Settings** (AI URL/model/key) + **Update banner**
- Live sensors (LHM-class): CPU/GPU/disk temps, power, clocks
- CPU bench (AVX) + GPU compute smoke + DiskSpd/fio
- SQLite history + before/after
- Installer replaces browser launcher

### Phase 2 — Toolkit parity (12–20 weeks)

- Stress modules (CPU/GPU/RAM combined burn-in)
- OpenRGB + LCD GIF
- Import HWiNFO / CPU-Z / 3DMark
- Toolkit UI for all 80 entries (live/import/orchestrate badges)

### Phase 3 — Server & enterprise (parallel track)

- IPMI/Redfish panels, multi-GPU/NIC inventory
- BurnInTest-style multi-hour profile
- Phoronix/fio/linpack orchestration on Linux

### Phase 4 — Polish & growth

- Auto-update, code signing, winget/apt
- Plugin SDK for community bench modules

---

## Repository layout (target)

```
pc-lab-kit/
├── native/                 ← v2 (this tree)
│   ├── core/
│   ├── probe/
│   ├── apps/pcverse/       ← Qt desktop
│   └── assets/
├── agent/                  ← v1 probe (maintain until parity)
├── app/                    ← v1 PHP (maintenance mode)
└── docs/                   ← public docs (FAQ, integration)
```

---

## Success criteria for v2 MVP

User double-clicks **PCVerse** → native window opens → live sensors stream → run **Full system scan** → see health score + report → optional AI with their URL/model → notified when `v1.1.0` hits GitHub — **never opens a browser tab**.

That is the bar. v1 shipped to prove releases and community presence; v2 is the real product.
