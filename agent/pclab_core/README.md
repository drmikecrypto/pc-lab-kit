# PC Lab Kit — Rust probe core (R1)

Hot-path sidecar for the Windows PowerShell probe. Phase R1 ships:

- **Telemetry ring buffer** (120 samples) via stdin/stdout JSON lines
- Foundation for R2 Blackwell MMIO reads and R3 Linux sysfs sensors

## Build

```powershell
cd agent/pclab_core
cargo build --release
```

Binary: `target/release/pclab_core.exe`

## Pipe protocol

PowerShell sends one JSON sample per line; core responds with full ring history:

```json
{"cpu_temp":72.1,"gpu_temp":68.0,"gpu_hotspot":84.2,"at":"2026-08-20T00:00:00Z"}
```

Response:

```json
{"ok":true,"count":1,"history":[...]}
```

## Integration (probe)

```powershell
$proc = Start-Process -FilePath ".\pclab_core.exe" -ArgumentList "pipe" -RedirectStandardInput -RedirectStandardOutput -NoNewWindow -PassThru
# Write samples to $proc.StandardInput; read ring from StandardOutput
```

PowerShell retains WMI/PnP/driver install; Rust owns tight telemetry loops.
