. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\platform.ps1"

function Get-ProbeNvmeSmart {
    return Get-ProbeNvmeSmartDetailed
}

<#
 Silicon Dossier - identity + raw dumps for assembly / RMA proof.
#>
function Get-ProbeSiliconDossier {
    param($Telemetry, $Devices)

    . "$PSScriptRoot\ram-spd.ps1" -ErrorAction SilentlyContinue

    $cpu = $Telemetry.cpu
    $gpu = $Telemetry.gpu
    $hwmon = $Telemetry.hwmon
    $arch = if ($cpu) { $cpu.architecture } else { @{} }
    $g0 = @($gpu.gpus) | Select-Object -First 1

    $platform = $null
    if ($Devices -and $Devices.platform) {
        $platform = $Devices.platform
    } else {
        $platform = Get-ProbePlatformIntelligence -Devices $Devices -HwMon $hwmon -Telemetry $Telemetry
    }
    $fingerprint = $null
    if ($Devices -and $Devices.fingerprint) {
        $fingerprint = $Devices.fingerprint
    } else {
        $fingerprint = Get-ProbeMachineFingerprint -Platform $platform -Devices $Devices -Telemetry $Telemetry
    }

    $microcode = if ($platform.microcode -and $platform.microcode.revision) {
        $platform.microcode.revision
    } else {
        $null
    }
    if (-not $microcode) {
        try {
            $cpu0 = Get-ItemProperty -Path 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -ErrorAction SilentlyContinue
            if ($cpu0 -and $cpu0.'Update Revision') { $microcode = "$($cpu0.'Update Revision')".Trim() }
            elseif ($cpu0 -and $cpu0.'UpdateRevision') { $microcode = "$($cpu0.UpdateRevision)".Trim() }
        } catch {}
    }

    $ram = $null
    try { $ram = Get-RamSpdTelemetry } catch {}
    if (-not $ram) { $ram = @{ modules = @(); source = 'unavailable'; note = 'SMBIOS SPD not present' } }
    if ($ram -and -not $ram.note) {
        $ram.note = 'SMBIOS/WMI module identity; raw SMBus EEPROM dump is optional when Ring0 I2C is available'
    }
    if ((@($ram.modules).Count -eq 0) -and $platform.smbios -and $platform.smbios.types -and @($platform.smbios.types.memory_devices).Count -gt 0) {
        $ram = @{
            modules = @($platform.smbios.types.memory_devices)
            source  = 'smbios_type17'
            note    = 'Decoded from raw SMBIOS Type 17'
        }
    }

    $monitors = @()
    if ($Devices -and $Devices.monitors) { $monitors = @($Devices.monitors) }

    $fw = $null
    if ($Devices -and $Devices.firmware) { $fw = $Devices.firmware }
    elseif ($Telemetry.os_kernel) { $fw = $Telemetry.motherboard }

    $pci = @()
    if ($platform.pci_config -and @($platform.pci_config).Count -gt 0) { $pci = @($platform.pci_config) }
    elseif ($hwmon -and $hwmon.pci_config) { $pci = @($hwmon.pci_config) }

    $storage = if ($platform.storage -and @($platform.storage).Count -gt 0) {
        @($platform.storage)
    } else {
        Get-ProbeNvmeSmart
    }

    $acpiTables = if ($platform.acpi -and $platform.acpi.signatures) {
        @($platform.acpi.signatures)
    } else {
        @()
    }

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

    $biosVendor = if ($platform.bios -and $platform.bios.vendor) { $platform.bios.vendor } elseif ($fw.bios -and $fw.bios.vendor) { $fw.bios.vendor } elseif ($fw.bios_vendor) { $fw.bios_vendor } else { $null }
    $biosVersion = if ($platform.bios -and $platform.bios.version) { $platform.bios.version } elseif ($fw.bios -and $fw.bios.version) { $fw.bios.version } elseif ($fw.bios_version) { $fw.bios_version } else { $null }
    $biosDate = if ($platform.bios -and $platform.bios.date) { $platform.bios.date } elseif ($fw.bios -and $fw.bios.date) { $fw.bios.date } elseif ($fw.bios_date) { $fw.bios_date } else { $null }

    return @{
        collected_at = (Get-Date).ToUniversalTime().ToString('o')
        platform     = $platform
        fingerprint  = $fingerprint
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
            smbios_major = if ($platform.bios) { $platform.bios.smbios_major } elseif ($fw.bios) { $fw.bios.smbios_major } else { $null }
            smbios_minor = if ($platform.bios) { $platform.bios.smbios_minor } elseif ($fw.bios) { $fw.bios.smbios_minor } else { $null }
        }
        firmware_inventory = @{
            bios_vendor   = $biosVendor
            bios_version  = $biosVersion
            bios_date     = $biosDate
            tpm           = if ($platform.tpm) { $platform.tpm } elseif ($fw.tpm) { $fw.tpm } else { @{ present = $false } }
            secure_boot   = if ($null -ne $platform.uefi.secure_boot) { $platform.uefi.secure_boot } elseif ($null -ne $fw.secure_boot) { $fw.secure_boot } else { $null }
            uefi          = $platform.uefi
            me_psp        = $platform.me_psp
            acpi          = $platform.acpi
            acpi_tables   = $acpiTables
            cpu_microcode = $microcode
            gpu_vbios     = if ($vbiosRaw) { $vbiosRaw } else { $null }
            gpu_vbios_sha256 = $vbiosHash
            storage_firmware = @($storage | ForEach-Object {
                @{ name = $_.friendly_name; serial = $_.serial; firmware = $_.firmware; source = $_.source; is_nvme = $_.is_nvme }
            })
            pci_config_count = @($pci).Count
            ec_board_count   = if ($platform.ec_board) { [int]$platform.ec_board.count } else { 0 }
            coverage_score   = if ($fingerprint) { $fingerprint.coverage_score } else { $null }
            provenance    = 'smbios+wmi+registry+storage_reliability+ring0'
            note          = 'Identity and register reads only - no BIOS/VBIOS flash, no vendor MODS binaries'
        }
        open_book_count = if ($Telemetry.open_book) { [int]$Telemetry.open_book.count } else { 0 }
    }
}
