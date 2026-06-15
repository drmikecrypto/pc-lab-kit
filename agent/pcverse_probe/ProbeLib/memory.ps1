. "$PSScriptRoot\common.ps1"

function Get-ProbeRamTelemetry {
    . "$PSScriptRoot\ram-spd.ps1"
    $spd = Get-RamSpdTelemetry

    $banks = @(Get-CimSafe "Win32_PhysicalMemory")
    $modules = @()
    $total = 0.0
    foreach ($m in $banks) {
        $cap = [math]::Round($m.Capacity / 1GB, 2)
        $total += $cap
        $enriched = ($spd.modules | Where-Object { $_.bank_label -eq $m.BankLabel } | Select-Object -First 1)
        if (-not $enriched -and $spd.modules.Count -gt $modules.Count) {
            $enriched = $spd.modules[$modules.Count]
        }
        $pn = ($m.PartNumber -replace '\x00','').Trim()
        $dieType = $null
        $dieConf = $null
        $timings = $null
        if ($enriched) {
            if ($enriched.part_number) { $pn = $enriched.part_number }
            $dieType = $enriched.die_type
            $dieConf = $enriched.die_confidence
            $timings = $enriched.timings
        }
        $modules += @{
            capacity_gb  = $cap
            speed_mhz    = $m.Speed
            configured_mhz = $m.ConfiguredClockSpeed
            manufacturer = ($m.Manufacturer -replace '\x00','').Trim()
            part_number  = $pn
            serial       = $m.SerialNumber
            form_factor  = $m.FormFactor
            bank_label   = $m.BankLabel
            data_width   = $m.DataWidth
            total_width  = $m.TotalWidth
            smbios_type  = $m.SMBIOSMemoryType
            die_type     = $dieType
            die_confidence = $dieConf
            timings      = $timings
        }
    }

    $memCounters = Get-CounterSafe @(
        '\Memory\Available MBytes',
        '\Memory\Committed Bytes',
        '\Memory\Commit Limit',
        '\Memory\Pages/sec',
        '\Memory\Page Faults/sec',
        '\Memory\Standby Cache Normal Priority Bytes',
        '\Memory\Cache Bytes',
        '\Memory\Pool Nonpaged Bytes',
        '\Memory\Pool Paged Bytes'
    )

    $cs = Get-CimSafe "Win32_ComputerSystem" | Select-Object -First 1

    return @{
        modules = $modules
        total_gb = if ($total -gt 0) { [math]::Round($total, 1) } else { $null }
        slots_used = $modules.Count
        status = @{
            available_mb     = $memCounters['\\memory\available mbytes']
            committed_bytes  = $memCounters['\\memory\committed bytes']
            commit_limit     = $memCounters['\\memory\commit limit']
            pages_per_sec    = $memCounters['\\memory\pages/sec']
            page_faults_sec  = $memCounters['\\memory\page faults/sec']
            standby_bytes    = $memCounters['\\memory\standby cache normal priority bytes']
            compression_note = "Memory compression via Get-Counter - Process counters for detail"
        }
        primary_timings = $spd.primary_timings
        primary_die = $spd.primary_die
        spd_source = $spd.source
        cpuz_auto_import = $spd.cpuz_auto_import
    }
}

function Get-ProbeStorageTelemetry {
    $disks = @()
    foreach ($d in (Get-CimSafe "Win32_DiskDrive")) {
        $disks += @{
            model       = ($d.Model -replace '\x00','').Trim()
            interface   = $d.InterfaceType
            size_gb     = [math]::Round($d.Size / 1GB, 1)
            media_type  = $d.MediaType
            serial      = $d.SerialNumber
            partitions  = $d.Partitions
            status      = $d.Status
        }
    }

    $smart = @()
    try {
        Import-Module Storage -ErrorAction SilentlyContinue
        foreach ($pd in Get-PhysicalDisk -ErrorAction SilentlyContinue) {
            $rel = $null
            try { $rel = Get-StorageReliabilityCounter -PhysicalDisk $pd -ErrorAction SilentlyContinue } catch {}
            $smart += @{
                friendly_name    = $pd.FriendlyName
                media_type       = $pd.MediaType
                health_status    = $pd.HealthStatus
                operational_status = $pd.OperationalStatus
                size_gb          = [math]::Round($pd.Size / 1GB, 1)
                temperature_c    = if ($rel) { $rel.Temperature } else { $null }
                wear_pct         = if ($rel) { $rel.Wear } else { $null }
                read_errors      = if ($rel) { $rel.ReadErrorsTotal } else { $null }
                write_errors     = if ($rel) { $rel.WriteErrorsTotal } else { $null }
                power_on_hours   = if ($rel) { $rel.PowerOnHours } else { $null }
                flush_latency_ms = if ($rel) { $rel.FlushLatencyMax } else { $null }
            }
        }
    } catch {}

    $diskCounters = Get-CounterSafe @(
        '\PhysicalDisk(_Total)\Disk Read Bytes/sec',
        '\PhysicalDisk(_Total)\Disk Write Bytes/sec',
        '\PhysicalDisk(_Total)\Avg. Disk sec/Read',
        '\PhysicalDisk(_Total)\Avg. Disk sec/Write',
        '\PhysicalDisk(_Total)\Current Disk Queue Length'
    )

    return @{
        drives = $disks
        smart  = $smart
        performance = @{
            read_bytes_sec  = $diskCounters['\\physicaldisk(_total)\disk read bytes/sec']
            write_bytes_sec = $diskCounters['\\physicaldisk(_total)\disk write bytes/sec']
            avg_read_sec    = $diskCounters['\\physicaldisk(_total)\avg. disk sec/read']
            avg_write_sec   = $diskCounters['\\physicaldisk(_total)\avg. disk sec/write']
            queue_length    = $diskCounters['\\physicaldisk(_total)\current disk queue length']
        }
    }
}

function Get-ProbeMotherboardTelemetry {
    $board = Get-CimSafe "Win32_BaseBoard" | Select-Object -First 1
    $bios = Get-CimSafe "Win32_BIOS" | Select-Object -First 1
    $sys = Get-CimSafe "Win32_ComputerSystem" | Select-Object -First 1

    $pcie = @()
    try {
        foreach ($d in Get-CimSafe "Win32_PnPEntity" | Where-Object { $_.Name -match 'PCI|Root Port' }) {
            if ($d.Name -match 'Root Port|Express') {
                $pcie += @{ name = $d.Name; device_id = $d.DeviceID; status = $d.Status }
            }
        }
        $pcie = $pcie | Select-Object -First 20
    } catch {}

    return @{
        manufacturer = $board.Manufacturer
        product      = $board.Product
        version      = $board.Version
        serial       = $board.SerialNumber
        bios = @{
            vendor  = $bios.Manufacturer
            version = $bios.SMBIOSBIOSVersion
            date    = $bios.ReleaseDate
        }
        system = @{
            manufacturer = $sys.Manufacturer
            model        = $sys.Model
            sku          = $sys.SystemSKUNumber
        }
        pcie_topology_sample = @($pcie)
    }
}
