# Build PCVerse native desktop Windows installer (no PHP/browser bundle)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$outDir = Join-Path $root 'public\downloads'
$outExe = Join-Path $outDir 'PCVerse-Native-Setup-Windows-x64.exe'
$setupDir = Join-Path $root 'installer\PCVerse.Setup'
$payloadZip = Join-Path $setupDir 'payload.zip'
$stage = Join-Path $env:TEMP ('pcverse-native-' + [guid]::NewGuid().ToString('n'))

. (Join-Path $root 'scripts\bootstrap-build-tools.ps1')

function Copy-ProbeMinimal {
    param([string]$DestRoot)
    $probeDest = Join-Path $DestRoot 'agent\pcverse_probe'
    New-Item -ItemType Directory -Force -Path $probeDest | Out-Null

    $probeSrc = Join-Path $root 'agent\pcverse_probe'
    $include = @(
        'PcVerseHwMon.exe',
        'PCVerseProbeServe.ps1',
        'PCVerseProbe.ps1'
    )
    foreach ($name in $include) {
        $src = Join-Path $probeSrc $name
        if (Test-Path $src) {
            Copy-Item $src (Join-Path $probeDest $name) -Force
        }
    }

    $libSrc = Join-Path $probeSrc 'ProbeLib'
    $libDest = Join-Path $probeDest 'ProbeLib'
    if (Test-Path $libSrc) {
        Copy-Item $libSrc $libDest -Recurse -Force
    }
}

function Copy-NativeDesktop {
    param([string]$DestRoot)
    $binDest = Join-Path $DestRoot 'bin'
    New-Item -ItemType Directory -Force -Path $binDest | Out-Null

    $exeDir = Join-Path $root 'native\build\apps\pcverse\Release'
    if (-not (Test-Path (Join-Path $exeDir 'pcverse.exe'))) {
        Write-Host 'Building native desktop...' -ForegroundColor Cyan
        & (Join-Path $root 'scripts\build-native-desktop.ps1')
        $exeDir = Join-Path $root 'native\build\apps\pcverse\Release'
    }

    Get-ChildItem $exeDir -File | Copy-Item -Destination $binDest -Force
    Get-ChildItem $exeDir -Directory | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $binDest $_.Name) -Recurse -Force
    }
}

function Write-NativeLauncher {
    param([string]$DestRoot)
    @'
@echo off
setlocal
cd /d "%~dp0"
start "" "%~dp0bin\pcverse.exe"
'@ | Set-Content -Path (Join-Path $DestRoot 'PCVerse.bat') -Encoding ASCII
}

try {
    Initialize-BuildTools
    try { & (Join-Path $root 'scripts\build-pcverse-hwmon.ps1') } catch { Write-Warning $_ }

    Write-Host 'Staging native payload...' -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    Copy-NativeDesktop -DestRoot $stage
    Copy-ProbeMinimal -DestRoot $stage
    Write-NativeLauncher -DestRoot $stage

    New-Item -ItemType Directory -Force -Path (Join-Path $stage 'native\assets') | Out-Null
    $catalog = Join-Path $root 'native\assets\tool_catalog.json'
    if (Test-Path $catalog) {
        Copy-Item $catalog (Join-Path $stage 'native\assets\tool_catalog.json') -Force
    }

    if (Test-Path $payloadZip) { Remove-Item $payloadZip -Force }
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $payloadZip -CompressionLevel Optimal -Force

    $payloadMb = [math]::Round((Get-Item $payloadZip).Length / 1MB, 1)
    Write-Host ("Publishing native installer ({0} MB payload)..." -f $payloadMb) -ForegroundColor Cyan

    $dotnet = Initialize-BundledDotNet
    Push-Location $setupDir
    & $dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
    Pop-Location

    $published = Join-Path $setupDir 'bin\Release\net8.0-windows\win-x64\publish\PCVerse-Setup.exe'
    if (-not (Test-Path $published)) {
        throw "Publish output not found: $published"
    }

    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    Copy-Item $published $outExe -Force
    $exeMb = [math]::Round((Get-Item $outExe).Length / 1MB, 1)
    Write-Host ('Built {0} ({1} MB)' -f $outExe, $exeMb) -ForegroundColor Green
}
finally {
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
}
