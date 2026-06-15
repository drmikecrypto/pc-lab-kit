. "$PSScriptRoot\common.ps1"

function Get-ProbeHwMonTelemetry {
    $exe = Join-Path (Split-Path $PSScriptRoot -Parent) "PcVerseHwMon.exe"
    if (-not (Test-Path $exe)) {
        return @{ available = $false; note = "PcVerseHwMon.exe not built — run scripts/build-pcverse-hwmon.ps1" }
    }

    try {
        $json = & $exe 2>$null
        if (-not $json) { return @{ available = $false } }
        $data = $json | ConvertFrom-Json
        return @{
            available = $true
            collector = "libre-hardware-monitor"
            collected_at = $data.collected_at
            hardware = $data.hardware
            sensors_flat = $data.sensors_flat
            by_type = $data.by_type
            vcore = Find-SensorValue $data.sensors_flat @('CPU Core', 'Vcore', 'Core VID', 'CPU Package')
            vrm = Find-Sensors $data.sensors_flat 'Temperature' | Where-Object { $_.name -match 'VRM|VR' }
            hotspots = Find-Sensors $data.sensors_flat 'Temperature' | Where-Object { $_.value -gt 0 }
        }
    } catch {
        return @{ available = $false; error = $_.Exception.Message }
    }
}

function Find-SensorValue($flat, [string[]]$nameHints) {
    if (-not $flat) { return $null }
    foreach ($s in $flat) {
        foreach ($h in $nameHints) {
            if ($s.name -like "*$h*" -and $s.type -eq 'Voltage') {
                return [math]::Round([double]$s.value, 3)
            }
        }
    }
    return $null
}

function Find-Sensors($flat, [string]$type) {
    if (-not $flat) { return @() }
    return @($flat | Where-Object { $_.type -eq $type })
}
