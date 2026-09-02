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

function Find-PresentMonExe {
    $root = Split-Path $PSScriptRoot -Parent
    $candidates = @(
        (Join-Path $root "tools\PresentMon\PresentMon.exe"),
        (Join-Path $root "tools\PresentMon.exe"),
        "PresentMon.exe"
    )
    foreach ($c in $candidates) {
        if ($c -eq "PresentMon.exe") {
            if (Get-Command PresentMon -ErrorAction SilentlyContinue) { return "PresentMon" }
        } elseif (Test-Path $c) { return $c }
    }
    return $null
}

function Get-PresentMonSessionPaths {
    $dir = Join-Path $env:LOCALAPPDATA 'PcLabKit\Probe'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return @{
        dir = $dir
        status = Join-Path $dir 'presentmon-session.json'
        csv = Join-Path $dir 'presentmon-session.csv'
    }
}

function ConvertFrom-PresentMonCsv {
    param([string]$CsvPath, [int]$TimedSeconds = 0)
    if (-not (Test-Path $CsvPath)) {
        return @{ available = $false; note = 'PresentMon produced no output' }
    }
    $lines = Get-Content $CsvPath -ErrorAction SilentlyContinue
    if ($lines.Count -lt 2) {
        return @{ available = $true; samples = 0; note = 'No active graphics process' }
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
    # Cap series for JSON size while keeping reviewable sparkline density
    $maxPts = 600
    $ftSeries = @($frametimes)
    $fpsSeries = @($fpsSamples)
    $msSeries = @($msBetween)
    if ($ftSeries.Count -gt $maxPts) {
        $step = [Math]::Max(1, [int][Math]::Ceiling($ftSeries.Count / [double]$maxPts))
        $ftSeries = for ($i = 0; $i -lt $frametimes.Count; $i += $step) { $frametimes[$i] }
        $fpsSeries = for ($i = 0; $i -lt $fpsSamples.Count; $i += $step) { $fpsSamples[$i] }
        $msSeries = for ($i = 0; $i -lt $msBetween.Count; $i += $step) { $msBetween[$i] }
    }

    return @{
        available = $true
        source = 'presentmon'
        timed_s = $TimedSeconds
        fps_avg = [math]::Round($fps, 1)
        fps_1pct_low = $lows.fps_1pct_low
        fps_0_1pct_low = $lows.fps_0_1pct_low
        frametime_p99_ms = [math]::Round($p99, 2)
        sample_count = $frametimes.Count
        frametime_series = @($ftSeries)
        ms_between_series = @($msSeries)
        fps_series = @($fpsSeries)
        methodology = '1%/0.1% lows = FPS samples at 1st / 0.1st percentile (sorted ascending), CapFrameX-compatible language'
    }
}

function Get-ProbePresentMonTelemetry {
    param([int]$TimedSeconds = 3)
    $TimedSeconds = [Math]::Max(1, [Math]::Min(300, $TimedSeconds))
    $exe = Find-PresentMonExe
    if (-not $exe) {
        return @{
            available = $false
            note = "PresentMon optional - place in agent/pclab_probe/tools/PresentMon.exe for render latency"
            install_url = "https://github.com/GameTechDev/PresentMon/releases"
        }
    }

    $outCsv = Join-Path $env:TEMP ("pclab_presentmon_" + [guid]::NewGuid().ToString("n") + ".csv")
    try {
        $null = Start-Process -FilePath $exe -ArgumentList @(
            '--output_stdout', 'CSV',
            '--terminate_on_proc_exit',
            '--delay', '0',
            '--timed', "$TimedSeconds",
            '--no_summary'
        ) -RedirectStandardOutput $outCsv -NoNewWindow -Wait -PassThru

        $parsed = ConvertFrom-PresentMonCsv -CsvPath $outCsv -TimedSeconds $TimedSeconds
        return $parsed
    } catch {
        return @{ available = $false; error = $_.Exception.Message }
    } finally {
        Remove-Item $outCsv -Force -ErrorAction SilentlyContinue
    }
}

function Get-ProbePresentMonSessionStatus {
    $paths = Get-PresentMonSessionPaths
    if (-not (Test-Path $paths.status)) {
        return @{ running = $false; available = $true; note = 'No session' }
    }
    try {
        $st = Get-Content $paths.status -Raw | ConvertFrom-Json
        $alive = $false
        if ($st.pid) {
            $p = Get-Process -Id ([int]$st.pid) -ErrorAction SilentlyContinue
            if ($p) { $alive = $true }
        }
        return @{
            running = $alive
            available = $true
            started_at = $st.started_at
            pid = $st.pid
            csv = $st.csv
            process_note = $st.process_note
            note = if ($alive) { 'Session capturing' } else { 'Session ended (stop to parse)' }
        }
    } catch {
        return @{ running = $false; available = $true; error = $_.Exception.Message }
    }
}

function Start-ProbePresentMonSession {
    param([string]$ProcessName = '')
    $exe = Find-PresentMonExe
    if (-not $exe) {
        return @{
            ok = $false
            available = $false
            note = "PresentMon optional - place in agent/pclab_probe/tools/PresentMon.exe"
            install_url = "https://github.com/GameTechDev/PresentMon/releases"
        }
    }
    $cur = Get-ProbePresentMonSessionStatus
    if ($cur.running) {
        return @{ ok = $false; running = $true; note = 'Session already running'; pid = $cur.pid }
    }

    $paths = Get-PresentMonSessionPaths
    Remove-Item $paths.csv -Force -ErrorAction SilentlyContinue
    $args = @(
        '--output_file', $paths.csv,
        '--terminate_on_proc_exit',
        '--delay', '0',
        '--no_summary'
    )
    $processNote = 'All presenting processes'
    if ($ProcessName) {
        $args += @('--process_name', $ProcessName)
        $processNote = "Target process: $ProcessName"
    }

    try {
        $proc = Start-Process -FilePath $exe -ArgumentList $args -NoNewWindow -PassThru
        $meta = @{
            pid = $proc.Id
            started_at = (Get-Date).ToUniversalTime().ToString('o')
            csv = $paths.csv
            process_note = $processNote
            process_name = $ProcessName
        }
        ($meta | ConvertTo-Json -Compress) | Set-Content -Path $paths.status -Encoding UTF8
        return @{
            ok = $true
            running = $true
            available = $true
            pid = $proc.Id
            started_at = $meta.started_at
            process_note = $processNote
            note = 'PresentMon session started — play a game/fullscreen app, then Stop & review'
        }
    } catch {
        return @{ ok = $false; available = $true; error = $_.Exception.Message }
    }
}

function Stop-ProbePresentMonSession {
    $paths = Get-PresentMonSessionPaths
    $procId = $null
    $started = $null
    if (Test-Path $paths.status) {
        try {
            $st = Get-Content $paths.status -Raw | ConvertFrom-Json
            $procId = $st.pid
            $started = $st.started_at
        } catch {}
    }
    if ($procId) {
        try {
            $p = Get-Process -Id ([int]$procId) -ErrorAction SilentlyContinue
            if ($p) {
                Stop-Process -Id ([int]$procId) -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 400
            }
        } catch {}
    }

    $elapsed = $null
    if ($started) {
        try { $elapsed = [Math]::Round(((Get-Date).ToUniversalTime() - [datetime]::Parse($started).ToUniversalTime()).TotalSeconds, 1) } catch {}
    }

    $parsed = ConvertFrom-PresentMonCsv -CsvPath $paths.csv -TimedSeconds $(if ($elapsed) { [int]$elapsed } else { 0 })
    $parsed.session = $true
    $parsed.ok = $true
    $parsed.running = $false
    $parsed.duration_s = $elapsed
    if ($started) { $parsed.started_at = $started }
    $parsed.stopped_at = (Get-Date).ToUniversalTime().ToString('o')

    Remove-Item $paths.status -Force -ErrorAction SilentlyContinue
    return $parsed
}
