# Contributing to PCVerse

Thanks for your interest in PCVerse.

## Before you start

- Read [LICENSE](LICENSE) (Elastic License 2.0) and [TRADEMARK.md](TRADEMARK.md).
- Local use and contributions are welcome.
- You may not launch a **competing hosted PCVerse service** for third parties without a commercial license.

## Development setup

```powershell
git clone https://github.com/drmikecrypto/pc-lab-kit.git
cd pc-lab-kit
.\scripts\install.ps1
.\scripts\start.ps1
composer test
```

Open http://127.0.0.1:8080/diagnostic

## Pull requests

1. Fork and branch from `main`
2. Keep changes focused
3. Run `composer test`
4. Describe **what** and **why** in the PR

## Reporting bugs

Open a GitHub Issue with OS, PHP version, steps to reproduce, and expected vs actual behavior.
