# Build pc-lab-kit-probe-windows.zip for /download/probe-windows
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$agentDir = Join-Path $root "agent\pclab_probe"
$outDir = Join-Path $root "public\downloads"
$outZip = Join-Path $outDir "pc-lab-kit-probe-windows.zip"
$hwmonScript = Join-Path $root "scripts\build-pclab-hwmon.ps1"
$vkScript = Join-Path $root "scripts\build-pclab-vkbench.ps1"

if (-not (Test-Path $agentDir)) {
    Write-Error "Agent folder not found: $agentDir"
}

if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    try {
        & $hwmonScript
    } catch {
        Write-Warning "PcLabHwMon build skipped: $_"
    }
    try {
        & $vkScript
    } catch {
        Write-Warning "PcLabVkBench build skipped: $_"
    }
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
if (Test-Path $outZip) { Remove-Item $outZip -Force }

$stage = Join-Path $env:TEMP "pclab-probe-stage"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null

Copy-Item (Join-Path $agentDir "*.ps1") $stage
Copy-Item (Join-Path $agentDir "*.bat") $stage
Copy-Item (Join-Path $agentDir "ProbeLib") (Join-Path $stage "ProbeLib") -Recurse
if (Test-Path (Join-Path $agentDir "PcLabHwMon.exe")) {
    Copy-Item (Join-Path $agentDir "PcLabHwMon.exe") $stage
}
if (Test-Path (Join-Path $agentDir "PcLabVkBench.exe")) {
    Copy-Item (Join-Path $agentDir "PcLabVkBench.exe") $stage
}
$tools = Join-Path $agentDir "tools"
if (Test-Path $tools) {
    Copy-Item $tools (Join-Path $stage "tools") -Recurse
}

Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $outZip -Force
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Built $outZip ($((Get-Item $outZip).Length) bytes)"
