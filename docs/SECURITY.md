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
- The web UI bootstraps the token via same-origin `GET /api/diagnostic/probe-auth` (PHP session), then caches it in `localStorage`.

## CSRF

- Every HTML page emits `<meta name="csrf-token">`.
- All PHP mutating methods (`POST` / `PUT` / `PATCH` / `DELETE`) require `X-CSRF-TOKEN` matching the session (`hash_equals`).

## Fleet / shop-floor

- Fleet discover scans loopback ports only.
- Burn-in `probe_base` is allowlisted to `127.0.0.1` / `localhost` on the default probe port and optional `PCLAB_FLEET_SCAN` range.
- Mutating diagnostic APIs use a per-session rate limit under `storage/rate_limit/`.

## Desktop (Tauri)

- Content-Security-Policy restricts scripts/styles to `'self'` (+ inline for the lab shell) and connects to loopback for the probe.
