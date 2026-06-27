# Build native desktop installers (Windows .exe + Linux .run via WSL)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

Write-Host 'PCVerse native installers' -ForegroundColor Cyan

& (Join-Path $root 'scripts\build-native-installer-windows.ps1')

$linuxBuilt = $false
if (Get-Command wsl -ErrorAction SilentlyContinue) {
    try {
        $wslPathArg = ($root -replace '\\', '/')
        $wslRoot = (wsl wslpath -u $wslPathArg 2>$null).Trim()
        if (-not $wslRoot) {
            throw "wslpath returned empty path for $wslPathArg"
        }
        Write-Host "Building Linux native installer via WSL ($wslRoot)..." -ForegroundColor Cyan
        wsl bash -lc "export PATH=\"\$HOME/.local/bin:\$PATH\"; cd '$wslRoot' && chmod +x scripts/bootstrap-qt.sh scripts/build-native-desktop.sh scripts/build-native-installer-linux.sh scripts/deploy-qt-linux.sh && ./scripts/build-native-installer-linux.sh"
        if ($LASTEXITCODE -ne 0) {
            throw "WSL build exited with code $LASTEXITCODE"
        }
        $linuxBuilt = $true
    } catch {
        Write-Warning "WSL Linux native installer failed: $_"
    }
}

if (-not $linuxBuilt) {
    Write-Warning @'
Linux native .run not built.

From WSL, cd into the repo first, then run the installer script:
  cd /mnt/f/StartUps/pc-lab-kit
  sudo apt install cmake build-essential patchelf python3-pip
  ./scripts/build-native-installer-linux.sh

Or re-run from PowerShell (after WSL deps are installed):
  .\scripts\build-native-release.ps1
'@
}

Write-Host ''
Write-Host 'Native installers in public/downloads/:' -ForegroundColor Green
Get-ChildItem (Join-Path $root 'public\downloads') -File | Where-Object { $_.Name -like 'PCVerse-Native*' } | Format-Table Name, Length
