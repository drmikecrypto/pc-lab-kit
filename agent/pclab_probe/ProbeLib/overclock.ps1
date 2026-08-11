. "$PSScriptRoot\common.ps1"

function Get-ProbeOcStorePath {
    $dir = Join-Path $env:LOCALAPPDATA "PcLabKit\Probe"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return Join-Path $dir "oc-baseline.json"
}

function Get-ProbeOcWatchPath {
    $dir = Join-Path $env:LOCALAPPDATA "PcLabKit\Probe"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return Join-Path $dir "oc-watch.json"
}

function Get-ProbeOcSample {
    $s = @{
        at = (Get-Date).ToUniversalTime().ToString('o')
        cpu_temp = $null
        gpu_temp = $null
        power_limit_w = $null
    }
    if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
        try {
            $q = & nvidia-smi --query-gpu=temperature.gpu,power.limit --format=csv,noheader,nounits 2>$null
            if ($q) {
                $p = ($q -split "`n")[0] -split ",\s*"
                $s.gpu_temp = [double]$p[0]
                $s.power_limit_w = [double]$p[1]
            }
        } catch {}
    }
    try {
        $zone = Get-CimInstance -Namespace root/wmi MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($zone -and $zone.CurrentTemperature) {
            $s.cpu_temp = [math]::Round(($zone.CurrentTemperature / 10.0) - 273.15, 1)
        }
    } catch {}
    return $s
}

function Invoke-ProbeOcPreflight {
    param(
        [int]$IdleSeconds = 15,
        [int]$LoadSeconds = 15
    )
    $IdleSeconds = [Math]::Max(5, [Math]::Min(60, $IdleSeconds))
    $LoadSeconds = [Math]::Max(5, [Math]::Min(60, $LoadSeconds))

    $idle = New-Object System.Collections.Generic.List[object]
    $endIdle = (Get-Date).AddSeconds($IdleSeconds)
    while ((Get-Date) -lt $endIdle) {
        $idle.Add((Get-ProbeOcSample))
        Start-Sleep -Seconds 2
    }

    $load = New-Object System.Collections.Generic.List[object]
    $endLoad = (Get-Date).AddSeconds($LoadSeconds)
    $job = Start-Job -ScriptBlock {
        param($until)
        while ((Get-Date) -lt $until) {
            $x = 0.0
            for ($i = 0; $i -lt 60000; $i++) { $x += [Math]::Sqrt($i + 1) }
        }
    } -ArgumentList $endLoad
    while ((Get-Date) -lt $endLoad) {
        $load.Add((Get-ProbeOcSample))
        Start-Sleep -Seconds 2
    }
    $job | Stop-Job -ErrorAction SilentlyContinue | Out-Null
    $job | Remove-Job -Force -ErrorAction SilentlyContinue

    $idleCpu = ($idle | ForEach-Object { $_.cpu_temp } | Where-Object { $_ -ne $null } | Measure-Object -Average).Average
    $loadCpu = ($load | ForEach-Object { $_.cpu_temp } | Where-Object { $_ -ne $null } | Measure-Object -Maximum).Maximum
    $idleGpu = ($idle | ForEach-Object { $_.gpu_temp } | Where-Object { $_ -ne $null } | Measure-Object -Average).Average
    $loadGpu = ($load | ForEach-Object { $_.gpu_temp } | Where-Object { $_ -ne $null } | Measure-Object -Maximum).Maximum

    $ok = $true
    $blockers = @()
    if ($loadCpu -and $loadCpu -ge 92) { $ok = $false; $blockers += "CPU load sample ${loadCpu}C too high for safe auto-tune" }
    if ($loadGpu -and $loadGpu -ge 88) { $ok = $false; $blockers += "GPU load sample ${loadGpu}C too high for safe auto-tune" }

    return @{
        ok = $ok
        idle_seconds = $IdleSeconds
        load_seconds = $LoadSeconds
        idle_avg = @{ cpu_temp = $idleCpu; gpu_temp = $idleGpu }
        load_peak = @{ cpu_temp = $loadCpu; gpu_temp = $loadGpu }
        blockers = $blockers
        samples_idle = @($idle)
        samples_load = @($load)
        message = if ($ok) { 'Pre-flight OK - safe to apply reversible tuning.' } else { 'Pre-flight blocked - cool down before apply.' }
    }
}

function Invoke-ProbeOcWatch {
    param(
        [int]$Seconds = 120,
        [double]$CpuLimit = 95,
        [double]$GpuLimit = 90,
        [int]$BreachSeconds = 30,
        [switch]$AutoRollback
    )
    $Seconds = [Math]::Max(30, [Math]::Min(600, $Seconds))
    $BreachSeconds = [Math]::Max(10, [Math]::Min(120, $BreachSeconds))
    $samples = New-Object System.Collections.Generic.List[object]
    $breachStart = $null
    $rolled = $false
    $reason = $null
    $end = (Get-Date).AddSeconds($Seconds)

    while ((Get-Date) -lt $end) {
        $s = Get-ProbeOcSample
        $samples.Add($s)
        $hot = $false
        if ($s.cpu_temp -and $s.cpu_temp -ge $CpuLimit) { $hot = $true }
        if ($s.gpu_temp -and $s.gpu_temp -ge $GpuLimit) { $hot = $true }
        if ($hot) {
            if (-not $breachStart) { $breachStart = Get-Date }
            $elapsed = ((Get-Date) - $breachStart).TotalSeconds
            if ($elapsed -ge $BreachSeconds) {
                $reason = "Limits exceeded for ${BreachSeconds}s"
                if ($AutoRollback) {
                    $rb = Invoke-ProbeOverclockRollback
                    $rolled = [bool]$rb.ok
                }
                break
            }
        } else {
            $breachStart = $null
        }
        Start-Sleep -Seconds 2
    }

    $result = @{
        ok = -not $rolled
        watched_s = $Seconds
        auto_rollback = [bool]$AutoRollback
        rolled_back = $rolled
        reason = $reason
        samples = @($samples)
        cpu_temp_max = ($samples | ForEach-Object { $_.cpu_temp } | Where-Object { $_ -ne $null } | Measure-Object -Maximum).Maximum
        gpu_temp_max = ($samples | ForEach-Object { $_.gpu_temp } | Where-Object { $_ -ne $null } | Measure-Object -Maximum).Maximum
    }
    $result | ConvertTo-Json -Depth 6 | Set-Content -Path (Get-ProbeOcWatchPath) -Encoding UTF8
    return $result
}

function Get-ProbeOcState {
    $state = @{
        nvidia_available = $false
        power_limit_w = $null
        power_default_w = $null
        core_clock_mhz = $null
        mem_clock_mhz = $null
        active_power_scheme = $null
    }

    if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
        try {
            $q = & nvidia-smi --query-gpu=power.limit,power.default_limit,clocks.gr,clocks.mem --format=csv,noheader,nounits 2>$null
            if ($q) {
                $p = $q -split ",\s*"
                $state.nvidia_available = $true
                $state.power_limit_w = [double]$p[0]
                $state.power_default_w = [double]$p[1]
                $state.core_clock_mhz = [double]$p[2]
                $state.mem_clock_mhz = [double]$p[3]
            }
        } catch {}
    }

    try {
        $active = powercfg /getactivescheme 2>$null
        if ($active -match '([0-9a-f-]{36})') {
            $state.active_power_scheme = $Matches[1]
        }
    } catch {}

    return $state
}

function Save-ProbeOcBaseline {
    param($Extra = @{})
    $state = Get-ProbeOcState
    $payload = @{
        saved_at = (Get-Date).ToUniversalTime().ToString("o")
        state = $state
    }
    foreach ($k in $Extra.Keys) { $payload[$k] = $Extra[$k] }
    $payload | ConvertTo-Json -Depth 6 | Set-Content -Path (Get-ProbeOcStorePath) -Encoding UTF8
    return $payload
}

function Invoke-ProbeOverclockRollback {
    $path = Get-ProbeOcStorePath
    if (-not (Test-Path $path)) {
        return @{ ok = $false; error = 'no_baseline'; message = 'No OC baseline saved' }
    }

    $base = Get-Content $path -Raw | ConvertFrom-Json
    $results = @()

    if ($base.state.nvidia_available -and (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
        try {
            if ($base.state.power_limit_w) {
                & nvidia-smi -pl ([int]$base.state.power_limit_w) 2>$null | Out-Null
                $results += "power_limit=$($base.state.power_limit_w)"
            }
            & nvidia-smi -rac 2>$null | Out-Null
            $results += 'clocks_reset'
        } catch {
            $results += "nvidia_error=$($_.Exception.Message)"
        }
    }

    if ($base.state.active_power_scheme) {
        try {
            powercfg /setactive $base.state.active_power_scheme 2>$null | Out-Null
            $results += "power_scheme=$($base.state.active_power_scheme)"
        } catch {}
    }

    return @{
        ok = $true
        rolled_back = $results
        baseline_saved_at = $base.saved_at
    }
}

function Set-PowerCfgProcessorTuning {
    param(
        [int]$BoostMode = 1,
        [int]$ThrottleMax = 100,
        [int]$ThrottleMin = 100
    )
    $scheme = 'SCHEME_CURRENT'
    $sub = 'SUB_PROCESSOR'
    $guidBoost = 'be337238-0d82-4146-a960-4f3749a470d6'
    $guidMax = 'bc5038f7-23e0-4960-96da-33abaf5935ed'
    $guidMin = '893dee8e-2bef-41e0-89c6-b55d0927964a'

    powercfg -setacvalueindex $scheme $sub $guidMax $ThrottleMax 2>$null | Out-Null
    powercfg -setacvalueindex $scheme $sub $guidMin $ThrottleMin 2>$null | Out-Null
    powercfg -setacvalueindex $scheme $sub $guidBoost $BoostMode 2>$null | Out-Null
    powercfg -setactive $scheme 2>$null | Out-Null
}

function Set-PowerCfgHighPerformance {
    $hp = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    powercfg /setactive $hp 2>$null | Out-Null
    return $hp
}

function Invoke-ProbeOverclockApply {
    param(
        [Parameter(Mandatory = $true)]
        $Plan
    )

    if (-not $Plan) {
        return @{ ok = $false; error = 'empty_plan' }
    }

    if ($Plan.eligible -ne $true) {
        return @{ ok = $false; error = 'not_eligible'; blockers = $Plan.blockers }
    }

    $targets = @($Plan.auto_targets)
    if ($targets.Count -eq 0) {
        $targets = @($Plan.targets | Where-Object { $_.apply_auto -eq $true })
    }
    if ($targets.Count -eq 0) {
        return @{ ok = $false; error = 'no_auto_targets' }
    }

    Save-ProbeOcBaseline @{ plan_profile = $Plan.profile; plan_version = $Plan.version }
    $applied = @()
    $skipped = @()

    foreach ($t in $targets) {
        $action = $t.action
        try {
            switch ($action) {
                'nvidia_smi_power_limit' {
                    if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
                        $skipped += @{ action = $action; reason = 'nvidia-smi missing' }
                        continue
                    }
                    $w = [int]$t.target
                    if ($w -lt 80 -or $w -gt 600) {
                        $skipped += @{ action = $action; reason = 'power out of safe range' }
                        continue
                    }
                    & nvidia-smi -pl $w 2>$null | Out-Null
                    $applied += @{ action = $action; target = $w }
                }
                'nvidia_smi_clock_offset' {
                    if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
                        $skipped += @{ action = $action; reason = 'nvidia-smi missing' }
                        continue
                    }
                    $gOff = 0
                    if ($t.graphics_offset_mhz) { $gOff = [int]$t.graphics_offset_mhz }
                    if ($gOff -lt 0 -or $gOff -gt 150) {
                        $skipped += @{ action = $action; reason = 'offset out of range' }
                        continue
                    }
                    $state = Get-ProbeOcState
                    $baseCore = 0
                    if ($state.core_clock_mhz) { $baseCore = [int]$state.core_clock_mhz }
                    if ($baseCore -gt 0) {
                        $targetCore = $baseCore + $gOff
                        & nvidia-smi -lgc $targetCore,$targetCore 2>$null | Out-Null
                        $applied += @{ action = $action; graphics_mhz = $targetCore; offset = $gOff }
                    } else {
                        $skipped += @{ action = $action; reason = 'no base clock' }
                    }
                }
                'powercfg_processor' {
                    $boost = 1
                    $tmax = 100
                    $tmin = 100
                    if ($t.perf_boost_mode) { $boost = [int]$t.perf_boost_mode }
                    if ($t.proc_throttle_max) { $tmax = [int]$t.proc_throttle_max }
                    if ($t.proc_throttle_min) { $tmin = [int]$t.proc_throttle_min }
                    Set-PowerCfgProcessorTuning -BoostMode $boost -ThrottleMax $tmax -ThrottleMin $tmin
                    $applied += @{ action = $action; boost = $t.perf_boost_mode }
                }
                'powercfg_high_performance' {
                    $guid = Set-PowerCfgHighPerformance
                    $applied += @{ action = $action; scheme = $guid }
                }
                default {
                    $skipped += @{ action = $action; reason = 'not_auto_or_unknown' }
                }
            }
        } catch {
            $skipped += @{ action = $action; reason = $_.Exception.Message }
        }
    }

    return @{
        ok = ($applied.Count -gt 0)
        applied = $applied
        skipped = $skipped
        profile = $Plan.profile
        engine = 'orchestrator'
        message = if ($applied.Count -gt 0) { 'Safe OC applied - watch + auto-rollback available.' } else { 'Nothing applied.' }
        message_fa = if ($applied.Count -gt 0) { 'PC Lab Kit overclock اعمال شد - Rollback از Agent در دسترس است.' } else { 'هیچ تنظیمی اعمال نشد.' }
    }
}
