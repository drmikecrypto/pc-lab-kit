# Sensor honesty matrix (PC Lab Kit)

Operators should know **what each reading needs** — Admin, `PcLabHwMon`, optional tools, or “not yet.”

This mirrors `/health` → `sensor_trust.honesty_matrix` and [SECURITY.md](SECURITY.md#sensor-trust).

## Modes

| Mode | When | What you get |
|------|------|----------------|
| **Elevated HwMon** | Admin + `PcLabHwMon.exe` | LHM-backed die/board sensors, Open Book where available |
| **HwMon-only / user** | Not elevated or helper missing | OS counters + honest limited temps |
| **Conflict** | HWiNFO / LHM / FanControl / Afterburner / RTSS / AIDA / OCCT running | Banner via `competing_tools` — close or expect contested SMBus |

## Capability matrix

| Capability | Needs | Status in 0.1.x |
|------------|-------|-----------------|
| CPU die / package | Admin + PcLabHwMon | OK when elevated |
| Board SuperIO fans/volts | Admin + PcLabHwMon (board-dependent) | Partial vs HWiNFO |
| GPU core / hotspot | Vendor APIs ± Open Book MMIO | OK / limited |
| Fan RPM read | PcLabHwMon Fan sensors | OK — `GET /fans` |
| Fan PWM write / live curves | PawnIO / Control write | **Missing** — v1 stages + preview only |
| NVMe SMART depth | Admin preferred + smartctl | OK / limited |
| PresentMon Forensics | `tools/PresentMon.exe` | OK (user mode) |
| Long sensor log | Probe live | OK — `GET /telemetry/log` |
| PawnIO helper | Phase 2 | Planned |
| Vulkan raster suite | Phase 2 | Planned (compute helper exists) |

## Shop handoff

1. Start probe elevated (`Start-PcLabProbe.bat`).
2. Overview trust banner should show elevated + no conflicts.
3. Full Lab → export cert / `.pclab` from Command Center.
4. Fan curves: RGB Lab → Fan curves → Save (JSON under `%LOCALAPPDATA%\PcLabKit\Probe\`).

See competitive roadmap in [MASTER_PLAN.md](MASTER_PLAN.md#competitive-gap-roadmap-post-v007).
