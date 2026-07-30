#Requires -Version 5.1
<#
  Build pc-lab-kit-windows-x64.zip — portable lab with bundled PHP.
  End users: unzip, double-click PcLabKit.bat.
#>
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

. (Join-Path $root 'scripts\bootstrap-build-tools.ps1')

$outDir = Join-Path $root 'public\downloads'
$outZip = Join-Path $outDir 'pc-lab-kit-windows-x64.zip'
$stageRoot = Join-Path $env:TEMP ('pclab-win-app-' + [guid]::NewGuid().ToString('n'))
$stage = Join-Path $stageRoot 'pc-lab-kit'

function Initialize-ComposerVendor {
    if (-not (Test-Path (Join-Path $root 'vendor\autoload.php'))) {
        Write-Host 'Installing PHP dependencies (bundled Composer)...'
        Push-Location $root
        Invoke-BundledComposer install --no-interaction --prefer-dist --no-dev
        Pop-Location
    }
}

function Copy-AppTree {
    param([string]$Src, [string]$Dest)

    $excludeDirNames = @(
        '.git', '.cursor', 'build-cache', 'graphify-out', 'vendor',
        'node_modules'
    )
    $excludeDirRel = @(
        'storage\cache',
        'public\downloads',
        'agent\pclab_probe\PcLabHwMon\bin',
        'agent\pclab_probe\PcLabHwMon\obj'
    )
    $excludeFileNames = @('.env', '.DS_Store', 'Thumbs.db')

    New-Item -ItemType Directory -Force -Path $Dest | Out-Null

    Get-ChildItem -LiteralPath $Src -Force | ForEach-Object {
        $name = $_.Name
        if ($excludeDirNames -contains $name) { return }
        if ($excludeFileNames -contains $name) { return }

        $relFromRoot = $_.FullName.Substring($root.Length).TrimStart('\', '/')
        foreach ($xd in $excludeDirRel) {
            if ($relFromRoot -eq $xd -or $relFromRoot.StartsWith($xd + '\')) { return }
        }

        if ($_.PSIsContainer) {
            Copy-AppTree -Src $_.FullName -Dest (Join-Path $Dest $name)
        } else {
            if ($name -like '*.sqlite') { return }
            if ($name -like '*.zip' -or $name -like '*.tar.gz' -or $name -like '*.exe' -or $name -like '*.run') {
                if ($relFromRoot.StartsWith('public\downloads')) { return }
            }
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Dest $name) -Force
        }
    }
}

try {
    Initialize-BuildTools
    Initialize-ComposerVendor

    Write-Host 'Staging Windows app payload...' -ForegroundColor Cyan
    if (Test-Path $stageRoot) { Remove-Item $stageRoot -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $stage | Out-Null

    Copy-AppTree -Src $root -Dest $stage

    # Production vendor inside the stage only (leave the repo vendor untouched)
    Write-Host 'Installing production vendor into stage...'
    if (Test-Path (Join-Path $root 'vendor')) {
        Copy-Item (Join-Path $root 'vendor') (Join-Path $stage 'vendor') -Recurse -Force
    }
    Push-Location $stage
    try {
        Invoke-BundledComposer install --no-interaction --prefer-dist --no-dev --optimize-autoloader --ignore-platform-reqs
    }
    finally {
        Pop-Location
    }
    if (-not (Test-Path (Join-Path $stage 'vendor\autoload.php'))) {
        throw 'Stage vendor/autoload.php missing after composer install'
    }

    Copy-BundledPhpToStage -StageDir $stage

    foreach ($sub in @(
        'storage\cache\benchmark',
        'storage\settings',
        'storage\database',
        'public\downloads'
    )) {
        New-Item -ItemType Directory -Force -Path (Join-Path $stage $sub) | Out-Null
    }
    if (Test-Path (Join-Path $root 'public\downloads\.gitkeep')) {
        Copy-Item (Join-Path $root 'public\downloads\.gitkeep') (Join-Path $stage 'public\downloads\.gitkeep') -Force
    }

    # Seed .env for first run
    Copy-Item (Join-Path $stage '.env.example') (Join-Path $stage '.env') -Force

    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    if (Test-Path $outZip) { Remove-Item $outZip -Force }

    Compress-Archive -Path $stage -DestinationPath $outZip -CompressionLevel Optimal -Force

    $mb = [math]::Round((Get-Item $outZip).Length / 1MB, 1)
    Write-Host ("Built {0} ({1} MB)" -f $outZip, $mb) -ForegroundColor Green
}
finally {
    if (Test-Path $stageRoot) {
        Remove-Item $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
