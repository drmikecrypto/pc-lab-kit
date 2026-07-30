# Build PcLabHwMon.exe (LibreHardwareMonitor) for the probe agent bundle
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$proj = Join-Path $root "agent\pclab_probe\PcLabHwMon\PcLabHwMon.csproj"
$out = Join-Path $root "agent\pclab_probe\PcLabHwMon.exe"

Write-Host "Publishing PcLabHwMon..."
dotnet publish $proj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o (Join-Path $root "agent\pclab_probe\PcLabHwMon\bin")

$built = Join-Path $root "agent\pclab_probe\PcLabHwMon\bin\PcLabHwMon.exe"
if (-not (Test-Path $built)) {
    Write-Error "Build failed: $built not found"
}

Copy-Item $built $out -Force
Write-Host "OK: $out ($((Get-Item $out).Length) bytes)"
