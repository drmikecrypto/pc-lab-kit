# Security

PC Lab Kit is a **local-first** lab. Hardening targets malicious browser tabs on the same machine and accidental LAN exposure — not internet multi-tenant hosting (Elastic-2.0 forbids managed SaaS of this software).

## Threat model

| In scope | Out of scope |
|----------|--------------|
| Cross-site POSTs to `127.0.0.1` PHP APIs | Remote unauthenticated attackers on the public internet |
| Probe mutating routes (suite / stress / OC / RGB) without a token | Full multi-user RBAC / accounts |
| Accidental bind beyond loopback | Cloud secrets management |

## Probe auth

- Windows and Linux probes bind to **127.0.0.1** and require `X-PcLab-Token` (or `Authorization: Bearer`) on mutating POSTs.
- Token lives in `%LOCALAPPDATA%\PcLabKit\Probe\auth.token` (Windows) or `~/.local/share/PcLabKit/Probe/auth.token` (Linux), overridable with `PCLAB_PROBE_TOKEN`.
- **`GET /health` never returns the token** — only `auth_required: true`.
- The web UI bootstraps the token via same-origin `GET /api/diagnostic/probe-auth` (PHP session) and keeps it **in memory only** (30-minute TTL, re-fetch). It does **not** persist to `localStorage`.
- The fleet job worker resolves the token via `ProbeAuthService` and **ignores** any `probe_token` field in job payloads.

## CSRF

- Every HTML page emits `<meta name="csrf-token">`.
- All PHP mutating methods (`POST` / `PUT` / `PATCH` / `DELETE`) require `X-CSRF-TOKEN` matching the session (`hash_equals`).

## Fleet / shop-floor

- Fleet discover scans loopback ports only.
- Burn-in `probe_base` is allowlisted to `127.0.0.1` / `localhost` on the default probe port and optional `PCLAB_FLEET_SCAN` range.
- Mutating diagnostic APIs use a per-session rate limit under `storage/rate_limit/`.

## Desktop (Tauri)

- Content-Security-Policy restricts scripts/styles to `'self'` (+ inline for the lab shell) and connects to loopback for the probe.

## Sensor trust

PC Lab Kit **does not ship WinRing0.sys**. Sensors use:

| Mode | When | What you get |
|------|------|----------------|
| **Elevated HwMon path** | Probe started as Administrator (`Start-PcLabProbe.bat` / elevated tray) + `PcLabHwMon.exe` present | LibreHardwareMonitor-backed die/board sensors + Open Book BAR0 (same class of Ring0 access LHM already opens — not a separate vulnerable WinRing0 driver package) |
| **HwMon-only / Sensors-only** | Non-elevated or helper missing | OS counters + honest limited temps; Overview shows a calm banner |

**Ring0 conflict banner:** `/health` → `sensor_trust.competing_tools` lists HWiNFO, LibreHardwareMonitor, FanControl, Afterburner, RTSS, AIDA64, OCCT when running. Close them or expect wrong / contested SMBus temps.

**Operator story (tray vs Service):**

- **Default:** desktop tray / sidecar Probe (`service_mode: false`) — good for Sensors-only sessions and interactive lab.
- **Optional forever-on:** `Install-PcLabProbeService.ps1` (Admin) sets `PCLAB_PROBE_SERVICE=1` for always-on telemetry / Rainmeter-style feeds. Not required for daily Test / Suite.

PawnIO (FanControl-style signed kernel helper) is the longer-term Defender-friendly migration target; until then shops should prefer elevated PcLabHwMon and closing competing Ring0 tools — never install random WinRing0 forks.

See also [OPEN_BOOK_SENSORS.md](OPEN_BOOK_SENSORS.md).
