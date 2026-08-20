# Platform Intelligence - SMBIOS / UEFI / TPM / ME-PSP / ACPI / NVMe / fingerprint
# Dot-sourced from devices.ps1, dossier.ps1, openbook.ps1
. "$PSScriptRoot\common.ps1"

function ConvertFrom-ProbeSmbiosString {
    param([byte[]]$Buf, [int]$Index, [int]$StringCount)
    if ($Index -le 0 -or $null -eq $Buf) { return $null }
    $pos = 0
    $n = 1
    while ($pos -lt $Buf.Length) {
        $end = $pos
        while ($end -lt $Buf.Length -and $Buf[$end] -ne 0) { $end++ }
        if ($n -eq $Index) {
            if ($end -le $pos) { return '' }
            return [System.Text.Encoding]::ASCII.GetString($Buf, $pos, $end - $pos).Trim()
        }
        $n++
        $pos = $end + 1
        if ($pos -lt $Buf.Length -and $Buf[$pos] -eq 0) { break }
    }
    return $null
}

function Get-ProbeSmbiosRawBytes {
    try {
        $raw = Get-CimInstance -Namespace root\wmi -ClassName MSSmBios_RawSMBiosTables -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($raw -and $raw.SMBiosData) {
            return @{
                bytes          = [byte[]]$raw.SMBiosData
                smbios_major   = [int]$raw.SmbiosMajorVersion
                smbios_minor   = [int]$raw.SmbiosMinorVersion
                dmi_revision   = [int]$raw.DmiRevision
                size           = [int]$raw.Size
                source         = 'wmi_mssmbios'
                confidence     = 'measured'
            }
        }
    } catch {}
    return $null
}

function Get-ProbeSmbiosDecoded {
    $pack = Get-ProbeSmbiosRawBytes
    if (-not $pack) {
        return @{
            available  = $false
            source     = 'unavailable'
            confidence = 'unavailable'
            types      = @{}
            note       = 'MSSmBios_RawSMBiosTables not readable'
        }
    }

    $data = $pack.bytes
    $types = @{
        bios         = $null
        system       = $null
        baseboard    = $null
        chassis      = $null
        processor    = $null
        cache        = @()
        slots        = @()
        physical_mem = $null
        memory_devices = @()
        memory_array_mapped = @()
    }

    $i = 0
    $len = $data.Length
    while ($i + 4 -lt $len) {
        $type = [int]$data[$i]
        $formatted = [int]$data[$i + 1]
        if ($formatted -lt 4) { break }
        $handle = [int]$data[$i + 2] + ([int]$data[$i + 3] -shl 8)
        $structEnd = $i + $formatted
        if ($structEnd -ge $len) { break }

        # Find end of string table (double NUL)
        $strStart = $structEnd
        $p = $structEnd
        while ($p + 1 -lt $len) {
            if ($data[$p] -eq 0 -and $data[$p + 1] -eq 0) { $p += 2; break }
            $p++
        }
        $strLen = [Math]::Max(0, $p - $strStart)
        $strBuf = if ($strLen -gt 0) { $data[$strStart..($strStart + $strLen - 1)] } else { [byte[]]@() }

        switch ($type) {
            0 { # BIOS
                $types.bios = @{
                    handle      = $handle
                    vendor      = ConvertFrom-ProbeSmbiosString $strBuf ([int]$data[$i + 4])
                    version     = ConvertFrom-ProbeSmbiosString $strBuf ([int]$data[$i + 5])
                    release_date = ConvertFrom-ProbeSmbiosString $strBuf ([int]$data[$i + 8])
                    rom_size_kb = if ($formatted -gt 9) { ([int]$data[$i + 9] + 1) * 64 } else { $null }
                    source      = 'smbios_type0'
                    confidence  = 'measured'
                }
            }
            1 { # System
                $types.system = @{
                    handle       = $handle
                    manufacturer = ConvertFrom-ProbeSmbiosString $strBuf ([int]$data[$i + 4])
                    product      = ConvertFrom-ProbeSmbiosString $strBuf ([int]$data[$i + 5])
                    version      = ConvertFrom-ProbeSmbiosString $strBuf ([int]$data[$i + 6])
                    serial       = ConvertFrom-ProbeSmbiosString $strBuf ([int]$data[$i + 7])
                    sku          = if ($formatted -gt 25) { ConvertFrom-ProbeSmbiosString $strBuf ([int]$data[$i + 25]) } else { $null }
                    family       = if ($formatted -gt 26) { ConvertFrom-ProbeSmbiosString $strBuf ([int]$data[$i + 26]) } else { $null }
                    uuid         = if ($formatted -ge 24) {
                        ($data[($i + 8)..($i + 23)] | ForEach-Object { $_.ToString('x2') }) -join ''
                    } else { $null }
                    source       = 'smbios_type1'
                    confidence   = 'measured'
                }
            }
            2 { # Baseboard
                $types.baseboard = @{
                    handle       = $handle
                    manufacturer = ConvertFrom-ProbeSmbiosString $strBuf ([int]$data[$i + 4])
                    product      = ConvertFrom-ProbeSmbiosString $strBuf ([int]$data[$i + 5])
                    version      = ConvertFrom-ProbeSmbiosString $strBuf ([int]$data[$i + 6])
                    serial       = ConvertFrom-ProbeSmbiosString $strBuf ([int]$data[$i + 7])
                    asset_tag    = ConvertFrom-ProbeSmbiosString $strBuf ([int]$data[$i + 8])
                    source       = 'smbios_type2'
                    confidence   = 'measured'
                }
            }
            3 { # Chassis
                $types.chassis = @{
                    handle       = $handle
                    manufacturer = ConvertFrom-ProbeSmbiosString $strBuf ([int]$data[$i + 4])
                    type_code    = [int]$data[$i + 5]
                    version      = ConvertFrom-ProbeSmbiosString $strBuf ([int]$data[$i + 6])
                    serial       = ConvertFrom-ProbeSmbiosString $strBuf ([int]$data[$i + 7])
                    source       = 'smbios_type3'
                    confidence   = 'measured'
                }
            }
            4 { # Processor
                if (-not $types.processor) {
                    $types.processor = @{
                        handle       = $handle
                        socket       = ConvertFrom-ProbeSmbiosString $strBuf ([int]$data[$i + 4])
                        manufacturer = ConvertFrom-ProbeSmbiosString $strBuf ([int]$data[$i + 7])
                        version      = ConvertFrom-ProbeSmbiosString $strBuf ([int]$data[$i + 16])
                        core_count   = if ($formatted -gt 35) { [int]$data[$i + 35] } else { $null }
                        thread_count = if ($formatted -gt 36) { [int]$data[$i + 36] } else { $null }
                        max_speed_mhz = if ($formatted -gt 22) { [int]$data[$i + 20] + ([int]$data[$i + 21] -shl 8) } else { $null }
                        source       = 'smbios_type4'
                        confidence   = 'measured'
                    }
                }
            }
            7 { # Cache
                $types.cache += @{
                    handle = $handle
                    socket = ConvertFrom-ProbeSmbiosString $strBuf ([int]$data[$i + 4])
                    source = 'smbios_type7'
                }
            }
            9 { # System Slot
                $types.slots += @{
                    handle     = $handle
                    designation = ConvertFrom-ProbeSmbiosString $strBuf ([int]$data[$i + 4])
                    type_code  = [int]$data[$i + 5]
                    data_bus_width = [int]$data[$i + 6]
                    current_usage = [int]$data[$i + 7]
                    source     = 'smbios_type9'
                    confidence = 'measured'
                }
            }
            16 { # Physical Memory Array
                $types.physical_mem = @{
                    handle           = $handle
                    location         = [int]$data[$i + 4]
                    use              = [int]$data[$i + 5]
                    error_correction = [int]$data[$i + 6]
                    max_capacity_kb  = if ($formatted -gt 10) {
                        [uint32]([int]$data[$i + 7] + ([int]$data[$i + 8] -shl 8) + ([int]$data[$i + 9] -shl 16) + ([int]$data[$i + 10] -shl 24))
                    } else { $null }
                    number_of_devices = if ($formatted -gt 14) { [int]$data[$i + 13] + ([int]$data[$i + 14] -shl 8) } else { $null }
                    source           = 'smbios_type16'
                    confidence       = 'measured'
                }
            }
            17 { # Memory Device
                $sizeRaw = [int]$data[$i + 12] + ([int]$data[$i + 13] -shl 8)
                $sizeMb = if ($sizeRaw -eq 0 -or $sizeRaw -eq 0xFFFF) { $null } elseif (($sizeRaw -band 0x8000) -ne 0) { $sizeRaw -band 0x7FFF } else { $sizeRaw }
                $types.memory_devices += @{
                    handle       = $handle
                    device_locator = ConvertFrom-ProbeSmbiosString $strBuf ([int]$data[$i + 16])
                    bank_locator = ConvertFrom-ProbeSmbiosString $strBuf ([int]$data[$i + 17])
                    manufacturer = ConvertFrom-ProbeSmbiosString $strBuf ([int]$data[$i + 23])
                    serial       = ConvertFrom-ProbeSmbiosString $strBuf ([int]$data[$i + 24])
                    part_number  = ConvertFrom-ProbeSmbiosString $strBuf ([int]$data[$i + 26])
                    size_mb      = $sizeMb
                    speed_mts    = if ($formatted -gt 21) { [int]$data[$i + 21] + ([int]$data[$i + 22] -shl 8) } else { $null }
                    type_code    = [int]$data[$i + 18]
                    source       = 'smbios_type17'
                    confidence   = 'measured'
                }
            }
            19 { # Memory Array Mapped Address
                $types.memory_array_mapped += @{
                    handle = $handle
                    source = 'smbios_type19'
                }
            }
        }

        $i = $p
        if ($type -eq 127) { break }
    }

    return @{
        available      = $true
        source         = $pack.source
        confidence     = 'measured'
        smbios_major   = $pack.smbios_major
        smbios_minor   = $pack.smbios_minor
        dmi_revision   = $pack.dmi_revision
        size_bytes     = $pack.size
        types          = $types
        type_counts    = @{
            bios = if ($types.bios) { 1 } else { 0 }
            system = if ($types.system) { 1 } else { 0 }
            baseboard = if ($types.baseboard) { 1 } else { 0 }
            chassis = if ($types.chassis) { 1 } else { 0 }
            processor = if ($types.processor) { 1 } else { 0 }
            cache = @($types.cache).Count
            slots = @($types.slots).Count
            memory_devices = @($types.memory_devices).Count
        }
        note           = 'Key SMBIOS types 0/1/2/3/4/7/9/16/17/19 - not a full DMI browser'
    }
}

function Get-ProbeUefiInfo {
    $firmwareType = $null
    try {
        $ft = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name PEFirmwareType -ErrorAction SilentlyContinue
        if ($null -ne $ft.PEFirmwareType) {
            $firmwareType = switch ([int]$ft.PEFirmwareType) {
                1 { 'bios' }
                2 { 'uefi' }
                default { "unknown_$($ft.PEFirmwareType)" }
            }
        }
    } catch {}

    $secureBoot = $null
    $secureBootSource = 'unavailable'
    try {
        $secureBoot = [bool](Confirm-SecureBootUEFI -ErrorAction Stop)
        $secureBootSource = 'confirm_secureboot_uefi'
    } catch {
        try {
            $v = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction SilentlyContinue
            if ($null -ne $v.UEFISecureBootEnabled) {
                $secureBoot = [bool]$v.UEFISecureBootEnabled
                $secureBootSource = 'registry'
            }
        } catch {}
    }

    $setupMode = $null
    $secureBootPolicy = $null
    try {
        $sm = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction SilentlyContinue
        if ($null -ne $sm.UEFISecureBootSetupMode) { $setupMode = [bool]$sm.UEFISecureBootSetupMode }
        if ($null -ne $sm.UEFISecureBootPolicy) { $secureBootPolicy = [int]$sm.UEFISecureBootPolicy }
    } catch {}

    $deviceGuard = @{
        virtualization_based_security = $null
        hypervisor_enforced_code_integrity = $null
        source = 'unavailable'
    }
    try {
        $dg = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($dg) {
            $deviceGuard.virtualization_based_security = [bool]$dg.VirtualizationBasedSecurityStatus
            $deviceGuard.hypervisor_enforced_code_integrity = if ($null -ne $dg.CodeIntegrityPolicyEnforcementStatus) {
                [int]$dg.CodeIntegrityPolicyEnforcementStatus
            } else { $null }
            $deviceGuard.source = 'wmi_deviceguard'
        }
    } catch {}

    $bitlocker = @{
        system_drive_protection = $null
        conversion_status = $null
        source = 'unavailable'
    }
    try {
        if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
            $sys = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
            if ($sys) {
                $bitlocker.system_drive_protection = "$($sys.ProtectionStatus)"
                $bitlocker.conversion_status = "$($sys.VolumeStatus)"
                $bitlocker.source = 'bitlocker'
            }
        }
    } catch {}

    $bootCurrent = $null
    $bootOrder = @()
    $bootEntries = @()
    $bootmgrPath = $null
    try {
        $bcd = & bcdedit /enum firmware 2>$null
        if ($LASTEXITCODE -eq 0 -and $bcd) {
            $currentId = $null
            $label = $null
            $device = $null
            $path = $null
            foreach ($line in @($bcd)) {
                if ($line -match '^\s*identifier\s+(\S+)') {
                    if ($currentId -and $label) {
                        $bootEntries += @{
                            id = $currentId
                            description = $label
                            device = $device
                            path = $path
                        }
                    }
                    $currentId = $Matches[1]
                    $label = $null
                    $device = $null
                    $path = $null
                } elseif ($line -match '^\s*description\s+(.+)$') {
                    $label = $Matches[1].Trim()
                } elseif ($line -match '^\s*device\s+(.+)$') {
                    $device = $Matches[1].Trim()
                } elseif ($line -match '^\s*path\s+(.+)$') {
                    $path = $Matches[1].Trim()
                }
            }
            if ($currentId -and $label) {
                $bootEntries += @{ id = $currentId; description = $label; device = $device; path = $path }
            }
            $bootOrder = @($bootEntries | ForEach-Object { $_.description }) | Select-Object -First 12
        }
    } catch {}

    try {
        $fwBoot = & bcdedit /enum '{fwbootmgr}' 2>$null
        if ($LASTEXITCODE -eq 0) {
            foreach ($line in @($fwBoot)) {
                if ($line -match '^\s*displayorder\s+(.+)$') {
                    $bootOrder = @($Matches[1] -split '\s+' | Where-Object { $_ }) | Select-Object -First 12
                }
                if ($line -match '^\s*bootsequence\s+(.+)$') {
                    $bootCurrent = $Matches[1].Trim()
                }
            }
        }
    } catch {}

    try {
        $bm = & bcdedit /enum '{bootmgr}' 2>$null
        if ($LASTEXITCODE -eq 0) {
            foreach ($line in @($bm)) {
                if ($line -match '^\s*path\s+(.+)$') { $bootmgrPath = $Matches[1].Trim() }
                if ($line -match '^\s*device\s+(.+)$' -and -not $bootmgrPath) { }
            }
        }
    } catch {}

    $elevated = Test-ProbeElevated
    $gaps = @()
    if ($firmwareType -ne 'uefi') {
        $gaps += @{ code = 'not_uefi'; detail = 'Firmware type is BIOS or unknown - UEFI variable reads limited' }
    }
    if ($null -eq $secureBoot) {
        $gaps += @{ code = 'secure_boot_unknown'; detail = 'Secure Boot state unreadable (needs UEFI + supported OS APIs)' }
    }
    if ($setupMode -eq $true) {
        $gaps += @{ code = 'setup_mode'; detail = 'UEFI Setup Mode is on - Secure Boot keys may not be enrolled' }
    }
    if (-not $elevated -and @($bootEntries).Count -eq 0) {
        $gaps += @{ code = 'boot_order_needs_admin'; detail = 'bcdedit firmware enum often needs elevation'; reason = 'needs_elevation' }
    }

    return @{
        firmware_type     = $firmwareType
        secure_boot       = $secureBoot
        secure_boot_source = $secureBootSource
        secure_boot_policy = $secureBootPolicy
        setup_mode        = $setupMode
        device_guard      = $deviceGuard
        bitlocker         = $bitlocker
        boot_current      = $bootCurrent
        boot_order        = @($bootOrder)
        boot_entries      = @($bootEntries | Select-Object -First 16)
        bootmgr_path      = $bootmgrPath
        source            = if ($firmwareType) { 'registry+bcdedit+deviceguard' } else { 'partial' }
        confidence        = if ($null -ne $secureBoot -and $firmwareType) { 'measured' } else { 'partial' }
        gaps              = @($gaps)
        note              = 'Read-only - no NVRAM write or firmware flash'
    }
}

function Get-ProbeTpmDetail {
    $basic = @{ present = $false; source = 'unavailable'; confidence = 'unavailable' }
    try {
        $t = Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $t) { return $basic }

        $pcrBanks = @()
        $pcrBankSource = 'unavailable'
        $ready = $null
        $lockedOut = $null
        $selfTest = $null
        $manufacturerIdInt = $null

        try {
            $tpmInfo = Get-Tpm -ErrorAction SilentlyContinue
            if ($tpmInfo) {
                if ($null -ne $tpmInfo.TpmReady) { $ready = [bool]$tpmInfo.TpmReady }
                if ($null -ne $tpmInfo.LockedOut) { $lockedOut = [bool]$tpmInfo.LockedOut }
                if ($null -ne $tpmInfo.SelfTest) { $selfTest = "$($tpmInfo.SelfTest)" }
                if ($null -ne $tpmInfo.ManufacturerId) { $manufacturerIdInt = [int]$tpmInfo.ManufacturerId }

                # Windows 10/11: Preferred/Active PCR banks appear as string arrays on some builds
                foreach ($propName in @('PcrBanks', 'PreferredPcrBanks', 'ActivePcrBanks', 'AvailablePcrBanks')) {
                    $prop = $tpmInfo.PSObject.Properties[$propName]
                    if (-not $prop -or $null -eq $prop.Value) { continue }
                    $vals = @($prop.Value)
                    foreach ($v in $vals) {
                        $s = "$v".Trim()
                        if ($s -and $s -notin $pcrBanks) { $pcrBanks += $s }
                    }
                    if ($pcrBanks.Count -gt 0) {
                        $pcrBankSource = "get_tpm.$propName"
                        break
                    }
                }
            }
        } catch {}

        # CIM method GetSupportedPcrs / algorithm list when present (TPM 2.0)
        if ($pcrBanks.Count -eq 0) {
            try {
                $methods = $t.CimClass.CimClassMethods.Name
                if ($methods -contains 'GetSupportedPcrs') {
                    $out = Invoke-CimMethod -InputObject $t -MethodName GetSupportedPcrs -ErrorAction SilentlyContinue
                    if ($out -and $out.Pcrs) {
                        foreach ($p in @($out.Pcrs)) {
                            $s = "$p".Trim()
                            if ($s) { $pcrBanks += $s }
                        }
                        $pcrBankSource = 'wmi_GetSupportedPcrs'
                    }
                }
            } catch {}
        }

        # Heuristic from SpecVersion when banks still empty
        if ($pcrBanks.Count -eq 0) {
            $spec = "$($t.SpecVersion)"
            if ($spec -match '2\.0') {
                $pcrBanks = @('Sha256')
                $pcrBankSource = 'heuristic_tpm2'
            } elseif ($spec -match '1\.2') {
                $pcrBanks = @('Sha1')
                $pcrBankSource = 'heuristic_tpm12'
            }
        }

        $ekDigest = $null
        try {
            if (Get-Command Get-TpmEndorsementKeyInfo -ErrorAction SilentlyContinue) {
                $ek = Get-TpmEndorsementKeyInfo -HashAlgorithm Sha256 -ErrorAction SilentlyContinue
                if ($ek -and $ek.PublicKeyHash) { $ekDigest = "$($ek.PublicKeyHash)".Substring(0, [Math]::Min(32, "$($ek.PublicKeyHash)".Length)) }
            }
        } catch {}

        $fwVer = "$($t.ManufacturerVersion)"
        if ($t.ManufacturerVersionFull20) { $fwVer = "$($t.ManufacturerVersionFull20)" }
        elseif ($t.ManufacturerVersionInfo) { $fwVer = "$($t.ManufacturerVersionInfo)" }

        return @{
            present              = $true
            enabled              = [bool]$t.IsEnabled_InitialValue
            activated            = [bool]$t.IsActivated_InitialValue
            owned                = [bool]$t.IsOwned_InitialValue
            ready                = $ready
            locked_out           = $lockedOut
            self_test            = $selfTest
            spec_version         = "$($t.SpecVersion)"
            manufacturer_id      = "$($t.ManufacturerIdTxt)"
            manufacturer_id_int  = $manufacturerIdInt
            manufacturer_version = $fwVer
            manufacturer_version_info = "$($t.ManufacturerVersionInfo)"
            physical_presence_version = "$($t.PhysicalPresenceVersionInfo)"
            pcr_banks            = @($pcrBanks)
            pcr_bank_source      = $pcrBankSource
            ek_public_hash_prefix = $ekDigest
            source               = 'wmi_win32_tpm+get_tpm'
            confidence           = 'measured'
            note                 = 'Status + PCR bank list when exposed - no remote attestation / PCR quote'
        }
    } catch {
        return $basic
    }
}

function Get-ProbeMePspInfo {
    $devices = @()
    try {
        foreach ($d in @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object {
            "$($_.FriendlyName)$($_.InstanceId)" -match 'Management Engine|MEI|HECI|PSP|Platform Security Processor|AMD\s+PSP|Intel\(R\) Management'
        })) {
            $driver = $null
            $driverDate = $null
            $driverVersion = $null
            $isGeneric = $false
            try {
                $di = Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_DriverVersion', 'DEVPKEY_Device_DriverDate', 'DEVPKEY_Device_DriverProvider' -ErrorAction SilentlyContinue
                foreach ($p in @($di)) {
                    if ($p.KeyName -match 'DriverVersion') { $driverVersion = "$($p.Data)" }
                    if ($p.KeyName -match 'DriverDate') { $driverDate = "$($p.Data)" }
                    if ($p.KeyName -match 'DriverProvider') { $driver = "$($p.Data)" }
                }
            } catch {}
            $name = "$($d.FriendlyName)"
            $prov = "$driver"
            if ($prov -match 'Microsoft' -or $name -match 'Generic') { $isGeneric = $true }
            $role = if ($name -match 'PSP|Platform Security') { 'psp' } else { 'mei' }
            $devices += @{
                name            = $name
                instance_id     = "$($d.InstanceId)"
                status          = "$($d.Status)"
                class           = "$($d.Class)"
                role            = $role
                driver_provider = $prov
                driver_version  = $driverVersion
                driver_date     = $driverDate
                is_generic      = $isGeneric
                source          = 'pnp'
                confidence      = 'measured'
            }
        }
    } catch {}

    $vendor = $null
    if (@($devices | Where-Object { $_.role -eq 'mei' }).Count -gt 0) { $vendor = 'intel' }
    elseif (@($devices | Where-Object { $_.role -eq 'psp' }).Count -gt 0) { $vendor = 'amd' }

    return @{
        vendor     = $vendor
        present    = @($devices).Count -gt 0
        devices    = @($devices)
        generic_driver = (@($devices | Where-Object { $_.is_generic }).Count -gt 0)
        source     = if (@($devices).Count -gt 0) { 'pnp_heuristic' } else { 'unavailable' }
        confidence = if (@($devices).Count -gt 0) { 'heuristic' } else { 'unavailable' }
        note       = 'Device + driver identity only - no proprietary MEI/PSP firmware version DLL'
    }
}

function Get-ProbeAcpiDetail {
    $signatures = @()
    $hasFadt = $false
    $hasDsdt = $false
    try {
        Get-ChildItem 'HKLM:\HARDWARE\ACPI' -ErrorAction SilentlyContinue | ForEach-Object {
            $sig = $_.PSChildName
            $signatures += $sig
            if ($sig -eq 'FADT' -or $sig -eq 'FACP') { $hasFadt = $true }
            if ($sig -eq 'DSDT') { $hasDsdt = $true }
        }
    } catch {}

    $sleep = @{
        s1 = $null; s2 = $null; s3 = $null; s4 = $null; s5 = $null
        source = 'unavailable'
    }
    try {
        $cs = Get-CimSafe Win32_ComputerSystem | Select-Object -First 1
        # Power capabilities via powercfg
        $pc = & powercfg /a 2>$null
        if ($pc) {
            $text = (@($pc) -join "`n").ToLowerInvariant()
            $sleep.s3 = $text -match 'standby \(s3\)' -and $text -notmatch 'standby \(s3\).*unavailable'
            $sleep.s4 = $text -match 'hibernate' -and $text -notmatch 'hibernate.*unavailable'
            $sleep.s5 = $true
            $sleep.s1 = $text -match 'standby \(s1\)'
            $sleep.s2 = $text -match 'standby \(s2\)'
            $sleep.source = 'powercfg'
        }
    } catch {}

    $thermalZones = 0
    try {
        $tz = @(Get-CimInstance -Namespace root\wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue)
        $thermalZones = $tz.Count
    } catch {}

    return @{
        signatures       = @($signatures | Sort-Object -Unique)
        signature_count  = @($signatures | Sort-Object -Unique).Count
        has_fadt         = $hasFadt
        has_dsdt         = $hasDsdt
        sleep_states     = $sleep
        thermal_zone_count = $thermalZones
        source           = 'registry+powercfg+wmi'
        confidence       = if (@($signatures).Count -gt 0) { 'measured' } else { 'partial' }
        note             = 'Table signatures + sleep availability - no AML interpreter'
    }
}

function Get-ProbeNvmeSmartDetailed {
    $drives = @()
    try {
        foreach ($d in @(Get-PhysicalDisk -ErrorAction SilentlyContinue)) {
            $health = $null
            try { $health = Get-StorageReliabilityCounter -PhysicalDisk $d -ErrorAction SilentlyContinue } catch {}
            $bus = "$($d.BusType)"
            $isNvme = $bus -match 'NVMe' -or "$($d.FriendlyName)" -match 'NVMe'
            $source = 'storage_reliability'
            $confidence = if ($health) { 'measured' } else { 'partial' }
            $adminSmart = $false
            $smartDepth = 'os_reliability'

            $percentUsed = $null
            $critWarn = $null
            $spare = $null
            $dataUnitsRead = $null
            $dataUnitsWritten = $null
            $unsafeShutdowns = $null
            $mediaErrors = $null
            $opStatus = $null

            if ($health) {
                # Map StorageReliability fields that approximate NVMe SMART semantics
                if ($null -ne $health.Wear) {
                    $percentUsed = [int]$health.Wear
                }
                try {
                    if ($null -ne $health.Temperature) { }
                    if ($health.PSObject.Properties['ReadLatencyMax'] -and $null -ne $health.ReadLatencyMax) { }
                } catch {}
            }

            # Disk operational status + partition style from Get-Disk
            try {
                $disk = Get-Disk -Number $d.DeviceId -ErrorAction SilentlyContinue
                if (-not $disk -and $d.SerialNumber) {
                    $disk = Get-Disk -ErrorAction SilentlyContinue | Where-Object { $_.SerialNumber -eq $d.SerialNumber } | Select-Object -First 1
                }
                if ($disk) {
                    $opStatus = @($disk.OperationalStatus) -join ','
                    if ($disk.HealthStatus) { }
                }
            } catch {}

            # Best-effort NVMe identify via Storage cmdlets / MSFT_PhysicalDisk extended props
            try {
                if ($isNvme) {
                    $pd = Get-CimInstance -Namespace root\microsoft\windows\storage -ClassName MSFT_PhysicalDisk -ErrorAction SilentlyContinue |
                        Where-Object { $_.SerialNumber -eq $d.SerialNumber -or $_.FriendlyName -eq $d.FriendlyName } |
                        Select-Object -First 1
                    if ($pd) {
                        if ($pd.PSObject.Properties['AdapterSerialNumber'] -and $pd.AdapterSerialNumber) { }
                        # Some builds expose SMART-ish counters via reliability; mark depth
                        if ($health -and $null -ne $percentUsed) {
                            $smartDepth = 'os_reliability_mapped'
                        }
                    }
                }
            } catch {}

            # Attempt nvme-cli if present on PATH (optional shop tool) - never require it
            try {
                if ($isNvme -and (Get-Command nvme -ErrorAction SilentlyContinue)) {
                    # Do not parse vendor-specific logs here; note capability only
                    $adminSmart = $false
                    $smartDepth = 'nvme_cli_available_not_parsed'
                }
            } catch {}

            $fw = $null
            try { if ($d.FirmwareVersion) { $fw = "$($d.FirmwareVersion)".Trim() } } catch {}

            $model = "$($d.Model)".Trim()
            if (-not $model) { $model = "$($d.FriendlyName)" }

            $drives += @{
                friendly_name    = "$($d.FriendlyName)"
                model            = $model
                serial           = "$($d.SerialNumber)".Trim()
                media_type       = "$($d.MediaType)"
                bus_type         = $bus
                is_nvme          = [bool]$isNvme
                size_gb          = if ($d.Size) { [math]::Round($d.Size / 1GB, 1) } else { $null }
                health_status    = "$($d.HealthStatus)"
                operational_status = $opStatus
                firmware         = $fw
                temperature_c    = if ($health -and $health.Temperature) { [int]$health.Temperature } else { $null }
                wear             = if ($health -and $null -ne $health.Wear) { [int]$health.Wear } else { $null }
                percentage_used  = $percentUsed
                available_spare  = $spare
                critical_warning = $critWarn
                data_units_read  = $dataUnitsRead
                data_units_written = $dataUnitsWritten
                unsafe_shutdowns = $unsafeShutdowns
                media_errors     = $mediaErrors
                read_errors      = if ($health) { $health.ReadErrorsUncorrected } else { $null }
                write_errors     = if ($health) { $health.WriteErrorsUncorrected } else { $null }
                power_on_hours   = if ($health) { $health.PowerOnHours } else { $null }
                start_stop_cycle = if ($health -and $null -ne $health.StartStopCycle) { $health.StartStopCycle } else { $null }
                flush_latency_max = if ($health -and $null -ne $health.FlushLatencyMax) { $health.FlushLatencyMax } else { $null }
                admin_smart      = $adminSmart
                smart_depth      = $smartDepth
                source           = $source
                confidence       = $confidence
                note             = if ($isNvme) {
                    'OS StorageReliability counters - not full NVMe Admin Identify/SMART log pages (smart_depth=' + $smartDepth + ')'
                } else {
                    'OS storage reliability counters'
                }
            }
        }
    } catch {}
    return @($drives)
}

function Get-ProbeEcBoardSensors {
    param($HwMon = $null)
    $rows = @()
    $boardMatch = $null
    if (-not $HwMon) { return @{ sensors = @(); count = 0; board_match_confidence = 'unavailable'; source = 'unavailable' } }

    $flat = @($HwMon.sensors_flat)
    if ($flat.Count -eq 0 -and $HwMon.hardware) {
        # leave empty - flat is preferred
    }

    foreach ($s in $flat) {
        $ht = "$($s.hardware_type)$($s.SensorType)$($s.type)".ToLowerInvariant()
        $name = "$($s.name)$($s.Name)".ToLowerInvariant()
        $hw = "$($s.hardware)$($s.Hardware)".ToLowerInvariant()
        $isEc = $ht -match 'superio|embedded|motherboard|cool' -or
                $name -match 'fan|vr\s|vrm|chipset|motherboard|ec |super io' -or
                $hw -match 'motherboard|superio|nct|it8|auxtin'
        if (-not $isEc) { continue }
        $v = $null
        if ($null -ne $s.value) { $v = [double]$s.value }
        elseif ($null -ne $s.Value) { $v = [double]$s.Value }
        $rows += @{
            name       = if ($s.name) { [string]$s.name } else { [string]$s.Name }
            value      = $v
            unit       = if ($s.unit) { [string]$s.unit } elseif ($s.SensorType -match 'Temperature') { '-C' } elseif ($s.SensorType -match 'Fan') { 'RPM' } else { $null }
            hardware   = if ($s.hardware) { [string]$s.hardware } else { [string]$s.Hardware }
            source     = 'lhm_ec_board'
            confidence = 'measured'
        }
    }

    if (@($rows).Count -gt 0) { $boardMatch = 'lhm_present' }
    return @{
        sensors                = @($rows | Select-Object -First 64)
        count                  = @($rows).Count
        board_match_confidence = if (@($rows).Count -gt 8) { 'high' } elseif (@($rows).Count -gt 0) { 'medium' } else { 'unavailable' }
        source                 = if (@($rows).Count -gt 0) { 'lhm' } else { 'unavailable' }
        note                   = 'LHM SuperIO/EC channels when elevated - no custom EC protocol'
    }
}

function Get-ProbePlatformIntelligence {
    param(
        $Devices = $null,
        $HwMon = $null,
        $Telemetry = $null
    )

    $smbios = Get-ProbeSmbiosDecoded
    $uefi = Get-ProbeUefiInfo
    $tpm = Get-ProbeTpmDetail
    $mePsp = Get-ProbeMePspInfo
    $acpi = Get-ProbeAcpiDetail
    $nvme = Get-ProbeNvmeSmartDetailed
    $ec = Get-ProbeEcBoardSensors -HwMon $HwMon

    $microcode = $null
    try {
        $cpu0 = Get-ItemProperty -Path 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -ErrorAction SilentlyContinue
        if ($cpu0 -and $cpu0.'Update Revision') { $microcode = "$($cpu0.'Update Revision')".Trim() }
        elseif ($cpu0 -and $cpu0.UpdateRevision) { $microcode = "$($cpu0.UpdateRevision)".Trim() }
    } catch {}

    $pci = @()
    if ($HwMon -and $HwMon.pci_config) { $pci = @($HwMon.pci_config) }
    elseif ($Telemetry -and $Telemetry.hwmon -and $Telemetry.hwmon.pci_config) { $pci = @($Telemetry.hwmon.pci_config) }

    $elevated = Test-ProbeElevated

    # Legacy WMI bios/board for merge
    $wmiBios = $null
    $wmiBoard = $null
    if ($Devices -and $Devices.firmware) {
        $wmiBios = $Devices.firmware.bios
        $wmiBoard = $Devices.firmware.board
    }

    $biosPlane = @{
        vendor     = if ($smbios.types.bios.vendor) { $smbios.types.bios.vendor } elseif ($wmiBios) { $wmiBios.vendor } else { $null }
        version    = if ($smbios.types.bios.version) { $smbios.types.bios.version } elseif ($wmiBios) { $wmiBios.version } else { $null }
        date       = if ($smbios.types.bios.release_date) { $smbios.types.bios.release_date } elseif ($wmiBios) { $wmiBios.date } else { $null }
        smbios_major = if ($null -ne $smbios.smbios_major) { $smbios.smbios_major } elseif ($wmiBios) { $wmiBios.smbios_major } else { $null }
        smbios_minor = if ($null -ne $smbios.smbios_minor) { $smbios.smbios_minor } elseif ($wmiBios) { $wmiBios.smbios_minor } else { $null }
        source     = if ($smbios.types.bios) { 'smbios_type0' } elseif ($wmiBios) { 'wmi' } else { 'unavailable' }
        confidence = if ($smbios.types.bios) { 'measured' } elseif ($wmiBios) { 'wmi' } else { 'unavailable' }
    }

    return @{
        schema_version = 1
        collected_at   = (Get-Date).ToUniversalTime().ToString('o')
        elevated       = $elevated
        bios           = $biosPlane
        smbios         = $smbios
        uefi           = $uefi
        tpm            = $tpm
        me_psp         = $mePsp
        acpi           = $acpi
        storage        = @($nvme)
        pci_config     = @($pci)
        ec_board       = $ec
        microcode      = @{
            revision   = $microcode
            source     = if ($microcode) { 'registry' } else { 'unavailable' }
            confidence = if ($microcode) { 'measured' } else { 'unavailable' }
        }
        planes = @(
            'bios', 'smbios', 'uefi', 'tpm', 'me_psp', 'acpi', 'storage', 'pci_config', 'ec_board', 'microcode'
        )
        note = 'Platform Intelligence - identity and register reads only; no firmware flash'
    }
}

function Get-ProbeMachineFingerprint {
    param(
        $Platform = $null,
        $Devices = $null,
        $Telemetry = $null
    )

    if (-not $Platform) {
        $HwMon = $null
        if ($Telemetry -and $Telemetry.hwmon) { $HwMon = $Telemetry.hwmon }
        $Platform = Get-ProbePlatformIntelligence -Devices $Devices -HwMon $HwMon -Telemetry $Telemetry
    }

    $parts = [System.Collections.Generic.List[string]]::new()
    $board = $null
    if ($Platform.smbios -and $Platform.smbios.types -and $Platform.smbios.types.baseboard) {
        $board = $Platform.smbios.types.baseboard
    } elseif ($Devices -and $Devices.firmware -and $Devices.firmware.board) {
        $board = $Devices.firmware.board
    }
    if ($board) {
        $parts.Add("board:$($board.manufacturer)|$($board.product)|$($board.serial)")
    }
    if ($Platform.bios) {
        $parts.Add("bios:$($Platform.bios.vendor)|$($Platform.bios.version)")
    }
    if ($Platform.smbios -and $Platform.smbios.types -and $Platform.smbios.types.system -and $Platform.smbios.types.system.uuid) {
        $parts.Add("uuid:$($Platform.smbios.types.system.uuid)")
    }

    $cpuId = $null
    try {
        $cpu0 = Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -ErrorAction SilentlyContinue
        if ($cpu0 -and $cpu0.ProcessorNameString) { $cpuId = "$($cpu0.ProcessorNameString)" }
        if ($cpu0 -and $cpu0.'FeatureSet') { $parts.Add("cpuid_feat:$($cpu0.FeatureSet)") }
    } catch {}
    if ($cpuId) { $parts.Add("cpu:$cpuId") }
    if ($Platform.microcode -and $Platform.microcode.revision) { $parts.Add("ucode:$($Platform.microcode.revision)") }

    foreach ($p in @($Platform.pci_config)) {
        $parts.Add("pci:$($p.vendor_id):$($p.device_id):$($p.pci_bdf)")
    }
    if ($Devices -and $Devices.pci) {
        foreach ($p in @($Devices.pci | Select-Object -First 12)) {
            if ($p.vendor_id -or $p.ven) {
                $parts.Add("pnp_pci:$($p.vendor_id)$($p.ven):$($p.device_id)$($p.dev)")
            }
        }
    }
    foreach ($d in @($Platform.storage)) {
        if ($d.serial) { $parts.Add("disk:$($d.serial)") }
    }

    $material = ($parts | Sort-Object -Unique) -join "`n"
    $hash = $null
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($material)
        $hash = -join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })
        $sha.Dispose()
    } catch {}

    # Coverage scoring
    $planes = @(
        @{ id = 'bios';       ok = ($Platform.bios.confidence -in @('measured', 'wmi')) }
        @{ id = 'smbios';     ok = [bool]$Platform.smbios.available }
        @{ id = 'uefi';       ok = ($null -ne $Platform.uefi.secure_boot -or $Platform.uefi.firmware_type) }
        @{ id = 'tpm';        ok = [bool]$Platform.tpm.present }
        @{ id = 'me_psp';     ok = [bool]$Platform.me_psp.present }
        @{ id = 'acpi';       ok = ($Platform.acpi.signature_count -gt 0) }
        @{ id = 'storage';    ok = (@($Platform.storage).Count -gt 0) }
        @{ id = 'pci_config'; ok = (@($Platform.pci_config).Count -gt 0) }
        @{ id = 'ec_board';   ok = ($Platform.ec_board.count -gt 0) }
        @{ id = 'microcode';  ok = [bool]$Platform.microcode.revision }
    )
    $measured = @($planes | Where-Object { $_.ok }).Count
    $total = $planes.Count
    $coverage = [int][math]::Round(100.0 * $measured / [math]::Max(1, $total))

    $gaps = [System.Collections.Generic.List[object]]::new()
    foreach ($p in $planes) {
        if ($p.ok) { continue }
        $reason = 'hardware_absent_or_unreadable'
        $detail = "$($p.id) plane not measured"
        switch ($p.id) {
            'pci_config' {
                if (-not $Platform.elevated) { $reason = 'needs_elevation'; $detail = 'PCI config dump requires elevated PcLabHwMon' }
                else { $detail = 'No PCI config dumps this sample (display/storage functions)' }
            }
            'ec_board' {
                if (-not $Platform.elevated) { $reason = 'needs_elevation'; $detail = 'Board/EC sensors need elevated LHM Ring0' }
                else { $detail = 'No SuperIO/EC channels from LHM' }
            }
            'tpm' { $detail = 'No TPM reported - enable fTPM/PTT in firmware if available'; $reason = 'hardware_absent' }
            'me_psp' { $detail = 'No Intel MEI / AMD PSP PnP device matched'; $reason = 'hardware_absent_or_name_mismatch' }
            'smbios' { $detail = 'Raw SMBIOS tables unavailable'; $reason = 'os_only' }
            'uefi' { $detail = 'UEFI/Secure Boot state incomplete'; $reason = 'os_only' }
        }
        $gaps.Add(@{ plane = $p.id; reason = $reason; detail = $detail })
    }
    foreach ($g in @($Platform.uefi.gaps)) {
        $gaps.Add(@{ plane = 'uefi'; reason = $(if ($g.reason) { $g.reason } else { $g.code }); detail = $g.detail })
    }

    $capabilities = [System.Collections.Generic.List[string]]::new()
    $capabilities.Add('inventory')
    if ($Platform.smbios.available) { $capabilities.Add('smbios_decode') }
    if ($null -ne $Platform.uefi.secure_boot) { $capabilities.Add('secure_boot_audit') }
    if ($Platform.tpm.present) { $capabilities.Add('tpm_status') }
    if (@($Platform.storage | Where-Object { $_.is_nvme }).Count -gt 0) { $capabilities.Add('nvme_reliability') }
    if (@($Platform.pci_config).Count -gt 0) { $capabilities.Add('pci_config_dump') }
    if ($Platform.ec_board.count -gt 0) { $capabilities.Add('board_ec_sensors') }
    if ($Platform.elevated) { $capabilities.Add('elevated_ring0') }
    $capabilities.Add('adaptive_lab')
    $capabilities.Add('driver_action_plan')

    # Form factor hints for adaptive plan
    $chassisTypes = @()
    if ($Devices -and $Devices.firmware -and $Devices.firmware.system -and $Devices.firmware.system.chassis_types) {
        $chassisTypes = @($Devices.firmware.system.chassis_types)
    }
    $isLaptop = $false
    foreach ($c in $chassisTypes) {
        if ([int]$c -in 8, 9, 10, 11, 12, 14, 30, 31, 32) { $isLaptop = $true }
    }
    if ($Devices -and $Devices.battery -and @($Devices.battery).Count -gt 0) { $isLaptop = $true }

    $hasDiscreteGpu = $false
    if (@($Platform.pci_config).Count -gt 0) { $hasDiscreteGpu = $true }
    if ($Devices -and $Devices.pci) {
        foreach ($p in @($Devices.pci)) {
            $n = "$($p.name)$($p.Name)"
            if ($n -match 'NVIDIA|GeForce|Radeon|RX\s|Arc\sA') { $hasDiscreteGpu = $true }
        }
    }

    return @{
        id              = if ($hash) { $hash.Substring(0, 32) } else { $null }
        hash_sha256     = $hash
        coverage_score  = $coverage
        planes_measured = $measured
        planes_total    = $total
        gaps            = @($gaps)
        capabilities    = @($capabilities)
        form_factor     = if ($isLaptop) { 'laptop' } else { 'desktop' }
        has_discrete_gpu = $hasDiscreteGpu
        nvme_count      = @($Platform.storage | Where-Object { $_.is_nvme }).Count
        disk_count      = @($Platform.storage).Count
        elevated        = [bool]$Platform.elevated
        material_parts  = $parts.Count
        source          = 'platform_intelligence'
        confidence      = if ($coverage -ge 70) { 'high' } elseif ($coverage -ge 40) { 'medium' } else { 'low' }
        collected_at    = (Get-Date).ToUniversalTime().ToString('o')
    }
}
