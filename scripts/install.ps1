#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

. (Join-Path $Root 'scripts\bootstrap-build-tools.ps1')

Write-Host "PCVerse — install" -ForegroundColor Cyan
Initialize-BuildTools

if (-not (Test-Path ".env")) {
    Copy-Item ".env.example" ".env"
    Write-Host "Created .env from .env.example"
}

if (-not (Test-Path "vendor/autoload.php")) {
    Write-Host "Installing PHP dependencies (bundled Composer)…"
    Invoke-BundledComposer install --no-interaction --prefer-dist
}

$php = Get-BuildPhpExe
& $php bin/migrate.php

New-Item -ItemType Directory -Force -Path "storage/cache/benchmark" | Out-Null
New-Item -ItemType Directory -Force -Path "storage/settings" | Out-Null
New-Item -ItemType Directory -Force -Path "storage/database" | Out-Null
New-Item -ItemType Directory -Force -Path "public/downloads" | Out-Null

# Dev convenience: symlink bundled PHP next to app (same as installer payload)
Copy-BundledPhpToStage -StageDir $Root

Write-Host ""
Write-Host "Ready." -ForegroundColor Green
Write-Host ""
Write-Host "Start the lab:"
Write-Host "  .\scripts\start.ps1"
Write-Host ""
Write-Host "Open http://127.0.0.1:8080/diagnostic"
