# OpenRGB (Portable) for PCVerse Probe

Place **OpenRGB.exe** here (no installer required):

```
agent/pcverse_probe/tools/OpenRGB/OpenRGB.exe
```

Download: https://openrgb.org/releases/release_0.9/openrgb_0.9.1240_64-win64.zip

## Why

PCVerse Probe uses OpenRGB in user-mode to control:

- Case LED strips and hubs
- Fan ring / center LEDs
- Many AIO pump rings
- Some LCD devices (GIF stored locally under `%LOCALAPPDATA%\PCVerseProbe\lcd-cache\`)

## Before scanning

1. Close **iCUE**, **NZXT CAM**, **SignalRGB** (only one controller can own the bus).
2. Run **Start-PCVerseProbe.bat** as Administrator once.
3. Open `/diagnostic` → **RGB Lab** → **اسکن مجدد RGB**.

GIF files are never uploaded to pcverse servers — only sent to `127.0.0.1:18765`.
