# Open-Book Sensors

PC Lab Kit **Pillar E**: recover hardware sensors that vendors hide from public consumer APIs, on the owner’s machine, with honest provenance.

## What we do / do not do

| Do | Do not |
|----|--------|
| Read GPU BAR0 THERM registers when elevated (same class of access as HWMonitor / TIMBER-style community tooling) | Ship NVIDIA **MODS** or any NDA/internal diagnostic binary |
| Label recovered values as register / open-book, not official NVAPI | Claim manufacturer calibration or cross-card absolute °C accuracy |
| Prefer open-book Hot Spot over locked NVAPI (`0xFF00` → 255 °C) or core-clone fakes | Crack DRM or bypass anti-cheat for remote systems |

## Blackwell GPU Hot Spot (first cut, v3.4)

NVIDIA removed Hot Spot from public (and partner) NVAPI on GeForce RTX 50-series. The die sensors remain; internal MODS can still see them. Consumer tools restored access via **MMIO**.

Public research (Igor Lab / TIMBER-style reporting) documents:

| Item | Value |
|------|--------|
| THERM region | `BAR0 + 0xAD0000` |
| Scratch / plausibility | `BAR0 + 0xAD00BC` (expect `0x000000FF` on examined cards) |
| Sensor field | `BAR0 + 0xAD0A90` (six DWORDs S1–S6) |
| Format | Q8.8: `(raw & 0xFFFF) / 256.0` °C |
| Validity | Upper word must be `0x4000`; reject lock `0xFF00` and out-of-range |
| Semantics | S1–S4 spatial channels; S5 max aggregator; S6 edge/reference — **not** six independent hotspots |

`PcLabHwMon` (elevated) reads these via the same Ring0 physical-memory path LibreHardwareMonitor already opens for CPU/board sensors, injects:

- `GPU Hot Spot` (primary = S5 when it matches max(S1–S4), else max(S1–S4))
- `GPU Therm S1` … `S4`, `GPU Therm Max`, `GPU Therm Ref`
- `source` / confidence tags: `blackwell_therm_mmio` / `register_raw`

Probe `Resolve-ProbeGpuThermal` prefers that Hot Spot. `nvidia-smi` **T.Limit** derivation remains last-resort estimate only.

## Catalog (v3.5)

| Vendor | What we recover | Source tag |
|--------|-----------------|------------|
| NVIDIA Blackwell | Die Hot Spot S1–S6 + Therm Spread | `blackwell_therm_mmio` |
| NVIDIA Blackwell | Extra THERM-window temps as VRAM junction / per-chip candidates | `blackwell_vram_mmio` |
| NVIDIA Ada / older | LHM NVAPI thermal sensors (Hot Spot when driver still returns it, not `0xFF00`) | `nvapi_raw` |
| AMD | LHM ADL junction / Hot Spot / VR / Liquid (same sensors Adrenalin uses) | `adl` |
| Intel Arc | LHM GpuIntel temperatures | `lhm_intel` |

Hardware Reference **Open Book sensors** table + probe `GET /openbook` list every recovered row with optional `raw_hex` and `pci_bdf`.

## Silicon Dossier (v3.6) and Assembly Certificate (v3.7)

`GET /openbook` also returns `dossier`: CPUID leaves, GPU PCI 256-byte config (NVIDIA Ring0), SMBIOS SPD modules, NVMe SMART, EDID hex, board serial/BIOS.

**v4.1 firmware inventory** adds first-class fields: BIOS vendor/version/date, CPU microcode revision, GPU VBIOS string + SHA-256, TPM/Secure Boot, ACPI table signatures, storage firmware revisions — all tagged with provenance. UI truth cards surface these on the Open Book tab.

After Full Lab finalize, **Export Assembly Certificate** prints a one-page client report (fingerprint, stress PASS/FAIL, open-book hotspot/VRAM, sensor count + sources). Shop name is set in Settings.

The **Open Book** tab is dossier + live open-book gauges. **Stress** and **Drivers** are separate tabs.

## Caveats

- Absolute °C may differ slightly from MODS / other tools; treat **delta vs core** and **S1–S4 spread** as the diagnostic signal for paste/cooler seating.
- Driver or VBIOS updates can move or re-lock registers — open-book paths can break; we keep fallbacks.
- Requires **Administrator** probe so Ring0 can map BAR0.
- Competing tools (HWiNFO, FanControl, Afterburner, etc.) can contest SMBus — Overview shows a conflict banner from `/health.sensor_trust`.
- Trust path: **PcLabHwMon / LHM** — we do **not** ship WinRing0.sys. Sensors-only (non-elevated) and optional Windows Service modes are documented in [SECURITY.md](SECURITY.md#sensor-trust).

## Catalog backlog (same pillar)

- Tighter per-die VRAM maps as community offsets stabilize
- Upstream LibreHardwareMonitor when it ships correct Blackwell NVAPI handling (MMIO stays primary for blocked channels)
- Deeper Intel Arc PECI / AMD SMU channels beyond ADL
