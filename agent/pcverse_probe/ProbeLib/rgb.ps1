. "$PSScriptRoot\common.ps1"

# Known USB RGB / LCD devices (VID/PID) — expanded as fingerprint library
$script:KnownRgbDb = @(
    @{ vid='1b1c'; pid='0c32'; vendor='Corsair'; type='aio_lcd'; name='Corsair iCUE LINK / ELITE LCD'; lcd_w=480; lcd_h=480; zones=@('pump_lcd','pump_ring') }
    @{ vid='1b1c'; pid='0c1c'; vendor='Corsair'; type='aio'; name='Corsair AIO Pump RGB'; zones=@('pump_ring') }
    @{ vid='1e71'; pid='170e'; vendor='NZXT'; type='aio_lcd'; name='NZXT Kraken Z Series'; lcd_w=640; lcd_h=640; zones=@('pump_lcd','pump_ring') }
    @{ vid='1e71'; pid='3008'; vendor='NZXT'; type='aio_lcd'; name='NZXT Kraken Elite'; lcd_w=640; lcd_h=640; zones=@('pump_lcd','pump_ring') }
    @{ vid='1e71'; pid='2001'; vendor='NZXT'; type='fan'; name='NZXT RGB Fan'; zones=@('fan_ring','fan_led') }
    @{ vid='1532'; pid='0c00'; vendor='Razer'; type='hub'; name='Razer RGB Controller'; zones=@('strip','fan') }
    @{ vid='0b05'; pid='1867'; vendor='ASUS'; type='motherboard'; name='ASUS Aura USB'; zones=@('header_argb','header_rgb') }
    @{ vid='0b05'; pid='1872'; vendor='ASUS'; type='motherboard'; name='ASUS Aura Terminal'; zones=@('strip','fan_ring') }
    @{ vid='1462'; pid='7d25'; vendor='MSI'; type='motherboard'; name='MSI Mystic Light USB'; zones=@('board','strip','fan') }
    @{ vid='1fc9'; pid='0094'; vendor='Phanteks'; type='case'; name='Phanteks RGB Controller'; zones=@('case_front','fan_ring') }
    @{ vid='2516'; pid='0051'; vendor='Cooler Master'; type='case'; name='Cooler Master RGB Hub'; zones=@('fan_ring','strip') }
    @{ vid='3633'; pid='0009'; vendor='Lian Li'; type='hub'; name='Lian Li RGB Hub'; zones=@('fan_ring','strip') }
    @{ vid='3633'; pid='0001'; vendor='Lian Li'; type='fan'; name='Lian Li UNI FAN'; zones=@('fan_ring','fan_center') }
)

function Get-OpenRgbExecutable {
    $root = Split-Path $PSScriptRoot -Parent
    $candidates = @(
        (Join-Path $root "tools\OpenRGB\OpenRGB.exe"),
        (Join-Path $root "tools\OpenRGB.exe"),
        "${env:ProgramFiles}\OpenRGB\OpenRGB.exe",
        "${env:ProgramFiles(x86)}\OpenRGB\OpenRGB.exe",
        (Join-Path $env:LOCALAPPDATA "Programs\OpenRGB\OpenRGB.exe")
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    return $null
}

function Get-RgbBlockingProcesses {
    $names = @('iCUE','SignalRgb','RazerAppEngine','ArmouryCrate','LightingService','MSI.CentralServer','NZXT CAM')
    $found = @()
    foreach ($n in $names) {
        if (Get-Process -Name $n -ErrorAction SilentlyContinue) {
            $found += $n
        }
    }
    return $found
}

function Match-KnownRgbDevice {
    param([string]$InstanceId, [string]$FriendlyName)
    $text = ($InstanceId + ' ' + $FriendlyName).ToUpper()
    foreach ($k in $script:KnownRgbDb) {
        $vid = $k.vid.ToUpper()
        $pid = $k.pid.ToUpper()
        if ($text -match "VID_$vid" -and $text -match "PID_$pid") {
            return $k
        }
    }
    if ($FriendlyName -match 'RGB|ARGB|AURA|MYSTIC|iCUE|NZXT|CORSAIR|RAZER|LIAN LI|PHANTEKS|COOLER MASTER|UNI FAN|ELITE LCD|KRAKEN') {
        return @{ vendor='Detected'; type='rgb_generic'; name=$FriendlyName; zones=@('zone_1') }
    }
    return $null
}

function Get-RgbHidDevices {
    $devices = @()
    try {
        Get-PnpDevice -Class 'HIDClass','USB','System' -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Status -ne 'OK') { return }
            $match = Match-KnownRgbDevice -InstanceId $_.InstanceId -FriendlyName ($_.FriendlyName -replace '\x00','')
            if (-not $match) { return }
            $devices += @{
                id = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($_.InstanceId)).Replace('=','').Replace('/','_').Replace('+','-').Substring(0, [Math]::Min(24, 32))
                instance_id = $_.InstanceId
                friendly_name = $_.FriendlyName
                vendor = $match.vendor
                device_type = $match.type
                label = $match.name
                zones = @($match.zones)
                lcd_width = $match.lcd_w
                lcd_height = $match.lcd_h
                control_backend = 'openrgb_or_hid'
            }
        }
    } catch {}
    return $devices
}

function Get-OpenRgbDeviceList {
    param([string]$Exe)
    $list = @()
    try {
        $out = & $Exe --list-devices 2>&1
        $current = $null
        foreach ($line in ($out -split "`n")) {
            if ($line -match '^\d+:\s*(.+)$') {
                if ($current) { $list += $current }
                $current = @{ index = [int]($line -replace ':.*',''); name = $Matches[1].Trim(); zones = @() }
            } elseif ($line -match '^\s+Zone \d+:\s*(.+)$' -and $current) {
                $current.zones += $Matches[1].Trim()
            }
        }
        if ($current) { $list += $current }
    } catch {}
    return $list
}

function Get-RgbSoftwareHints {
    $hints = @()
    $paths = @(
        @{ name='iCUE'; path="${env:ProgramFiles}\Corsair\Corsair iCUE5 Software\iCUE.exe" }
        @{ name='NZXT CAM'; path="${env:ProgramFiles}\NZXT CAM\NZXT CAM.exe" }
        @{ name='SignalRGB'; path="${env:LOCALAPPDATA}\VortxEngine\Signal-x64\SignalRgb.exe" }
        @{ name='OpenRGB'; path=(Get-OpenRgbExecutable) }
    )
    foreach ($p in $paths) {
        if ($p.path -and (Test-Path $p.path)) {
            $hints += @{ software = $p.name; installed = $true; path = $p.path }
        }
    }
    return $hints
}

function Get-RgbDeviceScan {
    $hid = Get-RgbHidDevices
    $openRgb = Get-OpenRgbExecutable
    $blocking = Get-RgbBlockingProcesses
    $openRgbDevices = @()
    if ($openRgb -and $blocking.Count -eq 0) {
        $openRgbDevices = Get-OpenRgbDeviceList -Exe $openRgb
    }

    $merged = @()
    $idx = 0
    foreach ($d in $hid) {
        $idx++
        $merged += @{
            id = "dev_$idx"
            label = $d.label
            vendor = $d.vendor
            device_type = $d.device_type
            zones = @($d.zones | ForEach-Object {
                @{
                    zone_id = "$idx`:$_"
                    zone_type = $_
                    label_fa = (Get-ZoneLabelFa $_)
                    capabilities = Get-ZoneCapabilities $_ $d.device_type
                }
            })
            lcd = if ($d.lcd_width) { @{ width = $d.lcd_width; height = $d.lcd_height; gif_supported = $true } } else { $null }
            instance_id = $d.instance_id
        }
    }

    foreach ($og in $openRgbDevices) {
        $idx++
        $zones = @()
        $zi = 0
        foreach ($z in $og.zones) {
            $zi++
            $zones += @{
                zone_id = "og$($og.index)_$zi"
                zone_type = 'openrgb_zone'
                label_fa = $z
                openrgb_device = $og.index
                openrgb_zone = $zi - 1
                capabilities = @{ effects = @('static','breathing','rainbow','wave','pulse'); rgb = $true; speed = $true }
            }
        }
        $merged += @{
            id = "og_$($og.index)"
            label = $og.name
            vendor = 'OpenRGB'
            device_type = 'openrgb'
            zones = $zones
            lcd = $null
            openrgb_index = $og.index
        }
    }

    $controlReady = ($openRgb -ne $null) -and ($blocking.Count -eq 0)
    $enableGuide = $null
    if (-not $controlReady -and $merged.Count -gt 0) {
        $enableGuide = Get-RgbEnableGuide -HasOpenRgb ($openRgb -ne $null) -Blocking $blocking
    }

    return @{
        scanned_at = (Get-Date).ToUniversalTime().ToString("o")
        device_count = $merged.Count
        devices = $merged
        control = @{
            ready = $controlReady
            backend = if ($controlReady) { 'openrgb' } elseif ($openRgb) { 'openrgb_blocked' } else { 'detect_only' }
            openrgb_path = $openRgb
            blocking_processes = $blocking
        }
        software = Get-RgbSoftwareHints
        enable_guide = $enableGuide
        vakhsh_note_fa = if ($controlReady) { 'وخش می‌تواند رنگ فن‌ها و LCD را از telemetry همگام کند.' } else { 'ابتدا RGB را فعال کنید — راهنمای پاپ‌آپ را ببینید.' }
    }
}

function Get-ZoneLabelFa {
    param([string]$Zone)
    switch -Regex ($Zone) {
        'pump_lcd' { return 'LCD پمپ / صفحه کیس' }
        'pump_ring' { return 'حلقه LED پمپ' }
        'fan_ring' { return 'حلقه LED دور فن' }
        'fan_center' { return 'LED مرکز فن' }
        'fan_led' { return 'LED فن' }
        'case_front' { return 'LED جلو کیس' }
        'strip' { return 'نوار LED' }
        'header_argb' { return 'هدر ARGB مادربرد' }
        'header_rgb' { return 'هدر RGB مادربرد' }
        default { return $Zone }
    }
}

function Get-ZoneCapabilities {
    param([string]$Zone, [string]$DeviceType)
    $fx = @('static','breathing','pulse','rainbow','wave','spectrum','off')
    if ($Zone -match 'lcd') {
        return @{ effects = @('static','gif'); rgb = $true; gif = $true; speed = $false }
    }
    if ($Zone -match 'fan_ring|fan_center|fan_led') {
        return @{ effects = $fx; rgb = $true; speed = $true; per_led = $false; ring = $true }
    }
    return @{ effects = $fx; rgb = $true; speed = $true }
}

function Get-RgbEnableGuide {
    param([bool]$HasOpenRgb, [array]$Blocking)
    $steps = @(
        'در BIOS گزینه ErP / Deep Sleep را بررسی کنید — بعضی بردها RGB را در حالت Sleep خاموش می‌کنند (در S0 باید روشن باشد).'
        'کابل ARGB/RGB فن‌ها و هاب کیس را به هدر مادربرد یا کنترلر اختصاصی وصل کنید.'
    )
    if (-not $HasOpenRgb) {
        $steps += 'OpenRGB Portable را در پوشه agent/pcverse_probe/tools/OpenRGB/ قرار دهید — بدون نصب درایور، کنترل مستقیم از PCVerse Probe.'
        $steps += 'PCVerse Probe را یک‌بار Run as Administrator اجرا کنید تا دسترسی SMBus/USB برای LED فعال شود.'
    }
    if ($Blocking.Count -gt 0) {
        $steps += "نرم‌افزارهای $($Blocking -join ', ') را ببندید — فقط یک کنترلر RGB همزمان می‌تواند سخت‌افزار را بگیرد."
    }
    $steps += 'پس از فعال‌سازی، دکمه «اسکن مجدد RGB» را بزنید — وخش تنظیم خودکار را پیشنهاد می‌دهد.'

    return @{
        title_fa = 'چرا RGB دیده می‌شود ولی کنترل نمی‌شود؟'
        why_fa = 'LED کیس، حلقه فن و LCD پمپ از USB/SMBus کنترل می‌شوند. Windows به‌تنهایی درایور RGB نصب نمی‌کند — PCVerse Probe با OpenRGB (user-mode) بدون درایور اختصاصی کنترل می‌کند.'
        steps_fa = $steps
        blocking = $Blocking
        needs_admin = -not $HasOpenRgb
        needs_openrgb = -not $HasOpenRgb
    }
}

function Get-PcverseLcdCacheDir {
    $dir = Join-Path $env:LOCALAPPDATA "PCVerseProbe\lcd-cache"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Save-PcverseLcdGif {
    param(
        [string]$DeviceId,
        [byte[]]$Bytes,
        [int]$ExpectedW = 0,
        [int]$ExpectedH = 0
    )
    if ($Bytes.Length -lt 10) {
        return @{ ok = $false; error = 'empty_file' }
    }
    if ($Bytes[0..2] -join ',' -ne '71,73,70') {
        return @{ ok = $false; error = 'not_gif'; message_fa = 'فقط فایل GIF پذیرفته می‌شود.' }
    }

    $w = [BitConverter]::ToUInt16($Bytes, 6)
    $h = [BitConverter]::ToUInt16($Bytes, 8)
    if ($ExpectedW -gt 0 -and ($w -ne $ExpectedW -or $h -ne $ExpectedH)) {
        return @{
            ok = $false
            error = 'resolution_mismatch'
            message_fa = "ابعاد GIF ${w}x${h} با LCD ${ExpectedW}x${ExpectedH} مطابقت ندارد."
            actual = @{ w = $w; h = $h }
            expected = @{ w = $ExpectedW; h = $ExpectedH }
        }
    }

    $path = Join-Path (Get-PcverseLcdCacheDir) ("lcd_" + ($DeviceId -replace '[^\w\-]','_') + ".gif")
    [System.IO.File]::WriteAllBytes($path, $Bytes)

    return @{
        ok = $true
        path = $path
        width = $w
        height = $h
        size_bytes = $Bytes.Length
        stored_local = $true
        message_fa = 'GIF فقط روی PC شما ذخیره شد — به سرور PCVerse ارسال نشد.'
    }
}

function Invoke-RgbApplySettings {
    param($Settings)

    $openRgb = Get-OpenRgbExecutable
    if (-not $openRgb) {
        return @{ ok = $false; error = 'openrgb_missing'; enable_guide = (Get-RgbEnableGuide -HasOpenRgb $false -Blocking (Get-RgbBlockingProcesses)) }
    }
    if ((Get-RgbBlockingProcesses).Count -gt 0) {
        return @{ ok = $false; error = 'blocking_process' }
    }

    $applied = @()
    foreach ($zone in @($Settings.zones)) {
        try {
            $dev = [int]$zone.openrgb_device
            $z = [int]$zone.openrgb_zone
            $mode = [string]$zone.effect
            $color = [string]$zone.color
            if ($color -match '^#') { $color = $color.Substring(1) }
            $args = @('--device', $dev, '--mode', $mode)
            if ($color -and $mode -in @('static','breathing','pulse')) {
                $args += @('--color', $color)
            }
            if ($zone.speed) {
                $args += @('--speed', [int]$zone.speed)
            }
            & $openRgb @args 2>$null | Out-Null
            $applied += @{ zone_id = $zone.zone_id; effect = $mode; color = $color }
        } catch {
            $applied += @{ zone_id = $zone.zone_id; error = $_.Exception.Message }
        }
    }

    return @{ ok = ($applied.Count -gt 0); applied = $applied; engine = 'openrgb' }
}
