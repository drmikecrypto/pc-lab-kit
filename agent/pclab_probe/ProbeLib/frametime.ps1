function Build-FrametimeSpikeMap {
    param(
        [double[]]$Samples,
        [double[]]$TimestampsMs = @(),
        [double]$SpikeThresholdMs = 25.0,
        [int]$MaxSpikes = 40,
        [int]$MaxSeries = 600
    )

    if (-not $Samples -or $Samples.Count -lt 3) {
        return @{ available = $false; spikes = @(); series = @() }
    }

    $mean = ($Samples | Measure-Object -Average).Average
    $threshold = [math]::Max($SpikeThresholdMs, $mean * 2.5)

    $spikes = @()
    $series = @()
    $step = [math]::Max(1, [int][math]::Floor($Samples.Count / $MaxSeries))

    for ($i = 0; $i -lt $Samples.Count; $i++) {
        $v = [double]$Samples[$i]
        $t = if ($TimestampsMs.Count -gt $i) { $TimestampsMs[$i] } else { $i * (1000.0 / 60.0) }

        if ($i % $step -eq 0) {
            $series += @{ t_ms = [math]::Round($t, 1); ft_ms = [math]::Round($v, 2) }
        }

        $prev = if ($i -gt 0) { [double]$Samples[$i - 1] } else { $v }
        $delta = $v - $prev
        if ($v -ge $threshold -or $delta -ge ($threshold * 0.5)) {
            $severity = if ($v -ge 50) { 'critical' } elseif ($v -ge 35) { 'high' } else { 'medium' }
            $cause = if ($v -ge 50) { 'severe_stutter' } elseif ($delta -ge 15) { 'spike_up' } else { 'frametime_high' }
            $spikes += @{
                index = $i
                t_ms = [math]::Round($t, 1)
                ft_ms = [math]::Round($v, 2)
                delta_ms = [math]::Round($delta, 2)
                severity = $severity
                likely_cause = $cause
            }
        }
    }

    if ($spikes.Count -gt $MaxSpikes) {
        $spikes = $spikes | Sort-Object { $_.ft_ms } -Descending | Select-Object -First $MaxSpikes | Sort-Object { $_.t_ms }
    }

    $sorted = $Samples | Sort-Object
    $p99 = $sorted[[int][math]::Floor($sorted.Count * 0.99)]
    $p01 = $sorted[[int][math]::Floor($sorted.Count * 0.01)]

    return @{
        available = $true
        spikes = @($spikes)
        series = @($series)
        stats = @{
            count = $Samples.Count
            mean_ms = [math]::Round($mean, 2)
            p99_ms = [math]::Round($p99, 2)
            p01_ms = [math]::Round($p01, 2)
            spike_count = $spikes.Count
            threshold_ms = [math]::Round($threshold, 1)
        }
    }
}

function Find-CapFrameXExports {
    $paths = @()
    $roots = @(
        (Join-Path $env:USERPROFILE 'Documents\CapFrameX'),
        (Join-Path $env:USERPROFILE 'Documents'),
        (Join-Path $env:USERPROFILE 'Downloads')
    )
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem -Path $root -Filter '*.json' -Recurse -ErrorAction SilentlyContinue | Where-Object {
            $_.Length -lt 50MB -and $_.LastWriteTime -gt (Get-Date).AddDays(-14)
        } | Sort-Object LastWriteTime -Descending | Select-Object -First 5 | ForEach-Object {
            $head = Get-Content $_.FullName -TotalCount 5 -ErrorAction SilentlyContinue
            if ($head -match 'CapFrameX|Frametime|Runs') { $paths += $_.FullName }
        }
    }
    return $paths | Select-Object -First 1
}

function Parse-CapFrameXFrametimes {
    param([string]$JsonPath)
    try {
        $data = Get-Content $JsonPath -Raw | ConvertFrom-Json
    } catch { return $null }

    $samples = @()
    $timestamps = @()

    if ($data.Runs -and $data.Runs[0]) {
        $run = $data.Runs[0]
        if ($run.CaptureData.Frametime) { $samples = @($run.CaptureData.Frametime | ForEach-Object { [double]$_ }) }
        elseif ($run.CaptureData.Frametimes) { $samples = @($run.CaptureData.Frametimes | ForEach-Object { [double]$_ }) }
        elseif ($run.Metrics.FrametimeSeries) { $samples = @($run.Metrics.FrametimeSeries | ForEach-Object { [double]$_ }) }
        if ($run.CaptureData.FrametimeTime) { $timestamps = @($run.CaptureData.FrametimeTime | ForEach-Object { [double]$_ }) }
    }
    if ($samples.Count -eq 0 -and $data.frametime) {
        $samples = @($data.frametime | ForEach-Object { [double]$_ })
    }

    if ($samples.Count -lt 3) { return $null }
    return Build-FrametimeSpikeMap -Samples $samples -TimestampsMs $timestamps
}

function Get-FrametimeTelemetry {
    . "$PSScriptRoot\presentmon.ps1"

    $map = $null
    $source = $null

    # CapFrameX auto-import
    foreach ($f in (Find-CapFrameXExports)) {
        $map = Parse-CapFrameXFrametimes $f
        if ($map -and $map.available) {
            $source = 'capframex_auto'
            break
        }
    }

    # PresentMon live capture
    if (-not $map) {
        $pm = Get-ProbePresentMonTelemetry
        if ($pm.available -and $pm.frametime_series) {
            $map = Build-FrametimeSpikeMap -Samples @($pm.frametime_series)
            $source = 'presentmon'
        }
    }

    if (-not $map) {
        return @{ available = $false; note = 'Run a game or place CapFrameX JSON in Documents/CapFrameX' }
    }

    $map.source = $source
    return $map
}
