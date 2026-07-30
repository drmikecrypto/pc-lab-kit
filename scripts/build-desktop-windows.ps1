#Requires -Version 5.1
<#
  Build PcLabKit-Setup-Windows-x64.exe (Tauri NSIS installer).
#>
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$stageScript = Join-Path $root 'scripts\stage-desktop-payload.ps1'
$desktop = Join-Path $root 'desktop'
$outDir = Join-Path $root 'public\downloads'
$outExe = Join-Path $outDir 'PcLabKit-Setup-Windows-x64.exe'

Write-Host '=== Stage lab payload ===' -ForegroundColor Cyan
& $stageScript

Write-Host '=== npm install (desktop) ===' -ForegroundColor Cyan
Push-Location $desktop
try {
    if (-not (Test-Path 'node_modules')) {
        npm install
    } else {
        npm install --prefer-offline
    }

    Write-Host '=== tauri build (NSIS) ===' -ForegroundColor Cyan
    npm run tauri -- build --bundles nsis
}
finally {
    Pop-Location
}

$bundleDir = Join-Path $desktop 'src-tauri\target\release\bundle\nsis'
$built = Get-ChildItem $bundleDir -Filter '*.exe' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $built) {
    throw "NSIS installer not found under $bundleDir"
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Copy-Item $built.FullName $outExe -Force
$mb = [math]::Round((Get-Item $outExe).Length / 1MB, 1)
Write-Host ("Built {0} ({1} MB)" -f $outExe, $mb) -ForegroundColor Green
