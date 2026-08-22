. "$PSScriptRoot\common.ps1"

<#
  Sensor trust path — PcLabHwMon (LHM-backed, elevated Ring0) vs HwMon-only,
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

    $msg = $null
    if ($conflicts.Count -gt 0) {
        $msg = "Close $($conflicts -join ', ') or expect conflicting / wrong temps (shared Ring0 / SMBus)."
    } elseif (-not $Elevated) {
        $msg = 'Probe not elevated — die/board sensors limited. Restart via Start-PcLabProbe.bat for full coverage.'
    } elseif (-not $hwmonExe) {
        $msg = 'PcLabHwMon.exe missing — rebuild Open Book sensors helper.'
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
        pawnio_note = 'PC Lab Kit does not ship WinRing0.sys. Sensors use PcLabHwMon (LibreHardwareMonitor path). Prefer closing other Ring0 tools; PawnIO migration is tracked for Defender-friendly shops.'
        docs = 'docs/SECURITY.md#sensor-trust'
    }
}
