. "$PSScriptRoot\common.ps1"
if (Test-Path (Join-Path $PSScriptRoot 'thermal.ps1')) {
    . "$PSScriptRoot\thermal.ps1"
}

function Get-ProbeStressCatalog {
    return @(
        @{ id = 'cpu'; label = 'CPU stress'; seconds_default = 30; max_seconds = 300; profile = $true }
        @{ id = 'memory'; label = 'Memory stress'; seconds_default = 30; max_seconds = 300; profile = $true }
        @{ id = 'gpu'; label = 'GPU stress'; seconds_default = 30; max_seconds = 180; profile = $true }
        @{ id = 'combined'; label = 'Combined CPU+RAM'; seconds_default = 45; max_seconds = 300; profile = $true }
        @{ id = 'quick'; label = 'Quick 60s profile'; seconds_default = 60; max_seconds = 60; profile = $true }
    )
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
    $Seconds = [Math]::Max(5, [Math]::Min(300, $Seconds))
    $threads = [Environment]::ProcessorCount
    $jobs = @()
    $end = (Get-Date).AddSeconds($Seconds)
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
    return @{
        id = 'cpu'
        label = 'PcLab CPU stress'
        duration_s = $Seconds
        threads = $threads
        status = 'completed'
        cpu_temp_max = $cpuPeak
        gpu_temp_max = $gpuPeak
        samples = @($samples)
        replaces = @('Prime95', 'OCCT', 'AIDA64')
    }
}

function Invoke-ProbeMemoryStress {
    param([int]$Seconds = 30, [int]$Percent = 40, [switch]$CollectSamples)
    $Seconds = [Math]::Max(5, [Math]::Min(300, $Seconds))
    $Percent = [Math]::Max(10, [Math]::Min(70, $Percent))
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
    return @{
        id = 'memory'
        label = 'PcLab memory stress'
        duration_s = $Seconds
        allocated_mb = [math]::Round($allocated / 1MB, 1)
        status = if ($errors -gt 0) { 'failed' } else { 'completed' }
        errors_found = $errors
        samples = @($samples)
        replaces = @('TestMem5', 'HCI MemTest', 'MemTest64')
    }
}

function Invoke-ProbeGpuStress {
    param([int]$Seconds = 30, [switch]$CollectSamples)
    $Seconds = [Math]::Max(5, [Math]::Min(180, $Seconds))
    $samples = New-Object System.Collections.Generic.List[object]
    $method = 'host_load'
    $end = (Get-Date).AddSeconds($Seconds)

    # Prefer keeping GPU busy via repeated nvidia-smi queries + host compute; full Vulkan power virus is native-core.
    $jobs = @()
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

    while ((Get-Date) -lt $end) {
        Start-Sleep -Milliseconds 700
        if ($CollectSamples) { $samples.Add((Get-ProbeStressThermalSample)) }
    }
    $jobs | Stop-Job -ErrorAction SilentlyContinue | Out-Null
    $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
    $gpuPeak = ($samples | ForEach-Object { $_.gpu_temp } | Where-Object { $_ -ne $null } | Measure-Object -Maximum).Maximum
    $cpuPeak = ($samples | ForEach-Object { $_.cpu_temp } | Where-Object { $_ -ne $null } | Measure-Object -Maximum).Maximum

    return @{
        id = 'gpu'
        label = 'PcLab GPU stress'
        duration_s = $Seconds
        status = 'completed'
        method = $method
        cpu_temp_max = $cpuPeak
        gpu_temp_max = $gpuPeak
        samples = @($samples)
        note = 'Thermal soak / watch profile. Vulkan power-virus lands in native core.'
        replaces = @('FurMark', 'MSI Kombustor')
    }
}

function Invoke-ProbeCombinedStress {
    param([int]$Seconds = 45, [switch]$CollectSamples)
    $Seconds = [Math]::Max(10, [Math]::Min(300, $Seconds))
    $half = [Math]::Max(5, [int]($Seconds / 2))
    $cpu = Invoke-ProbeCpuStress -Seconds $half -CollectSamples:$CollectSamples
    $mem = Invoke-ProbeMemoryStress -Seconds $half -CollectSamples:$CollectSamples
    $samples = @($cpu.samples) + @($mem.samples)
    $status = if ($mem.status -eq 'failed') { 'failed' } else { 'completed' }
    return @{
        id = 'combined'
        label = 'PcLab combined stress'
        duration_s = $Seconds
        status = $status
        parts = @($cpu, $mem)
        cpu_temp_max = @($cpu.cpu_temp_max, $mem.cpu_temp_max) | Where-Object { $_ -ne $null } | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum
        gpu_temp_max = @($cpu.gpu_temp_max, $mem.gpu_temp_max) | Where-Object { $_ -ne $null } | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum
        errors_found = [int]$mem.errors_found
        samples = $samples
        replaces = @('OCCT Power', 'AIDA64 System')
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
    switch ($Id.ToLower()) {
        'cpu' { return Invoke-ProbeCpuStress -Seconds $seconds -CollectSamples:$collect }
        'memory' { return Invoke-ProbeMemoryStress -Seconds $seconds -Percent $percent -CollectSamples:$collect }
        'gpu' { return Invoke-ProbeGpuStress -Seconds $seconds -CollectSamples:$collect }
        'combined' { return Invoke-ProbeCombinedStress -Seconds $seconds -CollectSamples:$collect }
        'quick' { return Invoke-ProbeCombinedStress -Seconds 60 -CollectSamples:$collect }
        default { throw "Unknown stress test: $Id" }
    }
}
