. "$PSScriptRoot\common.ps1"

function Get-PcverseOcStorePath {
    $dir = Join-Path $env:LOCALAPPDATA "PCVerseProbe"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return Join-Path $dir "oc-baseline.json"
}

function Get-PcverseOcState {
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

function Save-PcverseOcBaseline {
    param($Extra = @{})
    $state = Get-PcverseOcState
    $payload = @{
        saved_at = (Get-Date).ToUniversalTime().ToString("o")
        state = $state
    }
    foreach ($k in $Extra.Keys) { $payload[$k] = $Extra[$k] }
    $payload | ConvertTo-Json -Depth 6 | Set-Content -Path (Get-PcverseOcStorePath) -Encoding UTF8
    return $payload
}

function Invoke-PcverseOverclockRollback {
    $path = Get-PcverseOcStorePath
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

function Invoke-PcverseOverclockApply {
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

    Save-PcverseOcBaseline @{ plan_profile = $Plan.profile; plan_version = $Plan.version }
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
                    $state = Get-PcverseOcState
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
        engine = 'vakhsh'
        message_fa = if ($applied.Count -gt 0) { 'اوورکلاک وخش اعمال شد — Rollback از Agent در دسترس است.' } else { 'هیچ تنظیمی اعمال نشد.' }
    }
}
