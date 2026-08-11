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
    @{ id = 'network';     label = 'LAN / Wi-Fi / Bluetooth';  why = 'So the machine can reach Windows Update and vendor sites for the rest.' }
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
    if ($p -match 'microsoft' -and $n -match 'realtek|killer|intel\(r\) ethernet|intel\(r\) wi-fi|qualcomm|atheros|broadcom') {
        return $true
    }
    return $false
}

function ConvertFrom-ProbeHardwareId {
    param([string]$InstanceId)

    if (-not (Get-Command ConvertFrom-PnpDeviceId -ErrorAction SilentlyContinue)) {
        . "$PSScriptRoot\devices.ps1"
    }
    return ConvertFrom-PnpDeviceId $InstanceId
}

function Get-ProbeDriverCatalog {
    if ($script:ProbeDriverCatalog) { return $script:ProbeDriverCatalog }
    $path = Join-Path (Split-Path -Parent $PSScriptRoot) 'data\driver-catalog.json'
    try {
        if (Test-Path $path) {
            $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
            $script:ProbeDriverCatalog = $raw | ConvertFrom-Json
            return $script:ProbeDriverCatalog
        }
    } catch {}
    $script:ProbeDriverCatalog = [pscustomobject]@{ version = 0; pci = @(); usb = @(); board_patterns = @(); oem_patterns = @() }
    return $script:ProbeDriverCatalog
}

function Infer-ProbeDriverCategory {
    param(
        [string]$Category = "",
        [string]$DeviceName = "",
        [string]$VendorId = "",
        [string]$Class = ""
    )
    $c = "$Category".ToLower()
    $map = @{
        motherboard = 'chipset'; pci = 'chipset'; firmware = 'chipset'
        wireless = 'network'; thunderbolt = 'usb'; input = 'peripherals'
        other = ''; unknown = ''
    }
    if ($map.ContainsKey($c)) { $c = $map[$c] }
    if ($c -in @('gpu','chipset','audio','network','usb','storage','laptop_oem','peripherals')) {
        return $c
    }
    $n = "$DeviceName".ToLower()
    $v = "$VendorId".ToLower()
    $cl = "$Class".ToLower()
    if ($cl -match 'display' -or $n -match 'geforce|radeon|arc |uhd|iris|vga|3d|gpu' -or $v -in @('10de','1002')) { return 'gpu' }
    if ($cl -match 'net|bluetooth' -or $n -match 'ethernet|wi-?fi|wireless|bluetooth|wlan|lan ') { return 'network' }
    if ($cl -match 'media' -or $n -match 'audio|sound|hd audio') { return 'audio' }
    if ($n -match 'sm ?bus|management engine|mei|pch|chipset|lpc|serial io|pci simple' -or $v -in @('8086','1022')) { return 'chipset' }
    if ($cl -match 'usb' -or $n -match 'usb|thunderbolt|usb4') { return 'usb' }
    if ($cl -match 'hdc|scsi' -or $n -match 'nvme|ahci|sata|raid') { return 'storage' }
    return 'chipset'
}

function Get-ProbeVendorTagFromId {
    param([string]$VendorId, [string]$Fallback = 'unknown')
    switch ("$VendorId".ToLower()) {
        '10de' { return 'nvidia' }
        '1002' { return 'amd' }
        '1022' { return 'amd' }
        '8086' { return 'intel' }
        '10ec' { return 'realtek' }
        '14e4' { return 'broadcom' }
        '1969' { return 'qualcomm' }
        '168c' { return 'qualcomm' }
        '1b21' { return 'asmedia' }
        '0bda' { return 'realtek' }
        default { return $Fallback }
    }
}

function Resolve-ProbeDriverPackage {
    param(
        [string]$Category,
        [string]$VendorTag = 'unknown',
        [string]$DeviceName = "",
        [string]$InstanceId = "",
        [string]$VendorId = "",
        [string]$DeviceId = "",
        [string]$BoardMfr = "",
        [string]$BoardProduct = "",
        [string]$SystemMfr = "",
        [string]$SystemModel = "",
        [string]$Class = ""
    )

    $catalog = Get-ProbeDriverCatalog
    $hw = $null
    if ($InstanceId) {
        $hw = ConvertFrom-ProbeHardwareId $InstanceId
        if (-not $VendorId -and $hw.vendor_id) { $VendorId = "$($hw.vendor_id)" }
        if (-not $DeviceId -and $hw.device_id) { $DeviceId = "$($hw.device_id)" }
    }

    $Category = Infer-ProbeDriverCategory -Category $Category -DeviceName $DeviceName -VendorId $VendorId -Class $Class
    if ($VendorTag -eq 'unknown' -or -not $VendorTag) {
        $VendorTag = Get-ProbeVendorTagFromId -VendorId $VendorId -Fallback $VendorTag
    }

    $links = @()
    $confidence = 'generic'
    $primary = $null
    $bestScore = -1

    $bus = if ($hw -and $hw.bus) { "$($hw.bus)" } elseif ($InstanceId -match '^USB\\') { 'usb' } else { 'pci' }
    if ($bus -eq 'usb' -and $catalog.usb) {
        foreach ($row in @($catalog.usb)) {
            $vid = ("$($row.vid)").ToLower()
            $pid = ("$($row.pid)").ToLower()
            if ($vid -and $VendorId -and $vid -ne $VendorId.ToLower()) { continue }
            if ($pid -and $pid -ne '*' -and $DeviceId -and $pid -ne $DeviceId.ToLower()) { continue }
            if ($row.category -and $Category -and "$($row.category)" -ne $Category -and $Category -ne 'peripherals') { continue }
            $hit = New-ProbeDriverHit $row 'catalog'
            $links += $hit
            $score = 5
            if ($pid -and $pid -ne '*' -and $DeviceId -and $pid -eq $DeviceId.ToLower()) { $score += 40 }
            if ($score -gt $bestScore) {
                $bestScore = $score
                $primary = $hit
                $confidence = if ($pid -and $pid -ne '*') { 'exact' } else { 'vendor' }
            }
        }
    } elseif ($catalog.pci) {
        foreach ($row in @($catalog.pci)) {
            $ven = ("$($row.ven)").ToLower()
            $dev = ("$($row.dev)").ToLower()
            if ($ven -and $VendorId -and $ven -ne $VendorId.ToLower()) { continue }
            if ($dev -and $dev -ne '*' -and $DeviceId -and $dev -ne $DeviceId.ToLower()) { continue }
            $nameHit = $false
            if ($row.name_match) {
                if ($DeviceName -and ("$DeviceName" -match "$($row.name_match)")) { $nameHit = $true }
                elseif ($DeviceName) { continue }
            }
            if ($row.category -and $Category -and "$($row.category)" -ne $Category) {
                if (-not $nameHit -and ($dev -eq '*' -or -not $DeviceId)) { continue }
            }
            $hit = New-ProbeDriverHit $row 'catalog'
            $links += $hit
            $score = 0
            if ($dev -and $dev -ne '*' -and $DeviceId -and $dev -eq $DeviceId.ToLower()) { $score += 40 }
            if ($nameHit) { $score += 20 }
            if ($row.category -and "$($row.category)" -eq $Category) { $score += 10 }
            if ($ven -and $VendorId -and $ven -eq $VendorId.ToLower()) { $score += 5 }
            if ($score -gt $bestScore) {
                $bestScore = $score
                $primary = $hit
                $confidence = if ($dev -and $dev -ne '*' -and $DeviceId) { 'exact' } else { 'vendor' }
            }
        }
    }

    # Board-model aware support URLs
    if ($catalog.board_patterns -and ($BoardMfr -or $BoardProduct -or $SystemMfr)) {
        $hay = "$BoardMfr $BoardProduct $SystemMfr".ToLower()
        $product = if ($BoardProduct) { $BoardProduct } else { $SystemModel }
        $enc = [uri]::EscapeDataString("$product")
        foreach ($row in @($catalog.board_patterns)) {
            if ($hay -notmatch "$($row.match)") { continue }
            if ($row.category -and $Category -and "$($row.category)" -ne $Category -and $Category -notin @('chipset', 'audio', 'network', 'usb', 'storage')) { continue }
            $url = ("$($row.url_template)" -replace '\{product\}', $enc)
            if (-not $url) { $url = "$($row.url)" }
            $hit = @{ label = "$($row.label)"; url = $url; note = "Matched board/OEM pattern for $product"; source = 'board' }
            $links += $hit
            if ($confidence -eq 'generic' -or -not $primary) {
                $primary = $hit
                $confidence = 'board'
            }
        }
    }

    if ($Category -eq 'laptop_oem' -and $catalog.oem_patterns) {
        $sys = "$SystemMfr".ToLower()
        foreach ($row in @($catalog.oem_patterns)) {
            if ($sys -notmatch "$($row.match)") { continue }
            $hit = @{ label = "$($row.label)"; url = "$($row.url)"; source = 'oem' }
            $links += $hit
            if (-not $primary) { $primary = $hit; $confidence = 'board' }
        }
    }

    $fallback = @(Get-ProbeVendorDriverLinks -Category $Category -VendorTag $VendorTag -DeviceName $DeviceName `
            -BoardMfr $BoardMfr -BoardProduct $BoardProduct -SystemMfr $SystemMfr -SystemModel $SystemModel)
    foreach ($f in $fallback) {
        $dup = $false
        foreach ($existing in $links) {
            if ("$($existing.url)" -eq "$($f.url)") { $dup = $true; break }
        }
        if ($dup) { continue }
        $f2 = @{ label = "$($f.label)"; url = "$($f.url)"; note = "$($f.note)"; source = 'vendor' }
        $links += $f2
        if (-not $primary) {
            $primary = $f2
            $confidence = 'vendor'
        }
    }

    if (-not $primary -and $links.Count -gt 0) { $primary = $links[0] }
    if (-not $links -or $links.Count -eq 0) {
        $confidence = 'generic'
        $links = @(@{
            label = 'Windows Update drivers'; url = 'ms-settings:windowsupdate'
            note = 'Optional updates often hide OEM drivers.'; source = 'generic'
            install_method = 'open_url'; package_url = $null; version = $null; installable = $false
        })
        $primary = $links[0]
    }

    $method = if ($primary.install_method) { "$($primary.install_method)" } else { 'open_url' }
    $installable = $method -in @('inf_zip', 'msi', 'exe_silent', 'exe_ui', 'updater_app')

    return @{
        match_confidence = $confidence
        primary_link     = $primary
        links            = @($links)
        vendor_id        = if ($VendorId) { $VendorId.ToLower() } else { $null }
        device_id        = if ($DeviceId) { $DeviceId.ToLower() } else { $null }
        bus              = $bus
        category         = $Category
        instance_id      = $InstanceId
        install_method   = $method
        package_version  = if ($primary.version) { "$($primary.version)" } else { $null }
        package_url      = if ($primary.package_url) { "$($primary.package_url)" } else { $null }
        installable      = $installable
        silent_args      = if ($primary.silent_args) { "$($primary.silent_args)" } else { $null }
        sha256           = if ($primary.sha256) { "$($primary.sha256)" } else { $null }
        updater_names    = @($primary.updater_names)
    }
}

function New-ProbeDriverHit {
    param($Row, [string]$Source = 'catalog')
    return @{
        label          = "$($Row.label)"
        url            = "$($Row.url)"
        note           = "$($Row.note)"
        source         = $Source
        version        = if ($Row.version) { "$($Row.version)" } else { $null }
        released       = if ($Row.released) { "$($Row.released)" } else { $null }
        package_url    = if ($Row.package_url) { "$($Row.package_url)" } else { $null }
        install_method = if ($Row.install_method) { "$($Row.install_method)" } else { 'open_url' }
        silent_args    = if ($Row.silent_args) { "$($Row.silent_args)" } else { $null }
        sha256         = if ($Row.sha256) { "$($Row.sha256)" } else { $null }
        updater_names  = @($Row.updater_names)
        installable    = ("$($Row.install_method)" -in @('inf_zip', 'msi', 'exe_silent', 'exe_ui', 'updater_app'))
    }
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
    $product = if ($BoardProduct) { $BoardProduct } elseif ($SystemModel) { $SystemModel } else { '' }
    $enc = if ($product) { [uri]::EscapeDataString($product) } else { '' }

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
            if (($board -match 'asus' -or $sys -match 'asus') -and $enc) {
                $links += @{ label = "ASUS Support — $product"; url = "https://www.asus.com/searchresult?searchType=support&searchKey=$enc"; note = 'Chipset + LAN + audio for this board.' }
            } elseif ($board -match 'asus' -or $sys -match 'asus') {
                $links += @{ label = 'ASUS Support'; url = 'https://www.asus.com/support/'; note = 'Enter the board model for chipset + LAN + audio bundle.' }
            } elseif (($board -match 'msi|micro-star' -or $sys -match 'msi|micro-star') -and $enc) {
                $links += @{ label = "MSI Support — $product"; url = "https://www.msi.com/search/?q=$enc"; note = 'Chipset + LAN + audio under Drivers.' }
            } elseif ($board -match 'msi|micro-star' -or $sys -match 'msi|micro-star') {
                $links += @{ label = 'MSI Support'; url = 'https://www.msi.com/support'; note = 'Chipset + LAN + audio under Drivers.' }
            } elseif (($board -match 'gigabyte|aorus' -or $sys -match 'gigabyte|aorus') -and $enc) {
                $links += @{ label = "Gigabyte Support — $product"; url = "https://www.gigabyte.com/Search?keyword=$enc"; note = 'Download the chipset package for your board.' }
            } elseif ($board -match 'gigabyte|aorus' -or $sys -match 'gigabyte|aorus') {
                $links += @{ label = 'Gigabyte Support'; url = 'https://www.gigabyte.com/Support'; note = 'Download the chipset package for your board.' }
            } elseif (($board -match 'asrock' -or $sys -match 'asrock') -and $enc) {
                $links += @{ label = "ASRock Support — $product"; url = "https://www.asrock.com/support/index.us.asp?Model=$enc"; note = 'Chipset first, then LAN / audio.' }
            } elseif ($board -match 'asrock' -or $sys -match 'asrock') {
                $links += @{ label = 'ASRock Support'; url = 'https://www.asrock.com/support/'; note = 'Chipset first, then LAN / audio.' }
            } elseif ($board -match 'biostar') {
                $links += @{ label = 'BIOSTAR Support'; url = 'https://www.biostar.com.tw/app/en/support/index.php' }
            }
            if ($v -eq 'amd' -or $DeviceName -match 'AMD|Ryzen') {
                $links += @{ label = 'AMD Chipset Drivers'; url = 'https://www.amd.com/en/support/download/drivers.html'; note = 'Required for Ryzen USB / NVMe power management.' }
            } else {
                $links += @{ label = 'Intel Chipset INF'; url = 'https://www.intel.com/content/www/us/en/download/19347/chipset-inf-utility.html'; note = 'Plus Intel MEI / Serial IO from the same support page.' }
            }
        }
        'audio' {
            if ($enc -and ($board -match 'asus|msi|gigabyte|asrock' -or $sys -match 'asus|msi|gigabyte|asrock')) {
                $links += @{ label = "Board audio — $product"; url = "https://www.asus.com/searchresult?searchType=support&searchKey=$enc"; note = 'Prefer the motherboard package over Realtek generic.' }
            }
            $links += @{ label = 'Realtek Audio'; url = 'https://www.realtek.com/Download/List?cate_id=597' }
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
            if ($links.Count -eq 0 -and $enc) {
                $links += @{ label = "Board LAN / Wi-Fi — $product"; url = "https://www.asus.com/searchresult?searchType=support&searchKey=$enc"; note = 'Use your motherboard or laptop support page.' }
            } elseif ($links.Count -eq 0) {
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
        $drivers = @(Get-WindowsDriver -Online -ErrorAction SilentlyContinue)
        foreach ($d in $drivers) {
            if ($d.ProviderName -match '^Microsoft' -and $d.ClassName -notmatch 'Display|Net|MEDIA|HDC|USB|Bluetooth|System') {
                continue
            }
            $age = Get-ProbeDriverAgeDays $d.Date
            $list += @{
                class         = "$($d.ClassName)"
                class_guid    = "$($d.ClassGuid)"
                provider      = "$($d.ProviderName)"
                version       = "$($d.Version)"
                date          = if ($d.Date) { $d.Date.ToString('yyyy-MM-dd') } else { $null }
                age_days      = $age
                inf           = "$($d.Driver)"
                original_name = "$($d.OriginalFileName)"
                boot_critical = [bool]$d.BootCritical
                inbox         = [bool]$d.Inbox
            }
        }
    } catch {}
    return @($list)
}

function Compare-ProbeDriverVersion {
    param([string]$A, [string]$B)
    if (-not $A -or -not $B) { return 0 }
    try {
        $va = [version](($A -replace '[^\d\.]', ' ').Trim() -replace '\s+', '.')
        $vb = [version](($B -replace '[^\d\.]', ' ').Trim() -replace '\s+', '.')
        return $va.CompareTo($vb)
    } catch {
        return [string]::Compare("$A", "$B", $true)
    }
}

function Get-ProbeDeviceDrivers {
    $list = @()
    try {
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

    $out = @()
    foreach ($d in $list) {
        $age = Get-ProbeDriverAgeDays $d.Date
        $generic = Test-ProbeGenericDriver -Provider $d.Provider -InfName $d.Inf -DeviceName $d.Name
        $hw = ConvertFrom-ProbeHardwareId $d.InstanceId
        $out += @{
            name          = $d.Name
            class         = $d.Class
            instance_id   = $d.InstanceId
            provider      = $d.Provider
            version       = $d.Version
            date          = $d.Date
            age_days      = $age
            inf           = $d.Inf
            status        = $d.Status
            problem_code  = $d.ProblemCode
            is_generic    = $generic
            is_stale      = ($null -ne $age -and $age -gt 365)
            is_very_stale = ($null -ne $age -and $age -gt 730)
            bus           = $hw.bus
            vendor_id     = $hw.vendor_id
            device_id     = $hw.device_id
            subsystem_id  = $hw.subsystem_id
            vendor_name   = $hw.vendor_name
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
        $pnp = "$($g.PNPDeviceID)"
        $resolved = Resolve-ProbeDriverPackage -Category 'gpu' -VendorTag $vendor -DeviceName "$($g.Name)" -InstanceId $pnp
        $entry = @{
            name              = "$($g.Name)".Trim()
            vendor            = $vendor
            driver            = "$($g.DriverVersion)"
            driver_date       = if ($g.DriverDate) { ([datetime]$g.DriverDate).ToString('yyyy-MM-dd') } else { $null }
            age_days          = $age
            pnp_device_id     = $pnp
            instance_id       = $pnp
            vendor_id         = $resolved.vendor_id
            device_id         = $resolved.device_id
            status            = "$($g.Status)"
            is_generic        = $generic
            is_stale          = ($null -ne $age -and $age -gt 180)
            is_integrated     = ("$($g.Name)" -match 'UHD|Iris|Vega \d|Radeon\(TM\) Graphics')
            match_confidence  = $resolved.match_confidence
            primary_link      = $resolved.primary_link
            links             = @($resolved.links)
        }
        if ($vendor -eq 'nvidia') {
            $smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
            if ($smi) {
                try {
                    $ver = (& nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits 2>$null | Select-Object -First 1)
                    if ($ver) { $entry.nvidia_smi_version = "$ver".Trim() }
                } catch {}
            }
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

function Get-ProbeProblemDevices {
    $list = @()
    try {
        $raw = & pnputil.exe /enum-devices /problem 2>$null
        if (-not $raw) { return @() }
        $block = @{}
        foreach ($line in @($raw)) {
            if ($line -match '^\s*$') {
                if ($block.InstanceId) {
                    $hw = ConvertFrom-ProbeHardwareId $block.InstanceId
                    $list += @{
                        name         = $block.Name
                        instance_id  = $block.InstanceId
                        problem      = $block.Problem
                        code         = $block.Code
                        vendor_id    = $hw.vendor_id
                        device_id    = $hw.device_id
                        vendor_name  = $hw.vendor_name
                        bus          = $hw.bus
                    }
                    $block = @{}
                }
                continue
            }
            if ($line -match 'Instance ID:\s*(.+)$') { $block.InstanceId = $Matches[1].Trim(); continue }
            if ($line -match 'Device Description:\s*(.+)$') { $block.Name = $Matches[1].Trim(); continue }
            if ($line -match 'Problem Name:\s*(.+)$') { $block.Problem = $Matches[1].Trim(); continue }
            if ($line -match 'Problem Code:\s*(.+)$') { $block.Code = $Matches[1].Trim(); continue }
        }
        if ($block.InstanceId) {
            $hw = ConvertFrom-ProbeHardwareId $block.InstanceId
            $list += @{
                name        = $block.Name
                instance_id = $block.InstanceId
                problem     = $block.Problem
                code        = $block.Code
                vendor_id   = $hw.vendor_id
                device_id   = $hw.device_id
                vendor_name = $hw.vendor_name
                bus         = $hw.bus
            }
        }
    } catch {}
    return @($list)
}

function Get-ProbeWindowsUpdateDriverCandidates {
    param([switch]$IncludeWuScan)

    $out = @{
        available       = $false
        scanned         = $false
        note            = 'Windows Update driver scan is optional and can take minutes. Pass wu=1 to enable.'
        problem_devices = @(Get-ProbeProblemDevices)
        candidates      = @()
    }
    if ($out.problem_devices.Count -gt 0) { $out.available = $true }

    if (-not $IncludeWuScan) {
        return $out
    }

    $out.scanned = $true
    $out.note = 'Scanned Microsoft Update for driver-class updates (may take several minutes).'
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        # Driver updates often appear under BrowseOnly / optional; cast a wide net then filter.
        $result = $searcher.Search('IsInstalled=0 and Type=''Driver''')
        $list = @()
        foreach ($u in @($result.Updates)) {
            $cats = @()
            try {
                foreach ($c in @($u.Categories)) { $cats += "$($c.Name)" }
            } catch {}
            $list += @{
                title        = "$($u.Title)"
                is_downloaded = [bool]$u.IsDownloaded
                is_mandatory  = [bool]$u.IsMandatory
                categories    = $cats
                kb            = @($u.KBArticleIDs) -join ','
            }
        }
        $out.candidates = @($list | Select-Object -First 40)
        $out.available = $out.available -or ($out.candidates.Count -gt 0)
        $out.candidate_count = $out.candidates.Count
    } catch {
        $out.error = $_.Exception.Message
        $out.note = 'Windows Update COM scan failed. Problem devices from pnputil are still listed.'
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
        [string]$InstanceId = "",
        [string]$VendorId = "",
        [string]$DeviceId = "",
        [string]$BoardMfr = "",
        [string]$BoardProduct = "",
        [string]$SystemMfr = "",
        [string]$SystemModel = "",
        [string]$InfName = "",
        [string]$Provider = "",
        [string]$DriverVersion = "",
        [string]$DriverDate = "",
        $AgeDays = $null,
        [bool]$IsGeneric = $false,
        [bool]$IsStale = $false,
        [int]$Priority = 50
    )

    $resolved = Resolve-ProbeDriverPackage -Category $Category -VendorTag $VendorTag -DeviceName $DeviceName `
        -InstanceId $InstanceId -VendorId $VendorId -DeviceId $DeviceId `
        -BoardMfr $BoardMfr -BoardProduct $BoardProduct -SystemMfr $SystemMfr -SystemModel $SystemModel

    return @{
        severity         = $Severity
        code             = $Code
        title            = $Title
        detail           = $Detail
        category         = $Category
        priority         = $Priority
        device           = $DeviceName
        instance_id      = if ($InstanceId) { $InstanceId } else { $resolved.instance_id }
        vendor_id        = $resolved.vendor_id
        device_id        = $resolved.device_id
        bus              = $resolved.bus
        inf              = $InfName
        provider         = $Provider
        driver_version   = $DriverVersion
        driver_date      = $DriverDate
        age_days         = $AgeDays
        is_generic       = $IsGeneric
        is_stale         = $IsStale
        match_confidence = $resolved.match_confidence
        primary_link     = $resolved.primary_link
        links            = @($resolved.links)
        install_method   = $resolved.install_method
        package_version  = $resolved.package_version
        package_url      = $resolved.package_url
        installable      = [bool]$resolved.installable
    }
}

function Get-ProbeDriverAdvice {
    param(
        $DeviceInventory = $null,
        [switch]$IncludeWuScan
    )

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
    $installedStore = @(Get-ProbeInstalledDrivers)
    $wu = Get-ProbeWindowsUpdateDriverCandidates -IncludeWuScan:$IncludeWuScan

    $actions = @()

    foreach ($d in @($DeviceInventory.driverless)) {
        $cat = Infer-ProbeDriverCategory -Category $d.category -DeviceName $d.name -VendorId $d.vendor_id
        $vendor = Get-ProbeVendorTagFromId -VendorId $d.vendor_id -Fallback (
            if ($d.vendor_name) { (Get-ProbeVendorTag -Name "$($d.vendor_name) $($d.name)") } else { $cpuVendor }
        )
        $actions += New-ProbeDriverAction `
            -Severity 'critical' -Code 'missing_driver' -Category $cat -VendorTag $vendor `
            -DeviceName $d.name -InstanceId $d.instance_id -VendorId $d.vendor_id -DeviceId $d.device_id `
            -BoardMfr $boardMfr -BoardProduct $boardProduct -SystemMfr $sysMfr -SystemModel $sysModel `
            -Priority 10 `
            -Title "No driver: $($d.name)" `
            -Detail "$($d.problem_message). VEN_$("$($d.vendor_id)".ToUpper()) DEV_$("$($d.device_id)".ToUpper()) — install the matched vendor package before benchmarking."
    }

    foreach ($g in $gpuStatus) {
        if ($g.is_generic) {
            $actions += New-ProbeDriverAction `
                -Severity 'critical' -Code 'gpu_generic' -Category 'gpu' -VendorTag $g.vendor `
                -DeviceName $g.name -InstanceId $g.instance_id -VendorId $g.vendor_id -DeviceId $g.device_id `
                -DriverVersion $g.driver -DriverDate $g.driver_date -AgeDays $g.age_days `
                -IsGeneric $true -Priority 5 `
                -Title "GPU is on a generic Microsoft driver" `
                -Detail 'Performance and hot-spot sensors will be wrong until the vendor package is installed.'
        } elseif ($g.is_stale) {
            $actions += New-ProbeDriverAction `
                -Severity 'warn' -Code 'gpu_stale' -Category 'gpu' -VendorTag $g.vendor `
                -DeviceName $g.name -InstanceId $g.instance_id -VendorId $g.vendor_id -DeviceId $g.device_id `
                -DriverVersion $g.driver -DriverDate $g.driver_date -AgeDays $g.age_days `
                -IsStale $true -Priority 30 `
                -Title "$($g.name) driver is $($g.age_days) days old" `
                -Detail "Current: $($g.driver) ($($g.driver_date)). Game Ready / Adrenalin releases land every few weeks - update before a stability pass."
        } elseif (-not $g.updater_installed -and -not $g.is_integrated) {
            $actions += New-ProbeDriverAction `
                -Severity 'info' -Code 'gpu_no_updater' -Category 'gpu' -VendorTag $g.vendor `
                -DeviceName $g.name -InstanceId $g.instance_id -VendorId $g.vendor_id -DeviceId $g.device_id `
                -Priority 60 `
                -Title "Install the $($g.vendor.ToUpper()) updater app" `
                -Detail 'Keeps the card on a current Game Ready / Adrenalin / Arc release without manual downloads.'
        }
    }

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
            $cat = Infer-ProbeDriverCategory -Category $w.cat -DeviceName $d.name -VendorId $d.vendor_id -Class $d.class
            $vendor = Get-ProbeVendorTagFromId -VendorId $d.vendor_id -Fallback $cpuVendor
            $actions += New-ProbeDriverAction `
                -Severity 'warn' -Code 'generic_driver' -Category $cat -VendorTag $vendor `
                -DeviceName $d.name -InstanceId $d.instance_id -VendorId $d.vendor_id -DeviceId $d.device_id `
                -BoardMfr $boardMfr -BoardProduct $boardProduct `
                -SystemMfr $sysMfr -SystemModel $sysModel -Priority 20 `
                -InfName $d.inf -Provider $d.provider -DriverVersion $d.version -DriverDate $d.date `
                -AgeDays $d.age_days -IsGeneric $true `
                -Title $w.title `
                -Detail "Provider: $($d.provider) · INF: $($d.inf) · VEN_$("$($d.vendor_id)".ToUpper()) DEV_$("$($d.device_id)".ToUpper()). Replace with the motherboard / OEM package."
            break
        }
    }

    foreach ($d in $deviceDrivers) {
        if (-not $d.is_very_stale) { continue }
        if ($d.class -notmatch 'Net|MEDIA|Display|HDC|System|USB|Bluetooth') { continue }
        if ($d.is_generic) { continue }
        $cat = Infer-ProbeDriverCategory -Category '' -DeviceName $d.name -VendorId $d.vendor_id -Class $d.class
        $vendor = Get-ProbeVendorTagFromId -VendorId $d.vendor_id -Fallback $cpuVendor
        $actions += New-ProbeDriverAction `
            -Severity 'info' -Code 'driver_stale' -Category $cat -VendorTag $vendor `
            -DeviceName $d.name -InstanceId $d.instance_id -VendorId $d.vendor_id -DeviceId $d.device_id `
            -BoardMfr $boardMfr -BoardProduct $boardProduct `
            -SystemMfr $sysMfr -SystemModel $sysModel -Priority 70 `
            -InfName $d.inf -Provider $d.provider -DriverVersion $d.version -DriverDate $d.date `
            -AgeDays $d.age_days -IsStale $true `
            -Title "$($d.name) driver is $($d.age_days) days old" `
            -Detail "Provider: $($d.provider) · $($d.version) ($($d.date)) · VEN_$("$($d.vendor_id)".ToUpper()) DEV_$("$($d.device_id)".ToUpper())"
    }

    # Driver store vs active binding: newer package published but older INF still bound.
    $storeByInf = @{}
    foreach ($s in $installedStore) {
        $key = ("$($s.original_name)").ToLower()
        if (-not $key) { $key = ("$($s.inf)").ToLower() }
        if (-not $key) { continue }
        if (-not $storeByInf.ContainsKey($key) -or (Compare-ProbeDriverVersion $s.version $storeByInf[$key].version) -gt 0) {
            $storeByInf[$key] = $s
        }
    }
    foreach ($d in $deviceDrivers) {
        if (-not $d.inf) { continue }
        $infKey = ("$($d.inf)").ToLower()
        $store = $null
        if ($storeByInf.ContainsKey($infKey)) { $store = $storeByInf[$infKey] }
        else {
            foreach ($k in $storeByInf.Keys) {
                if ($k -like "*$infKey*" -or $infKey -like "*$k*") { $store = $storeByInf[$k]; break }
            }
        }
        if (-not $store) { continue }
        if ((Compare-ProbeDriverVersion $store.version $d.version) -le 0) { continue }
        if ($d.class -notmatch 'Net|MEDIA|Display|HDC|System|USB|Bluetooth') { continue }
        $cat = switch -Regex ($d.class) {
            'Display' { 'gpu' }
            'Net|Bluetooth' { 'network' }
            'MEDIA' { 'audio' }
            'HDC' { 'storage' }
            'USB' { 'usb' }
            default { 'chipset' }
        }
        $actions += New-ProbeDriverAction `
            -Severity 'warn' -Code 'store_newer' -Category $cat -VendorTag $cpuVendor `
            -DeviceName $d.name -InstanceId $d.instance_id -VendorId $d.vendor_id -DeviceId $d.device_id `
            -BoardMfr $boardMfr -BoardProduct $boardProduct `
            -SystemMfr $sysMfr -SystemModel $sysModel -Priority 35 `
            -InfName $d.inf -Provider $d.provider -DriverVersion $d.version -DriverDate $d.date `
            -AgeDays $d.age_days `
            -Title "Newer driver in store for $($d.name)" `
            -Detail "Active $($d.version); store has $($store.version) ($($store.date)). Reinstall / update the binding."
    }

    if ($isLaptop) {
        $actions += New-ProbeDriverAction `
            -Severity 'info' -Code 'laptop_oem' -Category 'laptop_oem' -VendorTag 'unknown' `
            -SystemMfr $sysMfr -SystemModel $sysModel -Priority 40 `
            -Title "Install the $sysMfr OEM package for $sysModel" `
            -Detail 'Laptop hotkeys, battery charge thresholds, and custom ACPI live in the OEM package - not in Windows Update.'
    }

    if ($IncludeWuScan -and $wu.candidates -and @($wu.candidates).Count -gt 0) {
        foreach ($c in @($wu.candidates | Select-Object -First 8)) {
            $actions += New-ProbeDriverAction `
                -Severity 'info' -Code 'wu_driver' -Category 'chipset' -VendorTag $cpuVendor `
                -BoardMfr $boardMfr -BoardProduct $boardProduct -SystemMfr $sysMfr -SystemModel $sysModel `
                -DeviceName "$($c.title)" -Priority 55 `
                -Title "Windows Update driver: $($c.title)" `
                -Detail 'Optional Microsoft Update driver candidate. Review before installing.'
        }
    }

    $rank = @{ critical = 0; warn = 1; info = 2 }
    $dedup = @{}
    foreach ($a in $actions) {
        $k = "$($a.code)|$($a.device)|$($a.title)"
        if (-not $dedup.ContainsKey($k) -or $rank[$a.severity] -lt $rank[$dedup[$k].severity]) {
            $dedup[$k] = $a
        }
    }
    $actions = @($dedup.Values | Sort-Object { $_.priority }, { $rank["$($_.severity)"] })

    $queue = @()
    foreach ($step in $script:ProbeDriverInstallOrder) {
        if ($step.id -eq 'laptop_oem' -and -not $isLaptop) { continue }
        $related = @($actions | Where-Object { $_.category -eq $step.id })
        $resolvedStep = Resolve-ProbeDriverPackage -Category $step.id -VendorTag $cpuVendor `
            -BoardMfr $boardMfr -BoardProduct $boardProduct -SystemMfr $sysMfr -SystemModel $sysModel
        $queue += @{
            id               = $step.id
            label            = $step.label
            why              = $step.why
            status           = if ($related | Where-Object { $_.severity -eq 'critical' }) { 'action_required' }
                               elseif ($related.Count -gt 0) { 'recommended' }
                               else { 'ok' }
            actions          = @($related)
            match_confidence = $resolvedStep.match_confidence
            primary_link     = $resolvedStep.primary_link
            links            = @($resolvedStep.links)
            install_method   = $resolvedStep.install_method
            package_version  = $resolvedStep.package_version
            package_url      = $resolvedStep.package_url
            installable      = [bool]$resolvedStep.installable
        }
    }

    $critical = @($actions | Where-Object { $_.severity -eq 'critical' }).Count
    $warn = @($actions | Where-Object { $_.severity -eq 'warn' }).Count

    $score = 100
    $score -= [math]::Min(60, $critical * 20)
    $score -= [math]::Min(30, $warn * 8)
    if ($score -lt 0) { $score = 0 }

    $grade = if ($score -ge 90) { 'A' } elseif ($score -ge 75) { 'B' } elseif ($score -ge 60) { 'C' } elseif ($score -ge 40) { 'D' } else { 'F' }

    # Attach package matches onto inventory driverless rows for UI cards.
    $enrichedDriverless = @()
    foreach ($d in @($DeviceInventory.driverless)) {
        $cat = Infer-ProbeDriverCategory -Category $d.category -DeviceName $d.name -VendorId $d.vendor_id
        $vendor = Get-ProbeVendorTagFromId -VendorId $d.vendor_id -Fallback $cpuVendor
        $resolved = Resolve-ProbeDriverPackage -Category $cat -VendorTag $vendor -DeviceName $d.name `
            -InstanceId $d.instance_id -VendorId $d.vendor_id -DeviceId $d.device_id `
            -BoardMfr $boardMfr -BoardProduct $boardProduct -SystemMfr $sysMfr -SystemModel $sysModel
        $copy = @{} + $d
        $copy.category = $cat
        $copy.match_confidence = $resolved.match_confidence
        $copy.primary_link = $resolved.primary_link
        $copy.links = @($resolved.links)
        $copy.install_method = $resolved.install_method
        $copy.package_version = $resolved.package_version
        $copy.package_url = $resolved.package_url
        $copy.installable = [bool]$resolved.installable
        $enrichedDriverless += $copy
    }
    if ($DeviceInventory -is [hashtable] -or $DeviceInventory.PSObject) {
        try { $DeviceInventory.driverless = @($enrichedDriverless) } catch {}
    }

    $staleEnriched = @()
    foreach ($d in @($deviceDrivers | Where-Object { $_.is_generic -or $_.is_very_stale } | Select-Object -First 40)) {
        $cat = Infer-ProbeDriverCategory -Category '' -DeviceName $d.name -VendorId $d.vendor_id -Class $d.class
        $vendor = Get-ProbeVendorTagFromId -VendorId $d.vendor_id -Fallback $cpuVendor
        $resolved = Resolve-ProbeDriverPackage -Category $cat -VendorTag $vendor -DeviceName $d.name `
            -InstanceId $d.instance_id -VendorId $d.vendor_id -DeviceId $d.device_id `
            -BoardMfr $boardMfr -BoardProduct $boardProduct -SystemMfr $sysMfr -SystemModel $sysModel -Class $d.class
        $row = @{} + $d
        $row.match_confidence = $resolved.match_confidence
        $row.primary_link = $resolved.primary_link
        $row.links = @($resolved.links)
        $row.resolved_category = $cat
        $staleEnriched += $row
    }

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
            store_packages   = $installedStore.Count
            wu_candidates    = @($wu.candidates).Count
            driverless       = $enrichedDriverless.Count
        }
        install_order    = @($script:ProbeDriverInstallOrder)
        install_queue    = @($queue)
        actions          = @($actions)
        gpus             = @($gpuStatus)
        stale_or_generic = @($staleEnriched)
        driverless       = @($enrichedDriverless)
        driver_store     = @($installedStore | Select-Object -First 80)
        windows_update   = $wu
        collected_at     = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Get-ProbeDriverReport {
    param([switch]$IncludeWuScan)
    . "$PSScriptRoot\devices.ps1"
    $devices = Get-ProbeDeviceInventory
    $advice = Get-ProbeDriverAdvice -DeviceInventory $devices -IncludeWuScan:$IncludeWuScan
    return @{
        devices = $devices
        drivers = $advice
    }
}

# ---------------------------------------------------------------------------
# One-click driver install worker (user-confirmed via probe API)
# ---------------------------------------------------------------------------

function Get-ProbeDriverCacheDir {
    $dir = Join-Path $env:LOCALAPPDATA 'PcLabKit\Probe\driver-cache'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Get-ProbeDriverJobsDir {
    $dir = Join-Path $env:LOCALAPPDATA 'PcLabKit\Probe\driver-jobs'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Save-ProbeDriverInstallJob {
    param($Job)
    $path = Join-Path (Get-ProbeDriverJobsDir) ("$($Job.id).json")
    ($Job | ConvertTo-Json -Depth 8) | Set-Content -Path $path -Encoding UTF8
}

function Start-ProbeDriverInstall {
    param(
        [string]$InstanceId = '',
        [string]$QueueId = '',
        [string]$Category = '',
        [bool]$Confirm = $false
    )

    if (-not $Confirm) {
        return @{ ok = $false; error = 'confirm_required'; message = 'Pass confirm=true after UI confirmation.' }
    }

    $elevated = Test-ProbeElevated
    $jobId = [guid]::NewGuid().ToString('n').Substring(0, 12)
    $before = $null
    if ($InstanceId) {
        try {
            $d = Get-PnpDevice -InstanceId $InstanceId -ErrorAction SilentlyContinue
            if ($d) {
                $before = @{
                    name = "$($d.FriendlyName)"
                    status = "$($d.Status)"
                    problem = if ($null -ne $d.Problem) { [int]$d.Problem } else { 0 }
                }
            }
        } catch {}
    }

    . "$PSScriptRoot\devices.ps1"
    $devices = Get-ProbeDeviceInventory
    $board = $devices.motherboard
    $sys = $devices.firmware.system
    $target = $null
    if ($InstanceId) {
        foreach ($d in @($devices.all_devices)) {
            if ("$($d.instance_id)" -eq $InstanceId) { $target = $d; break }
        }
    }
    if (-not $Category -and $QueueId) { $Category = $QueueId }
    if (-not $Category -and $target) { $Category = "$($target.category)" }
    if (-not $Category) { $Category = 'chipset' }

    $vendorId = if ($target) { "$($target.vendor_id)" } else { '' }
    $deviceId = if ($target) { "$($target.device_id)" } else { '' }
    $name = if ($target) { "$($target.name)" } else { $Category }
    $vendor = Get-ProbeVendorTagFromId -VendorId $vendorId -Fallback 'unknown'
    $resolved = Resolve-ProbeDriverPackage -Category $Category -VendorTag $vendor -DeviceName $name `
        -InstanceId $InstanceId -VendorId $vendorId -DeviceId $deviceId `
        -BoardMfr "$($board.manufacturer)" -BoardProduct "$($board.product)" `
        -SystemMfr "$($sys.manufacturer)" -SystemModel "$($sys.model)"

    $method = "$($resolved.install_method)"
    if (-not $method) { $method = 'open_url' }

    $job = @{
        id = $jobId
        status = 'running'
        started_at = (Get-Date).ToUniversalTime().ToString('o')
        instance_id = $InstanceId
        queue_id = $QueueId
        category = $Category
        install_method = $method
        package_version = $resolved.package_version
        package_url = $resolved.package_url
        elevated = $elevated
        before = $before
        log = @()
        ok = $false
    }
    Save-ProbeDriverInstallJob $job

    try {
        if ($method -eq 'updater_app') {
            $launched = $false
            $names = @($resolved.updater_names)
            if ($names.Count -eq 0) {
                if ($vendor -eq 'nvidia') { $names = @('NVIDIA App', 'NVIDIA GeForce Experience') }
                elseif ($vendor -eq 'amd') { $names = @('RadeonSoftware', 'AMDSoftware') }
                elseif ($vendor -eq 'intel') { $names = @('IntelGraphicsSoftware', 'ArcControl') }
            }
            foreach ($n in $names) {
                $p = Get-Process -Name $n -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($p) {
                    try { Start-Process -FilePath $p.Path -ErrorAction SilentlyContinue } catch {}
                    $launched = $true
                    $job.log += "Focused running updater process: $n"
                    break
                }
            }
            $candidates = @(
                "$env:ProgramFiles\NVIDIA Corporation\NVIDIA App\CEF\NVIDIA App.exe",
                "$env:ProgramFiles\NVIDIA Corporation\NVIDIA GeForce Experience\NVIDIA GeForce Experience.exe",
                "$env:ProgramFiles\AMD\CNext\CNext\RadeonSoftware.exe",
                "${env:ProgramFiles(x86)}\AMD\CNext\CNext\RadeonSoftware.exe"
            )
            if (-not $launched) {
                foreach ($c in $candidates) {
                    if (Test-Path $c) {
                        Start-Process -FilePath $c
                        $launched = $true
                        $job.log += "Launched updater: $c"
                        break
                    }
                }
            }
            if (-not $launched -and $resolved.primary_link.url) {
                Start-Process $resolved.primary_link.url
                $job.log += "Opened vendor page (updater not installed)"
                $job.status = 'needs_manual'
                $job.ok = $true
            } else {
                $job.status = if ($launched) { 'updater_launched' } else { 'needs_manual' }
                $job.ok = $true
            }
        } elseif ($method -in @('exe_silent', 'exe_ui', 'msi', 'inf_zip') -and $resolved.package_url) {
            if (-not $elevated -and $method -ne 'exe_ui') {
                $job.status = 'needs_elevation'
                $job.log += 'Administrator elevation required for package install.'
                $job.ok = $false
            } else {
                $cache = Get-ProbeDriverCacheDir
                $ext = [IO.Path]::GetExtension(([uri]$resolved.package_url).AbsolutePath)
                if (-not $ext) { $ext = '.exe' }
                $dest = Join-Path $cache ("pkg_" + $jobId + $ext)
                $job.log += "Downloading $($resolved.package_url)"
                Invoke-WebRequest -Uri $resolved.package_url -OutFile $dest -UseBasicParsing -TimeoutSec 180
                if ($resolved.sha256) {
                    $hash = (Get-FileHash -Path $dest -Algorithm SHA256).Hash.ToLower()
                    if ($hash -ne "$($resolved.sha256)".ToLower()) {
                        throw "SHA256 mismatch: got $hash"
                    }
                    $job.log += 'SHA256 verified'
                }
                if ($method -eq 'msi') {
                    $args = "/i `"$dest`" /qn /norestart"
                    $p = Start-Process msiexec.exe -ArgumentList $args -Wait -PassThru
                    $job.exit_code = $p.ExitCode
                    $job.log += "msiexec exit $($p.ExitCode)"
                } elseif ($method -eq 'inf_zip') {
                    $extract = Join-Path $cache ("inf_" + $jobId)
                    Expand-Archive -Path $dest -DestinationPath $extract -Force
                    $inf = Get-ChildItem -Path $extract -Filter '*.inf' -Recurse | Select-Object -First 1
                    if (-not $inf) { throw 'No INF in package' }
                    $out = & pnputil.exe /add-driver $inf.FullName /install 2>&1 | Out-String
                    $job.log += $out
                    $job.exit_code = $LASTEXITCODE
                } else {
                    $args = if ($method -eq 'exe_silent' -and $resolved.silent_args) { "$($resolved.silent_args)" } else { '' }
                    if ($method -eq 'exe_ui') {
                        Start-Process -FilePath $dest
                        $job.log += 'Opened installer UI'
                        $job.status = 'installer_ui'
                        $job.ok = $true
                    } else {
                        $p = Start-Process -FilePath $dest -ArgumentList $args -Wait -PassThru
                        $job.exit_code = $p.ExitCode
                        $job.log += "Installer exit $($p.ExitCode)"
                    }
                }
                if ($job.status -eq 'running') {
                    $job.status = 'completed'
                    $job.ok = $true
                }
            }
        } else {
            $url = if ($resolved.primary_link.url) { $resolved.primary_link.url } else { 'ms-settings:windowsupdate' }
            Start-Process $url
            $job.status = 'needs_manual'
            $job.log += "Opened $url"
            $job.ok = $true
        }
    } catch {
        $job.status = 'failed'
        $job.error = $_.Exception.Message
        $job.log += $_.Exception.Message
        $job.ok = $false
    }

    $after = $null
    if ($InstanceId) {
        try {
            $d = Get-PnpDevice -InstanceId $InstanceId -ErrorAction SilentlyContinue
            if ($d) {
                $after = @{
                    name = "$($d.FriendlyName)"
                    status = "$($d.Status)"
                    problem = if ($null -ne $d.Problem) { [int]$d.Problem } else { 0 }
                }
            }
        } catch {}
    }
    $job.after = $after
    $job.finished_at = (Get-Date).ToUniversalTime().ToString('o')
    Save-ProbeDriverInstallJob $job

    return @{
        ok = [bool]$job.ok
        job = $jobId
        status = $job.status
        install_method = $method
        package_version = $resolved.package_version
        before = $before
        after = $after
        log = @($job.log)
        elevated = $elevated
        error = $job.error
        primary_link = $resolved.primary_link
    }
}

function Get-ProbeDriverInstallStatus {
    param([string]$JobId)
    if (-not $JobId) { return @{ ok = $false; error = 'unknown_job' } }
    $path = Join-Path (Get-ProbeDriverJobsDir) ("$JobId.json")
    if (-not (Test-Path $path)) { return @{ ok = $false; error = 'unknown_job' } }
    try {
        $job = Get-Content $path -Raw | ConvertFrom-Json
        return @{ ok = $true; job = $job }
    } catch {
        return @{ ok = $false; error = $_.Exception.Message }
    }
}
