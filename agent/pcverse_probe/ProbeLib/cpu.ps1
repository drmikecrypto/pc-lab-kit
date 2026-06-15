. "$PSScriptRoot\common.ps1"

function Get-ProbeCpuTelemetry {
    $cpu0 = Get-CimSafe "Win32_Processor" | Select-Object -First 1
    if (-not $cpu0) { return @{} }

    $regPath = "HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0"
    $reg = $null
    try { $reg = Get-ItemProperty $regPath -ErrorAction SilentlyContinue } catch {}

    $featureSet = 0
    if ($reg -and $reg.FeatureSet) { $featureSet = [uint32]$reg.FeatureSet }

    $model = $cpu0.Name.Trim()
    $isa = Guess-InstructionSets -Model $model -CpuWmi $cpu0
    if ($featureSet -gt 0) {
        $isa = ($isa + (Parse-FeatureSet $featureSet)) | Select-Object -Unique
    }

    # Per-core clocks & utilization via perf counters
    $perCore = @()
    try {
        $freqSamples = Get-Counter -Counter "\Processor Information(*)\Processor Frequency" -MaxSamples 1 -ErrorAction SilentlyContinue
        $utilSamples = Get-Counter -Counter "\Processor Information(*)\% Processor Utility" -MaxSamples 1 -ErrorAction SilentlyContinue
        $idleSamples = Get-Counter -Counter "\Processor Information(*)\% Idle Time" -MaxSamples 1 -ErrorAction SilentlyContinue

        $freqMap = @{}
        foreach ($s in $freqSamples.CounterSamples) {
            if ($s.InstanceName -match '_Total|Idle') { continue }
            $freqMap[$s.InstanceName] = [math]::Round($s.CookedValue, 0)
        }
        foreach ($s in $utilSamples.CounterSamples) {
            if ($s.InstanceName -match '_Total|Idle') { continue }
            $idle = 0
            $idleS = $idleSamples.CounterSamples | Where-Object { $_.InstanceName -eq $s.InstanceName } | Select-Object -First 1
            if ($idleS) { $idle = [math]::Round($idleS.CookedValue, 1) }
            $perCore += @{
                core_id     = $s.InstanceName
                mhz         = $freqMap[$s.InstanceName]
                util_pct    = [math]::Round($s.CookedValue, 1)
                idle_pct    = $idle
            }
        }
    } catch {}

    $sysCounters = Get-CounterSafe @(
        '\Processor(_Total)\% Processor Time',
        '\Processor(_Total)\% Interrupt Time',
        '\Processor(_Total)\% DPC Time',
        '\Processor(_Total)\% Privileged Time',
        '\Processor(_Total)\% User Time',
        '\System\Context Switches/sec',
        '\System\Processor Queue Length',
        '\Processor Information(_Total)\Processor Frequency',
        '\Processor Information(_Total)\% Processor Utility'
    )

    $thermal = @{ package_c = $null; per_core_c = @(); throttle = $false }
    try {
        $zones = Get-CimSafe "MSAcpi_ThermalZoneTemperature" -Namespace "root/wmi"
        foreach ($z in $zones) {
            $c = KelvinToC $z.CurrentTemperature
            if ($null -ne $c) { $thermal.per_core_c += $c }
        }
        if ($thermal.per_core_c.Count -gt 0) {
            $thermal.package_c = ($thermal.per_core_c | Measure-Object -Maximum).Maximum
        }
    } catch {}

    # Power telemetry (Intel/AMD partial via perf)
    $power = @{}
    try {
        $pwr = Get-Counter -Counter "\Processor Information(_Total)\Processor Energy" -MaxSamples 1 -ErrorAction SilentlyContinue
        if ($pwr) {
            $power.package_energy_j = [math]::Round($pwr.CounterSamples[0].CookedValue, 2)
        }
    } catch {}

    return @{
        architecture = @{
            model            = $model
            vendor           = $cpu0.Manufacturer
            cores            = [int]$cpu0.NumberOfCores
            threads          = [int]$cpu0.NumberOfLogicalProcessors
            socket           = $cpu0.SocketDesignation
            stepping         = $cpu0.Stepping
            revision         = $cpu0.Revision
            family           = $cpu0.Family
            processor_id     = $cpu0.ProcessorId
            architecture_code = $cpu0.Architecture
            l2_cache_kb      = $cpu0.L2CacheSize
            l3_cache_kb      = $cpu0.L3CacheSize
            virtualization   = [bool]$cpu0.VirtualizationFirmwareEnabled
            instruction_sets = @($isa)
            smt_enabled      = ($cpu0.NumberOfLogicalProcessors -gt $cpu0.NumberOfCores)
        }
        clocks = @{
            base_mhz       = [int]$cpu0.MaxClockSpeed
            current_mhz    = [int]$cpu0.CurrentClockSpeed
            effective_mhz  = $sysCounters['\\processor information(_total)\processor frequency']
            per_core       = $perCore
            queue_length   = $sysCounters['\\system\processor queue length']
        }
        power = $power
        thermal = $thermal
        cache = @{
            l1_note = "L1 per-core via CPUID - use import for latency benches"
            l2_kb   = $cpu0.L2CacheSize
            l3_kb   = $cpu0.L3CacheSize
        }
        scheduler = @{
            context_switches_per_sec = $sysCounters['\\system\context switches/sec']
            interrupt_pct            = $sysCounters['\\processor(_total)\% interrupt time']
            dpc_pct                  = $sysCounters['\\processor(_total)\% dpc time']
            privileged_pct           = $sysCounters['\\processor(_total)\% privileged time']
            user_pct                 = $sysCounters['\\processor(_total)\% user time']
        }
    }
}
