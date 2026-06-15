# Publish PCVerse on GitHub — push, releases, and discovery

Step-by-step guide for **first-time publishers**. Written for this repo (`drmikecrypto/pc-lab-kit`), Windows dev machine, Elastic License 2.0.

---

## What you are publishing

| Layer | What the public sees |
|-------|----------------------|
| **GitHub repo** | Source code, README, docs, license |
| **GitHub Release** | Version tag + installer downloads (`.exe`, `.run`) |
| **In-app updates** | App checks `GET /api/app/update` against your latest release tag |

People discover you via **Google**, **GitHub search**, **AI assistants**, and **word of mouth**. Structure everything so each channel gets the same clear story in the first 10 seconds.

---

## Part 1 — One-time setup

### 1.1 Accounts and tools

1. [GitHub account](https://github.com/signup) — use **drmikecrypto** (or your org).
2. **Git** — [git-scm.com/download/win](https://git-scm.com/download/win)
3. **GitHub CLI** (optional but recommended): `winget install GitHub.cli` then `gh auth login`

**You do not need to install PHP, Composer, or .NET manually.** The build scripts download the latest pinned versions into `build-cache/` automatically:

| Tool | When it is downloaded | Where it lives |
|------|------------------------|----------------|
| **PHP 8.3** | First `.\scripts\install.ps1` or `.\scripts\build-release.ps1` | `build-cache/php-win-x64/` → copied into installer as `runtime/php/` |
| **Composer** | Same | `build-cache/composer.phar` |
| **.NET 8 SDK** | First Windows installer build | `build-cache/dotnet/` (self-contained `.exe` needs no user .NET) |

End users who download **`PCVerse-Setup-Windows-x64.exe`** or **`PCVerse-Setup-Linux-x64.run`** get PHP + the full app pre-built — **no separate installs**.

To build installers locally:

```powershell
.\scripts\build-release.ps1
```

Internet is required once to populate `build-cache/` (then builds can reuse the cache).

### 1.2 Create the empty GitHub repository

**In the browser:**

1. Go to [github.com/new](https://github.com/new)
2. **Repository name:** `pc-lab-kit` (matches `GITHUB_REPO` in `.env.example`)
3. **Description** (copy this — SEO-tuned):

   ```
   PCVerse — local PC diagnostic lab: HWiNFO-style health scan, live sensors, RGB, benchmarks, optional AI advisor. Windows & Linux installers.
   ```

4. **Public**
5. **Do not** add README, .gitignore, or license (you already have them locally)
6. Click **Create repository**

**Or with CLI:**

```powershell
gh repo create drmikecrypto/pc-lab-kit --public --description "PCVerse — local PC diagnostic lab: health scan, sensors, RGB, benchmarks. Windows & Linux installers."
```

### 1.3 Repo settings (do this once — huge for GitHub search)

On GitHub → **Settings** → General:

| Field | Value |
|-------|--------|
| **Description** | Same as above |
| **Website** | `https://github.com/drmikecrypto/pc-lab-kit#readme` (later: your landing page) |
| **Topics** | Add all that apply (see [Topic list](#github-topics-add-all-of-these) below) |
| **Include in the home page** | Yes |
| **Releases** | Yes |
| **Packages** | Off (unless you publish containers later) |

Enable **Issues** and **Discussions** (optional) — signals an active project to GitHub ranking.

---

## Part 2 — Push the repo from your PC

Open **PowerShell** in the project folder:

```powershell
cd F:\StartUps\pc-lab-kit
```

### 2.1 Initialize git (skip if already a repo)

```powershell
git init
git branch -M main
```

### 2.2 Verify secrets are NOT committed

These must **never** be pushed:

- `.env` (real API keys)
- `storage/settings/local.json`
- `storage/database/*.sqlite`
- `public/downloads/*.exe`, `*.run`, large zips
- `vendor/` is usually committed OR use CI to `composer install` — **this repo expects `vendor/` after `composer install` locally; CI runs composer on release**

Quick check:

```powershell
git status
```

If `.env` appears, it should be in `.gitignore` (it is). If you see installer binaries under `public/downloads/`, they are gitignored — good.

### 2.3 First commit

```powershell
git add .
git commit -m "Initial release: PCVerse local PC diagnostic lab"
```

### 2.4 Connect remote and push

Replace with your URL if different:

```powershell
git remote add origin https://github.com/drmikecrypto/pc-lab-kit.git
git push -u origin main
```

If GitHub asks for login, use **Personal Access Token** (Settings → Developer settings → Tokens) or `gh auth login`.

**Verify:** open `https://github.com/drmikecrypto/pc-lab-kit` — README, LICENSE, and TRADEMARK should render.

---

## Part 3 — GitHub Releases (installers users download)

A **Release** = a version tag (e.g. `v1.0.0`) + release notes + **binary attachments**.

Your app’s update checker compares `APP_VERSION` in `.env` to the **latest release tag** (without the `v` prefix in semver compare — tag `v1.0.0` → version `1.0.0`).

### 3.1 Version checklist (every release)

1. Bump in `.env.example` and your local `.env`:

   ```
   APP_VERSION=1.0.0
   ```

2. Add a section to `CHANGELOG.md` (create file if missing):

   ```markdown
   ## [1.0.0] - 2026-06-14
   ### Added
   - Windows & Linux one-click installers
   - Diagnostic history and comparison
   ```

3. Run tests:

   ```powershell
   composer test
   ```

4. Build installers locally (recommended before tagging):

   ```powershell
   .\scripts\build-release.ps1
   ```

   Outputs:

   - `public/downloads/PCVerse-Setup-Windows-x64.exe`
   - `public/downloads/PCVerse-Setup-Linux-x64.run`

5. Commit version bump:

   ```powershell
   git add .env.example CHANGELOG.md
   git commit -m "Release v1.0.0"
   git push
   ```

### 3.2 Create the release (first time — manual, easiest)

1. GitHub → your repo → **Releases** → **Draft a new release**
2. **Choose a tag:** `v1.0.0` → **Create new tag on publish** → target **main**
3. **Release title:** `PCVerse v1.0.0 — Local PC diagnostic lab`
4. **Description** — use this template (SEO + clarity):

   ```markdown
   ## PCVerse v1.0.0

   Local-first PC health lab — replaces juggling HWiNFO, GPU-Z, and CSV imports in one desktop app.

   ### Downloads
   | Platform | File |
   |----------|------|
   | **Windows 64-bit** | `PCVerse-Setup-Windows-x64.exe` |
   | **Linux 64-bit** | `PCVerse-Setup-Linux-x64.run` |

   ### Highlights
   - One-click install + desktop shortcut
   - Quick health quiz + full Probe scan (Windows)
   - Test history with before/after comparison
   - Optional AI advisor (your API key, stored locally)

   ### Requirements
   - Windows 10+ or Linux x64 with PHP 8.2+ (Linux installer prompts if missing)

   ### License
   Source available under [Elastic License 2.0](https://github.com/drmikecrypto/pc-lab-kit/blob/main/LICENSE).
   ```

5. **Attach binaries:** drag both files from `public/downloads/` into **Attach binaries**
6. Check **Set as the latest release**
7. Click **Publish release**

**Verify update checker:** with the lab running, open `/diagnostic` — if local `APP_VERSION` is older than `1.0.0`, the update banner should appear.

### 3.3 Create the release (command line — faster next times)

After building installers and pushing commits:

```powershell
git tag v1.0.0
git push origin v1.0.0

gh release create v1.0.0 `
  --title "PCVerse v1.0.0 — Local PC diagnostic lab" `
  --notes-file RELEASE_NOTES_v1.0.0.md `
  public/downloads/PCVerse-Setup-Windows-x64.exe `
  public/downloads/PCVerse-Setup-Linux-x64.run
```

Create `RELEASE_NOTES_v1.0.0.md` with the same body as section 3.2 (keep for records; optional to commit).

### 3.4 CI builds on tag (already in repo)

Workflow: `.github/workflows/release-bundles.yml`

- Triggers on push tag `v*`
- Builds Windows + Linux installers in GitHub Actions
- Uploads **Artifacts** (not auto-attached to Release yet)

If you tag **before** building locally:

1. Push tag → wait for Actions to finish
2. Download artifacts from the workflow run
3. Edit the Release → attach the two files

**Later improvement:** add `softprops/action-gh-release` to attach artifacts automatically — optional.

---

## Part 4 — Smart repo structure (what goes up and why)

Design for **humans**, **Google**, **GitHub search**, and **AI crawlers** in one pass.

```
pc-lab-kit/
├── README.md              ← #1 discovery surface (see Part 5)
├── LICENSE                ← Elastic-2.0 (trust + clarity)
├── TRADEMARK.md
├── CHANGELOG.md           ← release history (SEO + trust)
├── CONTRIBUTING.md        ← how to PR (signals serious project)
├── docs/
│   ├── GITHUB_PUBLISH_AND_RELEASE.md   ← this file
│   └── FAQ.md             ← questions people Google (create next)
├── .github/
│   ├── workflows/release-bundles.yml
│   └── ISSUE_TEMPLATE/    ← optional: bug report + feature
├── public/                ← web root (no secrets)
├── scripts/               ← install, start, build-release
└── app/                   ← PHP application
```

**Do publish:** source, docs, small assets, `.env.example`, benchmark configs.  
**Do not publish:** `.env`, user SQLite DBs, API keys, built installers in git (attach to Releases only).

---

## Part 5 — SEO and discovery playbook

### 5.1 README rules (Google + GitHub + AI)

Your README is the **product page**. Structure:

1. **First line (H1)** — product name + primary keyword  
   `PCVerse — local PC diagnostic lab (Windows & Linux)`

2. **First paragraph (160 chars)** — answer “what is this?” in plain English  
   Include: *local*, *PC health*, *HWiNFO*, *GPU*, *Windows*, *Linux*, *no cloud account*

3. **Screenshots / GIF** (add when ready) — alt text:  
   `PCVerse diagnostic dashboard showing CPU GPU health score`

4. **Clear H2 sections:** Download | Features | Quick start | License  
   AI systems and Google both extract headings.

5. **Link once** to Releases:  
   `https://github.com/drmikecrypto/pc-lab-kit/releases/latest`

6. **Badges** (top of README — social proof):

   ```markdown
   ![License](https://img.shields.io/badge/License-Elastic--2.0-blue)
   ![PHP](https://img.shields.io/badge/PHP-8.2+-777?logo=php)
   ![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux-lightgrey)
   ```

### 5.2 GitHub topics (add all of these)

In repo **Settings → Topics**:

```
pc-diagnostics
hardware-monitoring
system-diagnostics
gpu-diagnostics
cpu-benchmark
hwinfo
gpu-z
local-first
privacy
windows
linux
rgb-control
telemetry
php
pc-building
health-check
open-source-alternative
elastic-license
```

Topics power **GitHub Explore** and related-repo graphs.

### 5.3 Release notes = SEO fuel

Each release should repeat:

- Product name **PCVerse**
- Problem words: *PC slow*, *thermal*, *bottleneck*, *HWiNFO export*, *diagnostic*
- Platform: *Windows installer*, *Linux installer*
- One “what changed” bullet list

Google indexes release pages. Unique titles per version: `PCVerse v1.1.0 — test history comparison`.

### 5.4 Google search (technical SEO basics)

| Tactic | Action |
|--------|--------|
| **Unique title** | Repo name + tagline in description |
| **Stable URL** | `github.com/drmikecrypto/pc-lab-kit` — don’t rename lightly |
| **CHANGELOG + Releases** | Fresh content signals activity |
| **FAQ doc** | Add `docs/FAQ.md`: “Is PCVerse free?”, “HWiNFO alternative?”, “Does it upload data?” |
| **External links** | Post on Reddit r/pcmasterrace, r/linux, HN, dev.to — link to Releases |
| **Social preview** | Add `docs/social-preview.png` 1280×640; set as repo **Social preview** in Settings |

You don’t control Google directly — you control **clear pages with the words people search**.

### 5.5 AI assistants (ChatGPT, Claude, Perplexity, Cursor)

Models learn from **public GitHub**, docs, and the web.

| Tactic | Why it works |
|--------|----------------|
| **Explicit first paragraph in README** | “PCVerse is a local PC diagnostic laboratory for Windows and Linux…” |
| **`docs/FAQ.md`** | Q&A format matches how users ask AI |
| **Consistent naming** | Always **PCVerse**, not “pc lab kit” and “PCVerse” mixed |
| **Comparison phrases** | “Alternative to running HWiNFO + GPU-Z + spreadsheets locally” |
| **LICENSE summary in README** | AI users ask “can I host this?” — table already answers |
| **Optional `llms.txt`** at repo root | Emerging convention — short index for AI crawlers (see template below) |

**Optional `llms.txt` (repo root):**

```text
# PCVerse
> Local-first PC diagnostic lab for Windows and Linux.

- Install: GitHub Releases — PCVerse-Setup-Windows-x64.exe or PCVerse-Setup-Linux-x64.run
- Docs: README.md, docs/FAQ.md
- License: Elastic License 2.0 — local use OK; competing hosted SaaS not permitted
- Author: https://github.com/drmikecrypto
```

### 5.6 GitHub “Trending” and stars (realistic expectations)

You don’t hack the trending list. You **earn visibility**:

1. Ship a **polished v1.0.0** with working installers
2. **Respond to issues** within 48h
3. **Post** where the audience lives (PC building, homelab, Linux desktop)
4. **One clear demo** — 60s screen recording in README
5. **Repeat releases** every 4–8 weeks (momentum)

---

## Part 6 — Suggested launch sequence

Use this order **once**, then repeat Part 3 for each version.

| Step | Action |
|------|--------|
| 1 | Finish README + add 1 screenshot |
| 2 | Add `CHANGELOG.md`, `CONTRIBUTING.md`, `docs/FAQ.md` |
| 3 | Set repo description + **all topics** |
| 4 | `git push` to `main` |
| 5 | `.\scripts\build-release.ps1` |
| 6 | Publish **Release v1.0.0** with both installers |
| 7 | Test download + install on a clean folder |
| 8 | Post launch link (Releases URL, not random branch) |
| 9 | Pin the release in GitHub Discussions or profile README |

---

## Part 7 — Troubleshooting

| Problem | Fix |
|---------|-----|
| `git push` rejected | `git pull --rebase origin main` then push again |
| Installers missing on Release | Attach manually; filenames must match app routes |
| Update banner never shows | Release tag must be **newer** semver than `APP_VERSION`; repo must be public |
| CI fails on tag | Check Actions log; usually missing PHP extension or dotnet on Windows job |
| Huge push rejected | Ensure `vendor/` size OK; use Git LFS only if you add large assets |
| License confusion on GitHub | Set license to **Other**; point to `LICENSE` file |

---

## Part 8 — Quick reference commands

```powershell
# Daily dev
cd F:\StartUps\pc-lab-kit
.\scripts\start.ps1
# → http://127.0.0.1:8080/diagnostic

# Ship a version
composer test
.\scripts\build-release.ps1
# bump APP_VERSION, update CHANGELOG.md, commit, push
git tag v1.0.0
git push origin v1.0.0
gh release create v1.0.0 --title "PCVerse v1.0.0" `
  --notes "See CHANGELOG.md" `
  public/downloads/PCVerse-Setup-Windows-x64.exe `
  public/downloads/PCVerse-Setup-Linux-x64.run
```

---

## Links

- Repo: [github.com/drmikecrypto/pc-lab-kit](https://github.com/drmikecrypto/pc-lab-kit)
- Profile: [github.com/drmikecrypto](https://github.com/drmikecrypto)
- Elastic License: [elastic.co/licensing/elastic-license](https://www.elastic.co/licensing/elastic-license)

*Maintainer guide for PCVerse — update this doc when release automation changes.*
