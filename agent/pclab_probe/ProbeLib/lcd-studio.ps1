#Requires -Version 5.1
<#
  LCD Studio - universal AIO / case panel discovery, media fit, display player, HID transports.
  Dot-sourced from rgb.ps1 routes and /lcd/* endpoints.
#>
. "$PSScriptRoot\common.ps1"

$script:LcdPlayerStatePath = Join-Path $env:LOCALAPPDATA 'PcLabKit\Probe\lcd-player.json'

function Get-LcdLibraryDir {
    $dir = Join-Path $env:LOCALAPPDATA 'PcLabKit\Probe\lcd-library'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Get-LcdCacheDir {
    $dir = Join-Path $env:LOCALAPPDATA 'PcLabKit\Probe\lcd-cache'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Get-LcdPlayerDir {
    $dir = Join-Path $env:LOCALAPPDATA 'PcLabKit\Probe\lcd-player'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Find-LcdFfmpeg {
    $root = Split-Path $PSScriptRoot -Parent
    foreach ($c in @(
        (Join-Path $root 'tools\ffmpeg\ffmpeg.exe'),
        (Join-Path $root 'tools\ffmpeg.exe'),
        'ffmpeg.exe'
    )) {
        if ($c -eq 'ffmpeg.exe') {
            if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { return (Get-Command ffmpeg).Source }
        } elseif (Test-Path $c) { return (Resolve-Path $c).Path }
    }
    return $null
}

function Find-LcdLiquidctl {
    $root = Split-Path $PSScriptRoot -Parent
    foreach ($c in @(
        (Join-Path $root 'tools\liquidctl\liquidctl.exe'),
        (Join-Path $root 'tools\liquidctl.exe'),
        'liquidctl.exe',
        'liquidctl'
    )) {
        if ($c -in @('liquidctl.exe', 'liquidctl')) {
            if (Get-Command $c -ErrorAction SilentlyContinue) { return (Get-Command $c).Source }
        } elseif (Test-Path $c) { return (Resolve-Path $c).Path }
    }
    return $null
}

function Resolve-LcdTransportPreference {
    param([string]$Vendor, [string]$Kind, [string]$DeviceType)
    $v = ("$Vendor").ToLower()
    if ($Kind -eq 'case_display' -or $DeviceType -eq 'case_lcd') { return 'windows_display' }
    if ($v -match 'nzxt') {
        if (Find-LcdLiquidctl) { return 'liquidctl' }
        return 'openrgb'
    }
    if ($v -match 'corsair|lian|deepcool|cooler master|thermaltake') { return 'openrgb' }
    if ($DeviceType -match 'aio_lcd') { return 'openrgb' }
    return 'stage_only'
}

function New-LcdPanelObject {
    param(
        [string]$Id,
        [string]$Label,
        [string]$Vendor = 'Unknown',
        [string]$Kind = 'unknown',
        [int]$W = 480,
        [int]$H = 480,
        [string]$Shape = 'rect',
        [string]$Transport = 'stage_only',
        [hashtable]$Extra = @{}
    )
    if ($Shape -eq 'auto') {
        $Shape = if ($W -eq $H -and $W -ge 240) { 'round' } elseif ($W -gt ($H * 1.6)) { 'ultrawide' } else { 'rect' }
    }
    $caps = @{
        gif = $true
        video = ($Transport -eq 'windows_display')
        live_dashboard = $true
        max_duration_s = if ($Transport -eq 'windows_display') { 7200 } else { 120 }
        max_fps = if ($Transport -eq 'windows_display') { 60 } else { 30 }
        max_mb = if ($Transport -eq 'windows_display') { 512 } else { 25 }
    }
    $panel = @{
        id = $Id
        label = $Label
        vendor = $Vendor
        kind = $Kind
        geometry = @{
            w = $W
            h = $H
            shape = $Shape
            rotation = 0
            fit_default = if ($Shape -eq 'round') { 'round_mask' } else { 'fit' }
        }
        transport = $Transport
        capabilities = $caps
        honesty = @{
            note = switch ($Transport) {
                'windows_display' { 'Plays fullscreen on a Windows monitor - best for long video and any physical size/curve as pixels.' }
                'liquidctl' { 'NZXT LCD via liquidctl when installed; otherwise stage_only.' }
                'openrgb' { 'OpenRGB mode attempt - GIF apply is not confirmed by OpenRGB CLI; verify on panel.' }
                default { 'Media staged locally - import in vendor app if no HID transport confirms push.' }
            }
        }
    }
    foreach ($k in $Extra.Keys) { $panel[$k] = $Extra[$k] }
    return $panel
}

function Get-LcdWindowsDisplayBounds {
    # Screen bounds via .NET (works when PresentationFramework / Forms available)
    $screens = @()
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $i = 0
        foreach ($s in [System.Windows.Forms.Screen]::AllScreens) {
            $b = $s.Bounds
            $screens += @{
                index = $i
                primary = [bool]$s.Primary
                x = [int]$b.X
                y = [int]$b.Y
                width = [int]$b.Width
                height = [int]$b.Height
                device_name = "$($s.DeviceName)"
            }
            $i++
        }
    } catch {
        # Fallback: single primary from video controller
        foreach ($v in @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)) {
            if (-not $v.CurrentHorizontalResolution) { continue }
            $screens += @{
                index = $screens.Count
                primary = ($screens.Count -eq 0)
                x = 0
                y = 0
                width = [int]$v.CurrentHorizontalResolution
                height = [int]$v.CurrentVerticalResolution
                device_name = "$($v.Name)"
            }
        }
    }
    return @($screens)
}

function Get-LcdPanelCatalog {
    <# Returns LcdPanel[] from HID catalog + OpenRGB + Windows monitors. #>
    . "$PSScriptRoot\rgb.ps1"
    . "$PSScriptRoot\devices.ps1"

    $panels = @()
    $seen = @{}

    # USB / HID known LCD coolers
    foreach ($d in @(Get-RgbHidDevices)) {
        if (-not $d.lcd_width) { continue }
        $id = "hid_$($d.id)"
        if ($seen.ContainsKey($id)) { continue }
        $seen[$id] = $true
        $kind = if ($d.device_type -eq 'case_lcd') { 'case_display' } else { 'aio_hid' }
        $transport = Resolve-LcdTransportPreference -Vendor $d.vendor -Kind $kind -DeviceType $d.device_type
        $panels += (New-LcdPanelObject -Id $id -Label $d.label -Vendor $d.vendor -Kind $kind `
            -W ([int]$d.lcd_width) -H ([int]$d.lcd_height) -Shape 'auto' -Transport $transport `
            -Extra @{ instance_id = $d.instance_id; source = 'usb_hid' })
    }

    # OpenRGB LCD-looking devices
    $openRgb = Get-OpenRgbExecutable
    $blocking = Get-RgbBlockingProcesses
    if ($openRgb -and $blocking.Count -eq 0) {
        foreach ($og in @(Get-OpenRgbDeviceList -Exe $openRgb)) {
            $looksLcd = ($og.name -match 'LCD|Display|Screen|Kraken|ELITE|iCUE|Galahad|MasterLiquid|DeepCool|Thermaltake')
            if (-not $looksLcd) { continue }
            $id = "og_$($og.index)"
            if ($seen.ContainsKey($id)) { continue }
            $seen[$id] = $true
            $w = 480; $h = 480
            if ($og.name -match 'NZXT|Kraken') { $w = 640; $h = 640 }
            $vendor = 'OpenRGB'
            if ($og.name -match 'NZXT') { $vendor = 'NZXT' }
            elseif ($og.name -match 'Corsair|iCUE') { $vendor = 'Corsair' }
            elseif ($og.name -match 'Lian') { $vendor = 'Lian Li' }
            $transport = Resolve-LcdTransportPreference -Vendor $vendor -Kind 'aio_hid' -DeviceType 'aio_lcd'
            $panels += (New-LcdPanelObject -Id $id -Label $og.name -Vendor $vendor -Kind 'openrgb' `
                -W $w -H $h -Shape 'auto' -Transport $transport `
                -Extra @{ openrgb_index = $og.index; source = 'openrgb' })
        }
    }

    # Windows secondary displays (case panels / USB displays)
    $bounds = Get-LcdWindowsDisplayBounds
    $monMeta = @()
    try { $monMeta = @(Get-ProbeMonitors) } catch { $monMeta = @() }
    $mi = 0
    foreach ($b in $bounds) {
        $id = "disp_$($b.index)"
        if ($seen.ContainsKey($id)) { continue }
        $seen[$id] = $true
        $label = if ($b.primary) { "Display $($b.index) (primary)" } else { "Display $($b.index) (secondary)" }
        $mfr = ''
        if ($monMeta.Count -gt $mi) {
            $m = $monMeta[$mi]
            if ($m.name) { $label = "$($m.name) | $($b.width)x$($b.height)" }
            if ($m.manufacturer) { $mfr = $m.manufacturer }
        } else {
            $label = "$label | $($b.width)x$($b.height)"
        }
        # Prefer non-primary as case LCD candidates but list all
        $kind = if ($b.primary) { 'case_display' } else { 'case_display' }
        $panels += (New-LcdPanelObject -Id $id -Label $label -Vendor $(if ($mfr) { $mfr } else { 'Windows' }) `
            -Kind $kind -W ([int]$b.width) -H ([int]$b.height) -Shape 'auto' -Transport 'windows_display' `
            -Extra @{
                source = 'windows_display'
                display_index = $b.index
                display_bounds = @{ x = $b.x; y = $b.y; width = $b.width; height = $b.height }
                primary = [bool]$b.primary
                device_name = $b.device_name
            })
        $mi++
    }

    # Expand ASUS / generic detection stubs (stage_only) when PnP name matches LCD cooler language
    try {
        Get-PnpDevice -Class 'HIDClass','USB' -ErrorAction SilentlyContinue | ForEach-Object {
            $fn = "$($_.FriendlyName)"
            if ($fn -notmatch '(?i)LCD|AIO.?LCD|ROG.?RYUJIN|TUF.?LC|LCD.?Cooler|Sensor.?Panel|Smart.?Screen') { return }
            if ($_.Status -ne 'OK') { return }
            $hash = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($_.InstanceId)).Substring(0, 12) -replace '[^A-Za-z0-9]', 'x'
            $id = "pnp_$hash"
            if ($seen.ContainsKey($id)) { return }
            $seen[$id] = $true
            $vendor = 'Detected'
            if ($fn -match 'ASUS|ROG|TUF') { $vendor = 'ASUS' }
            $panels += (New-LcdPanelObject -Id $id -Label $fn -Vendor $vendor -Kind 'aio_hid' `
                -W 480 -H 480 -Shape 'round' -Transport 'stage_only' `
                -Extra @{ instance_id = $_.InstanceId; source = 'pnp_stub' })
        }
    } catch {}

    $liquidctl = Find-LcdLiquidctl
    $ffmpeg = Find-LcdFfmpeg
    return @{
        ok = $true
        scanned_at = (Get-Date).ToUniversalTime().ToString('o')
        panel_count = @($panels).Count
        panels = @($panels)
        tools = @{
            ffmpeg = $ffmpeg
            liquidctl = $liquidctl
            openrgb = (Get-OpenRgbExecutable)
        }
        note = 'LCD Studio panels: windows_display for long video; liquidctl/openrgb for AIO HID; stage_only when protocol missing.'
    }
}

function Detect-LcdMediaKind {
    param([byte[]]$Bytes, [string]$FileName = '')
    if ($Bytes -and $Bytes.Length -ge 6) {
        if ($Bytes[0] -eq 0x47 -and $Bytes[1] -eq 0x49 -and $Bytes[2] -eq 0x46) { return 'gif' }
        if ($Bytes[0] -eq 0x1A -and $Bytes[1] -eq 0x45 -and $Bytes[2] -eq 0xDF -and $Bytes[3] -eq 0xA3) { return 'webm' }
        # MP4 / ISO BMFF often has 'ftyp' at offset 4
        if ($Bytes.Length -ge 12) {
            $ftyp = [Text.Encoding]::ASCII.GetString($Bytes[4..7])
            if ($ftyp -eq 'ftyp') { return 'mp4' }
        }
    }
    $ext = [IO.Path]::GetExtension($FileName).ToLower()
    switch ($ext) {
        '.gif' { return 'gif' }
        '.mp4' { return 'mp4' }
        '.webm' { return 'webm' }
        '.mov' { return 'mp4' }
        '.mkv' { return 'mp4' }
        default { return 'unknown' }
    }
}

function Invoke-LcdMediaFit {
    param(
        [string]$SourcePath,
        [int]$TargetW,
        [int]$TargetH,
        [string]$FitMode = 'fit',  # fit | fill | stretch | round_mask
        [string]$OutKind = 'auto'  # auto | gif | mp4
    )
    if (-not (Test-Path $SourcePath)) {
        return @{ ok = $false; error = 'missing_source'; message = 'Source media not found.' }
    }
    $TargetW = [Math]::Max(64, [Math]::Min(4096, $TargetW))
    $TargetH = [Math]::Max(64, [Math]::Min(4096, $TargetH))
    $ext = [IO.Path]::GetExtension($SourcePath).ToLower()
    $kind = Detect-LcdMediaKind -Bytes ([IO.File]::ReadAllBytes($SourcePath) | Select-Object -First 32) -FileName $SourcePath
    if ($OutKind -eq 'auto') {
        $OutKind = if ($kind -eq 'gif' -and $FitMode -ne 'round_mask') { 'gif' } else { 'mp4' }
        if ($kind -eq 'gif' -and -not (Find-LcdFfmpeg)) { $OutKind = 'gif' }
    }

    $lib = Get-LcdLibraryDir
    $stamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
    $outExt = if ($OutKind -eq 'gif') { '.gif' } else { '.mp4' }
    $outPath = Join-Path $lib ("fit_${TargetW}x${TargetH}_${FitMode}_$stamp$outExt")

    $ffmpeg = Find-LcdFfmpeg
    if (-not $ffmpeg) {
        # No transcoder - copy as-is; display player will CSS-fit
        $copyPath = Join-Path $lib ("raw_$stamp$ext")
        Copy-Item $SourcePath $copyPath -Force
        return @{
            ok = $true
            path = $copyPath
            transcoded = $false
            fit_mode = $FitMode
            target_w = $TargetW
            target_h = $TargetH
            kind = $kind
            fallback = 'ffmpeg_missing'
            note = 'ffmpeg not found - media stored as-is; display player letterboxes. Place tools/ffmpeg/ffmpeg.exe for panel-fit transcode.'
        }
    }

    # scale + pad (fit) / crop (fill) / stretch / round via geq alpha on PNG sequence→mp4 is heavy;
    # for round_mask we produce mp4 with black letterbox and rely on player CSS circle clip for display;
    # HID path gets centered fit into WxH.
    $vf = switch ($FitMode) {
        'stretch' { "scale=${TargetW}:${TargetH}" }
        'fill' { "scale=${TargetW}:${TargetH}:force_original_aspect_ratio=increase,crop=${TargetW}:${TargetH}" }
        'round_mask' { "scale=${TargetW}:${TargetH}:force_original_aspect_ratio=decrease,pad=${TargetW}:${TargetH}:(ow-iw)/2:(oh-ih)/2:black" }
        default { "scale=${TargetW}:${TargetH}:force_original_aspect_ratio=decrease,pad=${TargetW}:${TargetH}:(ow-iw)/2:(oh-ih)/2:black" }
    }

    $args = @('-y', '-i', $SourcePath, '-vf', $vf)
    if ($OutKind -eq 'gif') {
        $args += @('-loop', '0', $outPath)
    } else {
        $args += @('-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', '-an', '-b:v', '2M', $outPath)
    }
    try {
        $p = Start-Process -FilePath $ffmpeg -ArgumentList $args -Wait -PassThru -NoNewWindow -RedirectStandardError (Join-Path $env:TEMP 'pclab_ffmpeg_err.txt')
        if ($p.ExitCode -ne 0 -or -not (Test-Path $outPath)) {
            $copyPath = Join-Path $lib ("raw_fallback_$stamp$ext")
            Copy-Item $SourcePath $copyPath -Force
            return @{
                ok = $true
                path = $copyPath
                transcoded = $false
                fit_mode = $FitMode
                fallback = 'ffmpeg_failed'
                note = 'ffmpeg failed - using original file.'
            }
        }
        return @{
            ok = $true
            path = $outPath
            transcoded = $true
            fit_mode = $FitMode
            target_w = $TargetW
            target_h = $TargetH
            kind = $OutKind
            round_mask_hint = ($FitMode -eq 'round_mask')
        }
    } catch {
        $copyPath = Join-Path $lib ("raw_err_$stamp$ext")
        Copy-Item $SourcePath $copyPath -Force
        return @{ ok = $true; path = $copyPath; transcoded = $false; fallback = 'exception'; note = $_.Exception.Message }
    }
}

function Invoke-LcdOpenRgbPush {
    param([string]$MediaPath, [int]$OpenRgbIndex = -1)
    . "$PSScriptRoot\rgb.ps1"
    return Invoke-ProbeLcdPush -DeviceId "studio_$OpenRgbIndex" -GifPath $MediaPath -OpenRgbIndex $OpenRgbIndex
}

function Invoke-LcdLiquidctlPush {
    param([string]$MediaPath, [string]$Match = 'kraken')
    $exe = Find-LcdLiquidctl
    if (-not $exe) {
        return @{
            pushed = $false
            attempted = $false
            transport = 'liquidctl'
            reason = 'liquidctl_missing'
            message = 'liquidctl not found. Place tools/liquidctl.exe or install liquidctl on PATH for NZXT LCD push.'
        }
    }
    if (-not (Test-Path $MediaPath)) {
        return @{ pushed = $false; attempted = $false; transport = 'liquidctl'; reason = 'missing_media' }
    }
    # Prefer GIF for liquidctl screen gif; if mp4, try anyway then fail honest
    $kind = Detect-LcdMediaKind -FileName $MediaPath -Bytes ([IO.File]::ReadAllBytes($MediaPath) | Select-Object -First 16)
    $mode = if ($kind -eq 'gif') { 'gif' } else { 'static' }
    $argsTried = @()
    $ok = $false
    $err = ''
    foreach ($cmd in @(
        @('--match', $Match, 'set', 'lcd', 'screen', 'gif', $MediaPath),
        @('--match', $Match, 'set', 'screen', 'gif', $MediaPath),
        @('set', 'lcd', 'screen', 'gif', $MediaPath)
    )) {
        $argsTried += ($cmd -join ' ')
        try {
            $out = & $exe @cmd 2>&1 | Out-String
            if ($LASTEXITCODE -eq 0) { $ok = $true; break }
            $err = $out
        } catch { $err = $_.Exception.Message }
    }
    return @{
        pushed = $ok
        attempted = $true
        transport = 'liquidctl'
        mode = $mode
        commands_tried = $argsTried
        message = if ($ok) {
            'liquidctl reported success - verify on Kraken LCD.'
        } else {
            "liquidctl push failed ($err). Close NZXT CAM, run Probe elevated, ensure GIF (not only MP4) for HID."
        }
        reason = if ($ok) { 'ok' } else { 'liquidctl_failed' }
    }
}

function Invoke-LcdStageOnly {
    param([string]$MediaPath, [string]$PanelId)
    $stageDir = Join-Path (Get-LcdCacheDir) 'stage'
    if (-not (Test-Path $stageDir)) { New-Item -ItemType Directory -Path $stageDir -Force | Out-Null }
    $dest = Join-Path $stageDir ("stage_" + ($PanelId -replace '[^\w\-]', '_') + [IO.Path]::GetExtension($MediaPath))
    Copy-Item $MediaPath $dest -Force -ErrorAction SilentlyContinue
    return @{
        pushed = $false
        attempted = $false
        transport = 'stage_only'
        staged_path = $dest
        reason = 'stage_only'
        message = "Staged at $dest - open once in the vendor AIO app if no HID transport confirms push."
    }
}

function Get-LcdPlayerHtml {
    param(
        [string]$MediaPath,
        [string]$Mode = 'media',
        [string]$Shape = 'rect',
        [string]$FitMode = 'fit',
        [int]$Port = 18765
    )
    $mediaUri = ([Uri]$MediaPath).AbsoluteUri
    if ($Mode -eq 'dashboard') {
        $dash = Join-Path $env:LOCALAPPDATA 'PcLabKit\Probe\lcd-dashboard\index.html'
        if (Test-Path $dash) { return (Get-Content $dash -Raw) }
    }
    $maskCss = if ($Shape -eq 'round' -or $FitMode -eq 'round_mask') {
        'border-radius:50%;overflow:hidden;width:min(100vmin,100%);height:min(100vmin,100%);'
    } else { 'width:100%;height:100%;' }
    $objFit = switch ($FitMode) {
        'fill' { 'cover' }
        'stretch' { 'fill' }
        default { 'contain' }
    }
    $isVideo = $MediaPath -match '\.(mp4|webm|mov|mkv)$'
    if ($isVideo) {
        $mediaTag = "<video id='m' src='$mediaUri' autoplay loop muted playsinline style='width:100%;height:100%;object-fit:$objFit;background:#000'></video>"
    } else {
        $mediaTag = "<img id='m' src='$mediaUri' style='width:100%;height:100%;object-fit:$objFit;background:#000' alt='LCD'>"
    }
    $scriptJs = 'document.addEventListener("keydown",function(e){ if(e.key==="Escape") window.close(); });'
    return @"
<!DOCTYPE html><html><head><meta charset="utf-8"><title>PC Lab Kit LCD</title>
<style>
html,body{margin:0;height:100%;background:#000;overflow:hidden;display:flex;align-items:center;justify-content:center}
.wrap{$maskCss}
</style></head><body><div class="wrap">$mediaTag</div>
<script>$scriptJs</script></body></html>
"@
}

function Stop-LcdDisplayPlayer {
    $path = $script:LcdPlayerStatePath
    if (-not (Test-Path $path)) {
        return @{ ok = $true; stopped = $false; note = 'No active LCD player' }
    }
    try {
        $st = Get-Content $path -Raw | ConvertFrom-Json
        if ($st.pid) {
            Stop-Process -Id ([int]$st.pid) -Force -ErrorAction SilentlyContinue
        }
    } catch {}
    Remove-Item $path -Force -ErrorAction SilentlyContinue
    return @{ ok = $true; stopped = $true }
}

function Start-LcdDisplayPlayer {
    param(
        [string]$MediaPath,
        [int]$DisplayIndex = 0,
        [string]$Mode = 'media',
        [string]$Shape = 'rect',
        [string]$FitMode = 'fit',
        [hashtable]$Bounds = $null
    )
    Stop-LcdDisplayPlayer | Out-Null

    if ($Mode -eq 'media' -and -not (Test-Path $MediaPath)) {
        return @{ ok = $false; played_on_display = $false; error = 'missing_media' }
    }

    if (-not $Bounds) {
        $all = Get-LcdWindowsDisplayBounds
        if ($DisplayIndex -ge 0 -and $DisplayIndex -lt $all.Count) {
            $b = $all[$DisplayIndex]
            $Bounds = @{ x = $b.x; y = $b.y; width = $b.width; height = $b.height }
        } else {
            $Bounds = @{ x = 0; y = 0; width = 800; height = 600 }
        }
    }

    $playerDir = Get-LcdPlayerDir
    $htmlPath = Join-Path $playerDir 'player.html'
    $html = Get-LcdPlayerHtml -MediaPath $MediaPath -Mode $Mode -Shape $Shape -FitMode $FitMode
    [IO.File]::WriteAllText($htmlPath, $html, [Text.UTF8Encoding]::new($false))

    $fileUrl = ([Uri]$htmlPath).AbsoluteUri
    $x = [int]$Bounds.x
    $y = [int]$Bounds.y
    $w = [int]$Bounds.width
    $h = [int]$Bounds.height

    $browser = $null
    foreach ($c in @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
    )) {
        if (Test-Path $c) { $browser = $c; break }
    }

    if (-not $browser) {
        # Fallback: default association (not positioned)
        $proc = Start-Process -FilePath $htmlPath -PassThru
        @{
            pid = $proc.Id
            display_index = $DisplayIndex
            html = $htmlPath
            mode = $Mode
            started_at = (Get-Date).ToUniversalTime().ToString('o')
            positioned = $false
        } | ConvertTo-Json | Set-Content $script:LcdPlayerStatePath -Encoding UTF8
        return @{
            ok = $true
            played_on_display = $true
            transport = 'windows_display'
            pushed = $false
            positioned = $false
            pid = $proc.Id
            message = 'Opened LCD player in default browser (positioning unavailable without Edge/Chrome).'
        }
    }

    $args = @(
        "--app=$fileUrl",
        "--window-position=$x,$y",
        "--window-size=$w,$h",
        '--disable-features=TranslateUI',
        '--no-first-run'
    )
    $proc = Start-Process -FilePath $browser -ArgumentList $args -PassThru
    @{
        pid = $proc.Id
        display_index = $DisplayIndex
        html = $htmlPath
        media = $MediaPath
        mode = $Mode
        bounds = $Bounds
        started_at = (Get-Date).ToUniversalTime().ToString('o')
        positioned = $true
        browser = $browser
    } | ConvertTo-Json -Depth 5 | Set-Content $script:LcdPlayerStatePath -Encoding UTF8

    return @{
        ok = $true
        played_on_display = $true
        transport = 'windows_display'
        pushed = $false
        positioned = $true
        pid = $proc.Id
        display_index = $DisplayIndex
        bounds = $Bounds
        message = "LCD player on display $DisplayIndex ($w×$h). Esc closes the window; or POST /lcd/stop."
    }
}

function Find-LcdPanelById {
    param([string]$PanelId)
    $cat = Get-LcdPanelCatalog
    foreach ($p in @($cat.panels)) {
        if ($p.id -eq $PanelId) { return $p }
    }
    # Legacy RGB Lab ids: og_N already match; try openrgb_index / display_index suffixes
    if ($PanelId -match '^og_(\d+)$') {
        $idx = [int]$Matches[1]
        foreach ($p in @($cat.panels)) {
            if ($null -ne $p.openrgb_index -and [int]$p.openrgb_index -eq $idx) { return $p }
        }
    }
    if ($PanelId -match '^disp_(\d+)$') {
        $idx = [int]$Matches[1]
        foreach ($p in @($cat.panels)) {
            if ($null -ne $p.display_index -and [int]$p.display_index -eq $idx) { return $p }
        }
    }
    return $null
}

function Invoke-LcdStudioApply {
    param(
        [string]$PanelId,
        [byte[]]$Bytes = $null,
        [string]$FileName = 'media.gif',
        [string]$SourcePath = $null,
        [string]$FitMode = 'fit',
        [string]$Mode = 'media',
        [bool]$PlayDisplay = $false,
        [int]$DisplayIndex = -1,
        [int]$ExpectedW = 0,
        [int]$ExpectedH = 0,
        [int]$OpenRgbIndex = -1
    )

    $panel = Find-LcdPanelById -PanelId $PanelId
    if (-not $panel) {
        # Synthesize from upload context (legacy RGB Lab device rows)
        $w = if ($ExpectedW -gt 0) { $ExpectedW } else { 480 }
        $h = if ($ExpectedH -gt 0) { $ExpectedH } else { 480 }
        $transport = if ($PlayDisplay -or $PanelId -match '^disp_') { 'windows_display' }
            elseif ($OpenRgbIndex -ge 0) { 'openrgb' }
            elseif ($PanelId -match 'nzxt|kraken') { 'liquidctl' }
            else { 'openrgb' }
        $panel = New-LcdPanelObject -Id $PanelId -Label $PanelId -Vendor 'Lab' -Kind 'unknown' `
            -W $w -H $h -Shape 'auto' -Transport $transport -Extra @{
                openrgb_index = $(if ($OpenRgbIndex -ge 0) { $OpenRgbIndex } else { $null })
                source = 'synthesized'
            }
    }

    $mediaPath = $null
    $kind = 'unknown'
    $stored = $false
    $fit = $null
    if ($Mode -eq 'dashboard') {
        . "$PSScriptRoot\orchestrator.ps1"
        $dash = Write-ProbeLcdDashboard -Port 18765
        $mediaPath = $dash
        $kind = 'dashboard'
    } else {
        if ($SourcePath -and (Test-Path $SourcePath)) {
            $mediaPath = $SourcePath
        } elseif ($Bytes -and $Bytes.Length -gt 0) {
            $kind = Detect-LcdMediaKind -Bytes $Bytes -FileName $FileName
            if ($kind -eq 'unknown') {
                return @{
                    ok = $false
                    error = 'unsupported_media'
                    message = 'Accepted: GIF, MP4, WebM.'
                }
            }
            $maxMb = [int]$panel.capabilities.max_mb
            if ($Bytes.Length -gt ($maxMb * 1MB)) {
                return @{ ok = $false; error = 'too_large'; message = "File exceeds ${maxMb} MB for this panel transport." }
            }
            $ext = switch ($kind) { 'gif' { '.gif' } 'webm' { '.webm' } default { '.mp4' } }
            $rawPath = Join-Path (Get-LcdLibraryDir) ("upload_" + ($PanelId -replace '[^\w\-]', '_') + "_$(Get-Date -Format 'yyyyMMdd_HHmmss')$ext")
            [IO.File]::WriteAllBytes($rawPath, $Bytes)
            $mediaPath = $rawPath
            $stored = $true
        } else {
            return @{ ok = $false; error = 'no_media'; message = 'Provide media bytes or source_path.' }
        }

        $fit = Invoke-LcdMediaFit -SourcePath $mediaPath `
            -TargetW ([int]$panel.geometry.w) -TargetH ([int]$panel.geometry.h) `
            -FitMode $(if ($FitMode) { $FitMode } else { $panel.geometry.fit_default }) `
            -OutKind $(if ($panel.transport -eq 'windows_display') { 'auto' } else { 'gif' })
        if (-not $fit.ok) { return $fit }
        $mediaPath = $fit.path
        if ($fit.kind) { $kind = $fit.kind }
    }

    $transport = [string]$panel.transport
    $push = $null
    $play = $null
    $pushed = $false
    $played = $false

    $forceDisplay = $PlayDisplay -or $transport -eq 'windows_display' -or $Mode -eq 'dashboard'
    if ($forceDisplay) {
        $di = if ($DisplayIndex -ge 0) { $DisplayIndex } elseif ($null -ne $panel.display_index) { [int]$panel.display_index } else { 0 }
        $play = Start-LcdDisplayPlayer -MediaPath $mediaPath -DisplayIndex $di -Mode $(if ($Mode -eq 'dashboard') { 'dashboard' } else { 'media' }) `
            -Shape $panel.geometry.shape -FitMode $FitMode -Bounds $panel.display_bounds
        $played = [bool]$play.played_on_display
    }

    if ($transport -ne 'windows_display' -or -not $forceDisplay) {
        switch ($transport) {
            'liquidctl' {
                $push = Invoke-LcdLiquidctlPush -MediaPath $mediaPath
                $pushed = [bool]$push.pushed
                if (-not $pushed) {
                    $stage = Invoke-LcdStageOnly -MediaPath $mediaPath -PanelId $PanelId
                    $push.staged_path = $stage.staged_path
                    $push.fallback = 'stage_only'
                }
            }
            'openrgb' {
                $ogi = -1
                if ($null -ne $panel.openrgb_index) { $ogi = [int]$panel.openrgb_index }
                elseif ($OpenRgbIndex -ge 0) { $ogi = $OpenRgbIndex }
                $push = Invoke-LcdOpenRgbPush -MediaPath $mediaPath -OpenRgbIndex $ogi
                $push.transport = 'openrgb'
                $pushed = [bool]$push.pushed
                if (-not $pushed) {
                    $stage = Invoke-LcdStageOnly -MediaPath $mediaPath -PanelId $PanelId
                    if (-not $push.staged_path) { $push.staged_path = $stage.staged_path }
                    $push.fallback = 'stage_only'
                }
            }
            'windows_display' { }
            default {
                if (-not $played) {
                    $push = Invoke-LcdStageOnly -MediaPath $mediaPath -PanelId $PanelId
                }
            }
        }
    }

    $headline = if ($pushed) {
        'Applied to device (HID confirmed)'
    } elseif ($played) {
        'Playing on Windows display'
    } else {
        'Saved / staged - hardware not confirmed'
    }

    return @{
        ok = $true
        panel_id = $PanelId
        panel = @{
            id = $panel.id
            label = $panel.label
            transport = $transport
            geometry = $panel.geometry
        }
        media_path = $mediaPath
        media_kind = $kind
        stored_local = $stored
        fit_mode = $FitMode
        transport = $transport
        pushed = $pushed
        played_on_display = $played
        attempted = if ($push) { [bool]$push.attempted } else { $false }
        transcoded = if ($fit) { [bool]$fit.transcoded } else { $false }
        push = $push
        play = $play
        message = ($headline + '. ' + $(if ($push -and $push.message) { $push.message } elseif ($play -and $play.message) { $play.message } else { '' })).Trim()
        honesty = $panel.honesty
    }
}
