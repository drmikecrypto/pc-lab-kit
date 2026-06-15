#Requires -Version 5.1
<#
  Ensures build-cache has portable PHP (Windows), Composer PHAR, and .NET 8 SDK.
  Used by install.ps1 and build-installer-windows.ps1 — no manual PHP/Composer/.NET install.
#>
$ErrorActionPreference = 'Stop'

function Get-BuildDepsRoot {
    if ($script:BuildDepsRoot) { return $script:BuildDepsRoot }
    if ($PSScriptRoot) {
        $script:BuildDepsRoot = Split-Path -Parent $PSScriptRoot
    } elseif ($MyInvocation.MyCommand.Path) {
        $script:BuildDepsRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
    } else {
        throw 'Could not resolve PCVerse root for bootstrap-build-tools.ps1'
    }
    return $script:BuildDepsRoot
}

function Get-BuildDepsConfig {
    if ($script:BuildDepsConfig) { return $script:BuildDepsConfig }
    $path = Join-Path (Get-BuildDepsRoot) 'config\build-deps.json'
    if (-not (Test-Path $path)) {
        throw "Missing config/build-deps.json"
    }
    $script:BuildDepsConfig = Get-Content $path -Raw | ConvertFrom-Json
    return $script:BuildDepsConfig
}

function Initialize-BuildCacheDir {
    $dir = Join-Path (Get-BuildDepsRoot) 'build-cache'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    return $dir
}

function Initialize-BundledComposer {
    $cache = Initialize-BuildCacheDir
    $phar = Join-Path $cache 'composer.phar'
    if (Test-Path $phar) { return $phar }

    $cfg = Get-BuildDepsConfig
    $url = [string]$cfg.composer_url
    Write-Host "Downloading latest Composer…" -ForegroundColor Cyan
    Invoke-WebRequest -Uri $url -OutFile $phar -UseBasicParsing
    return $phar
}

function Get-BundledWindowsPhpDir {
    $cache = Initialize-BuildCacheDir
    $runtimeDir = Join-Path $cache 'php-win-x64'
    if (Test-Path (Join-Path $runtimeDir 'php.exe')) { return $runtimeDir }

    $cfg = Get-BuildDepsConfig
    $zipPath = Join-Path $cache 'php-win-x64.zip'
    $url = [string]$cfg.php_windows_url
    Write-Host "Downloading PHP $($cfg.php_windows_version) for Windows…" -ForegroundColor Cyan
    Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing

    New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
    Expand-Archive -Path $zipPath -DestinationPath $runtimeDir -Force
    $nested = Get-ChildItem $runtimeDir -Filter php.exe -Recurse | Select-Object -First 1
    if ($nested -and $nested.DirectoryName -ne $runtimeDir) {
        Get-ChildItem $nested.DirectoryName | Move-Item -Destination $runtimeDir -Force
    }
    Initialize-BundledPhpIni $runtimeDir
    return $runtimeDir
}

function Initialize-BundledPhpIni {
    param([string]$RuntimeDir)
    $iniDev = Join-Path $RuntimeDir 'php.ini-development'
    $ini = Join-Path $RuntimeDir 'php.ini'
    if (-not (Test-Path $iniDev)) { return }
    Copy-Item $iniDev $ini -Force
    $extDir = Join-Path $RuntimeDir 'ext'
    $out = foreach ($line in Get-Content $ini) {
        if ($line -match '^;extension_dir') { "extension_dir=`"$extDir`""; continue }
        if ($line -match '^;extension=curl') { 'extension=curl'; continue }
        if ($line -match '^;extension=mbstring') { 'extension=mbstring'; continue }
        if ($line -match '^;extension=openssl') { 'extension=openssl'; continue }
        if ($line -match '^;extension=pdo_sqlite') { 'extension=pdo_sqlite'; continue }
        if ($line -match '^;extension=sqlite3') { 'extension=sqlite3'; continue }
        $line
    }
    Set-Content -Path $ini -Value $out -Encoding UTF8
}

function Get-BuildPhpExe {
    $bundled = Join-Path (Get-BundledWindowsPhpDir) 'php.exe'
    if (Test-Path $bundled) { return $bundled }
    if (Get-Command php -ErrorAction SilentlyContinue) { return 'php' }
    throw 'Could not resolve PHP for build. Bootstrap failed.'
}

function Invoke-BundledComposer {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    $php = Get-BuildPhpExe
    $phar = Initialize-BundledComposer
    & $php $phar @Args
    if ($LASTEXITCODE -ne 0) { throw "composer failed: $Args" }
}

function Initialize-BundledDotNet {
    $cache = Initialize-BuildCacheDir
    $dotnetRoot = Join-Path $cache 'dotnet'
    $dotnetExe = Join-Path $dotnetRoot 'dotnet.exe'
    if (Test-Path $dotnetExe) {
        $env:DOTNET_ROOT = $dotnetRoot
        $env:PATH = "$dotnetRoot;$env:PATH"
        return $dotnetExe
    }

    if (Get-Command dotnet -ErrorAction SilentlyContinue) {
        return 'dotnet'
    }

    $cfg = Get-BuildDepsConfig
    $installScript = Join-Path $cache 'dotnet-install.ps1'
    Write-Host 'Downloading .NET 8 SDK (one-time, into build-cache)…' -ForegroundColor Cyan
    Invoke-WebRequest -Uri ([string]$cfg.dotnet_install_script) -OutFile $installScript -UseBasicParsing
    & $installScript -Channel ([string]$cfg.dotnet_channel) -InstallDir $dotnetRoot -Architecture x64
    if (-not (Test-Path $dotnetExe)) {
        throw '.NET SDK bootstrap failed. Check network or install .NET 8 SDK manually.'
    }
    $env:DOTNET_ROOT = $dotnetRoot
    $env:PATH = "$dotnetRoot;$env:PATH"
    return $dotnetExe
}

function Copy-BundledPhpToStage {
    param([string]$StageDir)
    $src = Get-BundledWindowsPhpDir
    $dest = Join-Path $StageDir 'runtime\php'
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item -Path (Join-Path $src '*') -Destination $dest -Recurse -Force
}

function Initialize-BuildTools {
    Initialize-BundledComposer | Out-Null
    Get-BundledWindowsPhpDir | Out-Null
    Initialize-BundledDotNet | Out-Null
    Write-Host 'Build tools ready (PHP, Composer, .NET in build-cache).' -ForegroundColor Green
}

if ($MyInvocation.InvocationName -ne '.' -and $MyInvocation.InvocationName -ne '') {
    Initialize-BuildTools
}
