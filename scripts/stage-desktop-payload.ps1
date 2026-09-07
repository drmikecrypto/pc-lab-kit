#Requires -Version 5.1
<#
  Stage the PHP lab (+ bundled PHP + probe) into desktop/src-tauri/resources/lab
  for Tauri bundling.
#>
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

. (Join-Path $root 'scripts\bootstrap-build-tools.ps1')

$dest = Join-Path $root 'desktop\src-tauri\resources\lab'
$probeScript = Join-Path $root 'scripts\build-agent-bundle.ps1'

function Copy-AppTree {
    param([string]$Src, [string]$Dest)

    $excludeDirNames = @(
        '.git', '.cursor', 'build-cache', 'graphify-out', 'vendor',
        'node_modules', 'desktop'
    )
    $excludeDirRel = @(
        'storage\cache',
        'public\downloads',
        'agent\pclab_probe\PcLabHwMon\bin',
        'agent\pclab_probe\PcLabHwMon\obj',
        'agent\pclab_probe\PcLabVkBench\bin',
        'agent\pclab_probe\PcLabVkBench\obj'
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
            if ($name -like '*.zip' -or $name -like '*.tar.gz' -or $name -like '*.exe' -or $name -like '*.run' -or $name -like '*.AppImage' -or $name -like '*.msi') {
                if ($relFromRoot.StartsWith('public\downloads')) { return }
            }
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Dest $name) -Force
        }
    }
}

Initialize-BuildTools

Write-Host 'Staging desktop lab payload...' -ForegroundColor Cyan
if (Test-Path $dest) {
    Get-ChildItem $dest -Force | Where-Object { $_.Name -ne '.gitignore' -and $_.Name -ne '.gitkeep' } | Remove-Item -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $dest | Out-Null

Copy-AppTree -Src $root -Dest $dest

Write-Host 'Installing production vendor into stage...'
if (Test-Path (Join-Path $root 'vendor')) {
    Copy-Item (Join-Path $root 'vendor') (Join-Path $dest 'vendor') -Recurse -Force
}
Push-Location $dest
try {
    Invoke-BundledComposer install --no-interaction --prefer-dist --no-dev --optimize-autoloader --ignore-platform-reqs
}
finally {
    Pop-Location
}

Copy-BundledPhpToStage -StageDir $dest

foreach ($sub in @(
    'storage\cache\benchmark',
    'storage\settings',
    'storage\database',
    'public\downloads'
)) {
    New-Item -ItemType Directory -Force -Path (Join-Path $dest $sub) | Out-Null
}
Copy-Item (Join-Path $dest '.env.example') (Join-Path $dest '.env') -Force

# Ensure probe binary is present for Windows sidecar
if (Test-Path $probeScript) {
    try {
        & (Join-Path $root 'scripts\build-pclab-hwmon.ps1')
    } catch {
        Write-Warning "PcLabHwMon build skipped: $_"
    }
    try {
        & (Join-Path $root 'scripts\build-pclab-vkbench.ps1')
    } catch {
        Write-Warning "PcLabVkBench build skipped: $_"
    }
}
$probeSrc = Join-Path $root 'agent\pclab_probe'
$probeDest = Join-Path $dest 'agent\pclab_probe'
New-Item -ItemType Directory -Force -Path $probeDest | Out-Null
Copy-Item (Join-Path $probeSrc '*.ps1') $probeDest -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $probeSrc '*.bat') $probeDest -Force -ErrorAction SilentlyContinue
if (Test-Path (Join-Path $probeSrc 'ProbeLib')) {
    Copy-Item (Join-Path $probeSrc 'ProbeLib') (Join-Path $probeDest 'ProbeLib') -Recurse -Force
}
if (Test-Path (Join-Path $probeSrc 'PcLabHwMon.exe')) {
    Copy-Item (Join-Path $probeSrc 'PcLabHwMon.exe') $probeDest -Force
}
if (Test-Path (Join-Path $probeSrc 'PcLabVkBench.exe')) {
    Copy-Item (Join-Path $probeSrc 'PcLabVkBench.exe') $probeDest -Force
}
$coreExe = Join-Path $probeSrc 'pclab_core.exe'
$coreBuilt = Join-Path $root 'agent\pclab_core\target\release\pclab_core.exe'
if (Test-Path $coreExe) {
    Copy-Item $coreExe $probeDest -Force
} elseif (Test-Path $coreBuilt) {
    Copy-Item $coreBuilt (Join-Path $probeDest 'pclab_core.exe') -Force
}
if (Test-Path (Join-Path $probeSrc 'tools')) {
    Copy-Item (Join-Path $probeSrc 'tools') (Join-Path $probeDest 'tools') -Recurse -Force
}

Write-Host "Staged lab at $dest" -ForegroundColor Green
