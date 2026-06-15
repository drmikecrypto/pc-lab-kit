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
    $procCount = (Get-Process -ErrorAction SilentlyContinue).Count
    $threadCount = (Get-Process -ErrorAction SilentlyContinue | Measure-Object -Property Threads -Sum).Sum

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

function Get-PcverseDeepTelemetry {
    . "$PSScriptRoot\cpu.ps1"
    . "$PSScriptRoot\gpu.ps1"
    . "$PSScriptRoot\memory.ps1"
    . "$PSScriptRoot\hwmon.ps1"
    . "$PSScriptRoot\amd.ps1"
    . "$PSScriptRoot\presentmon.ps1"
    . "$PSScriptRoot\frametime.ps1"

    $hwmon = Get-ProbeHwMonTelemetry
    $amd = Get-ProbeAmdGpuTelemetry
    $present = Get-ProbePresentMonTelemetry
    $cpu = Get-ProbeCpuTelemetry
    $gpu = Get-ProbeGpuTelemetry

    # Merge LibreHardwareMonitor into CPU/GPU power & thermal
    if ($hwmon.available -and $hwmon.sensors_flat) {
        foreach ($s in $hwmon.sensors_flat) {
            if ($s.type -eq 'Temperature' -and $s.name -match 'Package|CPU') {
                if (-not $cpu.thermal.package_c -or $s.value -gt $cpu.thermal.package_c) {
                    $cpu.thermal.package_c = [math]::Round([double]$s.value, 1)
                }
            }
            if ($s.type -eq 'Temperature' -and $s.name -match 'Hot Spot|GPU Core') {
                $gpu.thermal.core_c = [math]::Round([double]$s.value, 1)
            }
            if ($s.type -eq 'Power' -and $s.name -match 'GPU') {
                $gpu.power.draw_w = [math]::Round([double]$s.value, 1)
            }
            if ($s.type -eq 'Voltage' -and $s.name -match 'Core|Vcore') {
                $cpu.power.vcore = [math]::Round([double]$s.value, 3)
            }
        }
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
        power        = @{
            vcore = $cpu.power.vcore
            hwmon = if ($hwmon.available) { $hwmon.by_type.Voltage } else { $null }
            psu   = if ($hwmon.available) { $hwmon.by_type.Power } else { $null }
        }
        collected_at = (Get-Date).ToUniversalTime().ToString("o")
    }
}

function Get-TelemetrySnapshot {
    $t = Get-PcverseDeepTelemetry
    return @{
        ts = $t.collected_at
        cpu_temp = $t.cpu.thermal.package_c
        gpu_temp = $t.gpu.thermal.core_c
        gpu_power = $t.gpu.power.draw_w
        gpu_util = $t.gpu.render.gpu_util_pct
        vcore = $t.power.vcore
        fps = $t.gaming.fps_avg
    }
}
