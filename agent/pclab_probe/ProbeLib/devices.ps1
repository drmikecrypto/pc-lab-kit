. "$PSScriptRoot\common.ps1"

# ---------------------------------------------------------------------------
# Vendor ID tables (PCI / USB). Kept short and focused on what a PC assembler
# actually sees; unknown IDs fall back to "Vendor XXXX" so the tree stays complete.
# ---------------------------------------------------------------------------

$script:ProbePciVendors = @{
    '8086' = 'Intel'; '10de' = 'NVIDIA'; '1002' = 'AMD'; '1022' = 'AMD'
    '1b21' = 'ASMedia'; '1d6a' = 'Aquantia / Marvell'; '14e4' = 'Broadcom'
    '10ec' = 'Realtek'; '1969' = 'Atheros / Qualcomm'; '168c' = 'Qualcomm Atheros'
    '8087' = 'Intel'; '1a86' = 'QinHeng'; '0bda' = 'Realtek'
    '1b4b' = 'Marvell'; '144d' = 'Samsung'; '1179' = 'Toshiba'
    '15b7' = 'Sandisk / WD'; '1c5c' = 'SK Hynix'; 'c0a9' = 'Micron'
    '1cc1' = 'ADATA'; '1987' = 'Phison'; '1e4b' = 'MAXIO'
    '2646' = 'Kingston'; '1f75' = 'Innostor'; '1b96' = 'Nuvia / Qualcomm'
    '1043' = 'ASUS'; '1462' = 'MSI'; '1458' = 'Gigabyte'; '1849' = 'ASRock'
    '1d50' = 'OpenMoko'; '1028' = 'Dell'; '103c' = 'HP'; '17aa' = 'Lenovo'
    '0e11' = 'Compaq'; '1af4' = 'Red Hat VirtIO'; '15ad' = 'VMware'
    '80ee' = 'Oracle VirtualBox'; '1414' = 'Microsoft'
}

$script:ProbeUsbVendors = @{
    '046d' = 'Logitech'; '045e' = 'Microsoft'; '1532' = 'Razer'; '1038' = 'SteelSeries'
    '0951' = 'Kingston'; '0781' = 'SanDisk'; '0b05' = 'ASUS'; '174c' = 'ASMedia'
    '2109' = 'VIA Labs'; '05e3' = 'Genesys Logic'; '1a40' = 'Terminus'
    '0bda' = 'Realtek'; '8087' = 'Intel'; '0a5c' = 'Broadcom'
    '048d' = 'ITE Tech'; '0c45' = 'Microdia'; '1b1c' = 'Corsair'
    '2516' = 'Cooler Master'; '0d8c' = 'C-Media'; '041e' = 'Creative'
    '04b4' = 'Cypress'; '05ac' = 'Apple'
    '18d1' = 'Google'; '22d9' = 'OPPO'; '04e8' = 'Samsung'
    '054c' = 'Sony'; '057e' = 'Nintendo'; '28de' = 'Valve'
    '2f0a' = 'Wooting'; '320f' = 'Glorious'; '3434' = 'Keychron'
    '258a' = 'SINOWEALTH'; '1e7d' = 'ROCCAT'; '04d9' = 'Holtek'
    '0c7d' = 'Thermaltake'; '1462' = 'MSI'; '0db0' = 'Micro-Star'
}

function Get-ProbePciVendorName {
    param([string]$VendorId)
    $id = ("$VendorId").ToLower()
    if ($script:ProbePciVendors.ContainsKey($id)) { return $script:ProbePciVendors[$id] }
    return "PCI Vendor $id"
}

function Get-ProbeUsbVendorName {
    param([string]$VendorId)
    $id = ("$VendorId").ToLower()
    if ($script:ProbeUsbVendors.ContainsKey($id)) { return $script:ProbeUsbVendors[$id] }
    return "USB Vendor $id"
}

function ConvertFrom-PnpDeviceId {
    param([string]$InstanceId)

    $info = @{
        bus          = 'other'
        vendor_id    = $null
        device_id    = $null
        subsystem_id = $null
        revision     = $null
        vendor_name  = $null
        class_guid   = $null
        raw          = $InstanceId
    }
    if (-not $InstanceId) { return $info }

    $id = $InstanceId.ToUpper()
    if ($id -match '^PCI\\VEN_([0-9A-F]{4})&DEV_([0-9A-F]{4})') {
        $info.bus = 'pci'
        $info.vendor_id = $Matches[1].ToLower()
        $info.device_id = $Matches[2].ToLower()
        $info.vendor_name = Get-ProbePciVendorName $info.vendor_id
        if ($id -match 'SUBSYS_([0-9A-F]{8})') { $info.subsystem_id = $Matches[1].ToLower() }
        if ($id -match 'REV_([0-9A-F]{2})') { $info.revision = $Matches[1].ToLower() }
    } elseif ($id -match '^USB\\VID_([0-9A-F]{4})&PID_([0-9A-F]{4})') {
        $info.bus = 'usb'
        $info.vendor_id = $Matches[1].ToLower()
        $info.device_id = $Matches[2].ToLower()
        $info.vendor_name = Get-ProbeUsbVendorName $info.vendor_id
    } elseif ($id -match '^ACPI\\') {
        $info.bus = 'acpi'
    } elseif ($id -match '^SCSI\\|^IDE\\|^RAID\\') {
        $info.bus = 'storage'
    } elseif ($id -match '^DISPLAY\\') {
        $info.bus = 'display'
    } elseif ($id -match '^HID\\|^HIDCLASS\\') {
        $info.bus = 'hid'
    } elseif ($id -match '^SWD\\|^SW\\') {
        $info.bus = 'software'
    } elseif ($id -match '^ROOT\\') {
        $info.bus = 'root'
    }
    return $info
}

<#
 Map a PnP class to the PC-part category an assembler thinks in. Categories are
 intentionally coarse so the Devices tab can show "Motherboard / Chipset / Storage /
 Audio / Network / GPU / USB / HID / Monitor" without drowning the user in WMI noise.
#>
function Get-ProbeDeviceCategory {
    param([string]$Class, [string]$Name = "", [string]$InstanceId = "")

    $c = "$Class".ToLower()
    $n = "$Name".ToLower()
    $id = "$InstanceId".ToUpper()

    if ($c -in @('display','computer','processor')) {
        if ($n -match 'graphics|geforce|radeon|arc |vga|gpu') { return 'gpu' }
        if ($c -eq 'processor') { return 'cpu' }
        return 'system'
    }
    if ($c -in @('net','networkadapter')) { return 'network' }
    if ($c -in @('media','audioendpoint','sound','softwarecomponent') -or $n -match 'audio|sound|realtek|nahimic') { return 'audio' }
    if ($c -in @('diskdrive','hdc','scsiadapter','cdrom','volume','floppydisk')) { return 'storage' }
    if ($c -in @('monitor')) { return 'monitor' }
    if ($c -in @('keyboard','mouse','hidclass')) { return 'input' }
    if ($c -in @('usb','usbdevice','wpd','bluetooth','camera','image')) {
        if ($c -match 'bluetooth') { return 'wireless' }
        if ($c -match 'camera|image') { return 'camera' }
        return 'usb'
    }
    if ($c -in @('system','firmware','securitydevices','softwaredevice')) {
        if ($n -match 'chipset|pch|south|bridge|host bridge|root complex|SMBus|LPC') { return 'chipset' }
        if ($n -match 'management engine|amt|mei|psp|secure processor') { return 'firmware' }
        if ($n -match 'thunderbolt|usb4') { return 'thunderbolt' }
        return 'motherboard'
    }
    if ($c -match 'print') { return 'printer' }
    if ($id -match 'PCI\\VEN_') {
        if ($n -match 'ethernet|wifi|wireless|bluetooth') { return 'network' }
        if ($n -match 'nvme|ahci|sata|raid') { return 'storage' }
        if ($n -match 'audio|hd audio') { return 'audio' }
        if ($n -match 'vga|3d|display') { return 'gpu' }
        return 'pci'
    }
    return 'other'
}

function Get-ProbeConfigManagerMessage {
    param([int]$Code)

    $map = @{
        0  = 'OK'
        1  = 'Device is not configured correctly'
        10 = 'Device cannot start'
        12 = 'This device cannot find enough free resources'
        14 = 'Device requires a restart'
        18 = 'Reinstall the drivers for this device'
        19 = 'Windows cannot start this hardware device'
        22 = 'Device is disabled'
        24 = 'Device is not present, not working, or does not have drivers'
        28 = 'Drivers for this device are not installed'
        31 = 'Windows cannot load the device driver'
        32 = 'A driver for this device was disabled'
        33 = 'Windows cannot determine which resources are required'
        37 = 'Windows cannot initialize the device driver'
        39 = 'Windows cannot load the device driver (corrupt or missing)'
        43 = 'Windows has stopped this device because it has reported problems'
        45 = 'Device is not connected'
        48 = 'The software for this device has been blocked'
        52 = 'Windows cannot verify the digital signature of the drivers'
    }
    if ($map.ContainsKey($Code)) { return $map[$Code] }
    return "Config Manager code $Code"
}

# ---------------------------------------------------------------------------
# Inventory collectors
# ---------------------------------------------------------------------------

function Get-ProbePnpInventory {
    $devices = @()
    $problem = @()
    $driverless = @()
    $byCategory = @{}

    $raw = @()
    try {
        # Get-PnpDevice is faster and richer than Win32_PnPEntity, and it is what
        # Device Manager itself uses. Fall back to CIM if the module is missing.
        $raw = @(Get-PnpDevice -PresentOnly -ErrorAction Stop)
    } catch {
        $raw = @(Get-CimSafe "Win32_PnPEntity" | Where-Object { $_.Present -eq $true })
    }

    foreach ($d in $raw) {
        $instanceId = if ($d.InstanceId) { "$($d.InstanceId)" } elseif ($d.PNPDeviceID) { "$($d.PNPDeviceID)" } else { "$($d.DeviceID)" }
        $name = if ($d.FriendlyName) { "$($d.FriendlyName)" } else { "$($d.Name)" }
        if (-not $name) { continue }

        $class = if ($d.Class) { "$($d.Class)" } elseif ($d.PNPClass) { "$($d.PNPClass)" } else { 'Unknown' }
        $status = if ($d.Status) { "$($d.Status)" } else { 'Unknown' }
        $problemCode = 0
        if ($null -ne $d.ConfigManagerErrorCode) { $problemCode = [int]$d.ConfigManagerErrorCode }
        elseif ($null -ne $d.Problem) { $problemCode = [int]$d.Problem }

        $parsed = ConvertFrom-PnpDeviceId $instanceId
        $category = Get-ProbeDeviceCategory -Class $class -Name $name -InstanceId $instanceId

        $entry = @{
            name            = $name
            class           = $class
            category        = $category
            status          = $status
            problem_code    = $problemCode
            problem_message = Get-ProbeConfigManagerMessage $problemCode
            instance_id     = $instanceId
            manufacturer    = if ($d.Manufacturer) { "$($d.Manufacturer)" } else { $parsed.vendor_name }
            bus             = $parsed.bus
            vendor_id       = $parsed.vendor_id
            device_id       = $parsed.device_id
            subsystem_id    = $parsed.subsystem_id
            vendor_name     = $parsed.vendor_name
            service         = if ($d.Service) { "$($d.Service)" } else { $null }
            present         = $true
        }

        # "Unknown device" with code 28 is the classic missing-driver case that
        # assemblers burn hours on. Surface it loudly.
        $isDriverless = ($problemCode -in @(28, 1, 31, 39, 52)) -or ($name -match 'Unknown device|PCI Simple Communications|SM Bus Controller' -and $problemCode -ne 0)
        $entry.needs_driver = $isDriverless
        $entry.has_problem  = ($problemCode -ne 0 -and $problemCode -ne 22)

        $devices += $entry
        if (-not $byCategory.ContainsKey($category)) { $byCategory[$category] = @() }
        $byCategory[$category] += $entry

        if ($entry.has_problem) { $problem += $entry }
        if ($isDriverless) { $driverless += $entry }
    }

    $counts = @{}
    foreach ($k in $byCategory.Keys) { $counts[$k] = @($byCategory[$k]).Count }

    return @{
        total          = $devices.Count
        problem_count  = $problem.Count
        driverless_count = $driverless.Count
        counts         = $counts
        by_category    = $byCategory
        problem        = @($problem | Sort-Object { $_.problem_code } -Descending)
        driverless     = @($driverless)
        devices        = @($devices)
    }
}

function Get-ProbePciDevices {
    $list = @()
    foreach ($d in @(Get-CimSafe "Win32_PnPEntity" | Where-Object { $_.PNPDeviceID -match '^PCI\\' })) {
        $parsed = ConvertFrom-PnpDeviceId "$($d.PNPDeviceID)"
        $list += @{
            name         = "$($d.Name)"
            manufacturer = "$($d.Manufacturer)"
            vendor_id    = $parsed.vendor_id
            device_id    = $parsed.device_id
            subsystem_id = $parsed.subsystem_id
            revision     = $parsed.revision
            vendor_name  = $parsed.vendor_name
            status       = "$($d.Status)"
            problem_code = [int]$d.ConfigManagerErrorCode
            instance_id  = "$($d.PNPDeviceID)"
            class_guid   = "$($d.ClassGuid)"
        }
    }
    return @($list | Sort-Object { $_.vendor_name }, { $_.name })
}

function Get-ProbeUsbTree {
    $controllers = @()
    foreach ($c in @(Get-CimSafe "Win32_USBController")) {
        $controllers += @{
            name         = "$($c.Name)"
            manufacturer = "$($c.Manufacturer)"
            status       = "$($c.Status)"
            device_id    = "$($c.DeviceID)"
            pnp_id       = "$($c.PNPDeviceID)"
        }
    }

    $hubs = @()
    foreach ($h in @(Get-CimSafe "Win32_USBHub")) {
        $hubs += @{
            name         = "$($h.Name)"
            status       = "$($h.Status)"
            device_id    = "$($h.DeviceID)"
            pnp_id       = "$($h.PNPDeviceID)"
        }
    }

    $devices = @()
    try {
        foreach ($d in @(Get-PnpDevice -Class USB -PresentOnly -ErrorAction SilentlyContinue)) {
            $parsed = ConvertFrom-PnpDeviceId "$($d.InstanceId)"
            $devices += @{
                name        = "$($d.FriendlyName)"
                status      = "$($d.Status)"
                instance_id = "$($d.InstanceId)"
                vendor_id   = $parsed.vendor_id
                product_id  = $parsed.device_id
                vendor_name = $parsed.vendor_name
                class       = "$($d.Class)"
            }
        }
    } catch {
        foreach ($d in @(Get-CimSafe "Win32_PnPEntity" | Where-Object { $_.PNPDeviceID -match '^USB\\' })) {
            $parsed = ConvertFrom-PnpDeviceId "$($d.PNPDeviceID)"
            $devices += @{
                name        = "$($d.Name)"
                status      = "$($d.Status)"
                instance_id = "$($d.PNPDeviceID)"
                vendor_id   = $parsed.vendor_id
                product_id  = $parsed.device_id
                vendor_name = $parsed.vendor_name
            }
        }
    }

    return @{
        controllers = @($controllers)
        hubs        = @($hubs)
        devices     = @($devices)
        device_count = $devices.Count
    }
}

function Get-ProbeMonitors {
    $list = @()
    foreach ($m in @(Get-CimSafe "WmiMonitorID" -Namespace "root\wmi")) {
        $decode = {
            param($arr)
            if (-not $arr) { return $null }
            $chars = @()
            foreach ($b in $arr) {
                if ($b -eq 0) { break }
                $chars += [char]$b
            }
            return (-join $chars).Trim()
        }
        $name = & $decode $m.UserFriendlyName
        $mfr  = & $decode $m.ManufacturerName
        $serial = & $decode $m.SerialNumberID
        $list += @{
            name         = if ($name) { $name } else { 'Display' }
            manufacturer = $mfr
            serial       = $serial
            year         = $m.YearOfManufacture
            week         = $m.WeekOfManufacture
            active       = [bool]$m.Active
            instance_name = "$($m.InstanceName)"
        }
    }

    # Resolution / refresh from the video controller connection.
    $modes = @()
    foreach ($v in @(Get-CimSafe "Win32_VideoController")) {
        if (-not $v.CurrentHorizontalResolution) { continue }
        $modes += @{
            adapter      = "$($v.Name)"
            width        = [int]$v.CurrentHorizontalResolution
            height       = [int]$v.CurrentVerticalResolution
            refresh_hz   = [int]$v.CurrentRefreshRate
            bits_per_pixel = [int]$v.CurrentBitsPerPixel
        }
    }

    return @{
        displays = @($list)
        modes    = @($modes)
        count    = $list.Count
    }
}

function Get-ProbeAudioDevices {
    $list = @()
    try {
        foreach ($d in @(Get-PnpDevice -Class MEDIA -PresentOnly -ErrorAction SilentlyContinue)) {
            $list += @{
                name        = "$($d.FriendlyName)"
                status      = "$($d.Status)"
                instance_id = "$($d.InstanceId)"
                manufacturer = "$($d.Manufacturer)"
                class       = 'MEDIA'
            }
        }
    } catch {}
    foreach ($d in @(Get-CimSafe "Win32_SoundDevice")) {
        $list += @{
            name         = "$($d.Name)"
            status       = "$($d.Status)"
            manufacturer = "$($d.Manufacturer)"
            product_name = "$($d.ProductName)"
            class        = 'Sound'
        }
    }
    # Deduplicate by name.
    $seen = @{}
    $out = @()
    foreach ($d in $list) {
        $k = "$($d.name)".ToLower()
        if ($seen.ContainsKey($k)) { continue }
        $seen[$k] = $true
        $out += $d
    }
    return @($out)
}

function Get-ProbeBluetoothDevices {
    $list = @()
    try {
        foreach ($d in @(Get-PnpDevice -Class Bluetooth -PresentOnly -ErrorAction SilentlyContinue)) {
            $list += @{
                name        = "$($d.FriendlyName)"
                status      = "$($d.Status)"
                instance_id = "$($d.InstanceId)"
            }
        }
    } catch {}
    return @($list)
}

function Get-ProbeSystemSlots {
    $slots = @()
    foreach ($s in @(Get-CimSafe "Win32_SystemSlot")) {
        $slots += @{
            name         = "$($s.Name)"
            slot_designation = "$($s.SlotDesignation)"
            status       = "$($s.Status)"
            current_usage = "$($s.CurrentUsage)"  # 3=Available, 4=In use
            max_data_width = $s.MaxDataWidth
            length       = "$($s.Length)"
            connector_type = @($s.ConnectorType)
            supports_hot_plug = [bool]$s.SupportsHotPlug
        }
    }
    return @($slots)
}

function Get-ProbePorts {
    $ports = @()
    foreach ($p in @(Get-CimSafe "Win32_PortConnector")) {
        $ports += @{
            name            = "$($p.ExternalReferenceDesignator)"
            internal_ref    = "$($p.InternalReferenceDesignator)"
            connector_type  = @($p.ConnectorType)
            port_type       = "$($p.PortType)"
            status          = "$($p.Status)"
        }
    }
    return @($ports)
}

function Get-ProbeBatteryDetail {
    $list = @()
    foreach ($b in @(Get-CimSafe "Win32_Battery")) {
        $design = [int]$b.DesignCapacity
        $full = [int]$b.FullChargeCapacity
        $health = $null
        if ($design -gt 0 -and $full -gt 0) { $health = [math]::Round(100.0 * $full / $design, 1) }
        $list += @{
            name              = "$($b.Name)"
            chemistry         = "$($b.Chemistry)"
            design_capacity   = $design
            full_capacity     = $full
            health_percent    = $health
            estimated_charge  = $b.EstimatedChargeRemaining
            status            = "$($b.Status)"
            battery_status    = $b.BatteryStatus
        }
    }
    # Enrich with modern battery static data when available.
    try {
        foreach ($s in @(Get-CimSafe "BatteryStaticData" -Namespace "root\wmi")) {
            if ($list.Count -gt 0) {
                $list[0].designed_capacity_mwh = $s.DesignedCapacity
                $list[0].manufacture_name = & {
                    if ($s.ManufactureName) { [Text.Encoding]::ASCII.GetString($s.ManufactureName).Trim([char]0) }
                }
            }
        }
        foreach ($f in @(Get-CimSafe "BatteryFullChargedCapacity" -Namespace "root\wmi")) {
            if ($list.Count -gt 0 -and $f.FullChargedCapacity) {
                $list[0].full_charged_capacity_mwh = $f.FullChargedCapacity
                if ($list[0].designed_capacity_mwh -gt 0) {
                    $list[0].health_percent = [math]::Round(100.0 * $f.FullChargedCapacity / $list[0].designed_capacity_mwh, 1)
                }
            }
        }
    } catch {}
    return @($list)
}

function Get-ProbeFirmwareInfo {
    $bios = Get-CimSafe "Win32_BIOS" | Select-Object -First 1
    $bb = Get-CimSafe "Win32_BaseBoard" | Select-Object -First 1
    $cs = Get-CimSafe "Win32_ComputerSystem" | Select-Object -First 1
    $enc = Get-CimSafe "Win32_SystemEnclosure" | Select-Object -First 1
    $tpm = $null
    try {
        $t = Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction SilentlyContinue
        if ($t) {
            $tpm = @{
                present           = $true
                enabled           = [bool]$t.IsEnabled_InitialValue
                activated         = [bool]$t.IsActivated_InitialValue
                owned             = [bool]$t.IsOwned_InitialValue
                spec_version      = "$($t.SpecVersion)"
                manufacturer_id   = "$($t.ManufacturerIdTxt)"
                manufacturer_version = "$($t.ManufacturerVersion)"
            }
        }
    } catch {}

    $secureBoot = $null
    try {
        $secureBoot = [bool](Confirm-SecureBootUEFI -ErrorAction SilentlyContinue)
    } catch {
        try {
            $v = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction SilentlyContinue
            if ($null -ne $v.UEFISecureBootEnabled) { $secureBoot = [bool]$v.UEFISecureBootEnabled }
        } catch {}
    }

    return @{
        bios = @{
            vendor  = "$($bios.Manufacturer)"
            version = "$($bios.SMBIOSBIOSVersion)"
            date    = "$($bios.ReleaseDate)"
            serial  = "$($bios.SerialNumber)"
            smbios_major = $bios.SMBIOSMajorVersion
            smbios_minor = $bios.SMBIOSMinorVersion
        }
        board = @{
            manufacturer = "$($bb.Manufacturer)"
            product      = "$($bb.Product)"
            version      = "$($bb.Version)"
            serial       = "$($bb.SerialNumber)"
            tag          = "$($bb.Tag)"
        }
        system = @{
            manufacturer = "$($cs.Manufacturer)"
            model        = "$($cs.Model)"
            sku          = "$($cs.SystemSKUNumber)"
            family       = "$($cs.SystemFamily)"
            domain       = "$($cs.Domain)"
            chassis_types = @($enc.ChassisTypes)
        }
        tpm = if ($tpm) { $tpm } else { @{ present = $false } }
        secure_boot = $secureBoot
    }
}

<#
 Public entry: everything that is physically or logically part of this PC,
 organised the way an assembler walks a build.
#>
function Get-ProbeDeviceInventory {
    $pnp = Get-ProbePnpInventory
    $firmware = Get-ProbeFirmwareInfo
    $monitors = Get-ProbeMonitors
    $usb = Get-ProbeUsbTree
    $audio = Get-ProbeAudioDevices
    $bt = Get-ProbeBluetoothDevices
    $slots = Get-ProbeSystemSlots
    $ports = Get-ProbePorts
    $battery = Get-ProbeBatteryDetail
    $pci = Get-ProbePciDevices

    $findings = @()
    if ($pnp.driverless_count -gt 0) {
        $findings += @{
            severity = 'critical'
            code     = 'devices_missing_drivers'
            title    = "$($pnp.driverless_count) device(s) have no working driver"
            detail   = 'Open the Drivers tab for install links. Typical post-build culprits: chipset, LAN, Wi-Fi, audio, Bluetooth, and the GPU.'
            devices  = @($pnp.driverless | Select-Object -First 8 | ForEach-Object { $_.name })
        }
    }
    if ($pnp.problem_count -gt $pnp.driverless_count) {
        $extra = $pnp.problem_count - $pnp.driverless_count
        $findings += @{
            severity = 'warn'
            code     = 'devices_with_errors'
            title    = "$extra additional device(s) report errors"
            detail   = 'Code 43 / 10 often means a bad PCIe seat, insufficient power, or a conflicting vendor utility. Reseat the card before chasing drivers.'
        }
    }
    if (-not $firmware.tpm.present) {
        $findings += @{
            severity = 'info'
            code     = 'tpm_missing'
            title    = 'No TPM detected'
            detail   = 'Windows 11 needs TPM 2.0. Enable fTPM (AMD) or PTT (Intel) in BIOS if the silicon supports it.'
        }
    }

    return @{
        summary = @{
            total_devices    = $pnp.total
            problem_devices  = $pnp.problem_count
            driverless       = $pnp.driverless_count
            usb_devices      = $usb.device_count
            monitors         = $monitors.count
            pci_devices      = $pci.Count
            audio_devices    = $audio.Count
            bluetooth        = $bt.Count
            system_slots     = $slots.Count
            categories       = $pnp.counts
        }
        firmware     = $firmware
        motherboard  = $firmware.board
        bios         = $firmware.bios
        tpm          = $firmware.tpm
        secure_boot  = $firmware.secure_boot
        monitors     = $monitors
        usb          = $usb
        audio        = @($audio)
        bluetooth    = @($bt)
        pci          = @($pci)
        system_slots = @($slots)
        ports        = @($ports)
        battery      = @($battery)
        problem      = @($pnp.problem)
        driverless   = @($pnp.driverless)
        by_category  = $pnp.by_category
        findings     = @($findings)
        # Full dump is large; keep it available for the geek tab / export.
        all_devices  = @($pnp.devices)
    }
}
