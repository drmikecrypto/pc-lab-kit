# FAQ — PC Lab Kit

## What is this?

A **local** PC laboratory: browser UI for diagnostics plus an optional Windows probe for real sensors, benchmarks, stress, RGB, and safe OS/GPU tuning.

## Does anything leave my PC?

No cloud account is required. Scans and history stay on your machine. Optional AI advisor uses **your** API key against **your** chosen OpenAI-compatible endpoint.

## How do I get CPU temperatures?

Run `Start-PcLabProbe.bat` — it elevates so the LibreHardwareMonitor helper (`PcLabHwMon.exe`) can read die/board sensors.

## Where do I download the app?

GitHub Releases: https://github.com/drmikecrypto/pc-lab-kit/releases/latest  

- Windows lab: `pc-lab-kit-windows-x64.zip` → `PcLabKit.bat`
- Linux lab: `pc-lab-kit-linux-x64.tar.gz` → `./PcLabKit`
- Windows probe: `pc-lab-kit-probe-windows.zip` → `Start-PcLabProbe.bat`

Local mirrors while the lab is running: `/download/windows`, `/download/linux`, `/download/probe-windows`.

## Where is the probe download?

With the lab running: **http://127.0.0.1:8080/download/probe-windows**  
Or the [latest GitHub release](https://github.com/drmikecrypto/pc-lab-kit/releases/latest).  
Or build: `.\scripts\build-agent-bundle.ps1`

## Is this PCVerse?

No. This repository is the standalone **PC Lab Kit**. It is not the PCVerse SaaS/mobile product.

## License

Elastic License 2.0 — see [LICENSE](../LICENSE).
