. "$PSScriptRoot\common.ps1"
if (Test-Path (Join-Path $PSScriptRoot 'thermal.ps1')) {
    . "$PSScriptRoot\thermal.ps1"
}

function Get-ProbeStressCatalog {
    return @(
        @{ id = 'cpu'; label = 'CPU stress'; seconds_default = 30; max_seconds = 86400; profile = $true }
        @{ id = 'memory'; label = 'Memory stress'; seconds_default = 30; max_seconds = 86400; profile = $true }
        @{ id = 'gpu'; label = 'GPU stress (fixed / thermal)'; seconds_default = 30; max_seconds = 86400; profile = $true }
        @{ id = 'gpu_adaptive'; label = 'GPU adaptive (variable load)'; seconds_default = 90; max_seconds = 86400; profile = $true; adaptive = $true }
        @{ id = 'gpu_variable'; label = 'GPU variable (power/thermal ramp)'; seconds_default = 90; max_seconds = 86400; profile = $true; adaptive = $true }
        @{ id = 'gpu_switch'; label = 'GPU switch (idle↔load)'; seconds_default = 90; max_seconds = 86400; profile = $true; adaptive = $true }
        @{ id = 'combined'; label = 'Combined CPU+GPU+RAM'; seconds_default = 45; max_seconds = 86400; profile = $true }
        @{ id = 'quick'; label = 'Quick 60s profile'; seconds_default = 60; max_seconds = 60; profile = $true }
        @{ id = 'oracle'; label = 'Stability oracle'; seconds_default = 120; max_seconds = 86400; profile = $true }
        @{ id = 'soak_15'; label = 'Soak 15 min'; seconds_default = 900; max_seconds = 900; profile = $true; soak = $true }
        @{ id = 'soak_30'; label = 'Soak 30 min'; seconds_default = 1800; max_seconds = 1800; profile = $true; soak = $true }
        @{ id = 'soak_60'; label = 'Soak 60 min'; seconds_default = 3600; max_seconds = 3600; profile = $true; soak = $true }
    )
}

function Get-ProbeWheaTimeline {
    param(
        [datetime]$Since = (Get-Date).AddHours(-1),
        [int]$MaxEvents = 50
    )
    $events = @()
    try {
        $whea = Get-WinEvent -FilterHashtable @{
            LogName = 'System'
            ProviderName = 'Microsoft-Windows-WHEA-Logger'
            StartTime = $Since
        } -MaxEvents $MaxEvents -ErrorAction SilentlyContinue
        foreach ($e in @($whea)) {
            $msg = ("$($e.Message)" -replace '\s+', ' ')
            if ($msg.Length -gt 240) { $msg = $msg.Substring(0, 240) }
            $events += @{
                at = $e.TimeCreated.ToUniversalTime().ToString('o')
                id = [int]$e.Id
                level = [string]$e.LevelDisplayName
                message = $msg
            }
        }
    } catch {}
    return @{
        since = $Since.ToUniversalTime().ToString('o')
        count = @($events).Count
        events = @($events)
    }
}

function Get-ProbeStressThermalSample {
    $sample = @{
        at = (Get-Date).ToUniversalTime().ToString('o')
        cpu_temp = $null
        gpu_temp = $null
        gpu_hotspot = $null
        whea_errors = 0
    }
    try {
        if (Get-Command Get-ProbeCpuThermalFindings -ErrorAction SilentlyContinue) {
            $t = Get-ProbeCpuThermalFindings
            if ($t.cpu_temp_max) { $sample.cpu_temp = [double]$t.cpu_temp_max }
            if ($t.gpu_temp_max) { $sample.gpu_temp = [double]$t.gpu_temp_max }
            if ($t.gpu_hotspot_max) { $sample.gpu_hotspot = [double]$t.gpu_hotspot_max }
        }
    } catch {}
    if (-not $sample.cpu_temp) {
        try {
            $ct = Get-CimSafe Win32_PerfFormattedData_Counters_ThermalZoneInformation -ErrorAction SilentlyContinue
            # best-effort; often empty
        } catch {}
    }
    if ((Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
        try {
            $q = & nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>$null
            if ($q) { $sample.gpu_temp = [double](($q -split "`n")[0]) }
        } catch {}
    }
    try {
        $whea = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = (Get-Date).AddMinutes(-5) } -MaxEvents 20 -ErrorAction SilentlyContinue
        if ($whea) { $sample.whea_errors = @($whea).Count }
    } catch {}
    return $sample
}

function Invoke-ProbeCpuStress {
    param([int]$Seconds = 30, [switch]$CollectSamples)
    $Seconds = [Math]::Max(5, [Math]::Min(86400, $Seconds))
    $threads = [Environment]::ProcessorCount
    $jobs = @()
    $stressStart = Get-Date
    $end = $stressStart.AddSeconds($Seconds)
    $samples = New-Object System.Collections.Generic.List[object]
    for ($t = 0; $t -lt $threads; $t++) {
        $jobs += Start-Job -ScriptBlock {
            param($until)
            while ((Get-Date) -lt $until) {
                $x = 0.0
                for ($i = 0; $i -lt 50000; $i++) { $x += [Math]::Sqrt($i + 1) }
            }
        } -ArgumentList $end
    }
    while ((Get-Date) -lt $end) {
        Start-Sleep -Milliseconds 800
        if ($CollectSamples) { $samples.Add((Get-ProbeStressThermalSample)) }
    }
    $jobs | Stop-Job -ErrorAction SilentlyContinue | Out-Null
    $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
    $cpuPeak = ($samples | ForEach-Object { $_.cpu_temp } | Where-Object { $_ -ne $null } | Measure-Object -Maximum).Maximum
    $gpuPeak = ($samples | ForEach-Object { $_.gpu_temp } | Where-Object { $_ -ne $null } | Measure-Object -Maximum).Maximum
    $wheaTimeline = Get-ProbeWheaTimeline -Since $stressStart
    $wheaTotal = ($samples | ForEach-Object { [int]$_.whea_errors } | Measure-Object -Sum).Sum
    if ($wheaTimeline.count -gt $wheaTotal) { $wheaTotal = $wheaTimeline.count }

    return @{
        id = 'cpu'
        label = 'PcLab CPU stress'
        duration_s = $Seconds
        threads = $threads
        status = 'completed'
        cpu_temp_max = $cpuPeak
        gpu_temp_max = $gpuPeak
        whea_errors = $wheaTotal
        whea_timeline = $wheaTimeline
        samples = @($samples)
        replaces = @('Prime95', 'OCCT', 'AIDA64')
    }
}

function Invoke-ProbeMemoryStress {
    param([int]$Seconds = 30, [int]$Percent = 40, [switch]$CollectSamples)
    $Seconds = [Math]::Max(5, [Math]::Min(86400, $Seconds))
    $Percent = [Math]::Max(10, [Math]::Min(70, $Percent))
    $stressStart = Get-Date
    $targetBytes = [long]([Math]::Min(
        ([GC]::GetTotalMemory($false) * 4),
        ((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory * 1KB) * ($Percent / 100.0)
    ))
    if ($targetBytes -lt 32MB) { $targetBytes = 32MB }
    $blocks = @()
    $chunk = 8MB
    $allocated = 0L
    $errors = 0
    $samples = New-Object System.Collections.Generic.List[object]
    try {
        while ($allocated -lt $targetBytes) {
            $take = [Math]::Min($chunk, $targetBytes - $allocated)
            $blocks += New-Object byte[] $take
            $allocated += $take
        }
        $end = (Get-Date).AddSeconds($Seconds)
        while ((Get-Date) -lt $end) {
            foreach ($b in $blocks) {
                for ($i = 0; $i -lt [Math]::Min($b.Length, 65536); $i += 4096) {
                    $before = $b[$i]
                    $b[$i] = ($b[$i] -bxor 0xA5)
                    if (($b[$i] -bxor 0xA5) -ne $before) { $errors++ }
                }
            }
            if ($CollectSamples) { $samples.Add((Get-ProbeStressThermalSample)) }
            Start-Sleep -Milliseconds 200
        }
    } finally {
        $blocks = $null
        [GC]::Collect()
    }
    $wheaTimeline = Get-ProbeWheaTimeline -Since $stressStart
    $wheaTotal = ($samples | ForEach-Object { [int]$_.whea_errors } | Measure-Object -Sum).Sum
    if ($wheaTimeline.count -gt $wheaTotal) { $wheaTotal = $wheaTimeline.count }

    return @{
        id = 'memory'
        label = 'PcLab memory stress'
        duration_s = $Seconds
        allocated_mb = [math]::Round($allocated / 1MB, 1)
        status = if ($errors -gt 0) { 'failed' } else { 'completed' }
        errors_found = $errors
        whea_errors = $wheaTotal
        whea_timeline = $wheaTimeline
        samples = @($samples)
        replaces = @('TestMem5', 'HCI MemTest', 'MemTest64')
    }
}

function Find-ProbeGpuStressExe {
    if (Get-Command Find-ProbeVkBench -ErrorAction SilentlyContinue) {
        $vk = Find-ProbeVkBench
        if ($vk) { return $vk }
    }
    $candidates = @(
        (Join-Path $PSScriptRoot '..\PcLabVkBench.exe'),
        (Join-Path $PSScriptRoot '..\tools\PcLabVkBench\PcLabVkBench.exe')
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return (Resolve-Path $c).Path }
    }
    return $null
}

function Invoke-ProbeGpuStress {
    param(
        [int]$Seconds = 30,
        [switch]$CollectSamples,
        [string]$LoadMode = 'fixed'
    )
    $Seconds = [Math]::Max(5, [Math]::Min(86400, $Seconds))
    $LoadMode = ("$LoadMode").ToLower()
    if ($LoadMode -in @('adaptive', 'variable', 'switch', 'gpu_adaptive', 'gpu_variable', 'gpu_switch')) {
        return Invoke-ProbeGpuAdaptiveStress -Seconds $Seconds -CollectSamples:$CollectSamples -Style $LoadMode
    }

    $stressStart = Get-Date
    $samples = New-Object System.Collections.Generic.List[object]
    $method = 'host_load'
    $vkScore = $null
    $vkEngine = $null
    $end = (Get-Date).AddSeconds($Seconds)
    $vk = Find-ProbeGpuStressExe

    $jobs = @()
    if ($vk) {
        $method = 'vulkan_d3d11_stress'
        $jobs += Start-Job -ScriptBlock {
            param($exe, $sec)
            & $exe --stress-seconds $sec 2>&1 | Out-String
        } -ArgumentList $vk, $Seconds
    } else {
        $jobs += Start-Job -ScriptBlock {
            param($until)
            while ((Get-Date) -lt $until) {
                $x = 0.0
                for ($i = 0; $i -lt 80000; $i++) { $x += [Math]::Sin($i) * [Math]::Cos($i) }
            }
        } -ArgumentList $end
        if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
            $method = 'nvidia_watch'
        }
    }

    while ((Get-Date) -lt $end) {
        Start-Sleep -Milliseconds 700
        if ($CollectSamples) { $samples.Add((Get-ProbeStressThermalSample)) }
    }
    $out = $jobs | Wait-Job | Receive-Job
    $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
    if ($vk -and $out) {
        $line = ("$out" -split "`r?`n" | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1)
        if ($line) {
            try {
                $j = $line | ConvertFrom-Json
                $vkScore = $j.score
                $vkEngine = $j.engine
            } catch {}
        }
    }
    $gpuPeak = ($samples | ForEach-Object { $_.gpu_temp } | Where-Object { $_ -ne $null } | Measure-Object -Maximum).Maximum
    $cpuPeak = ($samples | ForEach-Object { $_.cpu_temp } | Where-Object { $_ -ne $null } | Measure-Object -Maximum).Maximum
    $hsPeak = ($samples | ForEach-Object { $_.gpu_hotspot } | Where-Object { $_ -ne $null } | Measure-Object -Maximum).Maximum

    $wheaTimeline = Get-ProbeWheaTimeline -Since $stressStart
    $wheaTotal = ($samples | ForEach-Object { [int]$_.whea_errors } | Measure-Object -Sum).Sum
    if ($wheaTimeline.count -gt $wheaTotal) { $wheaTotal = $wheaTimeline.count }

    return @{
        id = 'gpu'
        label = 'PcLab GPU stress (fixed load)'
        duration_s = $Seconds
        status = 'completed'
        method = $method
        load_mode = 'fixed'
        engine = $vkEngine
        score = $vkScore
        cpu_temp_max = $cpuPeak
        gpu_temp_max = $gpuPeak
        gpu_hotspot_max = $hsPeak
        whea_errors = $wheaTotal
        whea_timeline = $wheaTimeline
        samples = @($samples)
        note = if ($vk) {
            'Fixed compute soak (FurMark-style) — power/thermal only. Use gpu_adaptive / gpu_variable / gpu_switch for OCCT-like boost coverage.'
        } else {
            'Fallback host/watch — PcLabVkBench.exe missing.'
        }
        replaces = @('FurMark', 'MSI Kombustor')
    }
}

<#
  OCCT-style adaptive / variable / switch GPU loads: stepped VkBench soaks with idle gaps
  so boost clocks and transient WHEA show up (fixed 100% forever often misses modern GPUs).
#>
function Invoke-ProbeGpuAdaptiveStress {
    param(
        [int]$Seconds = 90,
        [switch]$CollectSamples,
        [string]$Style = 'adaptive'
    )
    $Seconds = [Math]::Max(30, [Math]::Min(86400, $Seconds))
    $Style = ("$Style").ToLower() -replace '^gpu_', ''
    if ($Style -notin @('adaptive', 'variable', 'switch')) { $Style = 'adaptive' }

    $stressStart = Get-Date
    $samples = New-Object System.Collections.Generic.List[object]
    $phases = New-Object System.Collections.Generic.List[object]
    $vk = Find-ProbeGpuStressExe
    $vkScore = $null
    $vkEngine = $null

    # Duty fractions of wall time spent under load (rest is idle sample window)
    $plan = switch ($Style) {
        'switch' {
            @(
                @{ label = 'load_burst_a'; duty = 0.55; idle_after = $true }
                @{ label = 'idle_dwell'; duty = 0.0; idle_after = $false }
                @{ label = 'load_burst_b'; duty = 0.55; idle_after = $true }
            )
        }
        'variable' {
            @(
                @{ label = 'ramp_low'; duty = 0.35; idle_after = $false }
                @{ label = 'ramp_mid'; duty = 0.55; idle_after = $false }
                @{ label = 'ramp_high'; duty = 0.85; idle_after = $false }
            )
        }
        default {
            @(
                @{ label = 'warm'; duty = 0.40; idle_after = $true }
                @{ label = 'peak'; duty = 0.90; idle_after = $true }
                @{ label = 'recover'; duty = 0.50; idle_after = $false }
            )
        }
    }

    $slice = [Math]::Max(8, [int]($Seconds / [Math]::Max(1, $plan.Count)))
    $deadline = (Get-Date).AddSeconds($Seconds)

    foreach ($step in $plan) {
        if ((Get-Date) -ge $deadline) { break }
        $remain = [Math]::Max(5, [int](($deadline - (Get-Date)).TotalSeconds))
        $stepBudget = [Math]::Min($slice, $remain)
        $loadSec = [Math]::Max(0, [int]($stepBudget * [double]$step.duty))
        $idleSec = [Math]::Max(0, $stepBudget - $loadSec)
        if ($step.duty -le 0) {
            $loadSec = 0
            $idleSec = $stepBudget
        }

        $phaseStart = Get-Date
        if ($loadSec -gt 0) {
            $jobs = @()
            if ($vk) {
                $jobs += Start-Job -ScriptBlock {
                    param($exe, $sec)
                    & $exe --stress-seconds $sec 2>&1 | Out-String
                } -ArgumentList $vk, $loadSec
            } else {
                $until = (Get-Date).AddSeconds($loadSec)
                $jobs += Start-Job -ScriptBlock {
                    param($u)
                    while ((Get-Date) -lt $u) {
                        $x = 0.0
                        for ($i = 0; $i -lt 80000; $i++) { $x += [Math]::Sin($i) * [Math]::Cos($i) }
                    }
                } -ArgumentList $until
            }
            $loadEnd = (Get-Date).AddSeconds($loadSec)
            while ((Get-Date) -lt $loadEnd) {
                Start-Sleep -Milliseconds 700
                if ($CollectSamples) { $samples.Add((Get-ProbeStressThermalSample)) }
            }
            $out = $jobs | Wait-Job | Receive-Job
            $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
            if ($vk -and $out) {
                $line = ("$out" -split "`r?`n" | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1)
                if ($line) {
                    try {
                        $j = $line | ConvertFrom-Json
                        if ($j.score) { $vkScore = $j.score }
                        if ($j.engine) { $vkEngine = $j.engine }
                    } catch {}
                }
            }
        }
        if ($idleSec -gt 0 -or $step.idle_after) {
            $idleFor = if ($idleSec -gt 0) { $idleSec } else { [Math]::Min(5, [int](($deadline - (Get-Date)).TotalSeconds)) }
            $idleEnd = (Get-Date).AddSeconds([Math]::Max(1, $idleFor))
            while ((Get-Date) -lt $idleEnd -and (Get-Date) -lt $deadline) {
                Start-Sleep -Milliseconds 700
                if ($CollectSamples) { $samples.Add((Get-ProbeStressThermalSample)) }
            }
        }
        $phases.Add(@{
            label = $step.label
            load_s = $loadSec
            idle_s = $idleSec
            duration_s = [Math]::Round(((Get-Date) - $phaseStart).TotalSeconds, 1)
        })
    }

    $gpuPeak = ($samples | ForEach-Object { $_.gpu_temp } | Where-Object { $_ -ne $null } | Measure-Object -Maximum).Maximum
    $cpuPeak = ($samples | ForEach-Object { $_.cpu_temp } | Where-Object { $_ -ne $null } | Measure-Object -Maximum).Maximum
    $hsPeak = ($samples | ForEach-Object { $_.gpu_hotspot } | Where-Object { $_ -ne $null } | Measure-Object -Maximum).Maximum
    $wheaTimeline = Get-ProbeWheaTimeline -Since $stressStart
    $wheaTotal = ($samples | ForEach-Object { [int]$_.whea_errors } | Measure-Object -Sum).Sum
    if ($wheaTimeline.count -gt $wheaTotal) { $wheaTotal = $wheaTimeline.count }

    return @{
        id = "gpu_$Style"
        label = "PcLab GPU $Style stress"
        duration_s = $Seconds
        status = 'completed'
        method = if ($vk) { "vulkan_d3d11_$Style" } else { "host_load_$Style" }
        load_mode = $Style
        engine = $vkEngine
        score = $vkScore
        phases = @($phases)
        cpu_temp_max = $cpuPeak
        gpu_temp_max = $gpuPeak
        gpu_hotspot_max = $hsPeak
        whea_errors = $wheaTotal
        whea_timeline = $wheaTimeline
        samples = @($samples)
        note = "OCCT-like $Style GPU load (stepped soak + idle). Fixed gpu profile remains for pure power/thermal."
        replaces = @('OCCT Adaptive', 'OCCT Variable', 'OCCT Switch', 'FurMark')
    }
}

function Invoke-ProbeCombinedStress {
    param([int]$Seconds = 45, [switch]$CollectSamples)
    $Seconds = [Math]::Max(10, [Math]::Min(86400, $Seconds))
    $third = [Math]::Max(5, [int]($Seconds / 3))
    $cpu = Invoke-ProbeCpuStress -Seconds $third -CollectSamples:$CollectSamples
    $mem = Invoke-ProbeMemoryStress -Seconds $third -CollectSamples:$CollectSamples
    $gpu = Invoke-ProbeGpuStress -Seconds $third -CollectSamples:$CollectSamples
    $samples = @($cpu.samples) + @($mem.samples) + @($gpu.samples)
    $status = if ($mem.status -eq 'failed' -or $gpu.status -eq 'failed') { 'failed' } else { 'completed' }
    $wheaTotal = [int]$cpu.whea_errors + [int]$mem.whea_errors + [int]$gpu.whea_errors
    $wheaEvents = @()
    foreach ($part in @($cpu, $mem, $gpu)) {
        if ($part.whea_timeline -and $part.whea_timeline.events) {
            $wheaEvents += @($part.whea_timeline.events)
        }
    }
    $wheaTimeline = @{
        count = [Math]::Max($wheaTotal, @($wheaEvents).Count)
        events = @($wheaEvents | Select-Object -First 50)
    }
    if (Get-Command Get-ProbePcieLinkTruth -ErrorAction SilentlyContinue) {
        . "$PSScriptRoot\openbook.ps1"
    }
    $pcie = $null
    if (Get-Command Get-ProbePcieLinkTruth -ErrorAction SilentlyContinue) {
        $pcie = Get-ProbePcieLinkTruth
    }
    return @{
        id = 'combined'
        label = 'PcLab combined stress'
        duration_s = $Seconds
        status = $status
        parts = @($cpu, $mem, $gpu)
        cpu_temp_max = @($cpu.cpu_temp_max, $mem.cpu_temp_max, $gpu.cpu_temp_max) | Where-Object { $_ -ne $null } | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum
        gpu_temp_max = @($cpu.gpu_temp_max, $mem.gpu_temp_max, $gpu.gpu_temp_max) | Where-Object { $_ -ne $null } | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum
        gpu_hotspot_max = $gpu.gpu_hotspot_max
        errors_found = [int]$mem.errors_found
        whea_errors = $wheaTotal
        whea_timeline = $wheaTimeline
        pcie_warnings = if ($pcie) { @($pcie.warnings) } else { @() }
        samples = $samples
        note = $gpu.note
        replaces = @('OCCT Power', 'AIDA64 System', 'FurMark')
    }
}

function Invoke-ProbeStress {
    param([string]$Id = 'cpu', [hashtable]$Options = @{})
    $seconds = 30
    $percent = 40
    $collect = $true
    if ($Options.ContainsKey('seconds') -and $Options.seconds) { $seconds = [int]$Options.seconds }
    if ($Options.ContainsKey('percent') -and $Options.percent) { $percent = [int]$Options.percent }
    if ($Options.ContainsKey('collect_samples') -and $Options.collect_samples -eq $false) { $collect = $false }
    $gpuMode = 'fixed'
    if ($Options.ContainsKey('gpu_mode') -and $Options.gpu_mode) { $gpuMode = [string]$Options.gpu_mode }
    switch ($Id.ToLower()) {
        'cpu' { return Invoke-ProbeCpuStress -Seconds $seconds -CollectSamples:$collect }
        'memory' { return Invoke-ProbeMemoryStress -Seconds $seconds -Percent $percent -CollectSamples:$collect }
        'gpu' { return Invoke-ProbeGpuStress -Seconds $seconds -CollectSamples:$collect -LoadMode $gpuMode }
        'gpu_adaptive' { return Invoke-ProbeGpuAdaptiveStress -Seconds $seconds -CollectSamples:$collect -Style 'adaptive' }
        'gpu_variable' { return Invoke-ProbeGpuAdaptiveStress -Seconds $seconds -CollectSamples:$collect -Style 'variable' }
        'gpu_switch' { return Invoke-ProbeGpuAdaptiveStress -Seconds $seconds -CollectSamples:$collect -Style 'switch' }
        'combined' { return Invoke-ProbeCombinedStress -Seconds $seconds -CollectSamples:$collect }
        'quick' { return Invoke-ProbeCombinedStress -Seconds 60 -CollectSamples:$collect }
        'soak_15' { return Invoke-ProbeCombinedStress -Seconds 900 -CollectSamples:$collect }
        'soak_30' { return Invoke-ProbeCombinedStress -Seconds 1800 -CollectSamples:$collect }
        'soak_60' { return Invoke-ProbeCombinedStress -Seconds 3600 -CollectSamples:$collect }
        'oracle' { return Invoke-ProbeStabilityOracle -Options $Options }
        default { throw "Unknown stress test: $Id" }
    }
}

<#
 Adaptive stability oracle — ramp CPU → GPU → combined until thermal/WHEA limits.
#>
function Invoke-ProbeStabilityOracle {
    param([hashtable]$Options = @{})

    $cpuLimit = if ($Options.cpu_temp_max) { [double]$Options.cpu_temp_max } else { 82.0 }
    $gpuLimit = if ($Options.gpu_temp_max) { [double]$Options.gpu_temp_max } else { 83.0 }
    $hotspotLimit = if ($Options.gpu_hotspot_max) { [double]$Options.gpu_hotspot_max } else { 92.0 }
    $stepSeconds = if ($Options.step_seconds) { [int]$Options.step_seconds } else { 20 }
    $stepSeconds = [Math]::Max(10, [Math]::Min(60, $stepSeconds))

    $oracleStart = Get-Date
    $steps = @()
    $allSamples = New-Object System.Collections.Generic.List[object]
    $breached = $false
    $breachReason = $null
    $marginPct = 100.0

    $baselineSeconds = if ($Options.baseline_seconds) { [int]$Options.baseline_seconds } else { 30 }
    $baselineSeconds = [Math]::Max(5, [Math]::Min(120, $baselineSeconds))
    $baselineSamples = New-Object System.Collections.Generic.List[object]
    $baselineEnd = (Get-Date).AddSeconds($baselineSeconds)
    while ((Get-Date) -lt $baselineEnd) {
        Start-Sleep -Milliseconds 900
        $baselineSamples.Add((Get-ProbeStressThermalSample))
    }
    $baseline = @{
        duration_s = $baselineSeconds
        cpu_temp_avg = ($baselineSamples | ForEach-Object { $_.cpu_temp } | Where-Object { $_ -ne $null } | Measure-Object -Average).Average
        gpu_temp_avg = ($baselineSamples | ForEach-Object { $_.gpu_temp } | Where-Object { $_ -ne $null } | Measure-Object -Average).Average
        gpu_hotspot_avg = ($baselineSamples | ForEach-Object { $_.gpu_hotspot } | Where-Object { $_ -ne $null } | Measure-Object -Average).Average
        sample_count = $baselineSamples.Count
    }
    foreach ($s in @($baselineSamples)) { $allSamples.Add($s) }

    $phases = @(
        @{ id = 'cpu'; label = 'CPU ramp'; fn = { Invoke-ProbeCpuStress -Seconds $stepSeconds -CollectSamples } }
        @{ id = 'gpu'; label = 'GPU adaptive ramp'; fn = { Invoke-ProbeGpuAdaptiveStress -Seconds $stepSeconds -CollectSamples -Style 'adaptive' } }
        @{ id = 'combined'; label = 'Combined ramp'; fn = { Invoke-ProbeCombinedStress -Seconds ($stepSeconds * 2) -CollectSamples } }
    )

    foreach ($phase in $phases) {
        if ($breached) { break }
        $run = & $phase.fn
        $cpuPeak = [double]($run.cpu_temp_max)
        $gpuPeak = [double]($run.gpu_temp_max)
        $hsPeak = [double]($run.gpu_hotspot_max)
        $whea = [int]($run.whea_errors)
        foreach ($s in @($run.samples)) { $allSamples.Add($s) }

        $headroomCpu = if ($cpuPeak) { [Math]::Max(0, $cpuLimit - $cpuPeak) } else { $cpuLimit }
        $headroomGpu = if ($gpuPeak) { [Math]::Max(0, $gpuLimit - $gpuPeak) } else { $gpuLimit }
        $headroomHs = if ($hsPeak) { [Math]::Max(0, $hotspotLimit - $hsPeak) } else { $hotspotLimit }
        $stepMargin = [Math]::Round(([Math]::Min($headroomCpu, [Math]::Min($headroomGpu, $headroomHs)) / [Math]::Max(1.0, $cpuLimit)) * 100, 1)
        $marginPct = [Math]::Min($marginPct, $stepMargin)

        $stepRec = @{
            id = $phase.id
            label = $phase.label
            duration_s = $run.duration_s
            cpu_temp_max = $run.cpu_temp_max
            gpu_temp_max = $run.gpu_temp_max
            gpu_hotspot_max = $run.gpu_hotspot_max
            whea_errors = $whea
            stability_margin_pct = $stepMargin
            status = 'ok'
        }

        if ($whea -gt 0) {
            $breached = $true
            $breachReason = "WHEA events during $($phase.id)"
            $stepRec.status = 'breach'
        }
        if ($cpuPeak -ge $cpuLimit) {
            $breached = $true
            $breachReason = "CPU temp $cpuPeak >= limit $cpuLimit"
            $stepRec.status = 'breach'
        }
        if ($gpuPeak -ge $gpuLimit) {
            $breached = $true
            $breachReason = "GPU temp $gpuPeak >= limit $gpuLimit"
            $stepRec.status = 'breach'
        }
        if ($hsPeak -ge $hotspotLimit) {
            $breached = $true
            $breachReason = "Hotspot $hsPeak >= limit $hotspotLimit"
            $stepRec.status = 'breach'
        }
        $steps += $stepRec
    }

    $wheaTimeline = Get-ProbeWheaTimeline -Since $oracleStart
    $wheaTotal = ($allSamples | ForEach-Object { [int]$_.whea_errors } | Measure-Object -Sum).Sum
    if ($wheaTimeline.count -gt $wheaTotal) { $wheaTotal = $wheaTimeline.count }

    return @{
        id = 'oracle'
        label = 'PcLab Stability Oracle'
        duration_s = [int]((Get-Date) - $oracleStart).TotalSeconds
        status = if ($breached) { 'limited' } else { 'completed' }
        breached = $breached
        breach_reason = $breachReason
        stability_margin_pct = [Math]::Round($marginPct, 1)
        oracle_steps = @($steps)
        baseline = $baseline
        cpu_temp_max = ($steps | ForEach-Object { $_.cpu_temp_max } | Where-Object { $_ -ne $null } | Measure-Object -Maximum).Maximum
        gpu_temp_max = ($steps | ForEach-Object { $_.gpu_temp_max } | Where-Object { $_ -ne $null } | Measure-Object -Maximum).Maximum
        gpu_hotspot_max = ($steps | ForEach-Object { $_.gpu_hotspot_max } | Where-Object { $_ -ne $null } | Measure-Object -Maximum).Maximum
        whea_errors = $wheaTotal
        whea_timeline = $wheaTimeline
        samples = @($allSamples)
        limits = @{ cpu_temp_max = $cpuLimit; gpu_temp_max = $gpuLimit; gpu_hotspot_max = $hotspotLimit }
        replaces = @('OCCT', 'Prime95', 'FurMark')
    }
}
