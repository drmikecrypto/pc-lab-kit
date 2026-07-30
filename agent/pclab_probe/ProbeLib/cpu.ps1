. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\thermal.ps1"

<#
 Best-effort microarchitecture name from the CPUID family/model that Windows
 records in the registry Identifier string. Used for reporting and for choosing
 sensible thermal defaults; never treated as authoritative.
#>
function Get-ProbeCpuCodename {
    param([string]$Vendor, [int]$Family, [int]$Model, [string]$ModelName = "")

    if ($Vendor -eq 'intel' -and $Family -eq 6) {
        switch ($Model) {
            { $_ -in 60, 69, 70 }        { return 'Haswell' }
            { $_ -in 61, 71, 79, 86 }    { return 'Broadwell' }
            { $_ -in 78, 94 }            { return 'Skylake' }
            { $_ -in 142, 158 }          { return 'Kaby Lake / Coffee Lake' }
            { $_ -in 165, 166 }          { return 'Comet Lake' }
            { $_ -eq 167 }               { return 'Rocket Lake' }
            { $_ -in 140, 141 }          { return 'Tiger Lake' }
            { $_ -in 151, 154 }          { return 'Alder Lake' }
            { $_ -in 183, 186, 191 }     { return 'Raptor Lake' }
            { $_ -in 170, 172 }          { return 'Meteor Lake' }
            { $_ -eq 189 }               { return 'Lunar Lake' }
            { $_ -in 197, 198, 199 }     { return 'Arrow Lake' }
            { $_ -eq 143 }               { return 'Sapphire Rapids' }
            { $_ -eq 207 }               { return 'Emerald Rapids' }
        }
    }

    if ($Vendor -eq 'amd') {
        if ($Family -eq 23) {
            if ($Model -in 1, 8, 17, 24) { return 'Zen / Zen+' }
            return 'Zen 2'
        }
        if ($Family -eq 25) {
            if ($Model -in 33, 80, 1, 8, 68, 80) { return 'Zen 3' }
            return 'Zen 4'
        }
        if ($Family -eq 26) { return 'Zen 5' }
        if ($Family -eq 22) { return 'Jaguar / Puma' }
    }

    if ($ModelName -match 'Snapdragon|Oryon') { return 'Oryon (ARM64)' }
    return $null
}

function Get-ProbeCpuCacheDetail {
    $levels = @{}
    foreach ($c in @(Get-CimSafe "Win32_CacheMemory")) {
        $lvl = [int]$c.Level - 2   # WMI encodes L1 as 3, L2 as 4, L3 as 5
        if ($lvl -lt 1 -or $lvl -gt 4) { continue }
        $key = "l$lvl"
        if (-not $levels.ContainsKey($key)) {
            $levels[$key] = @{ total_kb = 0; instances = 0; associativity = $c.Associativity; line_size = $c.LineSize }
        }
        $size = 0
        if ($c.InstalledSize -and $c.InstalledSize -gt 0) { $size = [int]$c.InstalledSize }
        elseif ($c.MaxCacheSize) { $size = [int]$c.MaxCacheSize }
        $levels[$key].total_kb += $size
        $levels[$key].instances++
    }
    return $levels
}

function Get-ProbeCpuTelemetry {
    param($HwmonFlat = $null)

    $sockets = @(Get-CimSafe "Win32_Processor")
    $cpu0 = $sockets | Select-Object -First 1
    if (-not $cpu0) { return @{} }

    $model = "$($cpu0.Name)".Trim() -replace '\s+', ' '
    $vendorRaw = "$($cpu0.Manufacturer)"
    $vendor = Get-ProbeVendorTag -Name "$model $vendorRaw"

    $regPath = "HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0"
    $reg = $null
    try { $reg = Get-ItemProperty $regPath -ErrorAction SilentlyContinue } catch {}

    $family = 0
    $modelId = 0
    $stepping = 0
    if ($reg -and $reg.Identifier -match 'Family\s+(\d+)\s+Model\s+(\d+)\s+Stepping\s+(\d+)') {
        $family = [int]$Matches[1]; $modelId = [int]$Matches[2]; $stepping = [int]$Matches[3]
    } else {
        $family = [int]$cpu0.Family
        if ($cpu0.Description -match 'Model\s+(\d+)') { $modelId = [int]$Matches[1] }
        $stepping = [int]("$($cpu0.Stepping)" -replace '\D', '')
    }

    # Real feature detection beats guessing from the marketing name, which used to
    # claim AVX-512 on any i7 and miss it on the parts that actually have it.
    $isa = @(Get-ProbeProcessorFeatures)
    if ($isa.Count -eq 0) {
        $isa = @(Guess-InstructionSets -Model $model -CpuWmi $cpu0)
        if ($reg -and $reg.FeatureSet) {
            $isa = @(($isa + (Parse-FeatureSet ([uint32]$reg.FeatureSet))) | Select-Object -Unique)
        }
    }

    $topology = Get-ProbeCoreTopology
    $physicalCores = [int]$cpu0.NumberOfCores
    $logicalCores = [int]$cpu0.NumberOfLogicalProcessors
    if ($sockets.Count -gt 1) {
        $physicalCores = 0; $logicalCores = 0
        foreach ($s in $sockets) { $physicalCores += [int]$s.NumberOfCores; $logicalCores += [int]$s.NumberOfLogicalProcessors }
    }
    if ($topology.physical_cores -gt 0) { $physicalCores = $topology.physical_cores }
    if ($topology.logical_cores -gt 0) { $logicalCores = $topology.logical_cores }

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
                core_id  = $s.InstanceName
                mhz      = $freqMap[$s.InstanceName]
                util_pct = [math]::Round($s.CookedValue, 1)
                idle_pct = $idle
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

    # ACPI zones are collected for reference only. The resolver decides whether they
    # are good enough to stand in for a package temperature.
    $acpiZones = @()
    try {
        foreach ($z in @(Get-CimSafe "MSAcpi_ThermalZoneTemperature" -Namespace "root/wmi")) {
            $c = KelvinToC $z.CurrentTemperature
            if ($null -ne $c) { $acpiZones += $c }
        }
    } catch {}

    $thermal = Resolve-ProbeCpuThermal -Flat $HwmonFlat -Model $model -AcpiZones $acpiZones
    $thermal.findings = @(Get-ProbeCpuThermalFindings -Cpu $thermal -Model $model)
    # Legacy consumers read per_core_c as a flat list of temperatures.
    if (@($thermal.per_core_c).Count -eq 0 -and $acpiZones.Count -gt 0) {
        $thermal.per_core_c = @($acpiZones)
    }

    $power = @{}
    try {
        $pwr = Get-Counter -Counter "\Processor Information(_Total)\Processor Energy" -MaxSamples 1 -ErrorAction SilentlyContinue
        if ($pwr) { $power.package_energy_j = [math]::Round($pwr.CounterSamples[0].CookedValue, 2) }
    } catch {}

    if ($HwmonFlat) {
        $cpuPower = Select-ProbeSensors -Flat $HwmonFlat -Type 'Power' -HardwareTypePattern '^Cpu$'
        $pkg = Get-ProbeSensorValue -Sensors $cpuPower -NamePatterns @('^CPU Package$', '^Package$')
        if ($null -ne $pkg) { $power.package_w = $pkg }
        $coresW = Get-ProbeSensorValue -Sensors $cpuPower -NamePatterns @('^CPU Cores$', '^Cores$')
        if ($null -ne $coresW) { $power.cores_w = $coresW }
        $cpuVolt = Select-ProbeSensors -Flat $HwmonFlat -Type 'Voltage' -HardwareTypePattern '^Cpu$|^Motherboard$|^SuperIO$'
        $vcore = Get-ProbeSensorValue -Sensors $cpuVolt -NamePatterns @('^CPU Core$', '^Vcore$', '^CPU VCore$', 'Core VID')
        if ($null -ne $vcore) { $power.vcore = $vcore }
    }

    $cache = Get-ProbeCpuCacheDetail
    $codename = Get-ProbeCpuCodename -Vendor $vendor -Family $family -Model $modelId -ModelName $model

    return @{
        architecture = @{
            model             = $model
            vendor            = $vendorRaw
            vendor_tag        = $vendor
            codename          = $codename
            sockets           = $sockets.Count
            cores             = $physicalCores
            threads           = $logicalCores
            performance_cores = $topology.performance_cores
            efficiency_cores  = $topology.efficiency_cores
            hybrid            = $topology.hybrid
            core_classes      = @($topology.classes)
            socket            = $cpu0.SocketDesignation
            stepping          = $stepping
            cpuid_family      = $family
            cpuid_model       = $modelId
            revision          = $cpu0.Revision
            family            = $cpu0.Family
            processor_id      = $cpu0.ProcessorId
            architecture_code = $cpu0.Architecture
            l2_cache_kb       = $cpu0.L2CacheSize
            l3_cache_kb       = $cpu0.L3CacheSize
            virtualization    = [bool]$cpu0.VirtualizationFirmwareEnabled
            instruction_sets  = @($isa)
            smt_enabled       = ($logicalCores -gt $physicalCores)
        }
        clocks = @{
            base_mhz      = [int]$cpu0.MaxClockSpeed
            current_mhz   = [int]$cpu0.CurrentClockSpeed
            effective_mhz = $sysCounters['\\processor information(_total)\processor frequency']
            per_core      = $perCore
            queue_length  = $sysCounters['\\system\processor queue length']
        }
        power   = $power
        thermal = $thermal
        cache   = @{
            l1_kb   = if ($cache.l1) { $cache.l1.total_kb } else { $null }
            l2_kb   = if ($cache.l2) { $cache.l2.total_kb } else { $cpu0.L2CacheSize }
            l3_kb   = if ($cache.l3) { $cache.l3.total_kb } else { $cpu0.L3CacheSize }
            detail  = $cache
        }
        scheduler = @{
            context_switches_per_sec = $sysCounters['\\system\context switches/sec']
            interrupt_pct            = $sysCounters['\\processor(_total)\% interrupt time']
            dpc_pct                  = $sysCounters['\\processor(_total)\% dpc time']
            privileged_pct           = $sysCounters['\\processor(_total)\% privileged time']
            user_pct                 = $sysCounters['\\processor(_total)\% user time']
        }
        sockets_detail = @($sockets | ForEach-Object {
            @{
                name          = "$($_.Name)".Trim()
                socket        = $_.SocketDesignation
                cores         = [int]$_.NumberOfCores
                threads       = [int]$_.NumberOfLogicalProcessors
                max_clock_mhz = [int]$_.MaxClockSpeed
                status        = $_.Status
                device_id     = $_.DeviceID
            }
        })
    }
}
