#Requires -Version 5.1
<#
  Fetch portable ffmpeg into agent/pclab_probe/tools/ffmpeg/ for LCD Studio.
  liquidctl is not auto-downloaded (Python/pip or vendor EXE) — prints install hints.
  Run from repo root:  powershell -File .\scripts\fetch-lcd-tools.ps1
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$tools = Join-Path $root 'agent\pclab_probe\tools'
$ffDir = Join-Path $tools 'ffmpeg'
New-Item -ItemType Directory -Force -Path $ffDir | Out-Null

$ffmpegExe = Join-Path $ffDir 'ffmpeg.exe'
if (Test-Path $ffmpegExe) {
    Write-Host "ffmpeg already present: $ffmpegExe" -ForegroundColor Green
} else {
    # Official gyan.dev essentials build (common Windows portable zip)
    $zipUrl = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip'
    $zipPath = Join-Path $env:TEMP ('pclab_ffmpeg_' + [guid]::NewGuid().ToString('n') + '.zip')
    Write-Host "Downloading ffmpeg essentials..." -ForegroundColor Cyan
    Write-Host "  $zipUrl"
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
    $extract = Join-Path $env:TEMP ('pclab_ffmpeg_ex_' + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Force -Path $extract | Out-Null
    Expand-Archive -Path $zipPath -DestinationPath $extract -Force
    $found = Get-ChildItem $extract -Filter ffmpeg.exe -Recurse | Select-Object -First 1
    if (-not $found) { throw 'ffmpeg.exe not found inside downloaded zip' }
    Copy-Item $found.FullName $ffmpegExe -Force
    $ffprobe = Get-ChildItem $found.DirectoryName -Filter ffprobe.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ffprobe) { Copy-Item $ffprobe.FullName (Join-Path $ffDir 'ffprobe.exe') -Force }
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Installed: $ffmpegExe" -ForegroundColor Green
}

Write-Host ""
Write-Host "liquidctl (NZXT LCD push):" -ForegroundColor Cyan
Write-Host "  Option A: pip install liquidctl   then ensure liquidctl is on PATH"
Write-Host "  Option B: place liquidctl.exe at:"
Write-Host "    $(Join-Path $tools 'liquidctl\liquidctl.exe')"
Write-Host "    or $(Join-Path $tools 'liquidctl.exe')"
Write-Host ""
Write-Host "Then Rescan panels in LCD Studio." -ForegroundColor Yellow
