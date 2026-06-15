# Build PcVerseHwMon.exe (LibreHardwareMonitor) for agent bundle
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$proj = Join-Path $root "agent\pcverse_probe\PcVerseHwMon\PcVerseHwMon.csproj"
$out = Join-Path $root "agent\pcverse_probe\PcVerseHwMon.exe"

Write-Host "Publishing PcVerseHwMon..."
dotnet publish $proj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o (Join-Path $root "agent\pcverse_probe\PcVerseHwMon\bin")

$built = Join-Path $root "agent\pcverse_probe\PcVerseHwMon\bin\PcVerseHwMon.exe"
if (-not (Test-Path $built)) {
    Write-Error "Build failed: $built not found"
}

Copy-Item $built $out -Force
Write-Host "OK: $out ($((Get-Item $out).Length) bytes)"
