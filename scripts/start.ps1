#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

if (-not (Test-Path "vendor/autoload.php")) {
    Write-Host "Run .\scripts\install.ps1 first." -ForegroundColor Yellow
    exit 1
}

$port = 8080
if ($args.Count -gt 0) { $port = [int]$args[0] }

$php = 'php'
$bundled = Join-Path $Root 'runtime\php\php.exe'
if (Test-Path $bundled) { $php = $bundled }

Write-Host "PCVerse lab → http://127.0.0.1:$port/diagnostic" -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop."
& $php -S "127.0.0.1:$port" -t public
