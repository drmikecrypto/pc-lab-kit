. "$PSScriptRoot\common.ps1"

function Get-ProbeNvmeSmart {
    $drives = @()
    try {
        foreach ($d in @(Get-PhysicalDisk -ErrorAction SilentlyContinue)) {
            $health = $null
            try { $health = Get-StorageReliabilityCounter -PhysicalDisk $d -ErrorAction SilentlyContinue } catch {}
            $drives += @{
                friendly_name   = "$($d.FriendlyName)"
                serial          = "$($d.SerialNumber)".Trim()
                media_type      = "$($d.MediaType)"
                bus_type        = "$($d.BusType)"
                size_gb         = if ($d.Size) { [math]::Round($d.Size / 1GB, 1) } else { $null }
                health_status   = "$($d.HealthStatus)"
                temperature_c   = if ($health -and $health.Temperature) { [int]$health.Temperature } else { $null }
                wear            = if ($health -and $null -ne $health.Wear) { [int]$health.Wear } else { $null }
                read_errors     = if ($health) { $health.ReadErrorsUncorrected } else { $null }
                write_errors    = if ($health) { $health.WriteErrorsUncorrected } else { $null }
                power_on_hours  = if ($health) { $health.PowerOnHours } else { $null }
                source          = 'storage_reliability'
            }
        }
    } catch {}
    return $drives
}

<#
 Silicon Dossier — identity + raw dumps for assembly / RMA proof.
#>
function Get-ProbeSiliconDossier {
    param($Telemetry, $Devices)

    . "$PSScriptRoot\ram-spd.ps1" -ErrorAction SilentlyContinue

    $cpu = $Telemetry.cpu
    $gpu = $Telemetry.gpu
    $hwmon = $Telemetry.hwmon
    $arch = if ($cpu) { $cpu.architecture } else { @{} }
    $g0 = @($gpu.gpus) | Select-Object -First 1

    $microcode = $null
    try {
        $cpu0 = Get-ItemProperty -Path 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -ErrorAction SilentlyContinue
        if ($cpu0 -and $cpu0.'Update Revision') { $microcode = "$($cpu0.'Update Revision')".Trim() }
        elseif ($cpu0 -and $cpu0.'UpdateRevision') { $microcode = "$($cpu0.UpdateRevision)".Trim() }
    } catch {}

    $ram = $null
    try { $ram = Get-RamSpdTelemetry } catch {}
    if (-not $ram) { $ram = @{ modules = @(); source = 'unavailable'; note = 'SMBIOS SPD not present' } }
    if ($ram -and -not $ram.note) {
        $ram.note = 'SMBIOS/WMI module identity; raw SMBus EEPROM dump is optional when Ring0 I2C is available'
    }

    $monitors = @()
    if ($Devices -and $Devices.monitors) { $monitors = @($Devices.monitors) }

    $fw = $null
    if ($Devices -and $Devices.firmware) { $fw = $Devices.firmware }
    elseif ($Telemetry.os_kernel) { $fw = $Telemetry.motherboard }

    $pci = @()
    if ($hwmon -and $hwmon.pci_config) { $pci = @($hwmon.pci_config) }

    $storage = Get-ProbeNvmeSmart
    foreach ($d in @($storage)) {
        if (-not $d.firmware) {
            try {
                $pd = Get-PhysicalDisk -SerialNumber $d.serial -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($pd -and $pd.FirmwareVersion) { $d.firmware = "$($pd.FirmwareVersion)".Trim() }
            } catch {}
        }
    }

    $acpiTables = @()
    try {
        Get-ChildItem 'HKLM:\HARDWARE\ACPI' -ErrorAction SilentlyContinue | ForEach-Object {
            $acpiTables += $_.PSChildName
        }
    } catch {}

    $vbiosRaw = if ($g0 -and $g0.vbios) { [string]$g0.vbios } else { '' }
    $vbiosHash = $null
    if ($vbiosRaw) {
        try {
            $sha = [System.Security.Cryptography.SHA256]::Create()
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($vbiosRaw)
            $vbiosHash = -join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })
            $sha.Dispose()
        } catch {}
    }

    $biosVendor = if ($fw.bios -and $fw.bios.vendor) { $fw.bios.vendor } elseif ($fw.bios_vendor) { $fw.bios_vendor } else { $null }
    $biosVersion = if ($fw.bios -and $fw.bios.version) { $fw.bios.version } elseif ($fw.bios_version) { $fw.bios_version } else { $null }
    $biosDate = if ($fw.bios -and $fw.bios.date) { $fw.bios.date } elseif ($fw.bios_date) { $fw.bios_date } else { $null }

    return @{
        collected_at = (Get-Date).ToUniversalTime().ToString('o')
        cpu = @{
            model          = $arch.model
            vendor         = $arch.vendor_tag
            codename       = $arch.codename
            family         = $arch.cpuid_family
            model_id       = $arch.cpuid_model
            stepping       = $arch.stepping
            processor_id   = $arch.processor_id
            cores          = $arch.cores
            threads        = $arch.threads
            socket         = $arch.socket
            microcode      = $microcode
            source         = 'wmi+cpuid_registry'
        }
        gpu = @{
            name               = if ($g0) { $g0.name } else { $null }
            vendor             = if ($g0) { $g0.vendor } else { $null }
            vbios              = if ($vbiosRaw) { $vbiosRaw } else { $null }
            vbios_sha256       = $vbiosHash
            pci_config         = $pci
            hotspot_source     = if ($g0 -and $g0.thermal) { $g0.thermal.hotspot_source } else { $null }
        }
        ram = $ram
        storage = $storage
        monitors = @($monitors | ForEach-Object {
            @{
                name     = $_.name
                serial   = $_.serial
                edid     = $_.edid
                edid_hex = if ($_.edid) { $_.edid.raw_hex } else { $null }
            }
        })
        board = @{
            manufacturer = if ($fw.board -and $fw.board.manufacturer) { $fw.board.manufacturer } elseif ($fw.manufacturer) { $fw.manufacturer } elseif ($Telemetry.motherboard) { $Telemetry.motherboard.manufacturer } else { $null }
            product      = if ($fw.board -and $fw.board.product) { $fw.board.product } elseif ($fw.product) { $fw.product } elseif ($Telemetry.motherboard) { $Telemetry.motherboard.product } else { $null }
            serial       = if ($fw.board -and $fw.board.serial) { $fw.board.serial } elseif ($fw.serial) { $fw.serial } elseif ($Telemetry.motherboard) { $Telemetry.motherboard.serial } else { $null }
            bios         = $biosVersion
            bios_vendor  = $biosVendor
            bios_date    = $biosDate
            smbios_major = if ($fw.bios) { $fw.bios.smbios_major } else { $null }
            smbios_minor = if ($fw.bios) { $fw.bios.smbios_minor } else { $null }
        }
        firmware_inventory = @{
            bios_vendor   = $biosVendor
            bios_version  = $biosVersion
            bios_date     = $biosDate
            tpm           = if ($fw.tpm) { $fw.tpm } else { @{ present = $false } }
            secure_boot   = if ($null -ne $fw.secure_boot) { $fw.secure_boot } else { $null }
            acpi_tables   = $acpiTables
            cpu_microcode = $microcode
            gpu_vbios     = if ($vbiosRaw) { $vbiosRaw } else { $null }
            gpu_vbios_sha256 = $vbiosHash
            storage_firmware = @($storage | ForEach-Object {
                @{ name = $_.friendly_name; serial = $_.serial; firmware = $_.firmware }
            })
            provenance    = 'wmi+registry+smbios+storage_reliability'
            note          = 'Identity and register reads only — no BIOS/VBIOS flash, no vendor MODS binaries'
        }
        open_book_count = if ($Telemetry.open_book) { [int]$Telemetry.open_book.count } else { 0 }
    }
}
