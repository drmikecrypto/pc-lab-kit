# OpenRGB (Portable) for PcLab Probe

Place **OpenRGB.exe** here (no installer required):

```
agent/pclab_probe/tools/OpenRGB/OpenRGB.exe
```

Download: https://openrgb.org/releases/release_0.9/openrgb_0.9.1240_64-win64.zip

## Why

PcLab Probe uses OpenRGB in user-mode to control:

- Case LED strips and hubs
- Fan ring / center LEDs (static, breathing, blink with on/off ms)
- Many AIO pump rings
- LCD coolers / case panels (GIF cached locally; OpenRGB Custom/Direct push when supported)

## Before scanning

1. Close **iCUE**, **NZXT CAM**, **SignalRGB**, **Armoury Crate** (only one controller can own the bus).
2. Run **Start-PcLabProbe.bat** as Administrator once.
3. Open the lab → **RGB Lab** → **Rescan RGB**.

GIF files are never uploaded to PC Lab Kit servers — only sent to `127.0.0.1:18765`.
Staged copies for manual import live under `OpenRGB/pclab-lcd/` and `%LOCALAPPDATA%\PcLabKit\Probe\lcd-cache\`.
