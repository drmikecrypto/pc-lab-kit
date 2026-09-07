# Contributing driver catalog entries (v3)

PC Lab Kit matches PnP devices to vendor packages via [`agent/pclab_probe/data/driver-catalog.json`](../agent/pclab_probe/data/driver-catalog.json).

## v3 schema fields

| Field | Required | Description |
|-------|----------|-------------|
| `ven` / `vid` | yes | PCI vendor or USB vendor ID (hex, no `0x`) |
| `dev` / `pid` | yes | Device ID or `*` wildcard |
| `category` | yes | `gpu`, `chipset`, `network`, `audio`, `storage`, `usb`, … |
| `label` | yes | Human label shown in Driver tab |
| `url` | yes | Vendor download page |
| `install_method` | yes | `updater_app`, `exe_silent`, `exe_ui`, `msi`, `inf_zip`, `open_url` |
| `package_url` | optional | Direct download when installable |
| `sha256` | optional | SHA256 of `package_url` artifact |
| `last_verified` | optional | ISO date you tested the link |
| `success_rate` | optional | Community success % (local outcomes may override) |
| `hwid_patterns` | optional | PnP ID globs, e.g. `PCI\VEN_10DE&DEV_2803` |
| `inf_name` | optional | Expected INF after install |

## PR checklist

1. Test on real hardware — device resolves and link opens
2. Add `last_verified` date
3. For direct packages, include `sha256`
4. Note BIOS/UEFI prerequisites in `note`
5. Never submit credentials or NDA-only URLs

## Local outcome learning

After install, probe writes `%LOCALAPPDATA%\PcLabKit\Probe\driver-outcomes.json`. Re-scan updates `match_confidence_pct` in the UI — no cloud upload.
