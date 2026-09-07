# PresentMon overlay / OSD feed consumers

PC Lab Kit does **not** ship an RTSS-class in-game OSD in 0.1.x. Prefer these local feeds:

## JSON telemetry feed

- Live ring: `GET http://127.0.0.1:18765/telemetry` and `/telemetry/history`
- Long log: `GET /telemetry/log?hours=24&limit=2000` (optional `?format=csv`)
- Dense overlay-oriented snapshot fields: `cpu_temp`, `gpu_temp`, `fan_rpm`, FPS when PresentMon session is active

## Rainmeter / custom OSD

1. Point a local WebParser / script measure at `/telemetry` with the probe auth header if enabled (`X-PcLab-Token`).
2. Poll 500–2000 ms; never expose the probe beyond loopback.
3. Session Forensics remains **post-hoc** (stop session → spikes + temps) — CapFrameX-compatible export via `/presentmon/sessions/{id}/export`.

## Capture profiles (Forensics v2)

`GET /presentmon/profiles` returns presets (`quick_10s`, `standard_30s`, `deep_60s`, `process_named`). UI “Capture profile” fills seconds / process before Start session.

## Non-goals (for now)

- Full RTSS hook injection
- Cloud overlay sync
