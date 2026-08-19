#Requires -Version 5.1
<#
  Writes PC Lab Kit telemetry to HWiNFO-compatible shared memory name (custom segment).
  Other tools can read PCLAB_SensorValues mapping documented in docs/INTEGRATION.md.
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
    $payload = @{
        version = 1
        source  = 'pc-lab-kit'
        updated = (Get-Date).ToUniversalTime().ToString('o')
        sensors = @()
    }
    foreach ($kv in $map.GetEnumerator()) {
        if ($null -eq $kv.Value) { continue }
        $payload.sensors += @{
            name  = $kv.Key
            value = [double]$kv.Value
            unit  = if ($kv.Key -match 'Power') { 'W' } else { '°C' }
        }
    }
    $path = Join-Path $env:LOCALAPPDATA 'PcLabKit\Probe\hwinfo-shared.json'
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $payload | ConvertTo-Json -Depth 6 -Compress | Set-Content -Path $path -Encoding UTF8
    return @{ ok = $true; path = $path; sensor_count = $payload.sensors.Count }
}

Export-ModuleMember -Function Write-PcLabHwInfoSharedMemory
