. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\rgb.ps1"

function Get-ProbeDataDir {
    $dir = Join-Path $env:LOCALAPPDATA "PcLabKit\Probe"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Export-ProbeFanCurves {
    param($Plan)
    $fans = $Plan.fans
    if (-not $fans) { return $null }
    $path = Join-Path (Get-ProbeDataDir) "fan-curves.json"
    @{
        engine = 'orchestrator'
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

function Write-ProbeLcdDashboard {
    param($Plan, $Port = 18765, [int]$Width = 480, [int]$Height = 480)
    $dir = Join-Path (Get-ProbeDataDir) "lcd-dashboard"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $path = Join-Path $dir "index.html"
    $W = [Math]::Max(240, [Math]::Min(3840, $Width))
    $H = [Math]::Max(240, [Math]::Min(2160, $Height))
    $html = @"
<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=$W,height=$H">
<title>PC Lab Kit LCD</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:100%;height:100%;overflow:hidden;background:#05060a;color:#e8eef7;font-family:Segoe UI,system-ui,sans-serif}
.shell{min-height:100%;padding:clamp(12px,3vmin,28px);display:flex;flex-direction:column;justify-content:space-between;background:radial-gradient(120% 80% at 50% 0%,#12182a 0%,#05060a 55%)}
.brand{font-size:clamp(9px,1.6vmin,12px);letter-spacing:.22em;text-transform:uppercase;color:#7dd3c7;opacity:.9}
.hero{margin-top:clamp(8px,2vmin,18px)}
.temp{font-size:clamp(2.6rem,12vmin,5.5rem);font-weight:800;color:#5eead4;line-height:1;font-variant-numeric:tabular-nums}
.temp.warn{color:#fb7185}
.sub{margin-top:6px;font-size:clamp(11px,2vmin,14px);color:rgba(232,238,247,.5)}
.grid{display:grid;grid-template-columns:1fr 1fr 1fr;gap:clamp(8px,1.5vmin,14px);margin-top:clamp(16px,3vmin,28px)}
.cell{background:rgba(255,255,255,.04);border:1px solid rgba(255,255,255,.08);border-radius:10px;padding:clamp(10px,2vmin,16px)}
.cell strong{display:block;font-size:clamp(1.1rem,3.4vmin,1.8rem);color:#fbbf24;font-variant-numeric:tabular-nums}
.cell span{font-size:clamp(9px,1.5vmin,11px);color:rgba(232,238,247,.42);letter-spacing:.04em}
.foot{font-size:clamp(9px,1.4vmin,11px);color:rgba(232,238,247,.35);margin-top:auto;padding-top:12px}
</style></head>
<body>
<div class="shell">
  <div>
    <div class="brand">PC Lab Kit | Sensor panel</div>
    <div class="hero">
      <div class="temp" id="main">-</div>
      <div class="sub" id="sub">Probe localhost</div>
    </div>
    <div class="grid">
      <div class="cell"><strong id="cpu">-</strong><span>CPU C</span></div>
      <div class="cell"><strong id="gpu">-</strong><span>GPU C</span></div>
      <div class="cell"><strong id="hot">-</strong><span>Hot spot</span></div>
      <div class="cell"><strong id="cpup">-</strong><span>CPU W</span></div>
      <div class="cell"><strong id="gpup">-</strong><span>GPU W</span></div>
      <div class="cell"><strong id="load">-</strong><span>CPU %</span></div>
      <div class="cell"><strong id="gpul">-</strong><span>GPU %</span></div>
      <div class="cell"><strong id="ram">-</strong><span>RAM %</span></div>
      <div class="cell"><strong id="fps">-</strong><span>FPS</span></div>
    </div>
  </div>
  <div class="foot" id="foot">display path</div>
</div>
<script>
const AG='http://127.0.0.1:$Port';
const PANEL_W=$W;
const PANEL_H=$H;
function n(v,d){if(v===null||v===undefined||v==='')return '-';const x=Number(v);return Number.isFinite(x)?x.toFixed(d):String(v)}
async function tick(){
  try{
    const r=await fetch(AG+'/telemetry');
    const t=await r.json();
    const c=t.cpu?.thermal?.package_c||0;
    const g=t.gpu?.thermal?.core_c||t.gpu?.thermal?.hotspot_c||0;
    const hot=t.gpu?.thermal?.hotspot_c||g;
    const mx=Math.max(c,g,hot||0);
    const main=document.getElementById('main');
    main.textContent=mx?mx.toFixed(0)+'\u00b0':'-';
    main.className='temp'+(mx>=85?' warn':'');
    document.getElementById('cpu').textContent=c?n(c,0):'-';
    document.getElementById('gpu').textContent=g?n(g,0):'-';
    document.getElementById('hot').textContent=hot?n(hot,0):'-';
    document.getElementById('cpup').textContent=n(t.cpu?.power?.package_w||t.power?.cpu_w,0);
    document.getElementById('gpup').textContent=n(t.gpu?.power?.board_w||t.gpu?.power?.package_w,0);
    document.getElementById('load').textContent=n(t.cpu?.load?.total_pct||t.cpu?.util_pct,0);
    document.getElementById('gpul').textContent=n(t.gpu?.render?.gpu_util_pct,0);
    document.getElementById('ram').textContent=n(t.memory?.used_pct||t.ram?.used_pct,0);
    const fps=t.gaming?.fps_avg||t.presentmon?.fps_avg||t.fps?.avg;
    document.getElementById('fps').textContent=fps?n(fps,0):'-';
    document.getElementById('sub').textContent='GPU '+n(t.gpu?.render?.gpu_util_pct,0)+'% | RAM '+n(t.memory?.used_pct||t.ram?.used_pct,0)+'%';
    document.getElementById('foot').textContent=PANEL_W+'x'+PANEL_H+' | live telemetry';
  }catch(e){document.getElementById('sub').textContent='Probe offline'}
}
setInterval(tick,1500);tick();
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

function Invoke-ProbeOrchestrate {
    param($Payload)

    $scan = Get-RgbDeviceScan
    $plan = $Payload.plan
    if (-not $plan) {
        return @{ ok = $false; error = 'no_plan'; message_fa = 'پلن orchestration از سرور نیامد.' }
    }

    $conflicts = Get-RgbBlockingProcesses
    $result = @{
        ok = $false
        engine = 'orchestrator'
        profile = $plan.profile
        conflicts_detected = $conflicts
        conflicts_closed = @()
        applied = @()
        fan_curve_path = $null
        lcd_dashboard_path = $null
    }

    # Fan curves + LCD always local (no OpenRGB needed)
    $result.fan_curve_path = Export-ProbeFanCurves -Plan $plan
    $result.lcd_dashboard_path = Write-ProbeLcdDashboard -Plan $plan

    if (-not $scan.control.ready) {
        $result.ok = $true
        $result.partial = $true
        $result.enable_guide = $scan.enable_guide
        $result.message_fa = 'داشبورد LCD و منحنی فن آماده شد - RGB وقتی OpenRGB فعال باشد sync می‌شود.'
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

    $result.message_fa = 'Orchestrator setup حرفه‌ای اعمال شد.'
    return $result
}

function Invoke-ProbeRgbAuto {
    param(
        [hashtable]$Telemetry = @{},
        [hashtable]$Scan = @{},
        [hashtable]$Plan = $null
    )

    if ($Plan -and $Plan.rgb) {
        $orch = Invoke-ProbeOrchestrate -Payload @{ plan = $Plan }
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
    $result.orchestrator = @{
        profile = 'thermal_sync'
        summary_fa = "Lab: CPU ${cpuTemp}°C · GPU ${gpuTemp}°C -> #$color"
    }
    return $result
}
