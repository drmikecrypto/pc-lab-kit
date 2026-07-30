. "$PSScriptRoot\common.ps1"

function Get-ProbeNetworkTelemetry {
    $adapters = @()
    try {
        foreach ($a in (Get-NetAdapter -Physical -ErrorAction SilentlyContinue)) {
            $stats = $null
            try { $stats = Get-NetAdapterStatistics -Name $a.Name -ErrorAction SilentlyContinue } catch {}
            $linkMbps = if ($a.LinkSpeed) { [math]::Round($a.LinkSpeed / 1000000, 0) } else { 0 }
            $adapters += @{
                name            = $a.Name
                interface       = $a.InterfaceDescription
                mac             = $a.MacAddress
                link_speed_mbps = $linkMbps
                status          = $a.Status
                recv_bytes      = if ($stats) { $stats.ReceivedBytes } else { $null }
                sent_bytes      = if ($stats) { $stats.SentBytes } else { $null }
                recv_packets    = if ($stats) { $stats.ReceivedUnicastPackets } else { $null }
                sent_packets    = if ($stats) { $stats.SentUnicastPackets } else { $null }
                recv_errors     = if ($stats) { $stats.InboundDiscardedPackets + $stats.InboundPacketErrors } else { $null }
                outbound_errors = if ($stats) { $stats.OutboundDiscardedPackets + $stats.OutboundPacketErrors } else { $null }
            }
        }
    } catch {}

    $tcpCount = 0
    $udpCount = 0
    try {
        $tcpCount = @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue).Count
        $udpCount = @(Get-NetUDPEndpoint -ErrorAction SilentlyContinue).Count
    } catch {}

    $netCounters = Get-CounterSafe @(
        '\Network Interface(*)\Bytes Total/sec',
        '\Network Interface(*)\Packets Received/sec',
        '\Network Interface(*)\Packets Sent/sec',
        '\Network Interface(*)\Packets Outbound Discarded',
        '\Network Interface(*)\Packets Received Discarded'
    )

    return @{
        adapters = $adapters
        sessions = @{
            tcp_established = $tcpCount
            udp_endpoints   = $udpCount
        }
        counters = $netCounters
    }
}

function Get-ProbeOsKernelTelemetry {
    $procs = @(Get-Process -ErrorAction SilentlyContinue)
    $procCount = $procs.Count
    # Threads is a collection, not a number, so it has to be counted per process.
    $threadCount = 0
    foreach ($p in $procs) {
        try { $threadCount += $p.Threads.Count } catch {}
    }

    $sysCounters = Get-CounterSafe @(
        '\System\Processes',
        '\System\Threads',
        '\System\System Up Time',
        '\System\File Read Bytes/sec',
        '\System\File Write Bytes/sec',
        '\System\File Control Bytes/sec'
    )

    $whea = @()
    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName = 'System'
            ProviderName = 'Microsoft-Windows-WHEA-Logger'
        } -MaxEvents 10 -ErrorAction SilentlyContinue
        foreach ($e in $events) {
            $whea += @{
                time   = $e.TimeCreated.ToString('o')
                id     = $e.Id
                level  = $e.LevelDisplayName
                message = ($e.Message -replace '\s+', ' ').Substring(0, [math]::Min(200, $e.Message.Length))
            }
        }
    } catch {}

    return @{
        processes = @{
            count        = $procCount
            thread_count = $threadCount
            system_processes = $sysCounters['\\system\processes']
            system_threads   = $sysCounters['\\system\threads']
        }
        uptime_sec = $sysCounters['\\system\system up time']
        io = @{
            file_read_bytes_sec  = $sysCounters['\\system\file read bytes/sec']
            file_write_bytes_sec = $sysCounters['\\system\file write bytes/sec']
        }
        whea_errors = $whea
    }
}

function Get-ProbeGeekTelemetry {
    . "$PSScriptRoot\cstates.ps1"
    $cs = Get-ProbeCstateTelemetry

    $counters = Get-CounterSafe @(
        '\Processor(_Total)\% Idle Time',
        '\Memory\Transition Faults/sec',
        '\Memory\Demand Zero Faults/sec'
    )

    return @{
        idle_states = $cs.cstates
        cstates = $cs.cstates
        residency_summary = $cs.residency_summary
        pstates = $cs.pstates
        acpi_sleep = $cs.acpi_sleep
        residency_series = $cs.residency_series
        deep_idle_pct = $cs.deep_idle_pct
        cstate_source = $cs.source
        transition_faults_sec = $counters['\\memory\transition faults/sec']
        demand_zero_faults_sec = $counters['\\memory\demand zero faults/sec']
        cpu_idle_pct = $counters['\\processor(_total)\% idle time']
    }
}

function Get-ProbeDeepTelemetry {
    . "$PSScriptRoot\cpu.ps1"
    . "$PSScriptRoot\gpu.ps1"
    . "$PSScriptRoot\memory.ps1"
    . "$PSScriptRoot\hwmon.ps1"
    . "$PSScriptRoot\amd.ps1"
    . "$PSScriptRoot\thermal.ps1"
    . "$PSScriptRoot\presentmon.ps1"
    . "$PSScriptRoot\frametime.ps1"

    # Sensors are collected first so the CPU and GPU resolvers can classify them
    # per vendor rather than the caller pattern-matching names afterwards. The old
    # merge matched 'Hot Spot|GPU Core' with one regex, so whichever sensor came
    # last won and the hot spot reading was lost.
    $hwmon = Get-ProbeHwMonTelemetry
    $flat = if ($hwmon.available) { $hwmon.sensors_flat } else { $null }

    $amd = Get-ProbeAmdGpuTelemetry
    $present = Get-ProbePresentMonTelemetry
    $cpu = Get-ProbeCpuTelemetry -HwmonFlat $flat
    $gpu = Get-ProbeGpuTelemetry -HwmonFlat $flat -AmdTelemetry $amd

    if ($flat) {
        # GPU board power: LHM reports the whole-card figure, which is more useful
        # than nvidia-smi's chip-only number when sizing a PSU.
        $gpuPower = Select-ProbeSensors -Flat $flat -Type 'Power' -HardwareTypePattern '^Gpu'
        $board = Get-ProbeSensorValue -Sensors $gpuPower -NamePatterns @('^GPU Package$', '^GPU Board Power$', '^GPU Power$', 'GPU') -Max
        if ($null -ne $board) { $gpu.power.board_w = $board }
        if (-not $gpu.power.draw_w -and $null -ne $board) { $gpu.power.draw_w = $board }
    }

    $gaming = @{}
    $spikeMap = Get-FrametimeTelemetry
    if ($spikeMap.available) {
        $gaming = @{
            fps_avg = if ($present.fps_avg) { $present.fps_avg } else { $null }
            frametime_p99_ms = $spikeMap.stats.p99_ms
            frametime_mean_ms = $spikeMap.stats.mean_ms
            spike_count = $spikeMap.stats.spike_count
            source = $spikeMap.source
            samples = $spikeMap.stats.count
            spike_map = $spikeMap
        }
    } elseif ($present.available -and $present.sample_count -gt 0) {
        . "$PSScriptRoot\frametime.ps1"
        $localMap = Build-FrametimeSpikeMap -Samples @($present.frametime_series)
        $gaming = @{
            fps_avg = $present.fps_avg
            frametime_p99_ms = $present.frametime_p99_ms
            frametime_mean_ms = $localMap.stats.mean_ms
            spike_count = $localMap.stats.spike_count
            source = 'presentmon'
            samples = $present.sample_count
            spike_map = $localMap
        }
    }

    return @{
        cpu          = $cpu
        gpu          = $gpu
        ram          = Get-ProbeRamTelemetry
        storage      = Get-ProbeStorageTelemetry
        motherboard  = Get-ProbeMotherboardTelemetry
        network      = Get-ProbeNetworkTelemetry
        os_kernel    = Get-ProbeOsKernelTelemetry
        geek         = Get-ProbeGeekTelemetry
        hwmon        = $hwmon
        amd_gpu      = $amd
        presentmon   = $present
        gaming       = $gaming
        thermal      = Get-ProbeThermalSummary -Cpu $cpu -Gpu $gpu -Hwmon $hwmon -Flat $flat
        power        = @{
            vcore = $cpu.power.vcore
            cpu_package_w = $cpu.power.package_w
            gpu_board_w = $gpu.power.board_w
            hwmon = if ($hwmon.available) { $hwmon.by_type.Voltage } else { $null }
            psu   = if ($hwmon.available) { $hwmon.by_type.Power } else { $null }
        }
        elevated     = [bool]$hwmon.elevated
        collected_at = (Get-Date).ToUniversalTime().ToString("o")
    }
}

<#
 One place that answers "how hot is this machine and what should I do about it",
 so the web lab, the Qt app and the Flutter client all read the same numbers.
#>
function Get-ProbeThermalSummary {
    param($Cpu, $Gpu, $Hwmon, $Flat)

    $findings = @()
    foreach ($f in @($Cpu.thermal.findings)) { if ($f) { $findings += $f } }

    $gpuBlocks = @()
    foreach ($g in @($Gpu.gpus)) {
        if (-not $g) { continue }
        $t = $g.thermal
        $gpuBlocks += @{
            name            = $g.name
            vendor          = $g.vendor
            is_integrated   = $g.is_integrated
            core_c          = $t.core_c
            hot_spot_c      = $t.hot_spot_c
            hotspot_delta_c = $t.hotspot_delta_c
            hotspot_source  = $t.hotspot_source
            memory_c        = $t.memory_c
            vr_c            = $t.vr_c
            fan_pct         = $t.fan_pct
            headroom_c      = $t.headroom_c
            health          = $t.health
            throttling      = @($g.throttling)
        }
        foreach ($f in @($t.findings)) { if ($f) { $findings += $f } }
    }

    $fans = @()
    if ($Flat) {
        foreach ($s in (Select-ProbeSensors -Flat $Flat -Type 'Fan')) {
            $fans += @{ hardware = "$($s.hardware)"; name = "$($s.name)"; rpm = [math]::Round([double]$s.value, 0) }
        }
        $stalled = @($fans | Where-Object { $_.rpm -le 0 })
        if ($stalled.Count -gt 0 -and $fans.Count -gt $stalled.Count) {
            $findings += @{
                severity = 'info'
                code     = 'fan_header_idle'
                title    = "$($stalled.Count) fan header(s) reading 0 RPM"
                detail   = 'Either nothing is plugged into those headers or a fan has failed. Compare against the case fans you actually installed: ' + (($stalled | ForEach-Object { $_.name }) -join ', ')
            }
        }
    }

    $order = @{ critical = 0; warn = 1; info = 2 }
    $findings = @($findings | Sort-Object { $order["$($_.severity)"] })

    $worst = 'ok'
    foreach ($f in $findings) {
        if ($f.severity -eq 'critical') { $worst = 'critical'; break }
        if ($f.severity -eq 'warn') { $worst = 'warn' }
    }
    if ($findings.Count -eq 0 -and -not $Cpu.thermal.package_c) { $worst = 'unknown' }

    return @{
        status     = $worst
        elevated   = [bool]$Hwmon.elevated
        source     = $Cpu.thermal.source
        cpu        = @{
            model      = $Cpu.architecture.model
            vendor     = $Cpu.thermal.vendor
            package_c  = $Cpu.thermal.package_c
            hotspot_c  = $Cpu.thermal.hotspot_c
            average_c  = $Cpu.thermal.average_c
            per_core_c = @($Cpu.thermal.per_core_c)
            ccd_c      = @($Cpu.thermal.ccd_c)
            tjmax_c    = $Cpu.thermal.tjmax_c
            headroom_c = $Cpu.thermal.headroom_c
            throttling = $Cpu.thermal.throttling
            source     = $Cpu.thermal.source
        }
        gpus       = @($gpuBlocks)
        fans       = @($fans)
        findings   = @($findings)
    }
}

function Get-TelemetrySnapshot {
    $t = Get-ProbeDeepTelemetry
    return @{
        ts = $t.collected_at
        cpu_temp = $t.cpu.thermal.package_c
        cpu_hotspot = $t.cpu.thermal.hotspot_c
        gpu_temp = $t.gpu.thermal.core_c
        gpu_hotspot = $t.gpu.thermal.hot_spot_c
        gpu_vram_temp = $t.gpu.thermal.memory_c
        gpu_power = $t.gpu.power.draw_w
        gpu_util = $t.gpu.render.gpu_util_pct
        vcore = $t.power.vcore
        fps = $t.gaming.fps_avg
    }
}
