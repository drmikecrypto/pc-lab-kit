# FAQ — PC Lab Kit

## What is this?

A **local** PC laboratory: installable desktop app (Windows/Linux) with the diagnostic lab inside the app window, plus a Windows probe for real sensors, benchmarks, stress, RGB, and safe OS/GPU tuning.

## Does anything leave my PC?

No cloud account is required. Scans and history stay on your machine. Optional AI advisor uses **your** API key against **your** chosen OpenAI-compatible endpoint.

## How do I get CPU temperatures?

Run `Start-PcLabProbe.bat` — it elevates so the LibreHardwareMonitor helper (`PcLabHwMon.exe`) can read die/board sensors.

## Where do I download the app?

GitHub Releases: https://github.com/drmikecrypto/pc-lab-kit/releases/latest  

- Windows: `PcLabKit-Setup-Windows-x64.exe` — install, then open **PC Lab Kit** (probe bundled)
- Linux: `PcLabKit-Linux-x64.AppImage` — `chmod +x` and run

Local mirrors while the lab is running: `/download/windows`, `/download/linux`.

## Does the lab open in my browser?

No. The installable apps open a **PC Lab Kit** window. Developers can still use `scripts/start.ps1` for a browser-based workflow.

## Where is the probe?

Inside the **Windows desktop app** — it starts with PC Lab Kit. Developers can still build a standalone bundle with `.\scripts\build-agent-bundle.ps1` for local testing; it is not published as a GitHub Release asset.

## What is this product?

This repository is **PC Lab Kit** only: local diagnostics, hardware benchmarks, driver advice, stress/telemetry, and lab tools. It is not a PC builder, storefront, or cloud SaaS product.

## License

Elastic License 2.0 — see [LICENSE](../LICENSE).
