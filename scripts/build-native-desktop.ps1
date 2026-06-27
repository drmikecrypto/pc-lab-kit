# Build PCVerse native Qt desktop (Phase 1)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

& (Join-Path $root 'scripts\bootstrap-qt.ps1')

$php = 'php'
if (Test-Path (Join-Path $root 'runtime\php\php.exe')) {
    $php = Join-Path $root 'runtime\php\php.exe'
}
if (Test-Path (Join-Path $root 'vendor\autoload.php')) {
    & $php (Join-Path $root 'scripts\export-tool-catalog.php')
} else {
    Write-Host 'Skipping tool catalog export (vendor/ missing)' -ForegroundColor Yellow
}

$config = Get-Content (Join-Path $root 'config\build-deps.json') -Raw | ConvertFrom-Json
$versionRoot = Join-Path $root "build-cache\qt\$($config.qt_version)"
$qtDir = Get-ChildItem -Path $versionRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName 'lib\cmake\Qt6\Qt6Config.cmake') } |
    Select-Object -First 1 -ExpandProperty FullName
if (-not $qtDir) {
    Write-Error "Qt not found under $versionRoot - run bootstrap-qt.ps1 first"
}

$native = Join-Path $root 'native'
Set-Location $native

cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=$qtDir
cmake --build build --config Release --target pcverse

$exe = Join-Path $native 'build\apps\pcverse\Release\pcverse.exe'
if (-not (Test-Path $exe)) {
    Write-Error "Build failed - pcverse.exe not found"
}

$windeployqt = Join-Path $qtDir 'bin\windeployqt.exe'
if (Test-Path $windeployqt) {
    & $windeployqt $exe --no-translations
    Write-Host "Deployed Qt runtime next to pcverse.exe" -ForegroundColor Green
}

Write-Host ""
Write-Host "Run: $exe" -ForegroundColor Cyan
Write-Host "Run from the git clone so the probe service can be found." -ForegroundColor Gray
