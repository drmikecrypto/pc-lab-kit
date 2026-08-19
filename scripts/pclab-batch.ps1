# PC Lab Kit batch CLI — queue burn-in / deep lab jobs for shop mode
param(
    [string]$Profile = 'deep',
    [string]$Output = './reports',
    [switch]$Discover
)

$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Test-Path $root)) { $root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }

if ($Discover) {
    $php = Join-Path $root 'vendor\bin\phpunit'
    Write-Host 'Fleet discovery via PHP ShopFleetService — run from lab API or:'
    Write-Host "  curl http://127.0.0.1:8080/api/diagnostic/fleet/discover"
    exit 0
}

New-Item -ItemType Directory -Force -Path $Output | Out-Null
$job = @{
    profile = $Profile
    output  = (Resolve-Path $Output).Path
    queued  = (Get-Date).ToUniversalTime().ToString('o')
}
$outFile = Join-Path $Output ("batch-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
$job | ConvertTo-Json -Depth 6 | Set-Content -Path $outFile -Encoding UTF8
Write-Host "Queued batch manifest: $outFile"
Write-Host "Start Full Lab from desktop or POST /api/diagnostic/suite/start with profile=$Profile"
