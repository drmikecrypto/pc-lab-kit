. "$PSScriptRoot\common.ps1"

<# Adrenalin publishes its package version under the display class key. #>
function Get-AmdSoftwareInfo {
    $info = @{ installed = $false }
    try {
        $key = Get-ItemProperty 'HKLM:\SOFTWARE\AMD\CN' -ErrorAction SilentlyContinue
        if ($key) {
            $info.installed = $true
            if ($key.RadeonSoftwareVersion) { $info.radeon_software_version = "$($key.RadeonSoftwareVersion)" }
            if ($key.RadeonSoftwareEdition) { $info.edition = "$($key.RadeonSoftwareEdition)" }
        }
        $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        foreach ($k in (Get-ChildItem $base -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' })) {
            $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
            if ($p -and "$($p.ProviderName)" -match 'Advanced Micro Devices|AMD') {
                $info.installed = $true
                $info.driver_version = "$($p.DriverVersion)"
                $info.driver_date = "$($p.DriverDate)"
                $info.catalyst_version = "$($p.'Catalyst_Version')"
                break
            }
        }
    } catch {}
    return $info
}

<#
 AMD telemetry on Windows.

 rocm-smi is only present on ROCm/compute installs, so consumer Radeon cards fall
 back to LibreHardwareMonitor, which reads the same ADL sensors that Adrenalin uses
 (including "GPU Hot Spot"). This module normalizes whichever source exists into a
 flat shape the GPU resolver can consume, and reports the installed Adrenalin
 package version for the driver advisor.
#>
function Get-ProbeAmdGpuTelemetry {
    $result = @{
        available      = $false
        source         = $null
        temp_c         = $null
        junction_c     = $null
        mem_temp_c     = $null
        fan_pct        = $null
        power_w        = $null
        core_clock_mhz = $null
        mem_clock_mhz  = $null
        vram_total_mb  = $null
        vram_used_mb   = $null
        util_pct       = $null
        product        = $null
        software       = (Get-AmdSoftwareInfo)
    }

    if (-not (Get-Command rocm-smi -ErrorAction SilentlyContinue)) {
        $result.note = 'rocm-smi not installed. Radeon thermals come from LibreHardwareMonitor instead.'
        return $result
    }

    try {
        $jsonOut = & rocm-smi --showuse --showtemp --showpower --showclocks --showmeminfo vram --showproductname --json 2>$null
        if ($jsonOut) {
            $parsed = ($jsonOut -join "`n") | ConvertFrom-Json
            $result.available = $true
            $result.source = 'rocm-smi'
            $result.raw_json = $parsed

            $card = $null
            foreach ($p in $parsed.PSObject.Properties) {
                if ($p.Name -match '^card\d+$') { $card = $p.Value; break }
            }
            if ($card) {
                $pick = {
                    param([string[]]$Names)
                    foreach ($n in $Names) {
                        foreach ($p in $card.PSObject.Properties) {
                            if ($p.Name -match $n) {
                                $v = 0.0
                                if ([double]::TryParse(("$($p.Value)" -replace '[^\d\.\-]', ''), [ref]$v)) { return $v }
                            }
                        }
                    }
                    return $null
                }
                $result.temp_c         = & $pick @('Temperature \(Sensor edge\)', 'Temperature \(Sensor\)')
                $result.junction_c     = & $pick @('Temperature \(Sensor junction\)', 'junction')
                $result.mem_temp_c     = & $pick @('Temperature \(Sensor memory\)', 'memory')
                $result.fan_pct        = & $pick @('Fan speed \(%\)')
                $result.power_w        = & $pick @('Average Graphics Package Power', 'Current Socket Graphics Package Power')
                $result.core_clock_mhz = & $pick @('sclk clock speed')
                $result.mem_clock_mhz  = & $pick @('mclk clock speed')
                $result.vram_total_mb  = & $pick @('VRAM Total Memory')
                $result.vram_used_mb   = & $pick @('VRAM Total Used Memory')
                $result.util_pct       = & $pick @('GPU use \(%\)')
                foreach ($p in $card.PSObject.Properties) {
                    if ($p.Name -match 'Card series|Card model|Device Name') { $result.product = "$($p.Value)"; break }
                }
            }
            return $result
        }

        $text = & rocm-smi 2>$null
        if ($text) {
            $result.available = $true
            $result.source = 'rocm-smi'
            $result.raw_text = ($text -join "`n")
        }
    } catch {
        $result.error = $_.Exception.Message
    }

    return $result
}
