# PC Lab Kit — Linux Probe

Local Platform Intelligence agent for Linux. Same port and route shape as the Windows probe so the PHP/JS lab UI works unchanged.

## Quick start

```bash
chmod +x pclab-probe-linux.sh
./pclab-probe-linux.sh
# or: python3 pclab-probe-linux.py
```

Listens on `http://127.0.0.1:18765` (override with `PCLAB_PROBE_PORT`).

Run as root when you need fuller EFI/TPM/hwmon planes:

```bash
sudo ./pclab-probe-linux.sh
```

## Routes (parity with Windows)

| Method | Path | Notes |
|--------|------|--------|
| GET | `/health` | Capabilities (`platform: linux`, `oc`/`rgb` false) |
| GET | `/telemetry`, `/telemetry/history` | hwmon + nvidia-smi |
| GET | `/devices`, `/probe` | PCI/USB/DMI/TPM/UEFI inventory + fingerprint |
| GET | `/drivers` | Action plan with distro package hints (manual install) |
| GET | `/openbook` | hwmon Open Book (no Ring0 MMIO) |
| GET | `/suite/plan` | Adaptive Lab plan |
| POST | `/suite/start`, GET `/suite/status`, POST `/suite/cancel` | Light native suite |
| GET | `/audit` | Platform audit JSON + HTML |

## Honest limits vs Windows

- No Ring0 / BAR0 MMIO Open Book
- No one-click driver install (package manager)
- No OC / RGB / launchers / Vulkan Arena
- Suite benches are micro-benches + short thermal soak
