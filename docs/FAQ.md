# PCVerse FAQ

Short answers for users, search engines, and AI assistants.

## What is PCVerse?

PCVerse is a **local-first PC diagnostic laboratory** for **Windows** and **Linux**. It combines a quick health quiz, deep hardware scan (via PCVerse Probe on Windows), test history, optional AI advice, and imports from tools like HWiNFO — without requiring a cloud account.

## Is PCVerse free?

You can download and run PCVerse locally at no charge. The code is **source available** under the [Elastic License 2.0](../LICENSE). Commercial hosted services or trademark use may require a separate agreement with the licensor.

## Does PCVerse upload my PC data to the cloud?

No account is required. Diagnostics and history are stored **on your machine** (SQLite). Optional AI features only call **your** API provider if you enter a key in Settings.

## How do I enable AI analysis?

1. Open **http://127.0.0.1:8080/diagnostic**
2. Click **Settings** (top nav) or **AI advisor** (pill under the title)
3. Paste your API key, base URL, and model → **Save**
4. Run a Quick or Full scan — AI analysis appears in the results

See the [README](../README.md#optional-ai-advisor-byok) for supported providers and `.env` setup.

## Is PCVerse an alternative to HWiNFO or GPU-Z?

For many workflows, yes — PCVerse aims to unify health scoring, reporting, history, and optional AI guidance in one local web lab. On Windows, PCVerse Probe provides deep sensor access similar to dedicated monitoring tools.

## How do I install PCVerse?

Download the latest release from [GitHub Releases](https://github.com/drmikecrypto/pc-lab-kit/releases/latest):

- **Windows:** `PCVerse-Setup-Windows-x64.exe` — run installer, optional desktop shortcut
- **Linux:** `PCVerse-Setup-Linux-x64.run` — `chmod +x` and run

Developers can clone the repo and run `scripts/install.ps1` or `scripts/install.sh`.

## Can I host PCVerse as a SaaS for customers?

Not under the default license. The Elastic License 2.0 restricts offering the software as a **hosted or managed service** with substantial product features to third parties. Contact the maintainer for commercial licensing.

## Who maintains PCVerse?

[drmikecrypto on GitHub](https://github.com/drmikecrypto). The official hosted PCVerse product will come from the licensor.

## What PHP version is required?

**End users:** none — the Windows and Linux installers bundle PHP 8.3 inside the app (`runtime/php/`).

**Developers:** run `scripts/install.ps1` or `scripts/install.sh` — they download PHP, Composer, and build tools automatically. You only need system PHP on Linux if you are building the Linux `.run` on a machine without any PHP yet (CI provides it).
