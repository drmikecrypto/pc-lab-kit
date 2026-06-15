# Build pcverse-lab-windows.zip for /download/pcverse-lab-windows.zip
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$outDir = Join-Path $root 'public\downloads'
$outZip = Join-Path $outDir 'pcverse-lab-windows.zip'

$excludeDirs = @('vendor', '.git', 'storage\cache', 'pcverse_app\.dart_tool', 'pcverse_app\build')
$excludeFiles = @('.env', 'public\downloads\pcverse-probe-windows.zip', 'public\downloads\pcverse-lab-windows.zip', 'public\downloads\pcverse-lab-linux-mac.tar.gz')

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
if (Test-Path $outZip) { Remove-Item $outZip -Force }

$stage = Join-Path $env:TEMP ('pcverse-lab-win-' + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $stage | Out-Null

function Copy-TreeFiltered($src, $dest) {
    Get-ChildItem -LiteralPath $src -Force | ForEach-Object {
        $rel = $_.Name
        if ($excludeDirs -contains $rel) { return }
        if ($_.PSIsContainer) {
            $sub = Join-Path $dest $rel
            New-Item -ItemType Directory -Path $sub -Force | Out-Null
            Copy-TreeFiltered $_.FullName $sub
        } else {
            if ($excludeFiles -contains $rel) { return }
            if ($rel -like '*.sqlite') { return }
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dest $rel) -Force
        }
    }
}

Copy-TreeFiltered $root $stage
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $outZip -Force
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Built $outZip ($((Get-Item $outZip).Length) bytes)"
