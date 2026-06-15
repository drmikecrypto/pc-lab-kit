. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\rgb.ps1"

function Get-PcverseDataDir {
    $dir = Join-Path $env:LOCALAPPDATA "PCVerseProbe"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Export-VakhshFanCurves {
    param($Plan)
    $fans = $Plan.fans
    if (-not $fans) { return $null }
    $path = Join-Path (Get-PcverseDataDir) "fan-curves.json"
    @{
        engine = 'vakhsh'
        version = 1
        strategy = $fans.strategy
        hysteresis_c = $fans.hysteresis_c
        response_sec = $fans.response_sec
        sensors = $fans.sensors
        curves = $fans.curves
        fan_control_import_note = 'Import manually in Fan Control > Setup > Import'
    } | ConvertTo-Json -Depth 8 | Set-Content -Path $path -Encoding UTF8
    return $path
}

function Write-VakhshLcdDashboard {
    param($Plan, $Port = 18765)
    $dir = Join-Path (Get-PcverseDataDir) "lcd-dashboard"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $path = Join-Path $dir "index.html"
    $html = @"
<!DOCTYPE html>
<html lang="fa"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=480,height=480">
<title>وخش LCD</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:#0a0a12;color:#e2e8f0;font-family:Segoe UI,sans-serif;min-height:100vh;display:flex;align-items:center;justify-content:center}
.panel{text-align:center;padding:24px;width:100%;max-width:640px}
.brand{font-size:10px;letter-spacing:.2em;color:#a78bfa;margin-bottom:12px}
.temp{font-size:3.5rem;font-weight:900;color:#22d3ee;line-height:1}
.sub{font-size:13px;color:rgba(255,255,255,.45);margin-top:8px}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:24px}
.cell{background:rgba(255,255,255,.04);border-radius:12px;padding:14px;border:1px solid rgba(255,255,255,.08)}
.cell strong{display:block;font-size:1.4rem;color:#f29f05}
.cell span{font-size:10px;color:rgba(255,255,255,.4)}
.warn{color:#ff4466!important}
</style></head>
<body>
<div class="panel">
<div class="brand">وخش · SENSOR PANEL</div>
<div class="temp" id="main">—°</div>
<div class="sub" id="sub">PCVerse Probe localhost</div>
<div class="grid">
<div class="cell"><strong id="cpu">—</strong><span>CPU °C</span></div>
<div class="cell"><strong id="gpu">—</strong><span>GPU °C</span></div>
<div class="cell"><strong id="vcore">—</strong><span>Vcore</span></div>
<div class="cell"><strong id="fps">—</strong><span>FPS</span></div>
</div></div>
<script>
const AG='http://127.0.0.1:$Port';
async function tick(){
  try{
    const r=await fetch(AG+'/telemetry');
    const t=await r.json();
    const c=t.cpu?.thermal?.package_c||0;
    const g=t.gpu?.thermal?.core_c||0;
    const mx=Math.max(c,g);
    document.getElementById('main').textContent=mx.toFixed(0)+'°';
    document.getElementById('main').className='temp'+(mx>=85?' warn':'');
    document.getElementById('cpu').textContent=c?c.toFixed(0):'—';
    document.getElementById('gpu').textContent=g?g.toFixed(0):'—';
    document.getElementById('vcore').textContent=(t.power?.vcore||t.cpu?.power?.vcore||'—');
    document.getElementById('fps').textContent=t.gaming?.fps_avg||'—';
    document.getElementById('sub').textContent='GPU '+((t.gpu?.render?.gpu_util_pct)||0).toFixed(0)+'% util';
  }catch(e){document.getElementById('sub').textContent='Probe offline';}
}
setInterval(tick,2000);tick();
</script></body></html>
"@
    [System.IO.File]::WriteAllText($path, $html, [System.Text.UTF8Encoding]::new($false))
    return $path
}

function Map-RgbZonesFromPlan {
    param($Scan, $RgbPlan)
    $zones = @()
    $roleMap = @{}
    foreach ($r in @($RgbPlan.zones)) { $roleMap[$r.role] = $r }

    foreach ($dev in @($Scan.devices)) {
        foreach ($z in @($dev.zones)) {
            if ($z.openrgb_device -eq $null) { continue }
            $role = 'strip'
            $zt = [string]$z.zone_type
            if ($zt -match 'fan_ring|fan_led|fan_center') { $role = 'fan_ring' }
            elseif ($zt -match 'pump_ring') { $role = 'pump_ring' }
            elseif ($zt -match 'lcd|pump_lcd') { continue }
            elseif ($zt -match 'strip|case') { $role = 'strip' }

            $spec = $roleMap[$role]
            if (-not $spec) { $spec = $roleMap['strip'] }
            if (-not $spec) { continue }

            $color = [string]$spec.color
            $zones += @{
                zone_id = $z.zone_id
                openrgb_device = $z.openrgb_device
                openrgb_zone = $z.openrgb_zone
                effect = [string]$spec.effect
                color = $color
                speed = [int]$spec.speed
                role = $role
            }
        }
    }
    return $zones
}

function Invoke-VakhshOrchestrate {
    param($Payload)

    $scan = Get-RgbDeviceScan
    $plan = $Payload.plan
    if (-not $plan) {
        return @{ ok = $false; error = 'no_plan'; message_fa = 'پلن orchestration از سرور نیامد.' }
    }

    $conflicts = Get-RgbBlockingProcesses
    $result = @{
        ok = $false
        engine = 'vakhsh'
        profile = $plan.profile
        conflicts_detected = $conflicts
        conflicts_closed = @()
        applied = @()
        fan_curve_path = $null
        lcd_dashboard_path = $null
    }

    # Fan curves + LCD always local (no OpenRGB needed)
    $result.fan_curve_path = Export-VakhshFanCurves -Plan $plan
    $result.lcd_dashboard_path = Write-VakhshLcdDashboard -Plan $plan

    if (-not $scan.control.ready) {
        $result.ok = $true
        $result.partial = $true
        $result.enable_guide = $scan.enable_guide
        $result.message_fa = 'داشبورد LCD و منحنی فن آماده شد — RGB وقتی OpenRGB فعال باشد sync می‌شود.'
        return $result
    }

    $rgbZones = Map-RgbZonesFromPlan -Scan $scan -RgbPlan $plan.rgb
    if ($rgbZones.Count -gt 0) {
        $apply = Invoke-RgbApplySettings -Settings @{ zones = $rgbZones }
        $result.applied = @($apply.applied)
        $result.ok = $apply.ok
    } else {
        $result.ok = $true
        $result.partial = $true
    }

    $result.message_fa = 'وخش setup حرفه‌ای اعمال شد.'
    return $result
}

function Invoke-VakhshRgbAuto {
    param(
        [hashtable]$Telemetry = @{},
        [hashtable]$Scan = @{},
        [hashtable]$Plan = $null
    )

    if ($Plan -and $Plan.rgb) {
        $orch = Invoke-VakhshOrchestrate -Payload @{ plan = $Plan }
        return $orch
    }

    if (-not $Scan.control.ready) {
        return @{ ok = $false; error = 'control_not_ready'; enable_guide = $Scan.enable_guide }
    }

    $cpuTemp = 45.0
    $gpuTemp = 50.0
    if ($Telemetry.cpu_temp) { $cpuTemp = [double]$Telemetry.cpu_temp }
    elseif ($Telemetry.cpu -and $Telemetry.cpu.thermal) { $cpuTemp = [double]$Telemetry.cpu.thermal.package_c }
    if ($Telemetry.gpu_temp) { $gpuTemp = [double]$Telemetry.gpu_temp }
    elseif ($Telemetry.gpu -and $Telemetry.gpu.thermal) { $gpuTemp = [double]$Telemetry.gpu.thermal.core_c }

    $maxT = [Math]::Max($cpuTemp, $gpuTemp)
    $color = if ($maxT -ge 85) { 'FF3355' } elseif ($maxT -ge 70) { 'F29F05' } else { '00E5CC' }
    $effect = if ($maxT -ge 75) { 'pulse' } else { 'breathing' }

    $zones = @()
    foreach ($dev in @($Scan.devices)) {
        foreach ($z in @($dev.zones)) {
            if ($z.openrgb_device -ne $null) {
                $zones += @{
                    zone_id = $z.zone_id
                    openrgb_device = $z.openrgb_device
                    openrgb_zone = $z.openrgb_zone
                    effect = $effect
                    color = $color
                    speed = 50
                }
            }
        }
    }

    if ($zones.Count -eq 0) {
        return @{ ok = $false; error = 'no_controllable_zones' }
    }

    $result = Invoke-RgbApplySettings -Settings @{ zones = $zones }
    $result.vakhsh = @{
        profile = 'thermal_sync'
        summary_fa = "وخش: CPU ${cpuTemp}°C · GPU ${gpuTemp}°C → #$color"
    }
    return $result
}
