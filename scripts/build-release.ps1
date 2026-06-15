# Build both one-click installers (Windows .exe + Linux .run)
# Auto-downloads PHP, Composer, and .NET 8 SDK into build-cache/ on first run.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

Write-Host 'PCVerse installers' -ForegroundColor Cyan

& (Join-Path $root 'scripts\build-installer-windows.ps1')

$linuxBuilt = $false
if (Get-Command wsl -ErrorAction SilentlyContinue) {
    try {
        $wslRoot = (wsl wslpath -u $root).Trim()
        wsl bash -c "cd '$wslRoot' && chmod +x scripts/build-installer-linux.sh scripts/stage-payload-unix.sh && ./scripts/build-installer-linux.sh"
        $linuxBuilt = $true
    } catch {
        Write-Warning "WSL Linux installer failed: $_"
    }
}

if (-not $linuxBuilt) {
    Write-Warning 'Linux .run not built — run scripts/build-installer-linux.sh on Linux or WSL.'
}

Write-Host ''
Write-Host 'Installers in public/downloads/:' -ForegroundColor Green
Get-ChildItem (Join-Path $root 'public\downloads') -Include *.exe,*.run | Format-Table Name, Length
