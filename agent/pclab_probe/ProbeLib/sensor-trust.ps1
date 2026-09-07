. "$PSScriptRoot\common.ps1"

<#
  Sensor trust path - PcLabHwMon (LHM-backed, elevated Ring0) vs HwMon-only,
  plus competing Ring0 / sensor-tool conflict detection.
  We do not ship WinRing0.sys; trust story is signed helper + conflict banner.
#>

function Get-SensorCompetingTools {
    $candidates = @(
        @{ pattern = 'HWiNFO64'; label = 'HWiNFO' }
        @{ pattern = 'HWiNFO32'; label = 'HWiNFO' }
        @{ pattern = 'LibreHardwareMonitor'; label = 'LibreHardwareMonitor' }
        @{ pattern = 'OpenHardwareMonitor'; label = 'OpenHardwareMonitor' }
        @{ pattern = 'FanControl'; label = 'FanControl' }
        @{ pattern = 'MSIAfterburner'; label = 'MSI Afterburner' }
        @{ pattern = 'RTSS'; label = 'RivaTuner (RTSS)' }
        @{ pattern = 'RTSSHooksLoader64'; label = 'RivaTuner (RTSS)' }
        @{ pattern = 'AIDA64*'; label = 'AIDA64' }
        @{ pattern = 'OCCT*'; label = 'OCCT' }
    )
    $found = [System.Collections.Generic.List[string]]::new()
    $seen = @{}
    foreach ($c in $candidates) {
        if (Get-Process -Name $c.pattern -ErrorAction SilentlyContinue) {
            if (-not $seen.ContainsKey($c.label)) {
                $seen[$c.label] = $true
                $found.Add($c.label)
            }
        }
    }
    return @($found)
}

function Get-SensorHonestyMatrix {
    param(
        [bool]$Elevated = $false,
        [bool]$HwmonExe = $false
    )
    $ring0 = [bool]($Elevated -and $HwmonExe)
    return @(
        @{
            id = 'cpu_die_temp'
            label = 'CPU die / package temp'
            needs = 'admin + PcLabHwMon'
            status = if ($ring0) { 'ok' } elseif ($Elevated) { 'limited' } else { 'missing' }
            note = if ($ring0) { 'Elevated LHM path' } else { 'Restart Start-PcLabProbe.bat as Admin' }
        }
        @{
            id = 'motherboard_superio'
            label = 'Board SuperIO fans / voltages'
            needs = 'admin + PcLabHwMon (board-dependent)'
            status = if ($ring0) { 'partial' } else { 'missing' }
            note = 'Leaf coverage varies by chipset; HWiNFO may still win exotic sensors'
        }
        @{
            id = 'gpu_core_hotspot'
            label = 'GPU core / hotspot'
            needs = 'vendor APIs and/or Open Book MMIO'
            status = if ($Elevated) { 'ok' } else { 'limited' }
            note = 'Open Book BAR0 needs elevation where used'
        }
        @{
            id = 'fan_rpm_read'
            label = 'Fan RPM read'
            needs = 'PcLabHwMon Fan sensors'
            status = if ($HwmonExe) { 'ok' } else { 'missing' }
            note = 'See GET /fans'
        }
        @{
            id = 'fan_pwm_write'
            label = 'Fan PWM / curve apply'
            needs = 'PawnIO / elevated Control write (Phase 2)'
            status = 'missing'
            note = 'v1 stages curves + preview duty only'
        }
        @{
            id = 'nvme_smart'
            label = 'NVMe / SMART depth'
            needs = 'admin preferred + optional smartctl'
            status = if ($Elevated) { 'ok' } else { 'limited' }
            note = 'GET /storage/smart depth badges'
        }
        @{
            id = 'presentmon'
            label = 'PresentMon Session Forensics'
            needs = 'tools/PresentMon.exe (user mode)'
            status = 'ok'
            note = 'No admin required for capture'
        }
        @{
            id = 'long_sensor_log'
            label = 'Long-run sensor log'
            needs = 'Probe live (any elevation)'
            status = 'ok'
            note = 'GET /telemetry/log — JSONL under LOCALAPPDATA'
        }
        @{
            id = 'pawnio'
            label = 'PawnIO Ring0 helper'
            needs = 'Phase 2 signed helper'
            status = 'planned'
            note = 'Tracked; not shipped'
        }
        @{
            id = 'vulkan_raster'
            label = 'Vulkan raster suite'
            needs = 'Phase 2 PcLabVkBench raster path'
            status = 'planned'
            note = 'Compute helper ships; raster scores later'
        }
    )
}

function Get-SensorTrustStatus {
    param(
        [bool]$Elevated = $false,
        [bool]$ServiceMode = $false,
        [string]$ProbeRoot = ''
    )
    if (-not $ProbeRoot) {
        $ProbeRoot = Split-Path $PSScriptRoot -Parent
    }
    $hwmonExe = Test-Path (Join-Path $ProbeRoot 'PcLabHwMon.exe')
    $conflicts = @(Get-SensorCompetingTools)
    $mode = if ($Elevated -and $hwmonExe) { 'elevated_hwmon_ring0' } else { 'hwmon_only' }
    $backend = if ($hwmonExe) { 'pclab_hwmon_lhm' } else { 'os_counters_only' }
    $matrix = @(Get-SensorHonestyMatrix -Elevated $Elevated -HwmonExe $hwmonExe)

    $msg = $null
    if ($conflicts.Count -gt 0) {
        $msg = "Close $($conflicts -join ', ') or expect conflicting / wrong temps (shared Ring0 / SMBus)."
    } elseif (-not $Elevated) {
        $msg = 'Probe not elevated - die/board sensors limited. Restart via Start-PcLabProbe.bat for full coverage.'
    } elseif (-not $hwmonExe) {
        $msg = 'PcLabHwMon.exe missing - rebuild Open Book sensors helper.'
    }

    return @{
        ok = $true
        backend = $backend
        trust_mode = $mode
        elevated = [bool]$Elevated
        ring0_path = [bool]($Elevated -and $hwmonExe)
        hwmon_helper = [bool]$hwmonExe
        service_mode = [bool]$ServiceMode
        operator_story = if ($ServiceMode) {
            'Windows Service (always-on telemetry). Tray/desktop also works for Sensors-only sessions.'
        } else {
            'Tray / desktop sidecar (default). Optional forever-on: Install-PcLabProbeService.ps1 as Admin.'
        }
        competing_tools = $conflicts
        conflict = ($conflicts.Count -gt 0)
        message = $msg
        winring0_shipped = $false
        honesty_matrix = $matrix
        roadmap = @{
            pawnio = 'planned'
            superio_write = 'planned'
            vulkan_raster = 'planned'
            fan_curves_v1 = 'shipping'
            long_sensor_log = 'shipping'
        }
        pawnio_note = 'PC Lab Kit does not ship WinRing0.sys. Sensors use PcLabHwMon (LibreHardwareMonitor path). Prefer closing other Ring0 tools; PawnIO migration is tracked for Defender-friendly shops.'
        docs = 'docs/SENSOR_HONESTY.md'
    }
}
