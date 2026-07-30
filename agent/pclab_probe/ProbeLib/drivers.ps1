. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\thermal.ps1"

# ---------------------------------------------------------------------------
# Fresh-install order an assembler should follow. Chipset before GPU matters:
# without the chipset package the PCIe root ports and USB controllers stay on
# generic Microsoft drivers and the GPU install can fail to bind correctly.
# ---------------------------------------------------------------------------

$script:ProbeDriverInstallOrder = @(
    @{ id = 'chipset';     label = 'Chipset / ME / PSP';       why = 'Unlocks PCIe lanes, USB, NVMe and power management before anything else.' }
    @{ id = 'storage';     label = 'Storage (NVMe / RAID)';    why = 'Only needed when Windows Setup could not see the drive.' }
    @{ id = 'gpu';         label = 'GPU (NVIDIA / AMD / Intel)'; why = 'Biggest stability and performance win. Use DDU in Safe Mode when switching vendors.' }
    @{ id = 'audio';       label = 'Audio (Realtek / vendor)';  why = 'Board-vendor package, not the generic Microsoft HD Audio driver.' }
    @{ id = 'network';    label = 'LAN / Wi-Fi / Bluetooth';  why = 'So the machine can reach Windows Update and vendor sites for the rest.' }
    @{ id = 'usb';         label = 'USB / Thunderbolt / USB4';  why = 'Type-C PD, docks, and eGPU need the vendor stack.' }
    @{ id = 'laptop_oem';  label = 'Laptop OEM package';       why = 'Hotkeys, battery thresholds, and custom ACPI. Desktops can skip this.' }
    @{ id = 'peripherals'; label = 'Mouse / Keyboard / RGB';    why = 'Optional vendor software last, after the system is stable.' }
)

function Get-ProbeDriverAgeDays {
    param($DriverDate)
    if (-not $DriverDate) { return $null }
    try {
        $dt = [datetime]$DriverDate
        return [int]([datetime]::UtcNow - $dt.ToUniversalTime()).TotalDays
    } catch { return $null }
}

function Test-ProbeGenericDriver {
    param([string]$Provider, [string]$InfName, [string]$DeviceName = "")

    $p = "$Provider".ToLower()
    $inf = "$InfName".ToLower()
    $n = "$DeviceName".ToLower()

    if ($p -match 'microsoft' -and $inf -match 'usb\.inf|usbport\.inf|hdaudio\.inf|netadapter\.inf|basicdisplay|basicrender|monitor\.inf') {
        return $true
    }
    if ($n -match 'microsoft basic display|microsoft basic render|standard sata ahci|generic usb|usb composite device') {
        return $true
    }
    # A Realtek / Killer / Intel NIC still on netadapterx.inf is the classic
    # "Windows Update gave me something that works but is not the vendor package".
    if ($p -match 'microsoft' -and $n -match 'realtek|killer|intel\(r\) ethernet|intel\(r\) wi-fi|qualcomm|atheros|broadcom') {
        return $true
    }
    return $false
}

function Get-ProbeVendorDriverLinks {
    param(
        [string]$Category,
        [string]$VendorTag,
        [string]$DeviceName = "",
        [string]$BoardMfr = "",
        [string]$BoardProduct = "",
        [string]$SystemMfr = "",
        [string]$SystemModel = ""
    )

    $links = @()
    $v = "$VendorTag".ToLower()
    $board = "$BoardMfr".ToLower()
    $sys = "$SystemMfr".ToLower()

    switch ($Category) {
        'gpu' {
            if ($v -eq 'nvidia' -or $DeviceName -match 'NVIDIA|GeForce|RTX|GTX') {
                $links += @{ label = 'NVIDIA App / Game Ready'; url = 'https://www.nvidia.com/Download/index.aspx'; note = 'Or use NVIDIA App for auto updates.' }
                $links += @{ label = 'DDU (clean uninstall)'; url = 'https://www.wagnardsoft.com/'; note = 'Use in Safe Mode when switching AMD <-> NVIDIA.' }
            }
            if ($v -eq 'amd' -or $DeviceName -match 'AMD|Radeon') {
                $links += @{ label = 'AMD Software: Adrenalin'; url = 'https://www.amd.com/en/support'; note = 'Factory Reset install recommended on a fresh build.' }
            }
            if ($v -eq 'intel' -or $DeviceName -match 'Intel.*Arc|UHD|Iris') {
                $links += @{ label = 'Intel Arc / Graphics'; url = 'https://www.intel.com/content/www/us/en/download/785597/intel-arc-iris-xe-graphics-windows.html'; note = 'Also covers UHD / Iris Xe.' }
            }
        }
        'chipset' {
            if ($board -match 'asus' -or $sys -match 'asus') {
                $links += @{ label = 'ASUS Support'; url = 'https://www.asus.com/support/'; note = 'Enter the board model for chipset + LAN + audio bundle.' }
            } elseif ($board -match 'msi|micro-star' -or $sys -match 'msi|micro-star') {
                $links += @{ label = 'MSI Support'; url = 'https://www.msi.com/support'; note = 'Chipset + LAN + audio under Drivers.' }
            } elseif ($board -match 'gigabyte|aorus' -or $sys -match 'gigabyte|aorus') {
                $links += @{ label = 'Gigabyte Support'; url = 'https://www.gigabyte.com/Support'; note = 'Download the chipset package for your board.' }
            } elseif ($board -match 'asrock' -or $sys -match 'asrock') {
                $links += @{ label = 'ASRock Support'; url = 'https://www.asrock.com/support/'; note = 'Chipset first, then LAN / audio.' }
            } elseif ($board -match 'biostar') {
                $links += @{ label = 'BIOSTAR Support'; url = 'https://www.biostar.com.tw/app/en/support/index.php' }
            }
            # Always offer the silicon vendor as a fallback when the board page is unclear.
            if ($v -eq 'amd' -or $DeviceName -match 'AMD|Ryzen') {
                $links += @{ label = 'AMD Chipset Drivers'; url = 'https://www.amd.com/en/support/download/drivers.html'; note = 'Required for Ryzen USB / NVMe power management.' }
            } else {
                $links += @{ label = 'Intel Chipset INF'; url = 'https://www.intel.com/content/www/us/en/download/19347/chipset-inf-utility.html'; note = 'Plus Intel MEI / Serial IO from the same support page.' }
            }
        }
        'audio' {
            if ($board -match 'asus|msi|gigabyte|asrock' -or $sys -match 'asus|msi|gigabyte|asrock') {
                $links += @{ label = 'Board audio package'; url = 'https://www.realtek.com/Download/List?cate_id=597'; note = 'Prefer the package from your motherboard support page over the Realtek generic.' }
            } else {
                $links += @{ label = 'Realtek Audio'; url = 'https://www.realtek.com/Download/List?cate_id=597' }
            }
        }
        'network' {
            if ($DeviceName -match 'Realtek') {
                $links += @{ label = 'Realtek PCIe / USB NIC'; url = 'https://www.realtek.com/Download/List?cate_id=584' }
            }
            if ($DeviceName -match 'Intel') {
                $links += @{ label = 'Intel Ethernet / Wi-Fi'; url = 'https://www.intel.com/content/www/us/en/download-center/home.html' }
            }
            if ($DeviceName -match 'Killer') {
                $links += @{ label = 'Killer Networking'; url = 'https://www.killernetworking.com/driver-downloads/' }
            }
            if ($DeviceName -match 'MediaTek|MT79|RZ616|RZ608') {
                $links += @{ label = 'MediaTek Wi-Fi'; url = 'https://www.mediatek.com/products/broadband-wifi' }
            }
            if ($DeviceName -match 'Qualcomm|Atheros|QCN|QCA') {
                $links += @{ label = 'Qualcomm Wi-Fi / BT'; url = 'https://www.qualcomm.com/support' }
            }
            if ($links.Count -eq 0) {
                $links += @{ label = 'Board LAN / Wi-Fi package'; url = 'https://www.asus.com/support/'; note = 'Use your motherboard or laptop support page.' }
            }
        }
        'storage' {
            $links += @{ label = 'Intel RST / VMD'; url = 'https://www.intel.com/content/www/us/en/download/19512/intel-rapid-storage-technology-driver-installation-software-with-intel-optane-memory-32-bit-64-bit-for-windows-10-and-windows-11.html' }
            $links += @{ label = 'AMD RAID / Ryzen storage'; url = 'https://www.amd.com/en/support' }
        }
        'laptop_oem' {
            if ($sys -match 'dell') { $links += @{ label = 'Dell SupportAssist'; url = 'https://www.dell.com/support/home' } }
            elseif ($sys -match 'hp|hewlett') { $links += @{ label = 'HP Support'; url = 'https://support.hp.com/' } }
            elseif ($sys -match 'lenovo') { $links += @{ label = 'Lenovo Vantage / Support'; url = 'https://support.lenovo.com/' } }
            elseif ($sys -match 'asus') { $links += @{ label = 'MyASUS / Support'; url = 'https://www.asus.com/support/' } }
            elseif ($sys -match 'msi|micro-star') { $links += @{ label = 'MSI Center / Support'; url = 'https://www.msi.com/support' } }
            elseif ($sys -match 'gigabyte|aorus') { $links += @{ label = 'Gigabyte Control Center'; url = 'https://www.gigabyte.com/Support' } }
            elseif ($sys -match 'acer') { $links += @{ label = 'Acer Support'; url = 'https://www.acer.com/support' } }
            else { $links += @{ label = 'OEM support'; url = 'https://support.microsoft.com/' } }
        }
        default {
            $links += @{ label = 'Windows Update drivers'; url = 'ms-settings:windowsupdate'; note = 'Optional updates often hide OEM drivers.' }
        }
    }
    return @($links)
}

function Get-ProbeInstalledDrivers {
    $list = @()
    try {
        # Get-WindowsDriver -Online needs admin for the full store; without elevation
        # it still returns the third-party set which is what we care about.
        $drivers = @(Get-WindowsDriver -Online -ErrorAction SilentlyContinue)
        foreach ($d in $drivers) {
            if ($d.ProviderName -match '^Microsoft' -and $d.ClassName -notmatch 'Display|Net|MEDIA|HDC|USB|Bluetooth|System') {
                continue
            }
            $age = Get-ProbeDriverAgeDays $d.Date
            $list += @{
                class        = "$($d.ClassName)"
                class_guid   = "$($d.ClassGuid)"
                provider     = "$($d.ProviderName)"
                version      = "$($d.Version)"
                date         = if ($d.Date) { $d.Date.ToString('yyyy-MM-dd') } else { $null }
                age_days     = $age
                inf          = "$($d.Driver)"
                original_name = "$($d.OriginalFileName)"
                boot_critical = [bool]$d.BootCritical
                inbox        = [bool]$d.Inbox
            }
        }
    } catch {}
    return @($list)
}

function Get-ProbeDeviceDrivers {
    $list = @()
    try {
        # pnputil /enum-devices /drivers is Win10 2004+ and gives the live binding.
        $raw = & pnputil.exe /enum-devices /drivers 2>$null
        if (-not $raw) { return @() }
        $block = @{}
        foreach ($line in @($raw)) {
            if ($line -match '^\s*$') {
                if ($block.InstanceId) { $list += $block.Clone(); $block = @{} }
                continue
            }
            if ($line -match 'Instance ID:\s*(.+)$') { $block.InstanceId = $Matches[1].Trim(); continue }
            if ($line -match 'Device Description:\s*(.+)$') { $block.Name = $Matches[1].Trim(); continue }
            if ($line -match 'Class Name:\s*(.+)$') { $block.Class = $Matches[1].Trim(); continue }
            if ($line -match 'Driver Name:\s*(.+)$') { $block.Inf = $Matches[1].Trim(); continue }
            if ($line -match 'Driver Version:\s*(.+)$') { $block.Version = $Matches[1].Trim(); continue }
            if ($line -match 'Driver Date:\s*(.+)$') { $block.Date = $Matches[1].Trim(); continue }
            if ($line -match 'Provider Name:\s*(.+)$') { $block.Provider = $Matches[1].Trim(); continue }
            if ($line -match 'Status:\s*(.+)$') { $block.Status = $Matches[1].Trim(); continue }
            if ($line -match 'Problem Code:\s*(.+)$') { $block.ProblemCode = $Matches[1].Trim(); continue }
        }
        if ($block.InstanceId) { $list += $block }
    } catch {}

    # Enrich with CIM manufacturer when pnputil did not give a provider.
    $out = @()
    foreach ($d in $list) {
        $age = Get-ProbeDriverAgeDays $d.Date
        $generic = Test-ProbeGenericDriver -Provider $d.Provider -InfName $d.Inf -DeviceName $d.Name
        $out += @{
            name         = $d.Name
            class        = $d.Class
            instance_id  = $d.InstanceId
            provider     = $d.Provider
            version      = $d.Version
            date         = $d.Date
            age_days     = $age
            inf          = $d.Inf
            status       = $d.Status
            problem_code = $d.ProblemCode
            is_generic   = $generic
            is_stale     = ($null -ne $age -and $age -gt 365)
            is_very_stale = ($null -ne $age -and $age -gt 730)
        }
    }
    return @($out)
}

function Get-ProbeGpuDriverStatus {
    $gpus = @()
    foreach ($g in @(Get-CimSafe "Win32_VideoController" | Where-Object { $_.Name -and $_.Name -notmatch 'Microsoft Basic' })) {
        $vendor = Get-ProbeVendorTag -Name "$($g.Name)"
        $age = Get-ProbeDriverAgeDays $g.DriverDate
        $generic = ("$($g.Name)" -match 'Microsoft Basic') -or ("$($g.DriverVersion)" -eq '')
        $entry = @{
            name         = "$($g.Name)".Trim()
            vendor       = $vendor
            driver       = "$($g.DriverVersion)"
            driver_date  = if ($g.DriverDate) { ([datetime]$g.DriverDate).ToString('yyyy-MM-dd') } else { $null }
            age_days     = $age
            pnp_device_id = "$($g.PNPDeviceID)"
            status       = "$($g.Status)"
            is_generic   = $generic
            is_stale     = ($null -ne $age -and $age -gt 180)   # GPU drivers move fast
            is_integrated = ("$($g.Name)" -match 'UHD|Iris|Vega \d|Radeon\(TM\) Graphics')
            links        = @(Get-ProbeVendorDriverLinks -Category 'gpu' -VendorTag $vendor -DeviceName "$($g.Name)")
        }
        if ($vendor -eq 'nvidia') {
            $smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
            if ($smi) {
                try {
                    $ver = (& nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits 2>$null | Select-Object -First 1)
                    if ($ver) { $entry.nvidia_smi_version = "$ver".Trim() }
                } catch {}
            }
            # NVIDIA App / GeForce Experience install markers.
            $nvApp = Test-Path 'HKLM:\SOFTWARE\NVIDIA Corporation\NVIDIA App'
            $gfe = Test-Path 'HKLM:\SOFTWARE\NVIDIA Corporation\Global\GFExperience'
            $entry.updater_installed = ($nvApp -or $gfe)
            $entry.updater_name = if ($nvApp) { 'NVIDIA App' } elseif ($gfe) { 'GeForce Experience' } else { $null }
        } elseif ($vendor -eq 'amd') {
            $amd = Get-ItemProperty 'HKLM:\SOFTWARE\AMD\CN' -ErrorAction SilentlyContinue
            $entry.updater_installed = [bool]$amd
            $entry.updater_name = if ($amd) { 'AMD Adrenalin' } else { $null }
            if ($amd.RadeonSoftwareVersion) { $entry.radeon_software_version = "$($amd.RadeonSoftwareVersion)" }
        } elseif ($vendor -eq 'intel') {
            $entry.updater_installed = Test-Path 'HKLM:\SOFTWARE\Intel\Display'
            $entry.updater_name = if ($entry.updater_installed) { 'Intel Arc Control / Graphics' } else { $null }
        }
        $gpus += $entry
    }
    return @($gpus)
}

function Get-ProbeWindowsUpdateDriverCandidates {
    # pnputil /scan-devices triggers a re-enumeration; /enum-devices /problem
    # already covers most of what an assembler needs without waiting on WU.
    $out = @{
        available = $false
        note = 'Windows Update driver scan is optional and can take minutes. Use vendor links for a fresh build.'
        problem_devices = @()
    }
    try {
        $raw = & pnputil.exe /enum-devices /problem 2>$null
        if ($raw) {
            $out.available = $true
            $block = @{}
            $list = @()
            foreach ($line in @($raw)) {
                if ($line -match '^\s*$') {
                    if ($block.InstanceId) { $list += $block.Clone(); $block = @{} }
                    continue
                }
                if ($line -match 'Instance ID:\s*(.+)$') { $block.InstanceId = $Matches[1].Trim(); continue }
                if ($line -match 'Device Description:\s*(.+)$') { $block.Name = $Matches[1].Trim(); continue }
                if ($line -match 'Problem Name:\s*(.+)$') { $block.Problem = $Matches[1].Trim(); continue }
                if ($line -match 'Problem Code:\s*(.+)$') { $block.Code = $Matches[1].Trim(); continue }
            }
            if ($block.InstanceId) { $list += $block }
            $out.problem_devices = @($list)
        }
    } catch {
        $out.error = $_.Exception.Message
    }
    return $out
}

function New-ProbeDriverAction {
    param(
        [string]$Severity,
        [string]$Code,
        [string]$Title,
        [string]$Detail,
        [string]$Category,
        [string]$VendorTag = 'unknown',
        [string]$DeviceName = "",
        [string]$BoardMfr = "",
        [string]$BoardProduct = "",
        [string]$SystemMfr = "",
        [string]$SystemModel = "",
        [int]$Priority = 50
    )

    return @{
        severity   = $Severity
        code       = $Code
        title      = $Title
        detail     = $Detail
        category   = $Category
        priority   = $Priority
        device     = $DeviceName
        links      = @(Get-ProbeVendorDriverLinks -Category $Category -VendorTag $VendorTag -DeviceName $DeviceName `
                        -BoardMfr $BoardMfr -BoardProduct $BoardProduct -SystemMfr $SystemMfr -SystemModel $SystemModel)
    }
}

<#
 Build the action list an assembler wants on a fresh Windows install: what is
 missing, what is generic, what is stale, and the order to install it in.
#>
function Get-ProbeDriverAdvice {
    param($DeviceInventory = $null)

    $board = Get-CimSafe "Win32_BaseBoard" | Select-Object -First 1
    $cs = Get-CimSafe "Win32_ComputerSystem" | Select-Object -First 1
    $cpu = Get-CimSafe "Win32_Processor" | Select-Object -First 1
    $boardMfr = "$($board.Manufacturer)"
    $boardProduct = "$($board.Product)"
    $sysMfr = "$($cs.Manufacturer)"
    $sysModel = "$($cs.Model)"
    $cpuVendor = Get-ProbeVendorTag -Name "$($cpu.Name)"
    $isLaptop = $false
    try {
        $enc = Get-CimSafe "Win32_SystemEnclosure" | Select-Object -First 1
        $chassis = @($enc.ChassisTypes)[0]
        $isLaptop = $chassis -in @(8, 9, 10, 11, 12, 14, 18, 21)
    } catch {}

    if (-not $DeviceInventory) {
        . "$PSScriptRoot\devices.ps1"
        $DeviceInventory = Get-ProbeDeviceInventory
    }

    $gpuStatus = @(Get-ProbeGpuDriverStatus)
    $deviceDrivers = @(Get-ProbeDeviceDrivers)
    $wu = Get-ProbeWindowsUpdateDriverCandidates

    $actions = @()

    # --- Missing drivers (Device Manager yellow bangs) ---
    foreach ($d in @($DeviceInventory.driverless)) {
        $cat = $d.category
        if ($cat -eq 'motherboard' -or $cat -eq 'chipset' -or $cat -eq 'pci') { $cat = 'chipset' }
        if ($cat -eq 'wireless') { $cat = 'network' }
        $vendor = if ($d.vendor_name) { (Get-ProbeVendorTag -Name "$($d.vendor_name) $($d.name)") } else { $cpuVendor }
        $actions += New-ProbeDriverAction `
            -Severity 'critical' -Code 'missing_driver' -Category $cat -VendorTag $vendor `
            -DeviceName $d.name -BoardMfr $boardMfr -BoardProduct $boardProduct -SystemMfr $sysMfr -SystemModel $sysModel `
            -Priority 10 `
            -Title "No driver: $($d.name)" `
            -Detail "$($d.problem_message). Install the vendor package for this class before benchmarking."
    }

    # --- GPU status ---
    foreach ($g in $gpuStatus) {
        if ($g.is_generic) {
            $actions += New-ProbeDriverAction `
                -Severity 'critical' -Code 'gpu_generic' -Category 'gpu' -VendorTag $g.vendor `
                -DeviceName $g.name -Priority 5 `
                -Title "GPU is on a generic Microsoft driver" `
                -Detail 'Performance and hot-spot sensors will be wrong until the vendor package is installed.'
        } elseif ($g.is_stale) {
            $actions += New-ProbeDriverAction `
                -Severity 'warn' -Code 'gpu_stale' -Category 'gpu' -VendorTag $g.vendor `
                -DeviceName $g.name -Priority 30 `
                -Title "$($g.name) driver is $($g.age_days) days old" `
                -Detail "Current: $($g.driver) ($($g.driver_date)). Game Ready / Adrenalin releases land every few weeks - update before a stability pass."
        } elseif (-not $g.updater_installed -and -not $g.is_integrated) {
            $actions += New-ProbeDriverAction `
                -Severity 'info' -Code 'gpu_no_updater' -Category 'gpu' -VendorTag $g.vendor `
                -DeviceName $g.name -Priority 60 `
                -Title "Install the $($g.vendor.ToUpper()) updater app" `
                -Detail 'Keeps the card on a current Game Ready / Adrenalin / Arc release without manual downloads.'
        }
    }

    # --- Generic board drivers that Windows Update left behind ---
    $genericWatch = @(
        @{ match = 'SM Bus Controller|SMBus'; cat = 'chipset'; title = 'SMBus is on a generic driver' }
        @{ match = 'PCI Simple Communications|Management Engine|MEI|Interface'; cat = 'chipset'; title = 'Intel ME / AMD PSP interface needs the vendor package' }
        @{ match = 'High Definition Audio Controller'; cat = 'audio'; title = 'Audio controller has no codec package' }
        @{ match = 'Ethernet|Wi-Fi|Wireless|Bluetooth|WLAN|LAN '; cat = 'network'; title = 'Network adapter on a generic driver' }
        @{ match = 'USB.?[34x]|USB Root|USB4|Thunderbolt'; cat = 'usb'; title = 'USB / Thunderbolt stack is generic' }
    )
    foreach ($d in $deviceDrivers) {
        if (-not $d.is_generic) { continue }
        foreach ($w in $genericWatch) {
            if ("$($d.name)" -notmatch $w.match) { continue }
            $actions += New-ProbeDriverAction `
                -Severity 'warn' -Code 'generic_driver' -Category $w.cat -VendorTag $cpuVendor `
                -DeviceName $d.name -BoardMfr $boardMfr -BoardProduct $boardProduct `
                -SystemMfr $sysMfr -SystemModel $sysModel -Priority 20 `
                -Title $w.title `
                -Detail "Provider: $($d.provider) · INF: $($d.inf). Replace with the motherboard / OEM package."
            break
        }
    }

    # --- Stale non-GPU drivers on critical classes ---
    foreach ($d in $deviceDrivers) {
        if (-not $d.is_very_stale) { continue }
        if ($d.class -notmatch 'Net|MEDIA|Display|HDC|System|USB|Bluetooth') { continue }
        if ($d.is_generic) { continue }
        $cat = switch -Regex ($d.class) {
            'Display' { 'gpu' }
            'Net|Bluetooth' { 'network' }
            'MEDIA' { 'audio' }
            'HDC' { 'storage' }
            'USB' { 'usb' }
            default { 'chipset' }
        }
        $actions += New-ProbeDriverAction `
            -Severity 'info' -Code 'driver_stale' -Category $cat -VendorTag $cpuVendor `
            -DeviceName $d.name -BoardMfr $boardMfr -BoardProduct $boardProduct `
            -SystemMfr $sysMfr -SystemModel $sysModel -Priority 70 `
            -Title "$($d.name) driver is $($d.age_days) days old" `
            -Detail "Provider: $($d.provider) · $($d.version) ($($d.date))"
    }

    if ($isLaptop) {
        $actions += New-ProbeDriverAction `
            -Severity 'info' -Code 'laptop_oem' -Category 'laptop_oem' -VendorTag 'unknown' `
            -SystemMfr $sysMfr -SystemModel $sysModel -Priority 40 `
            -Title "Install the $sysMfr OEM package for $sysModel" `
            -Detail 'Laptop hotkeys, battery charge thresholds, and custom ACPI live in the OEM package - not in Windows Update.'
    }

    # De-duplicate by title, keep highest severity.
    $rank = @{ critical = 0; warn = 1; info = 2 }
    $dedup = @{}
    foreach ($a in $actions) {
        $k = "$($a.code)|$($a.device)|$($a.title)"
        if (-not $dedup.ContainsKey($k) -or $rank[$a.severity] -lt $rank[$dedup[$k].severity]) {
            $dedup[$k] = $a
        }
    }
    $actions = @($dedup.Values | Sort-Object { $_.priority }, { $rank["$($_.severity)"] })

    # Build the recommended install queue for this machine.
    $queue = @()
    foreach ($step in $script:ProbeDriverInstallOrder) {
        if ($step.id -eq 'laptop_oem' -and -not $isLaptop) { continue }
        $related = @($actions | Where-Object { $_.category -eq $step.id })
        $queue += @{
            id       = $step.id
            label    = $step.label
            why      = $step.why
            status   = if ($related | Where-Object { $_.severity -eq 'critical' }) { 'action_required' }
                       elseif ($related.Count -gt 0) { 'recommended' }
                       else { 'ok' }
            actions  = @($related)
            links    = @(Get-ProbeVendorDriverLinks -Category $step.id -VendorTag $cpuVendor `
                            -BoardMfr $boardMfr -BoardProduct $boardProduct -SystemMfr $sysMfr -SystemModel $sysModel)
        }
    }

    $critical = @($actions | Where-Object { $_.severity -eq 'critical' }).Count
    $warn = @($actions | Where-Object { $_.severity -eq 'warn' }).Count

    $score = 100
    $score -= [math]::Min(60, $critical * 20)
    $score -= [math]::Min(30, $warn * 8)
    if ($score -lt 0) { $score = 0 }

    $grade = if ($score -ge 90) { 'A' } elseif ($score -ge 75) { 'B' } elseif ($score -ge 60) { 'C' } elseif ($score -ge 40) { 'D' } else { 'F' }

    return @{
        score            = $score
        grade            = $grade
        is_laptop        = $isLaptop
        board            = @{ manufacturer = $boardMfr; product = $boardProduct }
        system           = @{ manufacturer = $sysMfr; model = $sysModel }
        cpu_vendor       = $cpuVendor
        summary          = @{
            critical_actions = $critical
            warn_actions     = $warn
            info_actions     = @($actions | Where-Object { $_.severity -eq 'info' }).Count
            gpu_count        = $gpuStatus.Count
            driver_bindings  = $deviceDrivers.Count
        }
        install_order    = @($script:ProbeDriverInstallOrder)
        install_queue    = @($queue)
        actions          = @($actions)
        gpus             = @($gpuStatus)
        stale_or_generic = @($deviceDrivers | Where-Object { $_.is_generic -or $_.is_very_stale } | Select-Object -First 40)
        windows_update   = $wu
        collected_at     = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Get-ProbeDriverReport {
    . "$PSScriptRoot\devices.ps1"
    $devices = Get-ProbeDeviceInventory
    $advice = Get-ProbeDriverAdvice -DeviceInventory $devices
    return @{
        devices = $devices
        drivers = $advice
    }
}
