# PC Lab Kit Desktop

Tauri 2 shell that embeds the PHP lab UI in a native window.

## Develop

```powershell
# From repo root — uses repo as lab (PCLAB_LAB_ROOT optional)
cd desktop
npm install
$env:PCLAB_LAB_ROOT = (Resolve-Path ..).Path
npm run tauri -- dev
```

## Build installers

```powershell
.\scripts\build-desktop-windows.ps1   # → public/downloads/PcLabKit-Setup-Windows-x64.exe
```

```bash
./scripts/build-desktop-linux.sh      # → public/downloads/PcLabKit-Linux-x64.AppImage
```
