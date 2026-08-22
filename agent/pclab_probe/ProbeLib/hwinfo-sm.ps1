#Requires -Version 5.1
<#
  Writes PC Lab Kit telemetry to a JSON sensor feed (not binary HWiNFO Shared Memory).
  Path + schema are documented in docs/INTEGRATION.md for Rainmeter WebParser / overlays.
#>
function Write-PcLabHwInfoSharedMemory {
    param(
        [Parameter(Mandatory)][hashtable]$Telemetry
    )
    $map = @{
        'CPU Package'       = $Telemetry.cpu_temp
        'GPU Core'          = $Telemetry.gpu_temp
        'GPU Hot Spot'      = $Telemetry.gpu_hotspot
        'GPU Memory Junction' = $Telemetry.gpu_vram_temp
        'CPU Package Power' = $Telemetry.package_power_w
    }
    $path = Join-Path $env:LOCALAPPDATA 'PcLabKit\Probe\hwinfo-shared.json'
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $sensors = @()
    foreach ($kv in $map.GetEnumerator()) {
        if ($null -eq $kv.Value) { continue }
        $sensors += @{
            name  = $kv.Key
            value = [double]$kv.Value
            unit  = if ($kv.Key -match 'Power') { 'W' } else { '°C' }
        }
    }
    $payload = @{
        schema_version = 1
        version = 1
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
        schema_version = 1
        feed_kind = 'json_file'
        path = $path
        sensor_count = $payload.sensor_count
        sensors = $payload.sensors
        note = $payload.note
    }
}

Export-ModuleMember -Function Write-PcLabHwInfoSharedMemory
