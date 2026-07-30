# OpenRGB (Portable) for PcLab Probe

Place **OpenRGB.exe** here (no installer required):

```
agent/pclab_probe/tools/OpenRGB/OpenRGB.exe
```

Download: https://openrgb.org/releases/release_0.9/openrgb_0.9.1240_64-win64.zip

## Why

PcLab Probe uses OpenRGB in user-mode to control:

- Case LED strips and hubs
- Fan ring / center LEDs
- Many AIO pump rings
- Some LCD devices (GIF stored locally under `%LOCALAPPDATA%\PcLabKit\Probe\lcd-cache\`)

## Before scanning

1. Close **iCUE**, **NZXT CAM**, **SignalRGB** (only one controller can own the bus).
2. Run **Start-PcLabProbe.bat** as Administrator once.
3. Open `/diagnostic` → **RGB Lab** → **اسکن مجدد RGB**.

GIF files are never uploaded to pclab servers — only sent to `127.0.0.1:18765`.
