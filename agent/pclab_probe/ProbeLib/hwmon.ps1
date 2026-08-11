. "$PSScriptRoot\common.ps1"

<#
 Runs the bundled LibreHardwareMonitor collector.

 CPU die temperatures and most board sensors come from model-specific registers and
 SMBus, which need a kernel helper that only loads when the process is elevated.
 When the probe runs unelevated the collector still returns GPU and storage data but
 the CPU node comes back empty, which is why the report was previously falling back
 to ACPI zones. The `elevated` flag makes that visible instead of silently wrong.
#>
function Get-ProbeHwMonTelemetry {
    $exe = Join-Path (Split-Path $PSScriptRoot -Parent) "PcLabHwMon.exe"
    $elevated = Test-ProbeElevated

    if (-not (Test-Path $exe)) {
        return @{
            available = $false
            elevated  = $elevated
            note      = "PcLabHwMon.exe not built - run scripts/build-pclab-hwmon.ps1"
        }
    }

    try {
        $json = & $exe 2>$null
        if (-not $json) {
            return @{ available = $false; elevated = $elevated; note = "Collector produced no output" }
        }
        $data = ($json -join "`n") | ConvertFrom-Json

        $flat = @($data.sensors_flat)
        $cpuSensors = @($flat | Where-Object { "$($_.hardware_type)" -eq 'Cpu' -and "$($_.type)" -eq 'Temperature' })

        # Tag every flat sensor with source + confidence for Hardware Reference.
        $flatTagged = @()
        foreach ($s in $flat) {
            $row = @{
                name          = $s.name
                type          = $s.type
                value         = $s.value
                unit          = $s.unit
                hardware      = $s.hardware
                hardware_type = $s.hardware_type
                source        = 'libre-hardware-monitor'
                confidence    = if ($elevated -or ("$($s.hardware_type)" -ne 'Cpu')) { 'measured' } else { 'heuristic' }
                elevated      = $elevated
                plausible     = $true
            }
            if ("$($s.type)" -eq 'Temperature') {
                $t = 0.0
                if ([double]::TryParse("$($s.value)", [ref]$t)) {
                    $row.plausible = ($t -ge 5 -and $t -le 125)
                    if (-not $row.plausible) { $row.confidence = 'heuristic' }
                }
            }
            $flatTagged += $row
        }
        $flat = $flatTagged

        $result = @{
            available      = $true
            collector      = "libre-hardware-monitor"
            collected_at   = $data.collected_at
            elevated       = $elevated
            hardware       = $data.hardware
            sensors_flat   = $flat
            by_type        = $data.by_type
            sensor_count   = $flat.Count
            cpu_sensor_count = $cpuSensors.Count
            vcore          = Find-SensorValue $flat @('CPU Core', 'Vcore', 'Core VID', 'CPU Package')
            vrm            = @(Find-Sensors $flat 'Temperature' | Where-Object { $_.name -match 'VRM|VR ' })
            fans           = @(Find-Sensors $flat 'Fan')
            temperatures   = @(Find-Sensors $flat 'Temperature' | Where-Object { $_.value -gt 0 })
        }
        # Retained for older report consumers that looked for a generic hotspot list.
        $result.hotspots = @($result.temperatures | Where-Object { $_.name -match 'Hot ?Spot|Junction' })

        if ($data.environment) { $result.environment = $data.environment }
        if ($data.resolved) { $result.resolved = $data.resolved }

        if ($cpuSensors.Count -eq 0) {
            $result.note = if ($elevated) {
                "No CPU temperature sensors exposed. The kernel helper may be blocked by an anti-cheat or security driver."
            } else {
                "No CPU temperature sensors. Restart the probe as Administrator - CPU die sensors need elevation."
            }
        }

        return $result
    } catch {
        return @{ available = $false; elevated = $elevated; error = $_.Exception.Message }
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
