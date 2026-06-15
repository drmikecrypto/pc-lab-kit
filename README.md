# PCVerse — local PC laboratory

**PCVerse** is a local-first PC test lab: hardware probe, health scoring, live telemetry, RGB control, and an optional AI advisor (your API key). Everything runs on your machine — no cloud account required.

## Download (one click per platform)

| Platform | What you get |
|----------|--------------|
| **Windows 64-bit** | `PCVerse-Setup-Windows-x64.exe` — full lab, bundled PHP 8.3, Probe, desktop shortcut — **no PHP/Composer/.NET install** |
| **Linux 64-bit** | `PCVerse-Setup-Linux-x64.run` — guided install, bundled PHP, folder picker, desktop shortcut — **no apt/brew PHP step** |

Open **http://127.0.0.1:8080/download** in the running lab, or build installers locally:

```powershell
.\scripts\build-release.ps1
```

### Windows — user flow

1. Download **PCVerse-Setup-Windows-x64.exe**
2. Run it → choose install folder → tick **Create desktop shortcut**
3. Double-click **PCVerse** on the desktop (or `PCVerse.bat` in the install folder)

### Linux — user flow

1. Download **PCVerse-Setup-Linux-x64.run**
2. `chmod +x PCVerse-Setup-Linux-x64.run && ./PCVerse-Setup-Linux-x64.run`
3. Pick folder, optional desktop shortcut, launch from **PCVerse** shortcut

Requires nothing else — PHP is bundled inside the `.run` installer.

## Developers (Git clone)

**Requirements:** Git only for a normal setup. **`.\scripts\install.ps1`** (Windows) or **`./scripts/install.sh`** (Linux) auto-download **PHP 8.3**, **Composer**, and (for building the Windows `.exe`) **.NET 8 SDK** into `build-cache/` on first run.

```powershell
git clone https://github.com/drmikecrypto/pc-lab-kit.git
cd pc-lab-kit
.\scripts\install.ps1
.\scripts\start.ps1
```

```bash
git clone https://github.com/drmikecrypto/pc-lab-kit.git
cd pc-lab-kit
chmod +x scripts/install.sh scripts/start.sh
./scripts/install.sh
./scripts/start.sh
```

Open **http://127.0.0.1:8080/diagnostic**

## Optional AI advisor (BYOK)

PCVerse can turn each scan into **expert hardware analysis** — bottleneck diagnosis, upgrade plan, thermal risks, and comparison vs your last test. This is **optional**; the lab works fully without it.

### How to enable

1. Open the lab → click **Settings** in the top nav (or **AI advisor** under the page title).
2. Paste an **OpenAI-compatible API key** (`sk-…`).
3. Set **API base URL** (default `https://api.openai.com/v1`) and **model**.
   - Recommended for best analysis: `gpt-4o` or `gpt-4.1`
   - Default / budget: `gpt-4o-mini`
4. Click **Save**. The key is stored locally in `storage/settings/local.json` — not sent to PCVerse servers.

Works with any OpenAI-compatible provider (OpenAI, Azure OpenAI, local Ollama with `/v1`, etc.).

### When analysis runs

After you finish a **Quick scan** or **Full scan**, PCVerse sends your diagnostic results (scores, temps, bottleneck, history comparison, benchmark context) to **your** LLM and shows:

- **Headline** — the main finding  
- **Summary** — what it means and what to do  
- **Do this first** — priority actions  
- **Upgrade plan** — ranked component recommendations  
- **Thermal & stability** — burn-in / PSU / throttle risks  
- **Changes since last test** — if you have saved history  

### Alternative: `.env`

```env
LLM_API_KEY=sk-your-key-here
LLM_BASE_URL=https://api.openai.com/v1
LLM_MODEL=gpt-4o
```

When `LLM_API_KEY` is set in `.env`, it overrides the UI-saved key.

## Tests

```powershell
composer test
```

## License

PCVerse is **source available** under the [Elastic License 2.0](LICENSE) — not OSI “open source.”

| Allowed | Not allowed |
|---------|-------------|
| Download, install, and run locally | Offer PCVerse (or a substantial fork) as a **hosted/managed service** to third parties |
| Study, modify, and contribute back | Remove copyright or license notices |
| Use for personal, team, or internal lab work | Use the **PCVerse** name for a competing cloud product (see [TRADEMARK.md](TRADEMARK.md)) |

The official hosted PCVerse SaaS will come from the licensor only: [github.com/drmikecrypto](https://github.com/drmikecrypto).

**Commercial licensing** (OEM, white-label, managed service, trademark): contact via GitHub before launch.

Third-party dependencies in `vendor/` remain under their respective licenses (mostly MIT).

## Docs

All documentation is under **[docs/](docs/README.md)**.

| Doc | Purpose |
|-----|---------|
| [FAQ](docs/FAQ.md) | Common questions (search + AI friendly) |
| [Integration guide](docs/INTEGRATION.md) | Kit layout, routes, Flutter contract |
| [Mobile API routes](docs/API_MOBILE_ROUTES.md) | Flutter ↔ PHP endpoint map |
| [Contributing](CONTRIBUTING.md) | PR guidelines |
| [Changelog](CHANGELOG.md) | Version history |
