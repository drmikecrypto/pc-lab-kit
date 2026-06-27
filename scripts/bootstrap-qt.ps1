# Download Qt 6 base (Widgets + Network) into build-cache for native desktop builds.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$config = Get-Content (Join-Path $root 'config\build-deps.json') -Raw | ConvertFrom-Json
$version = [string]$config.qt_version
$arch = [string]$config.qt_windows_arch
$outRoot = Join-Path $root 'build-cache\qt'
$versionRoot = Join-Path $outRoot $version

function Resolve-QtInstallDir {
    param([string]$VersionRoot)
    $marker = 'lib\cmake\Qt6\Qt6Config.cmake'
    if (Test-Path (Join-Path $VersionRoot $marker)) {
        return $VersionRoot
    }
    foreach ($child in Get-ChildItem -Path $VersionRoot -Directory -ErrorAction SilentlyContinue) {
        if (Test-Path (Join-Path $child.FullName $marker)) {
            return $child.FullName
        }
    }
    return $null
}

$qtDir = Resolve-QtInstallDir -VersionRoot $versionRoot

if ($qtDir) {
    Write-Host "Qt $version already in build-cache ($qtDir)" -ForegroundColor Green
    Write-Host "Set: `$env:QT6_ROOT = '$qtDir'"
    exit 0
}

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Error 'Python required: winget install Python.Python.3.12'
}

python -m pip install --quiet --upgrade aqtinstall
New-Item -ItemType Directory -Force -Path $outRoot | Out-Null

Write-Host "Downloading Qt $version ($arch) - first run may take several minutes..." -ForegroundColor Cyan
aqt install-qt windows desktop $version $arch -O $outRoot

$qtDir = Resolve-QtInstallDir -VersionRoot $versionRoot
if (-not $qtDir) {
    Write-Error "Qt install failed - no Qt6Config.cmake under $versionRoot"
}

Write-Host "OK: $qtDir" -ForegroundColor Green
Write-Host "Build desktop: cd native && cmake -B build -DCMAKE_PREFIX_PATH=$qtDir"
