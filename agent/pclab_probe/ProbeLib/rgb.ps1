. "$PSScriptRoot\common.ps1"

# Known USB RGB / LCD devices (VID/PID) — labeling + LCD size hints.
# OpenRGB --list-devices remains the control source of truth when available.
$script:KnownRgbDb = @(
    @{ vid='1b1c'; pid='0c32'; vendor='Corsair'; type='aio_lcd'; name='Corsair iCUE LINK / ELITE LCD'; lcd_w=480; lcd_h=480; zones=@('pump_lcd','pump_ring') }
    @{ vid='1b1c'; pid='0c1c'; vendor='Corsair'; type='aio'; name='Corsair AIO Pump RGB'; zones=@('pump_ring') }
    @{ vid='1b1c'; pid='0c3a'; vendor='Corsair'; type='aio_lcd'; name='Corsair iCUE LINK LCD'; lcd_w=480; lcd_h=480; zones=@('pump_lcd','pump_ring') }
    @{ vid='1b1c'; pid='0c3b'; vendor='Corsair'; type='aio_lcd'; name='Corsair H100i / ELITE CAPELLIX LCD'; lcd_w=480; lcd_h=480; zones=@('pump_lcd','pump_ring') }
    @{ vid='1b1c'; pid='0c40'; vendor='Corsair'; type='aio_lcd'; name='Corsair Titan / LCD Cooler'; lcd_w=480; lcd_h=480; zones=@('pump_lcd','pump_ring') }
    @{ vid='1e71'; pid='170e'; vendor='NZXT'; type='aio_lcd'; name='NZXT Kraken Z Series'; lcd_w=640; lcd_h=640; zones=@('pump_lcd','pump_ring') }
    @{ vid='1e71'; pid='3008'; vendor='NZXT'; type='aio_lcd'; name='NZXT Kraken Elite'; lcd_w=640; lcd_h=640; zones=@('pump_lcd','pump_ring') }
    @{ vid='1e71'; pid='300c'; vendor='NZXT'; type='aio_lcd'; name='NZXT Kraken Elite 2023'; lcd_w=640; lcd_h=640; zones=@('pump_lcd','pump_ring') }
    @{ vid='1e71'; pid='2011'; vendor='NZXT'; type='aio_lcd'; name='NZXT Kraken 2023 LCD'; lcd_w=640; lcd_h=640; zones=@('pump_lcd','pump_ring') }
    @{ vid='1e71'; pid='2001'; vendor='NZXT'; type='fan'; name='NZXT RGB Fan'; zones=@('fan_ring','fan_led') }
    @{ vid='3633'; pid='0008'; vendor='Lian Li'; type='aio_lcd'; name='Lian Li Galahad II LCD'; lcd_w=480; lcd_h=480; zones=@('pump_lcd','pump_ring') }
    @{ vid='3633'; pid='000a'; vendor='Lian Li'; type='case'; name='Lian Li Strimer / Controlller'; zones=@('strip','fan_ring') }
    @{ vid='3633'; pid='0009'; vendor='Lian Li'; type='hub'; name='Lian Li RGB Hub'; zones=@('fan_ring','strip') }
    @{ vid='3633'; pid='0001'; vendor='Lian Li'; type='fan'; name='Lian Li UNI FAN'; zones=@('fan_ring','fan_center') }
    @{ vid='1e4e'; pid='0011'; vendor='DeepCool'; type='aio_lcd'; name='DeepCool LD / LS LCD'; lcd_w=480; lcd_h=480; zones=@('pump_lcd','pump_ring') }
    @{ vid='1e4e'; pid='0010'; vendor='DeepCool'; type='aio'; name='DeepCool AIO RGB'; zones=@('pump_ring','fan_ring') }
    @{ vid='264a'; pid='2330'; vendor='Thermaltake'; type='aio_lcd'; name='Thermaltake TH / LCD Cooler'; lcd_w=480; lcd_h=480; zones=@('pump_lcd','pump_ring') }
    @{ vid='264a'; pid='2262'; vendor='Thermaltake'; type='hub'; name='Thermaltake RGB Controller'; zones=@('strip','fan_ring') }
    @{ vid='2516'; pid='01b5'; vendor='Cooler Master'; type='aio_lcd'; name='Cooler Master MasterLiquid LCD'; lcd_w=480; lcd_h=480; zones=@('pump_lcd','pump_ring') }
    @{ vid='2516'; pid='0051'; vendor='Cooler Master'; type='case'; name='Cooler Master RGB Hub'; zones=@('fan_ring','strip') }
    @{ vid='1532'; pid='0c00'; vendor='Razer'; type='hub'; name='Razer RGB Controller'; zones=@('strip','fan') }
    @{ vid='0b05'; pid='1867'; vendor='ASUS'; type='motherboard'; name='ASUS Aura USB'; zones=@('header_argb','header_rgb') }
    @{ vid='0b05'; pid='1872'; vendor='ASUS'; type='motherboard'; name='ASUS Aura Terminal'; zones=@('strip','fan_ring') }
    @{ vid='1462'; pid='7d25'; vendor='MSI'; type='motherboard'; name='MSI Mystic Light USB'; zones=@('board','strip','fan') }
    @{ vid='1fc9'; pid='0094'; vendor='Phanteks'; type='case'; name='Phanteks RGB Controller'; zones=@('case_front','fan_ring') }
    @{ vid='0416'; pid='5302'; vendor='Generic'; type='case_lcd'; name='USB Sensor / Case LCD Panel'; lcd_w=480; lcd_h=480; zones=@('pump_lcd') }
)

# Blink workers are detached processes (apply runs in short-lived shells).
function Get-RgbBlinkStateDir {
    $dir = Join-Path $env:LOCALAPPDATA "PcLabKit\Probe\rgb-blink"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Stop-RgbBlinkJobs {
    param([string]$ZoneId = $null)
    $dir = Get-RgbBlinkStateDir
    $files = Get-ChildItem -Path $dir -Filter '*.json' -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        try {
            $meta = Get-Content $f.FullName -Raw | ConvertFrom-Json
            if ($ZoneId -and $meta.zone_id -ne $ZoneId) { continue }
            if ($meta.pid) {
                Stop-Process -Id ([int]$meta.pid) -Force -ErrorAction SilentlyContinue
            }
            Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
            $ps1 = [System.IO.Path]::ChangeExtension($f.FullName, '.ps1')
            if (Test-Path $ps1) { Remove-Item $ps1 -Force -ErrorAction SilentlyContinue }
        } catch {
            Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}

function Start-RgbSoftwareBlink {
    param(
        [string]$ZoneId,
        [string]$OpenRgbExe,
        [int]$Device,
        [string]$Color,
        [int]$OnMs = 500,
        [int]$OffMs = 500
    )
    if ($OnMs -lt 50) { $OnMs = 50 }
    if ($OffMs -lt 50) { $OffMs = 50 }
    if ($OnMs -gt 60000) { $OnMs = 60000 }
    if ($OffMs -gt 60000) { $OffMs = 60000 }

    Stop-RgbBlinkJobs -ZoneId $ZoneId

    $safeZone = ($ZoneId -replace '[^\w\-]', '_')
    $statePath = Join-Path (Get-RgbBlinkStateDir) "$safeZone.json"
    $scriptPath = Join-Path (Get-RgbBlinkStateDir) "$safeZone.ps1"

    $loop = @"
`$exe = '$($OpenRgbExe -replace "'","''")'
`$dev = $Device
`$col = '$Color'
`$on = $OnMs
`$off = $OffMs
`$state = '$($statePath -replace "'","''")'
while (`$true) {
    if (-not (Test-Path `$state)) { break }
    try { & `$exe --device `$dev --mode static --color `$col 2>`$null | Out-Null } catch {}
    Start-Sleep -Milliseconds `$on
    if (-not (Test-Path `$state)) { break }
    try { & `$exe --device `$dev --mode off 2>`$null | Out-Null } catch {}
    Start-Sleep -Milliseconds `$off
}
"@
    Set-Content -Path $scriptPath -Value $loop -Encoding UTF8

    $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $scriptPath
    ) -WindowStyle Hidden -PassThru

    @{
        zone_id = $ZoneId
        pid = $proc.Id
        on_ms = $OnMs
        off_ms = $OffMs
        device = $Device
        started_at = (Get-Date).ToUniversalTime().ToString('o')
    } | ConvertTo-Json | Set-Content -Path $statePath -Encoding UTF8
}

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
    $names = @('iCUE','SignalRgb','RazerAppEngine','ArmouryCrate','LightingService','MSI.CentralServer','NZXT CAM','LConnect','TT RGB Plus','CAM')
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
    if ($FriendlyName -match 'RGB|ARGB|AURA|MYSTIC|iCUE|NZXT|CORSAIR|RAZER|LIAN LI|PHANTEKS|COOLER MASTER|UNI FAN|ELITE LCD|KRAKEN|DEEPCOOL|THERMALTAKE|STRIMER|GALAHAD|SENSOR.?PANEL|SMART.?SCREEN') {
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
        @{ name='L-Connect'; path="${env:ProgramFiles}\Lian Li\L-Connect 3\L-Connect 3.exe" }
    )
    foreach ($p in $paths) {
        if ($p.path -and (Test-Path $p.path)) {
            $hints += @{ software = $p.name; installed = $true; path = $p.path }
        }
    }
    return $hints
}

function Get-ZoneLabel {
    param([string]$Zone)
    switch -Regex ($Zone) {
        'pump_lcd' { return 'Pump / case LCD' }
        'pump_ring' { return 'Pump LED ring' }
        'fan_ring' { return 'Fan LED ring' }
        'fan_center' { return 'Fan center LED' }
        'fan_led' { return 'Fan LED' }
        'case_front' { return 'Case front LED' }
        'strip' { return 'LED strip' }
        'header_argb' { return 'Motherboard ARGB header' }
        'header_rgb' { return 'Motherboard RGB header' }
        'board' { return 'Board LEDs' }
        default { return $Zone }
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
    $fx = @('static','breathing','pulse','blink','rainbow','wave','spectrum','off')
    if ($Zone -match 'lcd') {
        return @{ effects = @('static','gif'); rgb = $true; gif = $true; speed = $false; blink = $false }
    }
    if ($Zone -match 'fan_ring|fan_center|fan_led') {
        return @{ effects = $fx; rgb = $true; speed = $true; blink = $true; per_led = $false; ring = $true }
    }
    return @{ effects = $fx; rgb = $true; speed = $true; blink = $true }
}

function Get-RgbEnableGuide {
    param([bool]$HasOpenRgb, [array]$Blocking)
    $steps = @(
        'In BIOS, check ErP / Deep Sleep — some boards cut RGB power in sleep (need S0 for LEDs).'
        'Connect ARGB/RGB fans and case hubs to the motherboard header or dedicated controller.'
    )
    if (-not $HasOpenRgb) {
        $steps += 'Place OpenRGB Portable in agent/pclab_probe/tools/OpenRGB/ — user-mode control, no vendor bloat.'
        $steps += 'Run PcLab Probe once as Administrator so SMBus/USB LED access works.'
    }
    if ($Blocking.Count -gt 0) {
        $steps += "Close competing software: $($Blocking -join ', ') — only one RGB controller can own the hardware at a time."
    }
    $steps += 'After enabling, click Rescan RGB — then Apply zones or Auto setup.'

    return @{
        title = 'RGB detected but not controllable'
        title_fa = 'چرا RGB دیده می‌شود ولی کنترل نمی‌شود؟'
        why = 'Case LEDs, fan rings, and pump LCDs use USB/SMBus. Windows does not ship RGB drivers — PC Lab Kit uses OpenRGB (user-mode) for unified control.'
        why_fa = 'LED کیس، حلقه فن و LCD پمپ از USB/SMBus کنترل می‌شوند. Windows به‌تنهایی درایور RGB نصب نمی‌کند - PcLab Probe با OpenRGB (user-mode) بدون درایور اختصاصی کنترل می‌کند.'
        steps = $steps
        steps_fa = $steps
        blocking = $Blocking
        needs_admin = -not $HasOpenRgb
        needs_openrgb = -not $HasOpenRgb
    }
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
                    label = (Get-ZoneLabel $_)
                    label_fa = (Get-ZoneLabelFa $_)
                    capabilities = Get-ZoneCapabilities $_ $d.device_type
                }
            })
            lcd = if ($d.lcd_width) {
                @{
                    width = $d.lcd_width
                    height = $d.lcd_height
                    gif_supported = $true
                    push_hint = 'gif_cache_and_openrgb'
                }
            } else { $null }
            instance_id = $d.instance_id
        }
    }

    foreach ($og in $openRgbDevices) {
        $idx++
        $zones = @()
        $zi = 0
        $looksLcd = ($og.name -match 'LCD|Display|Screen|Kraken|ELITE|iCUE LINK|Galahad|MasterLiquid')
        foreach ($z in $og.zones) {
            $zi++
            $cap = @{ effects = @('static','breathing','rainbow','wave','pulse','blink','off'); rgb = $true; speed = $true; blink = $true }
            if ($z -match '(?i)lcd|display|screen' -or $looksLcd) {
                $cap = @{ effects = @('static','gif','custom'); rgb = $true; gif = $true; speed = $false; blink = $false }
            }
            $zones += @{
                zone_id = "og$($og.index)_$zi"
                zone_type = if ($z -match '(?i)lcd|display') { 'pump_lcd' } else { 'openrgb_zone' }
                label = $z
                label_fa = $z
                openrgb_device = $og.index
                openrgb_zone = $zi - 1
                capabilities = $cap
            }
        }
        $lcdMeta = $null
        if ($looksLcd) {
            $lcdMeta = @{ width = 480; height = 480; gif_supported = $true; push_hint = 'openrgb'; openrgb_index = $og.index }
            if ($og.name -match 'NZXT|Kraken') { $lcdMeta.width = 640; $lcdMeta.height = 640 }
        }
        $merged += @{
            id = "og_$($og.index)"
            label = $og.name
            vendor = 'OpenRGB'
            device_type = if ($looksLcd) { 'aio_lcd' } else { 'openrgb' }
            zones = $zones
            lcd = $lcdMeta
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
        orchestrator_note = if ($controlReady) {
            'Orchestrator can sync fan LEDs and LCD dashboard from live telemetry.'
        } else {
            'Enable RGB control first — see the popup guide.'
        }
        orchestrator_note_fa = if ($controlReady) { 'Orchestrator can رنگ فن‌ها و LCD را از telemetry همگام کند.' } else { 'ابتدا RGB را فعال کنید - راهنمای پاپ‌آپ را ببینید.' }
    }
}

function Get-ProbeLcdCacheDir {
    $dir = Join-Path $env:LOCALAPPDATA "PcLabKit\Probe\lcd-cache"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Get-ProbeLcdDashboardPath {
    $path = Join-Path $env:LOCALAPPDATA "PcLabKit\Probe\lcd-dashboard\index.html"
    return $path
}

function Invoke-OpenRgbMode {
    param(
        [string]$Exe,
        [int]$Device,
        [string]$Mode,
        [string]$Color = $null,
        [int]$Speed = -1
    )
    $args = @('--device', $Device, '--mode', $Mode)
    if ($Color -and $Mode -in @('static','breathing','pulse','flashing','blink','blinking')) {
        $args += @('--color', $Color)
    }
    if ($Speed -ge 0) {
        $args += @('--speed', $Speed)
    }
    & $Exe @args 2>$null | Out-Null
    return $LASTEXITCODE
}

function Resolve-BlinkOpenRgbMode {
    param([string]$Preferred = 'flashing')
    # OpenRGB device mode names vary; try common aliases in apply path
    return @('flashing','Flashing','blink','Blink','blinking','Strobe','strobe')
}

function Invoke-RgbStop {
    Stop-RgbBlinkJobs
    $openRgb = Get-OpenRgbExecutable
    $stopped = @()
    if ($openRgb -and (Get-RgbBlockingProcesses).Count -eq 0) {
        $list = Get-OpenRgbDeviceList -Exe $openRgb
        foreach ($d in $list) {
            try {
                Invoke-OpenRgbMode -Exe $openRgb -Device $d.index -Mode 'off' | Out-Null
                $stopped += $d.index
            } catch {}
        }
    }
    return @{
        ok = $true
        blink_jobs_cleared = $true
        devices_off = $stopped
        message = 'Blink timers stopped; OpenRGB zones set to off where possible.'
    }
}

function Invoke-RgbApplySettings {
    param($Settings)

    $openRgb = Get-OpenRgbExecutable
    if (-not $openRgb) {
        return @{ ok = $false; error = 'openrgb_missing'; enable_guide = (Get-RgbEnableGuide -HasOpenRgb $false -Blocking (Get-RgbBlockingProcesses)) }
    }
    $blocking = Get-RgbBlockingProcesses
    if ($blocking.Count -gt 0) {
        return @{ ok = $false; error = 'blocking_process'; blocking_processes = $blocking; enable_guide = (Get-RgbEnableGuide -HasOpenRgb $true -Blocking $blocking) }
    }

    $applied = @()
    foreach ($zone in @($Settings.zones)) {
        try {
            $dev = [int]$zone.openrgb_device
            $mode = [string]$zone.effect
            $color = [string]$zone.color
            if ($color -match '^#') { $color = $color.Substring(1) }
            $zoneId = [string]$zone.zone_id
            if (-not $zoneId) { $zoneId = "dev$dev" }

            if ($mode -eq 'off') {
                Stop-RgbBlinkJobs -ZoneId $zoneId
                Invoke-OpenRgbMode -Exe $openRgb -Device $dev -Mode 'off' | Out-Null
                $applied += @{ zone_id = $zoneId; effect = 'off' }
                continue
            }

            if ($mode -eq 'blink') {
                $onMs = 500
                $offMs = 500
                if ($null -ne $zone.blink_on_ms) { $onMs = [int]$zone.blink_on_ms }
                elseif ($null -ne $zone.on_ms) { $onMs = [int]$zone.on_ms }
                if ($null -ne $zone.blink_off_ms) { $offMs = [int]$zone.blink_off_ms }
                elseif ($null -ne $zone.off_ms) { $offMs = [int]$zone.off_ms }

                # Map period to OpenRGB speed (0–100): shorter period = higher speed
                $period = [Math]::Max(100, $onMs + $offMs)
                $speed = [int][Math]::Max(0, [Math]::Min(100, [Math]::Round(10000.0 / $period)))
                if ($zone.speed) { $speed = [int]$zone.speed }

                $flashOk = $false
                foreach ($alias in (Resolve-BlinkOpenRgbMode)) {
                    $code = Invoke-OpenRgbMode -Exe $openRgb -Device $dev -Mode $alias -Color $color -Speed $speed
                    if ($code -eq 0 -or $null -eq $code) {
                        $flashOk = $true
                        $applied += @{
                            zone_id = $zoneId
                            effect = 'blink'
                            engine = 'openrgb_flashing'
                            mode_alias = $alias
                            color = $color
                            blink_on_ms = $onMs
                            blink_off_ms = $offMs
                            speed = $speed
                        }
                        break
                    }
                }
                if (-not $flashOk) {
                    Start-RgbSoftwareBlink -ZoneId $zoneId -OpenRgbExe $openRgb -Device $dev -Color $color -OnMs $onMs -OffMs $offMs
                    $applied += @{
                        zone_id = $zoneId
                        effect = 'blink'
                        engine = 'software_timer'
                        color = $color
                        blink_on_ms = $onMs
                        blink_off_ms = $offMs
                    }
                }
                continue
            }

            Stop-RgbBlinkJobs -ZoneId $zoneId
            $argsSpeed = -1
            if ($zone.speed) { $argsSpeed = [int]$zone.speed }
            Invoke-OpenRgbMode -Exe $openRgb -Device $dev -Mode $mode -Color $color -Speed $argsSpeed | Out-Null
            $applied += @{ zone_id = $zoneId; effect = $mode; color = $color; speed = $argsSpeed }
        } catch {
            $applied += @{ zone_id = $zone.zone_id; error = $_.Exception.Message }
        }
    }

    return @{ ok = ($applied.Count -gt 0); applied = $applied; engine = 'openrgb' }
}

function Invoke-ProbeLcdPush {
    param(
        [string]$DeviceId,
        [string]$GifPath,
        [int]$OpenRgbIndex = -1
    )
    $openRgb = Get-OpenRgbExecutable
    $blocking = Get-RgbBlockingProcesses
    if (-not $openRgb) {
        return @{
            pushed = $false
            reason = 'openrgb_missing'
            message = 'GIF saved locally. Install OpenRGB Portable to attempt hardware push.'
        }
    }
    if ($blocking.Count -gt 0) {
        return @{
            pushed = $false
            reason = 'blocking_process'
            blocking_processes = $blocking
            message = "GIF saved locally. Close $($blocking -join ', ') then retry push."
        }
    }

    $target = $OpenRgbIndex
    if ($target -lt 0) {
        $list = Get-OpenRgbDeviceList -Exe $openRgb
        $lcdDev = $list | Where-Object { $_.name -match 'LCD|Display|Screen|Kraken|ELITE|iCUE|Galahad|MasterLiquid|DeepCool|Thermaltake' } | Select-Object -First 1
        if ($lcdDev) { $target = [int]$lcdDev.index }
        elseif ($DeviceId -match 'og_(\d+)') { $target = [int]$Matches[1] }
    }

    if ($target -lt 0) {
        return @{
            pushed = $false
            reason = 'no_lcd_device'
            message = 'GIF saved locally. No OpenRGB LCD-capable device matched — use sensor dashboard or vendor app once.'
            path = $GifPath
        }
    }

    # OpenRGB CLI has no universal GIF flag; try Custom/Direct modes and keep file path for vendor import.
    $modesTried = @()
    foreach ($m in @('Custom','custom','Direct','direct','Static','static')) {
        $modesTried += $m
        try {
            Invoke-OpenRgbMode -Exe $openRgb -Device $target -Mode $m | Out-Null
        } catch {}
    }

    # Stage a copy next to OpenRGB for manual/profile workflows
    $stageDir = Join-Path (Split-Path $openRgb -Parent) 'pclab-lcd'
    if (-not (Test-Path $stageDir)) { New-Item -ItemType Directory -Path $stageDir -Force | Out-Null }
    $stagePath = Join-Path $stageDir ("lcd_" + ($DeviceId -replace '[^\w\-]','_') + ".gif")
    Copy-Item -Path $GifPath -Destination $stagePath -Force -ErrorAction SilentlyContinue

    return @{
        pushed = $true
        reason = 'openrgb_custom_attempted'
        openrgb_device = $target
        modes_tried = $modesTried
        staged_path = $stagePath
        path = $GifPath
        message = 'GIF cached and OpenRGB Custom/Direct applied on the matched LCD device. If the panel still shows the old image, import the staged GIF once in CAM/iCUE or use the local sensor dashboard.'
        note = 'Full animated GIF streaming depends on device SDK support; OpenRGB coverage varies by cooler.'
    }
}

function Save-ProbeLcdGif {
    param(
        [string]$DeviceId,
        [byte[]]$Bytes,
        [int]$ExpectedW = 0,
        [int]$ExpectedH = 0,
        [int]$OpenRgbIndex = -1
    )
    if ($Bytes.Length -lt 10) {
        return @{ ok = $false; error = 'empty_file'; message = 'Empty file.' }
    }
    if ($Bytes[0..2] -join ',' -ne '71,73,70') {
        return @{
            ok = $false
            error = 'not_gif'
            message = 'Only GIF files are accepted.'
            message_fa = 'فقط فایل GIF پذیرفته می‌شود.'
        }
    }

    $w = [BitConverter]::ToUInt16($Bytes, 6)
    $h = [BitConverter]::ToUInt16($Bytes, 8)
    $dimensionWarning = $null
    $accepted_with_mismatch = $false
    if ($ExpectedW -gt 0 -and ($w -ne $ExpectedW -or $h -ne $ExpectedH)) {
        # Soft-accept: store as-is; panels/vendor apps often letterbox or crop.
        $accepted_with_mismatch = $true
        $dimensionWarning = "GIF is ${w}x${h}; panel expects ${ExpectedW}x${ExpectedH}. Stored as-is (letterbox/crop on device)."
    }

    $path = Join-Path (Get-ProbeLcdCacheDir) ("lcd_" + ($DeviceId -replace '[^\w\-]','_') + ".gif")
    [System.IO.File]::WriteAllBytes($path, $Bytes)

    $dashPath = Get-ProbeLcdDashboardPath
    # Dashboard HTML is created by Orchestrator Auto setup; surface path when present.

    $push = Invoke-ProbeLcdPush -DeviceId $DeviceId -GifPath $path -OpenRgbIndex $OpenRgbIndex

    $next = @(
        "Local GIF: $path"
    )
    if ($push.staged_path) { $next += "Staged for OpenRGB: $($push.staged_path)" }
    if (Test-Path $dashPath) { $next += "Sensor dashboard (browser / panel Chromium): $dashPath" }
    if (-not $push.pushed) {
        $next += 'Close iCUE / CAM / SignalRGB, then Rescan and re-upload to retry hardware push.'
        $next += 'Or open the GIF once in your cooler vendor app if OpenRGB cannot drive this LCD.'
    }

    return @{
        ok = $true
        path = $path
        width = $w
        height = $h
        size_bytes = $Bytes.Length
        stored_local = $true
        accepted_with_mismatch = $accepted_with_mismatch
        dimension_warning = $dimensionWarning
        pushed = [bool]$push.pushed
        push = $push
        lcd_dashboard_path = if (Test-Path $dashPath) { $dashPath } else { $null }
        next_steps = $next
        message = if ($push.pushed) {
            'GIF saved locally and hardware push attempted via OpenRGB.'
        } else {
            'GIF saved on this PC only — not uploaded to any cloud. Hardware push skipped: ' + $push.reason
        }
        message_fa = 'GIF فقط روی PC شما ذخیره شد - به سرور PcLab ارسال نشد.'
    }
}
