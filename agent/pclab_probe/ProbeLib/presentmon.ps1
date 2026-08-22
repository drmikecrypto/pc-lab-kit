. "$PSScriptRoot\common.ps1"

function Get-PresentMonPercentileLows {
    param([double[]]$FpsSamples)
    if (-not $FpsSamples -or $FpsSamples.Count -lt 2) {
        return @{ fps_1pct_low = $null; fps_0_1pct_low = $null }
    }
    $sorted = @($FpsSamples | Sort-Object)
    $n = $sorted.Count
    $i1 = [Math]::Max(0, [int][Math]::Floor($n * 0.01))
    $i01 = [Math]::Max(0, [int][Math]::Floor($n * 0.001))
    if ($i1 -ge $n) { $i1 = $n - 1 }
    if ($i01 -ge $n) { $i01 = $n - 1 }
    return @{
        fps_1pct_low = [math]::Round($sorted[$i1], 1)
        fps_0_1pct_low = [math]::Round($sorted[$i01], 1)
    }
}

function Get-ProbePresentMonTelemetry {
    param([int]$TimedSeconds = 3)
    $TimedSeconds = [Math]::Max(1, [Math]::Min(120, $TimedSeconds))
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
            note = "PresentMon optional - place in agent/pclab_probe/tools/PresentMon.exe for render latency"
            install_url = "https://github.com/GameTechDev/PresentMon/releases"
        }
    }

    $outCsv = Join-Path $env:TEMP ("pclab_presentmon_" + [guid]::NewGuid().ToString("n") + ".csv")
    try {
        $proc = Start-Process -FilePath $exe -ArgumentList @(
            '--output_stdout', 'CSV',
            '--terminate_on_proc_exit',
            '--delay', '0',
            '--timed', "$TimedSeconds",
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
        $fpsSamples = @()
        foreach ($line in $lines | Select-Object -Skip 1) {
            $cols = $line -split ','
            if ($cols.Count -ge 10) {
                $ft = 0.0
                if ([double]::TryParse($cols[9], [ref]$ft) -and $ft -gt 0) { $frametimes += $ft }
                $mb = 0.0
                if ([double]::TryParse($cols[8], [ref]$mb) -and $mb -gt 0) {
                    $msBetween += $mb
                    $fpsSamples += (1000.0 / $mb)
                }
            }
        }

        $fps = if ($msBetween.Count) { 1000.0 / (($msBetween | Measure-Object -Average).Average) } else { 0 }
        $sorted = $frametimes | Sort-Object
        $p99 = 0
        if ($sorted.Count) {
            $idx = [int][math]::Floor($sorted.Count * 0.99)
            if ($idx -ge $sorted.Count) { $idx = $sorted.Count - 1 }
            $p99 = $sorted[$idx]
        }
        $lows = Get-PresentMonPercentileLows -FpsSamples @($fpsSamples)

        return @{
            available = $true
            source = 'presentmon'
            timed_s = $TimedSeconds
            fps_avg = [math]::Round($fps, 1)
            fps_1pct_low = $lows.fps_1pct_low
            fps_0_1pct_low = $lows.fps_0_1pct_low
            frametime_p99_ms = [math]::Round($p99, 2)
            sample_count = $frametimes.Count
            frametime_series = @($frametimes)
            ms_between_series = @($msBetween)
            fps_series = @($fpsSamples)
            methodology = '1%/0.1% lows = FPS samples at 1st / 0.1st percentile (sorted ascending), CapFrameX-compatible language'
        }
    } catch {
        return @{ available = $false; error = $_.Exception.Message }
    } finally {
        Remove-Item $outCsv -Force -ErrorAction SilentlyContinue
    }
}
