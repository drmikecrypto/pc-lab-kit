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

## Caveats

- Absolute °C may differ slightly from MODS / other tools; treat **delta vs core** and **S1–S4 spread** as the diagnostic signal for paste/cooler seating.
- Driver or VBIOS updates can move or re-lock registers — open-book paths can break; we keep fallbacks.
- Requires **Administrator** probe so Ring0 can map BAR0.

## Catalog backlog (same pillar)

- Per-VRAM chip temps (Blackwell memory maps)
- Upstream LibreHardwareMonitor when it ships correct Blackwell NVAPI handling (MMIO stays primary for blocked channels)
- AMD / Intel Arc incomplete or blocked channels
