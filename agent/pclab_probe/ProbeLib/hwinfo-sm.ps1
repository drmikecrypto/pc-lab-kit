#Requires -Version 5.1
<#
  Writes PC Lab Kit telemetry to a JSON sensor feed (not binary HWiNFO Shared Memory).
  Dense channel set for Rainmeter / overlays — see docs/INTEGRATION.md.
#>
function Write-PcLabHwInfoSharedMemory {
    param(
        [Parameter(Mandatory)][hashtable]$Telemetry
    )
    $map = [ordered]@{
        'CPU Package'         = $Telemetry.cpu_temp
        'CPU Hot Spot'        = $Telemetry.cpu_hotspot
        'GPU Core'            = $Telemetry.gpu_temp
        'GPU Hot Spot'        = $Telemetry.gpu_hotspot
        'GPU Memory Junction' = $Telemetry.gpu_vram_temp
        'CPU Package Power'   = $Telemetry.package_power_w
        'GPU Board Power'     = $Telemetry.gpu_power_w
        'CPU Load'            = $Telemetry.cpu_load
        'GPU Load'            = $Telemetry.gpu_util
        'RAM Used %'          = $Telemetry.ram_used_pct
        'Fan RPM'             = $Telemetry.fan_rpm
        'Vcore'               = $Telemetry.vcore
        'FPS Avg'             = $Telemetry.fps
        'FPS 1% Low'          = $Telemetry.fps_1pct_low
    }
    $path = Join-Path $env:LOCALAPPDATA 'PcLabKit\Probe\hwinfo-shared.json'
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $sensors = @()
    foreach ($kv in $map.GetEnumerator()) {
        if ($null -eq $kv.Value -or "$($kv.Value)" -eq '') { continue }
        $unit = '°C'
        if ($kv.Key -match 'Power') { $unit = 'W' }
        elseif ($kv.Key -match 'Load|Used %|FPS') { $unit = if ($kv.Key -match 'FPS') { 'FPS' } else { '%' } }
        elseif ($kv.Key -match 'RPM') { $unit = 'RPM' }
        elseif ($kv.Key -match 'Vcore') { $unit = 'V' }
        $sensors += @{
            name  = $kv.Key
            value = [double]$kv.Value
            unit  = $unit
        }
    }
    $payload = @{
        schema_version = 2
        version = 2
        source  = 'pc-lab-kit'
        feed_kind = 'json_file'
        note = 'JSON sensor feed — not binary HWiNFO Shared Memory. See docs/INTEGRATION.md.'
        updated = (Get-Date).ToUniversalTime().ToString('o')
        path = $path
        sensors = @($sensors)
        sensor_count = @($sensors).Count
    }
    $payload | ConvertTo-Json -Depth 6 -Compress | Set-Content -Path $path -Encoding UTF8
    return @{
        ok = $true
        schema_version = 2
        feed_kind = 'json_file'
        path = $path
        sensor_count = $payload.sensor_count
        sensors = $payload.sensors
        note = $payload.note
    }
}
