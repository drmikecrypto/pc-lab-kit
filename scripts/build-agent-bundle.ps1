# Build pcverse-probe-windows.zip for /download/pcverse-probe.zip
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$agentDir = Join-Path $root "agent\pcverse_probe"
$outDir = Join-Path $root "public\downloads"
$outZip = Join-Path $outDir "pcverse-probe-windows.zip"
$hwmonScript = Join-Path $root "scripts\build-pcverse-hwmon.ps1"

if (-not (Test-Path $agentDir)) {
    Write-Error "Agent folder not found: $agentDir"
}

# Build LibreHardwareMonitor helper if dotnet available
if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    try {
        & $hwmonScript
    } catch {
        Write-Warning "PcVerseHwMon build skipped: $_"
    }
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
if (Test-Path $outZip) { Remove-Item $outZip -Force }

$stage = Join-Path $env:TEMP "pcverse-probe-stage"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null

Copy-Item (Join-Path $agentDir "*.ps1") $stage
Copy-Item (Join-Path $agentDir "*.bat") $stage
Copy-Item (Join-Path $agentDir "ProbeLib") (Join-Path $stage "ProbeLib") -Recurse
if (Test-Path (Join-Path $agentDir "PcVerseHwMon.exe")) {
    Copy-Item (Join-Path $agentDir "PcVerseHwMon.exe") $stage
}

Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $outZip -Force
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Built $outZip ($((Get-Item $outZip).Length) bytes)"

