# Build PcLabVkBench.exe — native GPU compute helper for the probe
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$proj = Join-Path $root "agent\pclab_probe\PcLabVkBench\PcLabVkBench.csproj"
$out = Join-Path $root "agent\pclab_probe\PcLabVkBench.exe"

Write-Host "Publishing PcLabVkBench..."
dotnet publish $proj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o (Join-Path $root "agent\pclab_probe\PcLabVkBench\bin")

$built = Join-Path $root "agent\pclab_probe\PcLabVkBench\bin\PcLabVkBench.exe"
if (-not (Test-Path $built)) {
    Write-Error "Build failed: $built not found"
}

Copy-Item $built $out -Force
Write-Host "OK: $out ($((Get-Item $out).Length) bytes)"
