# PC Lab Kit

**PC Lab Kit** is a local-first PC diagnostic and hardware lab. Download a portable build for your OS, or run from source.

## Download (end users)

Get the latest release: **https://github.com/drmikecrypto/pc-lab-kit/releases/latest**

| File | Platform | How to run |
|------|----------|------------|
| `pc-lab-kit-windows-x64.zip` | Windows x64 | Unzip → double-click **PcLabKit.bat** |
| `pc-lab-kit-linux-x64.tar.gz` | Linux x64 | `tar xzf … && cd pc-lab-kit && chmod +x PcLabKit && ./PcLabKit` |
| `pc-lab-kit-probe-windows.zip` | Windows | Unzip → run **Start-PcLabProbe.bat** (for sensors, benches, OC) |

The lab opens at **http://127.0.0.1:8080/diagnostic**. PHP is bundled — no separate install.

## Quick start (developers)

**Requirements:** Git. On first run, `.\scripts\install.ps1` (Windows) or `./scripts/install.sh` (Linux/macOS) can bootstrap **PHP 8.3** and **Composer** into `build-cache/`.

```powershell
git clone https://github.com/drmikecrypto/pc-lab-kit.git
cd pc-lab-kit
.\scripts\install.ps1
.\scripts\start.ps1
```

```bash
git clone https://github.com/drmikecrypto/pc-lab-kit.git
cd pc-lab-kit
chmod +x scripts/install.sh scripts/start.sh PcLabKit
./scripts/install.sh
./scripts/start.sh
```

Open **http://127.0.0.1:8080/diagnostic**

Or double-click **`PcLabKit.bat`** (Windows) / run **`./PcLabKit`** (Unix).

## Windows probe (full hardware scan)

For real sensors, benchmarks, stress tests, RGB, and safe OC:

1. Download `pc-lab-kit-probe-windows.zip` from the [latest release](https://github.com/drmikecrypto/pc-lab-kit/releases/latest), or build with `.\scripts\build-agent-bundle.ps1`
2. Or open **http://127.0.0.1:8080/download/probe-windows** while the lab is running
3. Unzip and run **`Start-PcLabProbe.bat`** (self-elevates for CPU die temps)
4. In the lab, open **Full scan** → **Connect**

Probe listens on **http://127.0.0.1:18765/** (status page + JSON API).

## Build release packages locally

```powershell
.\scripts\build-app-windows.ps1          # → public/downloads/pc-lab-kit-windows-x64.zip
.\scripts\build-agent-bundle.ps1         # → public/downloads/pc-lab-kit-probe-windows.zip
```

```bash
chmod +x scripts/*.sh
./scripts/build-app-linux.sh             # → public/downloads/pc-lab-kit-linux-x64.tar.gz
```

Tag `v*` pushes trigger GitHub Actions to publish all three assets on the release.

## Optional AI advisor (BYOK)

1. Lab → **Settings**
2. Paste an OpenAI-compatible API key
3. Save — key stays in `storage/settings/local.json`

Works without AI; BYOK only unlocks the advisor narrative.

```env
LLM_API_KEY=sk-your-key-here
LLM_BASE_URL=https://api.openai.com/v1
LLM_MODEL=gpt-4o
```

## Tests

```powershell
composer test
```

## License

PC Lab Kit is **source available** under the [Elastic License 2.0](LICENSE).

| Allowed | Not allowed |
|---------|-------------|
| Download, install, and run locally | Offer PC Lab Kit (or a substantial fork) as a **hosted/managed service** to third parties |
| Study, modify, and contribute back | Remove copyright or license notices |
| Use for personal, team, or internal lab work | |

Third-party dependencies in `vendor/` remain under their respective licenses.

## Docs

| Doc | Purpose |
|-----|---------|
| [FAQ](docs/FAQ.md) | Common questions |
| [Integration guide](docs/INTEGRATION.md) | Kit layout and routes |
| [Contributing](CONTRIBUTING.md) | PR guidelines |
| [Changelog](CHANGELOG.md) | Version history |
