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
    $appCounts = @{}
    foreach ($line in $lines | Select-Object -Skip 1) {
        $cols = $line -split ','
        if ($cols.Count -ge 10) {
            $app = ($cols[0] -replace '^"|"$', '').Trim()
            if ($app -and $app -notmatch '^(Application|Process)$') {
                if (-not $appCounts.ContainsKey($app)) { $appCounts[$app] = 0 }
                $appCounts[$app]++
            }
            $ft = 0.0
            if ([double]::TryParse($cols[9], [ref]$ft) -and $ft -gt 0) { $frametimes += $ft }
            $mb = 0.0
            if ([double]::TryParse($cols[8], [ref]$mb) -and $mb -gt 0) {
                $msBetween += $mb
                $fpsSamples += (1000.0 / $mb)
            }
        }
    }
    $topApp = $null
    if ($appCounts.Count -gt 0) {
        $topApp = ($appCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key
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
        process_name = $topApp
        label = $topApp
        methodology = '1%/0.1% lows = FPS samples at 1st / 0.1st percentile (sorted ascending), CapFrameX-compatible language'
    }
}

function Get-ProbePresentMonTelemetry {
    param([int]$TimedSeconds = 3, [string]$ContextJsonPath = '')
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
        if ($parsed.available -and $parsed.sample_count -gt 1) {
            $parsed.duration_s = $TimedSeconds
            $parsed.stopped_at = (Get-Date).ToUniversalTime().ToString('o')
            $lab = if ($parsed.label) { [string]$parsed.label } else { ("Timed {0}s" -f $TimedSeconds) }
            $saved = Save-ProbePresentMonSessionArtifact -Parsed $parsed -Source 'presentmon' -Label $lab -ContextJsonPath $ContextJsonPath
            if ($saved.ok) {
                $parsed.session_id = $saved.id
                $parsed.saved = $true
                $parsed.context = $saved.context
                $parsed.spikes = $saved.spikes
            }
        }
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
            note = 'PresentMon session started - play a game/fullscreen app, then Stop & review'
        }
    } catch {
        return @{ ok = $false; available = $true; error = $_.Exception.Message }
    }
}

function Stop-ProbePresentMonSession {
    param([string]$ContextJsonPath = '')
    $paths = Get-PresentMonSessionPaths
    $procId = $null
    $started = $null
    $sessionProcess = ''
    if (Test-Path $paths.status) {
        try {
            $st = Get-Content $paths.status -Raw | ConvertFrom-Json
            $procId = $st.pid
            $started = $st.started_at
            if ($st.process_name) { $sessionProcess = [string]$st.process_name }
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
    if ($sessionProcess) {
        $parsed.process_name = $sessionProcess
        if (-not $parsed.label) { $parsed.label = $sessionProcess }
    }
    if ($parsed.sample_count -gt 1) {
        $label = if ($parsed.label) { [string]$parsed.label } elseif ($parsed.process_name) { [string]$parsed.process_name } else { '' }
        $saved = Save-ProbePresentMonSessionArtifact -Parsed $parsed -Source 'presentmon' -Label $label -ContextJsonPath $ContextJsonPath
        if ($saved.ok) {
            $parsed.session_id = $saved.id
            $parsed.saved = $true
            $parsed.artifact_path = $saved.path
            $parsed.context = $saved.context
            $parsed.spikes = $saved.spikes
        }
    }
    return $parsed
}

function Get-PresentMonSessionsDir {
    $dir = Join-Path $env:LOCALAPPDATA 'PcLabKit\Probe\presentmon-sessions'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Get-ProbePresentMonForegroundHint {
    $hint = $null
    $title = $null
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class PcLabFg {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
}
"@ -ErrorAction SilentlyContinue
        $hwnd = [PcLabFg]::GetForegroundWindow()
        if ($hwnd -ne [IntPtr]::Zero) {
            $pid = [uint32]0
            [void][PcLabFg]::GetWindowThreadProcessId($hwnd, [ref]$pid)
            $sb = New-Object System.Text.StringBuilder 512
            [void][PcLabFg]::GetWindowText($hwnd, $sb, $sb.Capacity)
            $title = $sb.ToString()
            if ($pid -gt 0) {
                $proc = Get-Process -Id ([int]$pid) -ErrorAction SilentlyContinue
                if ($proc) { $hint = $proc.ProcessName }
            }
        }
    } catch {}
    if (-not $hint) {
        try {
            $fg = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle } |
                Sort-Object StartTime -Descending | Select-Object -First 1
            if ($fg) {
                $hint = $fg.ProcessName
                if (-not $title) { $title = $fg.MainWindowTitle }
            }
        } catch {}
    }
    return @{
        ok = $true
        process_name = $hint
        window_title = $title
        note = if ($hint) { "Foreground: $hint" } else { 'No foreground process detected' }
    }
}

function Normalize-PresentMonContextSamples {
    param($RawSamples, [double]$DurationS = 0)
    $rows = @()
    if (-not $RawSamples) {
        return @{ available = $false; samples = @(); note = 'No telemetry history during capture - open Sensor Deck / leave Probe live for spike context.' }
    }
    $list = @($RawSamples)
    if ($list.Count -eq 0) {
        return @{ available = $false; samples = @(); note = 'Telemetry ring empty - spike temps unavailable.' }
    }
    foreach ($s in $list) {
        try {
            $ts = $null
            if ($s.ts) { $ts = [string]$s.ts }
            elseif ($s.collected_at) { $ts = [string]$s.collected_at }
            $rows += @{
                t = $ts
                cpu_c = $(if ($null -ne $s.cpu_temp) { $s.cpu_temp } else { $s.cpu_c })
                gpu_c = $(if ($null -ne $s.gpu_temp) { $s.gpu_temp } else { $s.gpu_c })
                gpu_hotspot_c = $(if ($null -ne $s.gpu_hotspot) { $s.gpu_hotspot } else { $s.gpu_hotspot_c })
                package_w = $(if ($null -ne $s.package_power_w) { $s.package_power_w } else { $s.package_w })
                gpu_w = $(if ($null -ne $s.gpu_power_w) { $s.gpu_power_w } elseif ($null -ne $s.gpu_power) { $s.gpu_power } else { $s.gpu_w })
            }
        } catch {}
    }
    if ($rows.Count -eq 0) {
        return @{ available = $false; samples = @(); note = 'Telemetry history had no usable samples.' }
    }
    # Keep last samples covering roughly duration (assume ~1 sample / few sec; cap 120)
    $keep = 120
    if ($DurationS -gt 0) {
        $keep = [Math]::Max(8, [Math]::Min(120, [int][Math]::Ceiling($DurationS / 2.0) + 4))
    }
    if ($rows.Count -gt $keep) {
        $rows = $rows[($rows.Count - $keep)..($rows.Count - 1)]
    }
    return @{
        available = $true
        samples = @($rows)
        sample_count = $rows.Count
        note = $null
    }
}

function Get-PresentMonContextFromJsonPath {
    param([string]$Path, [double]$DurationS = 0)
    if (-not $Path -or -not (Test-Path $Path)) {
        return Normalize-PresentMonContextSamples -RawSamples @() -DurationS $DurationS
    }
    try {
        $raw = Get-Content $Path -Raw -ErrorAction Stop
        if (-not $raw -or $raw.Trim() -eq '' -or $raw.Trim() -eq 'null') {
            return Normalize-PresentMonContextSamples -RawSamples @() -DurationS $DurationS
        }
        $j = $raw | ConvertFrom-Json
        return Normalize-PresentMonContextSamples -RawSamples $j -DurationS $DurationS
    } catch {
        return @{ available = $false; samples = @(); note = "Context parse failed: $($_.Exception.Message)" }
    }
}

function Add-PresentMonSpikeContext {
    param($Spikes, $Context, [double]$DurationMs = 0)
    if (-not $Spikes) { return $Spikes }
    $spikeList = @($Spikes.spikes)
    if (-not $Context -or -not $Context.available -or -not $Context.samples -or @($Context.samples).Count -eq 0) {
        $Spikes.context_attached = $false
        return $Spikes
    }
    $samples = @($Context.samples)
    $n = $samples.Count
    if ($DurationMs -le 0) {
        foreach ($sp in $spikeList) {
            $tm = if ($sp -is [hashtable]) { [double]$sp['t_ms'] } else { [double]$sp.t_ms }
            if ($tm -gt $DurationMs) { $DurationMs = $tm }
        }
    }
    if ($DurationMs -le 0) { $DurationMs = 1000.0 }
    $enriched = @()
    foreach ($sp in $spikeList) {
        $row = @{}
        if ($sp -is [hashtable]) {
            foreach ($k in $sp.Keys) { $row[$k] = $sp[$k] }
        } else {
            foreach ($k in $sp.PSObject.Properties.Name) { $row[$k] = $sp.$k }
        }
        $tMs = [double]$row['t_ms']
        $idx = 0
        if ($n -gt 1) {
            $idx = [int][Math]::Floor(($tMs / $DurationMs) * ($n - 1))
            if ($idx -lt 0) { $idx = 0 }
            if ($idx -ge $n) { $idx = $n - 1 }
        }
        $ctx = $samples[$idx]
        $row['cpu_c'] = $ctx.cpu_c
        $row['gpu_c'] = $ctx.gpu_c
        $row['gpu_hotspot_c'] = $ctx.gpu_hotspot_c
        $row['package_w'] = $ctx.package_w
        $row['gpu_w'] = $ctx.gpu_w
        $enriched += $row
    }
    $Spikes.spikes = $enriched
    $Spikes.context_attached = $true
    return $Spikes
}

function Get-ProbePresentMonSpikes {
    param(
        [double[]]$FrametimeMs,
        [double]$SpikeThresholdMs = 25.0,
        [int]$MaxSpikes = 40
    )
    if (-not $FrametimeMs -or $FrametimeMs.Count -lt 2) {
        return @{ available = $false; spikes = @(); spike_count = 0; threshold_ms = $SpikeThresholdMs; context_attached = $false }
    }
    $mean = ($FrametimeMs | Measure-Object -Average).Average
    $threshold = [Math]::Max($SpikeThresholdMs, $mean * 2.5)
    $spikes = @()
    $t = 0.0
    for ($i = 0; $i -lt $FrametimeMs.Count; $i++) {
        $v = [double]$FrametimeMs[$i]
        $t += $v
        if ($v -ge $threshold) {
            $spikes += @{
                i = $i
                t_ms = [math]::Round($t, 1)
                ft_ms = [math]::Round($v, 2)
                fps = if ($v -gt 0) { [math]::Round(1000.0 / $v, 1) } else { $null }
                likely_cause = if ($v -ge 50) { 'severe_stutter' } elseif ($v -ge ($mean * 3)) { 'spike_up' } else { 'frametime_high' }
            }
        }
    }
    $spikes = @($spikes | Sort-Object { $_.ft_ms } -Descending | Select-Object -First $MaxSpikes | Sort-Object { $_.t_ms })
    return @{
        available = $true
        spikes = $spikes
        spike_count = $spikes.Count
        threshold_ms = [math]::Round($threshold, 2)
        mean_ms = [math]::Round($mean, 2)
        context_attached = $false
    }
}

function Save-ProbePresentMonSessionArtifact {
    param(
        [hashtable]$Parsed,
        [string]$Source = 'presentmon',
        [string]$Label = '',
        [string]$ContextJsonPath = ''
    )
    if (-not $Parsed) { return @{ ok = $false; error = 'no_data' } }
    $dir = Get-PresentMonSessionsDir
    $id = (Get-Date).ToUniversalTime().ToString('yyyyMMdd_HHmmss') + '_' + ([guid]::NewGuid().ToString('n').Substring(0, 8))
    $ft = @($Parsed.frametime_series)
    if (-not $ft.Count -and $Parsed.ms_between_series) { $ft = @($Parsed.ms_between_series) }
    $spikes = Get-ProbePresentMonSpikes -FrametimeMs $ft
    $dur = 0.0
    if ($null -ne $Parsed.duration_s) { $dur = [double]$Parsed.duration_s }
    elseif ($null -ne $Parsed.timed_s) { $dur = [double]$Parsed.timed_s }
    $context = Get-PresentMonContextFromJsonPath -Path $ContextJsonPath -DurationS $dur
    $durMs = if ($dur -gt 0) { $dur * 1000.0 } else { 0.0 }
    $spikes = Add-PresentMonSpikeContext -Spikes $spikes -Context $context -DurationMs $durMs
    $fpsSeries = @($Parsed.fps_series)
    $hist = @{
        bins = @()
        counts = @()
    }
    if ($fpsSeries.Count -ge 2) {
        $minF = ($fpsSeries | Measure-Object -Minimum).Minimum
        $maxF = ($fpsSeries | Measure-Object -Maximum).Maximum
        $binCount = 24
        $span = [Math]::Max(1.0, $maxF - $minF)
        $width = $span / $binCount
        $counts = New-Object int[] $binCount
        $bins = @()
        for ($b = 0; $b -lt $binCount; $b++) {
            $bins += [math]::Round($minF + ($b + 0.5) * $width, 1)
        }
        foreach ($v in $fpsSeries) {
            $idx = [int][Math]::Floor(([double]$v - $minF) / $width)
            if ($idx -ge $binCount) { $idx = $binCount - 1 }
            if ($idx -lt 0) { $idx = 0 }
            $counts[$idx]++
        }
        $hist = @{ bins = $bins; counts = @($counts); min = [math]::Round($minF, 1); max = [math]::Round($maxF, 1) }
    }

    $procName = $null
    if ($Parsed.process_name) { $procName = [string]$Parsed.process_name }
    $labelOut = $Label
    if (-not $labelOut -and $Parsed.label) { $labelOut = [string]$Parsed.label }
    if (-not $labelOut -and $procName) { $labelOut = $procName }
    if (-not $labelOut) { $labelOut = if ($Source -eq 'import') { 'CapFrameX import' } else { 'PresentMon session' } }

    $artifact = @{
        id = $id
        source = $Source
        label = $labelOut
        process_name = $procName
        started_at = $Parsed.started_at
        stopped_at = $Parsed.stopped_at
        duration_s = $Parsed.duration_s
        timed_s = $Parsed.timed_s
        fps_avg = $Parsed.fps_avg
        fps_1pct_low = $Parsed.fps_1pct_low
        fps_0_1pct_low = $Parsed.fps_0_1pct_low
        frametime_p99_ms = $Parsed.frametime_p99_ms
        sample_count = $Parsed.sample_count
        fps_series = $fpsSeries
        frametime_series = $ft
        ms_between_series = @($Parsed.ms_between_series)
        spikes = $spikes
        context = $context
        histogram = $hist
        methodology = $Parsed.methodology
        available = [bool]$Parsed.available
        saved_at = (Get-Date).ToUniversalTime().ToString('o')
    }
    $path = Join-Path $dir ("$id.json")
    ($artifact | ConvertTo-Json -Depth 10 -Compress) | Set-Content -Path $path -Encoding UTF8

    $all = @(Get-ChildItem $dir -Filter '*.json' -File | Sort-Object LastWriteTime -Descending)
    if ($all.Count -gt 40) {
        $all | Select-Object -Skip 40 | ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
    }
    return @{ ok = $true; id = $id; path = $path; context = $context; spikes = $spikes }
}

function Get-ProbePresentMonSessions {
    param([int]$Limit = 20)
    $Limit = [Math]::Max(1, [Math]::Min(40, $Limit))
    $dir = Get-PresentMonSessionsDir
    $exe = Find-PresentMonExe
    $items = @()
    Get-ChildItem $dir -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First $Limit |
        ForEach-Object {
            try {
                $j = Get-Content $_.FullName -Raw | ConvertFrom-Json
                $items += @{
                    id = $j.id
                    source = $j.source
                    label = $j.label
                    process_name = $j.process_name
                    started_at = $j.started_at
                    duration_s = $j.duration_s
                    fps_avg = $j.fps_avg
                    fps_1pct_low = $j.fps_1pct_low
                    fps_0_1pct_low = $j.fps_0_1pct_low
                    frametime_p99_ms = $j.frametime_p99_ms
                    sample_count = $j.sample_count
                    spike_count = $(if ($j.spikes) { $j.spikes.spike_count } else { 0 })
                    context_available = $(if ($j.context) { [bool]$j.context.available } else { $false })
                    saved_at = $j.saved_at
                }
            } catch {}
        }
    return @{
        ok = $true
        count = $items.Count
        sessions = @($items)
        presentmon_available = [bool]$exe
        presentmon_missing = -not [bool]$exe
        note = if ($exe) { $null } else { 'PresentMon optional - place tools/PresentMon.exe for live capture; CapFrameX import still works.' }
        install_url = 'https://github.com/GameTechDev/PresentMon/releases'
    }
}

function Get-ProbePresentMonSessionById {
    param([string]$Id)
    if (-not $Id) { return @{ ok = $false; error = 'missing_id' } }
    $safe = ($Id -replace '[^\w\-]', '')
    $path = Join-Path (Get-PresentMonSessionsDir) ("$safe.json")
    if (-not (Test-Path $path)) {
        return @{ ok = $false; error = 'not_found'; message = "Session $Id not found" }
    }
    try {
        $j = Get-Content $path -Raw | ConvertFrom-Json
        return @{
            ok = $true
            session = $j
        }
    } catch {
        return @{ ok = $false; error = 'parse_failed'; message = $_.Exception.Message }
    }
}

function Import-ProbePresentMonCapFrameX {
    param([string]$JsonContent, [string]$Label = '')
    if (-not $JsonContent) {
        return @{ ok = $false; error = 'empty'; message = 'Provide CapFrameX JSON content.' }
    }
    try {
        $data = $JsonContent | ConvertFrom-Json
    } catch {
        return @{ ok = $false; error = 'invalid_json'; message = $_.Exception.Message }
    }

    $fpsAvg = $null
    $fps1 = $null
    $fps01 = $null
    $p99 = $null
    $ftSamples = @()
    $labelOut = if ($Label) { $Label } else { 'CapFrameX import' }

    if ($data.Runs -and @($data.Runs).Count -gt 0) {
        $run = @($data.Runs)[0]
        $m = $run.Metrics
        if ($m) {
            if ($null -ne $m.AvgFps) { $fpsAvg = [double]$m.AvgFps }
            elseif ($null -ne $m.AverageFPS) { $fpsAvg = [double]$m.AverageFPS }
            if ($null -ne $m.Fps1PctLow) { $fps1 = [double]$m.Fps1PctLow }
            elseif ($null -ne $m.OnePercentLow) { $fps1 = [double]$m.OnePercentLow }
            if ($null -ne $m.Fps01PctLow) { $fps01 = [double]$m.Fps01PctLow }
            if ($null -ne $m.FrametimeP99) { $p99 = [double]$m.FrametimeP99 }
            if ($m.FrametimeSeries) { $ftSamples = @($m.FrametimeSeries | ForEach-Object { [double]$_ }) }
        }
        $cap = $run.CaptureData
        if (-not $cap) { $cap = $run.CapturedData }
        if ($cap) {
            foreach ($key in @('Frametime', 'Frametimes', 'FrameTimes', 'MsBetweenPresents')) {
                if ($cap.$key -and @($cap.$key).Count -gt 0) {
                    $ftSamples = @($cap.$key | ForEach-Object { [double]$_ })
                    break
                }
            }
        }
        if ($run.Info -and $run.Info.GameName) { $labelOut = [string]$run.Info.GameName }
        elseif ($data.Info -and $data.Info.GameName) { $labelOut = [string]$data.Info.GameName }
    } elseif ($data.frametime -and ($data.frametime -is [System.Array] -or $data.frametime.Count)) {
        try { $ftSamples = @($data.frametime | ForEach-Object { [double]$_ }) } catch {}
        if ($data.fps) {
            if ($null -ne $data.fps.avg) { $fpsAvg = [double]$data.fps.avg }
            if ($null -ne $data.fps.'1pct_low') { $fps1 = [double]$data.fps.'1pct_low' }
        }
    } elseif ($data.fps_series -or $data.frametime_series) {
        # Already our artifact shape
        $parsed = @{
            available = $true
            source = 'import'
            fps_avg = $data.fps_avg
            fps_1pct_low = $data.fps_1pct_low
            fps_0_1pct_low = $data.fps_0_1pct_low
            frametime_p99_ms = $data.frametime_p99_ms
            sample_count = $data.sample_count
            fps_series = @($data.fps_series)
            frametime_series = @($data.frametime_series)
            ms_between_series = @($data.ms_between_series)
            duration_s = $data.duration_s
            methodology = 'Imported session artifact'
            started_at = $data.started_at
            stopped_at = (Get-Date).ToUniversalTime().ToString('o')
        }
        $saved = Save-ProbePresentMonSessionArtifact -Parsed $parsed -Source 'import' -Label $labelOut
        if (-not $saved.ok) { return $saved }
        $full = Get-ProbePresentMonSessionById -Id $saved.id
        return @{
            ok = $true
            id = $saved.id
            path = $saved.path
            session = $full.session
            message = "Imported as session $($saved.id)"
        }
    }

    if ($ftSamples.Count -lt 2) {
        return @{ ok = $false; error = 'no_frametimes'; message = 'CapFrameX JSON had no frametime series.' }
    }

    $maxPts = 600
    $ftSeries = @($ftSamples)
    if ($ftSeries.Count -gt $maxPts) {
        $step = [Math]::Max(1, [int][Math]::Ceiling($ftSeries.Count / [double]$maxPts))
        $ftSeries = for ($i = 0; $i -lt $ftSamples.Count; $i += $step) { $ftSamples[$i] }
    }
    $fpsSeries = @($ftSeries | ForEach-Object { if ($_ -gt 0) { 1000.0 / $_ } else { 0 } })
    $lows = Get-PresentMonPercentileLows -FpsSamples $fpsSeries
    if ($null -eq $fpsAvg -and $fpsSeries.Count) {
        $fpsAvg = [math]::Round(($fpsSeries | Measure-Object -Average).Average, 1)
    }
    if ($null -eq $fps1) { $fps1 = $lows.fps_1pct_low }
    if ($null -eq $fps01) { $fps01 = $lows.fps_0_1pct_low }
    if ($null -eq $p99) {
        $sorted = @($ftSeries | Sort-Object)
        $idx = [int][math]::Floor($sorted.Count * 0.99)
        if ($idx -ge $sorted.Count) { $idx = $sorted.Count - 1 }
        $p99 = [math]::Round($sorted[$idx], 2)
    }

    $parsed = @{
        available = $true
        source = 'import'
        fps_avg = $fpsAvg
        fps_1pct_low = $fps1
        fps_0_1pct_low = $fps01
        frametime_p99_ms = $p99
        sample_count = $ftSamples.Count
        fps_series = @($fpsSeries)
        frametime_series = @($ftSeries)
        ms_between_series = @($ftSeries)
        duration_s = [math]::Round(($ftSamples | Measure-Object -Sum).Sum / 1000.0, 1)
        methodology = 'Imported CapFrameX JSON - 1%/0.1% from frametime->FPS when metrics missing'
        started_at = $null
        stopped_at = (Get-Date).ToUniversalTime().ToString('o')
    }
    $saved = Save-ProbePresentMonSessionArtifact -Parsed $parsed -Source 'import' -Label $labelOut
    if (-not $saved.ok) { return $saved }
    $full = Get-ProbePresentMonSessionById -Id $saved.id
    return @{
        ok = $true
        id = $saved.id
        path = $saved.path
        session = $full.session
        message = "Imported as session $($saved.id)"
    }
}

function Export-ProbePresentMonCapFrameX {
    param([string]$Id)
    $full = Get-ProbePresentMonSessionById -Id $Id
    if (-not $full.ok) { return $full }
    $s = $full.session
    $ft = @()
    if ($s.frametime_series) { $ft = @($s.frametime_series | ForEach-Object { [double]$_ }) }
    elseif ($s.ms_between_series) { $ft = @($s.ms_between_series | ForEach-Object { [double]$_ }) }
    $game = if ($s.label) { [string]$s.label } elseif ($s.process_name) { [string]$s.process_name } else { 'PcLabKit Session' }
    $payload = @{
        Info = @{
            ProcessName = $(if ($s.process_name) { [string]$s.process_name } else { $game })
            GameName = $game
            CreationDate = $(if ($s.saved_at) { [string]$s.saved_at } else { (Get-Date).ToUniversalTime().ToString('o') })
            Comment = 'Exported from PcLab Kit Session Forensics'
        }
        Runs = @(
            @{
                Info = @{ GameName = $game }
                Metrics = @{
                    AvgFps = $s.fps_avg
                    AverageFPS = $s.fps_avg
                    Fps1PctLow = $s.fps_1pct_low
                    OnePercentLow = $s.fps_1pct_low
                    Fps01PctLow = $s.fps_0_1pct_low
                    FrametimeP99 = $s.frametime_p99_ms
                }
                CaptureData = @{
                    Frametimes = $ft
                    MsBetweenPresents = $ft
                }
            }
        )
    }
    return @{
        ok = $true
        format = 'capframex'
        id = $s.id
        filename = ("pclab_{0}_capframex.json" -f ($s.id -replace '[^\w\-]', '_'))
        export = $payload
    }
}

