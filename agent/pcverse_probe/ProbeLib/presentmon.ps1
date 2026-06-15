. "$PSScriptRoot\common.ps1"

function Get-ProbePresentMonTelemetry {
    $root = Split-Path $PSScriptRoot -Parent
    $candidates = @(
        (Join-Path $root "tools\PresentMon\PresentMon.exe"),
        (Join-Path $root "tools\PresentMon.exe"),
        "PresentMon.exe"
    )
    $exe = $null
    foreach ($c in $candidates) {
        if ($c -eq "PresentMon.exe") {
            if (Get-Command PresentMon -ErrorAction SilentlyContinue) { $exe = "PresentMon"; break }
        } elseif (Test-Path $c) { $exe = $c; break }
    }

    if (-not $exe) {
        return @{
            available = $false
            note = "PresentMon optional — place in agent/pcverse_probe/tools/PresentMon.exe for render latency"
            install_url = "https://github.com/GameTechDev/PresentMon/releases"
        }
    }

    $outCsv = Join-Path $env:TEMP ("pcverse_presentmon_" + [guid]::NewGuid().ToString("n") + ".csv")
    try {
        # 3 second capture snapshot
        $proc = Start-Process -FilePath $exe -ArgumentList @(
            '--output_stdout', 'CSV',
            '--terminate_on_proc_exit',
            '--delay', '0',
            '--timed', '3',
            '--no_summary'
        ) -RedirectStandardOutput $outCsv -NoNewWindow -Wait -PassThru

        if (-not (Test-Path $outCsv)) {
            return @{ available = $false; note = "PresentMon produced no output" }
        }

        $lines = Get-Content $outCsv -ErrorAction SilentlyContinue
        if ($lines.Count -lt 2) {
            return @{ available = $true; samples = 0; note = "No active graphics process" }
        }

        $frametimes = @()
        $msBetween = @()
        foreach ($line in $lines | Select-Object -Skip 1) {
            $cols = $line -split ','
            if ($cols.Count -ge 10) {
                $ft = 0.0
                if ([double]::TryParse($cols[9], [ref]$ft) -and $ft -gt 0) { $frametimes += $ft }
                $mb = 0.0
                if ([double]::TryParse($cols[8], [ref]$mb) -and $mb -gt 0) { $msBetween += $mb }
            }
        }

        $fps = if ($msBetween.Count) { 1000.0 / (($msBetween | Measure-Object -Average).Average) } else { 0 }
        $sorted = $frametimes | Sort-Object
        $p99 = if ($sorted.Count) { $sorted[[int][math]::Floor($sorted.Count * 0.99)]] } else { 0 }

        return @{
            available = $true
            source = 'presentmon'
            fps_avg = [math]::Round($fps, 1)
            frametime_p99_ms = [math]::Round($p99, 2)
            sample_count = $frametimes.Count
            frametime_series = @($frametimes)
            ms_between_series = @($msBetween)
        }
    } catch {
        return @{ available = $false; error = $_.Exception.Message }
    } finally {
        Remove-Item $outCsv -Force -ErrorAction SilentlyContinue
    }
}
