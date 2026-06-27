# Launch PCVerse native desktop (dev). Starts probe if port 18765 is free.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

$exe = Join-Path $root 'native\build\apps\pcverse\Release\pcverse.exe'
if (-not (Test-Path $exe)) {
    Write-Host 'pcverse.exe not built. Run: .\scripts\build-native-desktop.ps1' -ForegroundColor Yellow
    exit 1
}

$probePort = 18765
$probeUp = $false
try {
    $null = Invoke-RestMethod -Uri "http://127.0.0.1:$probePort/health" -TimeoutSec 2
    $probeUp = $true
} catch {
    $probeUp = $false
}

if (-not $probeUp) {
    Write-Host 'Starting probe on port 18765...' -ForegroundColor Cyan
    $probeScript = Join-Path $root 'agent\pcverse_probe\PCVerseProbeServe.ps1'
    Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $probeScript `
        -WorkingDirectory $root -WindowStyle Minimized
    Start-Sleep -Seconds 2
}

Write-Host "Launching PCVerse desktop..." -ForegroundColor Green
Start-Process -FilePath $exe -WorkingDirectory $root
