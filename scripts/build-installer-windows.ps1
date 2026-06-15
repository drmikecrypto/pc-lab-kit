# Stage and build PCVerse-Setup-Windows-x64.exe (single download)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$outDir = Join-Path $root 'public\downloads'
$outExe = Join-Path $outDir 'PCVerse-Setup-Windows-x64.exe'
$setupDir = Join-Path $root 'installer\PCVerse.Setup'
$payloadZip = Join-Path $setupDir 'payload.zip'
$stage = Join-Path $env:TEMP ('pcverse-payload-' + [guid]::NewGuid().ToString('n'))

. (Join-Path $root 'scripts\bootstrap-build-tools.ps1')

function Initialize-ComposerVendor {
    if (-not (Test-Path (Join-Path $root 'vendor\autoload.php'))) {
        Write-Host 'Installing PHP dependencies (bundled Composer)…'
        Push-Location $root
        Invoke-BundledComposer install --no-interaction --prefer-dist --no-dev
        Pop-Location
    }
}

function Invoke-ProbeBuild {
    try { & (Join-Path $root 'scripts\build-pcverse-hwmon.ps1') } catch { Write-Warning $_ }
}

function Copy-InstallerPayload {
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    $excludeDirs = @('.git', 'build-cache', 'storage\cache', 'pcverse_app\.dart_tool', 'pcverse_app\build',
        'installer\PCVerse.Setup\bin', 'installer\PCVerse.Setup\obj', 'public\downloads')
    $robocopyArgs = @($root, $stage, '/MIR', '/NFL', '/NDL', '/NJH', '/NJS', '/NC', '/NS')
    foreach ($d in $excludeDirs) { $robocopyArgs += '/XD'; $robocopyArgs += (Join-Path $root $d) }
    $robocopyArgs += '/XF'; $robocopyArgs += '.env'
    & robocopy @robocopyArgs | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed: $LASTEXITCODE" }

    foreach ($sub in @('storage\cache\benchmark', 'storage\settings', 'storage\database', 'public\downloads')) {
        New-Item -ItemType Directory -Force -Path (Join-Path $stage $sub) | Out-Null
    }
    if (Test-Path (Join-Path $root 'public\downloads\.gitkeep')) {
        Copy-Item (Join-Path $root 'public\downloads\.gitkeep') (Join-Path $stage 'public\downloads\.gitkeep') -Force
    }

    Get-ChildItem $outDir -Include *.zip,*.tar.gz,*.exe,*.run -ErrorAction SilentlyContinue | ForEach-Object {
        $maybe = Join-Path (Join-Path $stage 'public\downloads') $_.Name
        Remove-Item $maybe -Force -ErrorAction SilentlyContinue
    }
}

try {
    Initialize-BuildTools
    Initialize-ComposerVendor
    Invoke-ProbeBuild
    Write-Host 'Staging Windows payload…'
    Copy-InstallerPayload
    Copy-BundledPhpToStage -StageDir $stage

    if (Test-Path $payloadZip) { Remove-Item $payloadZip -Force }
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $payloadZip -CompressionLevel Optimal -Force

    $payloadMb = [math]::Round((Get-Item $payloadZip).Length / 1MB, 1)
    Write-Host ('Publishing installer ({0} MB payload)…' -f $payloadMb)

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
