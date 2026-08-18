# PcLab Thermal Resolver
# Turns raw LibreHardwareMonitor sensor names into a vendor-correct thermal model.
#
# Why this exists: LHM exposes different sensor names per vendor. Intel reports
# "CPU Package" + "CPU Core #n", AMD Zen reports "Core (Tctl/Tdie)" + "CCDn (Tdie)",
# NVIDIA reports "GPU Core" + "GPU Hot Spot", AMD GPUs add "GPU VR SoC"/"GPU Liquid".
# Matching those with one regex collapses distinct sensors onto each other, which is
# how GPU hot spot ended up overwriting GPU core and why CPU package was falling back
# to ACPI thermal zones. Everything thermal in the probe should flow through here.

. "$PSScriptRoot\common.ps1"

# ---------------------------------------------------------------------------
# Vendor + limit tables
# ---------------------------------------------------------------------------

function Get-ProbeVendorTag {
    param([string]$Name, [string]$HardwareType = "")

    $h = "$HardwareType".ToLower()
    if ($h -eq 'gpunvidia') { return 'nvidia' }
    if ($h -eq 'gpuamd') { return 'amd' }
    if ($h -eq 'gpuintel') { return 'intel' }

    $n = "$Name".ToLower()
    if ($n -match 'nvidia|geforce|rtx|gtx|quadro|tesla|titan|nvs\b') { return 'nvidia' }
    if ($n -match 'amd|radeon|ryzen|athlon|threadripper|epyc|vega|rx\s?\d{3}|firepro') { return 'amd' }
    if ($n -match 'intel|core\s?i\d|core\s?ultra|xeon|pentium|celeron|arc\s|iris|uhd graphics') { return 'intel' }
    return 'unknown'
}

<#
 CPU throttle ceiling (TjMax). Used for headroom, not for display -
 a wrong guess must never look like a measurement, so every result carries
 a `tjmax_source` of 'sensor' (read from hardware) or 'model-table' (inferred).
#>
function Get-ProbeCpuTjMax {
    param([string]$Model, [string]$Vendor)

    $m = "$Model".ToLower()

    if ($Vendor -eq 'amd') {
        if ($m -match 'threadripper|epyc') { return 95 }
        if ($m -match '7\d{3}x3d|9\d{3}x3d') { return 89 }   # Zen4/Zen5 X3D run a lower ceiling
        if ($m -match '5\d{3}x3d') { return 90 }
        if ($m -match 'ryzen\s?[3579]\s?9\d{3}') { return 95 }   # Zen 5
        if ($m -match 'ryzen\s?[3579]\s?7\d{3}') { return 95 }   # Zen 4
        if ($m -match 'ryzen\s?[3579]\s?[2345]\d{3}') { return 90 }
        if ($m -match 'ryzen') { return 95 }
        return 90
    }

    if ($Vendor -eq 'intel') {
        if ($m -match 'core\s?ultra') { return 105 }
        if ($m -match 'i9-14|i7-14|i5-14|i9-13|i7-13|i5-13|i9-12|i7-12|i5-12') { return 100 }
        if ($m -match 'xeon') { return 95 }
        if ($m -match 'atom|celeron|pentium') { return 105 }
        return 100
    }

    return 100
}

<#
 GPU limits per vendor/family. `core` = edge sensor throttle point,
 `hotspot` = junction throttle point, `memory` = VRAM junction limit,
 `delta_warn`/`delta_crit` = healthy hotspot-minus-core spread. The delta is the
 single most useful number for an assembler: a rising spread means the paste has
 pumped out or the cooler is not seated, long before the card actually throttles.
#>
function Get-ProbeGpuThermalLimits {
    param([string]$Name, [string]$Vendor)

    $n = "$Name".ToLower()

    if ($Vendor -eq 'nvidia') {
        $mem = 105
        if ($n -match '3080|3090|4080|4090|5080|5090') { $mem = 110 }   # GDDR6X / GDDR7
        $core = 88
        if ($n -match 'rtx\s?(30|31)') { $core = 93 }
        if ($n -match 'rtx\s?(40|41|50|51)') { $core = 88 }
        return @{
            core       = $core
            hotspot    = 105
            memory     = $mem
            delta_warn = 20
            delta_crit = 27
            family     = 'nvidia'
        }
    }

    if ($Vendor -eq 'amd') {
        # RDNA2+ is designed around junction temp, so a wider spread is normal.
        return @{
            core       = 110
            hotspot    = 110
            memory     = 105
            delta_warn = 25
            delta_crit = 32
            family     = 'radeon'
        }
    }

    if ($Vendor -eq 'intel') {
        return @{
            core       = 100
            hotspot    = 105
            memory     = 105
            delta_warn = 20
            delta_crit = 28
            family     = 'arc'
        }
    }

    return @{ core = 95; hotspot = 105; memory = 105; delta_warn = 22; delta_crit = 30; family = 'unknown' }
}

# ---------------------------------------------------------------------------
# Sensor helpers
# ---------------------------------------------------------------------------

function Select-ProbeSensors {
    param($Flat, [string]$Type = 'Temperature', [string]$HardwareTypePattern = '', [string]$HardwarePattern = '')

    if (-not $Flat) { return @() }
    $out = @()
    foreach ($s in $Flat) {
        if (-not $s) { continue }
        if ($Type -and "$($s.type)" -ne $Type) { continue }
        if ($HardwareTypePattern -and "$($s.hardware_type)" -notmatch $HardwareTypePattern) { continue }
        if ($HardwarePattern -and "$($s.hardware)" -notmatch $HardwarePattern) { continue }
        if ($null -eq $s.value) { continue }
        $out += $s
    }
    return @($out)
}

function Get-ProbeSensorValue {
    param($Sensors, [string[]]$NamePatterns, [switch]$Max)

    $hits = @()
    foreach ($p in $NamePatterns) {
        foreach ($s in $Sensors) {
            if ("$($s.name)" -match $p) { $hits += [double]$s.value }
        }
        # First pattern that matches wins unless caller asked for the max across all.
        if ($hits.Count -gt 0 -and -not $Max) { break }
    }
    if ($hits.Count -eq 0) { return $null }
    $v = if ($Max) { ($hits | Measure-Object -Maximum).Maximum } else { $hits[0] }
    return [math]::Round([double]$v, 1)
}

function Test-ProbePlausibleTemp {
    param($Value, [double]$Floor = 5, [double]$Ceiling = 125)
    if ($null -eq $Value) { return $false }
    $v = 0.0
    if (-not [double]::TryParse("$Value", [ref]$v)) { return $false }
    return ($v -gt $Floor -and $v -lt $Ceiling)
}

function New-ProbeHeadroom {
    param($Value, $Limit)
    if (-not (Test-ProbePlausibleTemp $Value) -or -not $Limit) { return $null }
    return [math]::Round([double]$Limit - [double]$Value, 1)
}

# ---------------------------------------------------------------------------
# CPU
# ---------------------------------------------------------------------------

<#
 Resolve CPU thermals from LHM sensors.

 package_c  - the die-level reading a user recognises (Intel "CPU Package",
              AMD "Core (Tctl/Tdie)").
 hotspot_c  - hottest point on the die: max of per-core sensors, Intel "Core Max",
              or AMD CCD dies. On Ryzen, Tctl/Tdie already *is* the hottest-core
              reading, so it doubles as the hotspot when no per-core data exists.
#>
function Resolve-ProbeCpuThermal {
    param($Flat, [string]$Model = "", $AcpiZones = @())

    $vendor = Get-ProbeVendorTag -Name $Model
    $sensors = Select-ProbeSensors -Flat $Flat -Type 'Temperature' -HardwareTypePattern '^Cpu$'

    $result = @{
        vendor        = $vendor
        package_c     = $null
        hotspot_c     = $null
        average_c     = $null
        per_core_c    = @()
        ccd_c         = @()
        soc_c         = $null
        tjmax_c       = $null
        tjmax_source  = 'model-table'
        headroom_c    = $null
        throttling    = $false
        source        = 'none'
        acpi_zones_c  = @()
        note          = $null
    }

    # Per-core sensors: Intel "CPU Core #3", AMD "Core #3" / "Core 3".
    $coreVals = @()
    foreach ($s in $sensors) {
        $n = "$($s.name)"
        if ($n -match 'Distance to TjMax') { continue }
        if ($n -match '^(CPU )?Core\s*#?\d+$') {
            if (Test-ProbePlausibleTemp $s.value) { $coreVals += [math]::Round([double]$s.value, 1) }
        }
    }
    $result.per_core_c = @($coreVals)

    # AMD chiplet dies.
    $ccd = @()
    foreach ($s in $sensors) {
        if ("$($s.name)" -match '^CCD\d*\s*\(?T?die?\)?' -or "$($s.name)" -match '^CCD\d+$') {
            if (Test-ProbePlausibleTemp $s.value) {
                $ccd += @{ name = "$($s.name)"; value_c = [math]::Round([double]$s.value, 1) }
            }
        }
    }
    $result.ccd_c = @($ccd)

    if ($vendor -eq 'amd') {
        $result.package_c = Get-ProbeSensorValue -Sensors $sensors -NamePatterns @(
            'Core \(Tctl/Tdie\)', 'Core \(Tdie\)', 'Core \(Tctl\)', '^CPU Package$', '^Package$'
        )
        $result.soc_c = Get-ProbeSensorValue -Sensors $sensors -NamePatterns @('^SoC$', 'GPU Core \(SoC\)')
    } else {
        $result.package_c = Get-ProbeSensorValue -Sensors $sensors -NamePatterns @(
            '^CPU Package$', '^Package$', '^CPU Platform$', '^Core \(Tctl/Tdie\)$'
        )
    }

    $result.average_c = Get-ProbeSensorValue -Sensors $sensors -NamePatterns @('^Core Average$', '^CPU Total$')

    # Hotspot: prefer an explicit max sensor, then the hottest individual core/CCD.
    $explicitMax = Get-ProbeSensorValue -Sensors $sensors -NamePatterns @('^Core Max$', 'Hot ?Spot')
    $candidates = @()
    if (Test-ProbePlausibleTemp $explicitMax) { $candidates += $explicitMax }
    if ($coreVals.Count -gt 0) { $candidates += ($coreVals | Measure-Object -Maximum).Maximum }
    foreach ($c in $ccd) { $candidates += $c.value_c }
    if ($candidates.Count -gt 0) {
        $result.hotspot_c = [math]::Round(($candidates | Measure-Object -Maximum).Maximum, 1)
    } elseif ($vendor -eq 'amd' -and (Test-ProbePlausibleTemp $result.package_c)) {
        # Tctl/Tdie on Zen is already the hottest-core reading.
        $result.hotspot_c = $result.package_c
        $result.note = 'AMD Tctl/Tdie is a hottest-core reading, so package and hot spot are the same sensor.'
    }

    if (-not (Test-ProbePlausibleTemp $result.package_c) -and (Test-ProbePlausibleTemp $result.hotspot_c)) {
        $result.package_c = $result.hotspot_c
    }

    if (Test-ProbePlausibleTemp $result.package_c) { $result.source = 'libre-hardware-monitor' }

    # ACPI thermal zones: kept for reference only. They usually report a board zone,
    # not the CPU die, so they are a last-resort fallback rather than a package temp.
    $zones = @()
    foreach ($z in @($AcpiZones)) {
        if (Test-ProbePlausibleTemp $z) { $zones += [math]::Round([double]$z, 1) }
    }
    $result.acpi_zones_c = @($zones)
    if ($result.source -eq 'none' -and $zones.Count -gt 0) {
        $result.package_c = ($zones | Measure-Object -Maximum).Maximum
        $result.source = 'acpi-thermal-zone'
        $result.note = 'ACPI thermal zone only. Run the probe as Administrator so the CPU die sensors can be read.'
    }

    # Distance-to-TjMax is a real sensor on Intel; when present it beats any table.
    $dist = @()
    foreach ($s in $sensors) {
        if ("$($s.name)" -match 'Distance to TjMax' -and $null -ne $s.value) { $dist += [double]$s.value }
    }
    if ($dist.Count -gt 0 -and (Test-ProbePlausibleTemp $result.hotspot_c)) {
        $minDist = ($dist | Measure-Object -Minimum).Minimum
        $result.tjmax_c = [math]::Round($result.hotspot_c + $minDist, 0)
        $result.tjmax_source = 'sensor'
        $result.headroom_c = [math]::Round($minDist, 1)
    } else {
        $result.tjmax_c = Get-ProbeCpuTjMax -Model $Model -Vendor $vendor
        $result.headroom_c = New-ProbeHeadroom -Value $result.hotspot_c -Limit $result.tjmax_c
    }

    if ($null -ne $result.headroom_c -and $result.headroom_c -le 2) { $result.throttling = $true }

    return $result
}

# ---------------------------------------------------------------------------
# GPU
# ---------------------------------------------------------------------------

<#
 Resolve one GPU's thermals. Hot spot is kept strictly separate from core:
 they are different physical sensors and conflating them hides exactly the
 problem an assembler is looking for.
#>
function Resolve-ProbeGpuThermal {
    param($Flat, [string]$HardwareName = "", [string]$HardwareType = "", $Fallback = $null, [string]$SensorNode = "")

    $vendor = Get-ProbeVendorTag -Name $HardwareName -HardwareType $HardwareType
    $limits = Get-ProbeGpuThermalLimits -Name $HardwareName -Vendor $vendor

    # Only read sensors from this card's own LHM node. Falling back to every GPU node
    # would copy the discrete card's readings onto the iGPU sitting next to it.
    $sensors = @()
    $node = if ($SensorNode) { $SensorNode } else { $HardwareName }
    if ($node) {
        $sensors = Select-ProbeSensors -Flat $Flat -Type 'Temperature' -HardwarePattern ([regex]::Escape($node))
    } elseif (-not $HardwareName) {
        $sensors = Select-ProbeSensors -Flat $Flat -Type 'Temperature' -HardwareTypePattern '^Gpu'
    }

    $result = @{
        vendor          = $vendor
        hardware        = $HardwareName
        core_c          = Get-ProbeSensorValue -Sensors $sensors -NamePatterns @('^GPU Core$', '^GPU Temperature$', '^Core$')
        hot_spot_c      = $null
        memory_c        = Get-ProbeSensorValue -Sensors $sensors -NamePatterns @('^GPU Memory Junction$', '^GPU Memory$', '^GPU VRAM$', 'Memory Junction')
        vr_c            = Get-ProbeSensorValue -Sensors $sensors -NamePatterns @('^GPU VR (VDDC|SoC|MVDD)$', 'GPU VR') -Max
        liquid_c        = Get-ProbeSensorValue -Sensors $sensors -NamePatterns @('^GPU Liquid$')
        therm_spread_c  = Get-ProbeSensorValue -Sensors $sensors -NamePatterns @('^GPU Therm Spread$')
        fan_pct         = $null
        limits          = $limits
        hotspot_delta_c = $null
        headroom_c      = $null
        source          = 'libre-hardware-monitor'
        hotspot_source  = 'unavailable'
        health          = 'unknown'
        findings        = @()
    }

    # Prefer open-book BAR0 THERM Hot Spot (Blackwell) over NVAPI / LHM fakes.
    $obHot = @($sensors | Where-Object {
        "$($_.name)" -match '^GPU Hot ?Spot$' -and (
            "$($_.source)" -eq 'blackwell_therm_mmio' -or $_.open_book -eq $true
        )
    }) | Select-Object -First 1
    if ($obHot -and (Test-ProbePlausibleTemp $obHot.value)) {
        $result.hot_spot_c = [math]::Round([double]$obHot.value, 1)
        $result.hotspot_source = 'blackwell_therm_mmio'
        $result.source = 'blackwell_therm_mmio'
    } else {
        $hotRow = @($sensors | Where-Object { "$($_.name)" -match '^GPU Hot ?Spot$|^GPU Junction$|Hot ?Spot' } | Select-Object -First 1)
        if ($hotRow -and (Test-ProbePlausibleTemp $hotRow.value) -and [double]$hotRow.value -lt 250) {
            $result.hot_spot_c = [math]::Round([double]$hotRow.value, 1)
            $src = "$($hotRow.source)"
            if ($src -eq 'nvapi_raw' -or $src -eq 'adl' -or $src -eq 'lhm_intel') {
                $result.hotspot_source = $src
                $result.source = $src
            } else {
                $result.hotspot_source = 'libre-hardware-monitor'
            }
        }
    }

    $memOb = @($sensors | Where-Object {
        "$($_.name)" -match 'Memory Junction|^GPU Memory$' -and (
            "$($_.source)" -eq 'blackwell_vram_mmio' -or $_.open_book -eq $true
        )
    }) | Select-Object -First 1
    if ($memOb -and (Test-ProbePlausibleTemp $memOb.value) -and [double]$memOb.value -lt 250) {
        $result.memory_c = [math]::Round([double]$memOb.value, 1)
        $result.memory_source = 'blackwell_vram_mmio'
    }

    # Reject NVAPI lock (255) and Blackwell core-clone fakes when not open-book.
    if (Test-ProbePlausibleTemp $result.hot_spot_c) {
        if ([double]$result.hot_spot_c -ge 250) {
            $result.hot_spot_c = $null
            $result.hotspot_source = 'unavailable'
        } elseif (
            $result.hotspot_source -ne 'blackwell_therm_mmio' -and
            $vendor -eq 'nvidia' -and
            (Test-ProbePlausibleTemp $result.core_c) -and
            [math]::Abs([double]$result.hot_spot_c - [double]$result.core_c) -lt 0.25 -and
            ("$HardwareName" -match 'RTX\s*50|GeForce\s*RTX\s*50')
        ) {
            $result.hot_spot_c = $null
            $result.hotspot_source = 'unavailable'
        }
    }
    if (Test-ProbePlausibleTemp $result.memory_c -and [double]$result.memory_c -ge 250) {
        $result.memory_c = $null
    }

    # nvidia-smi / rocm-smi values fill any gap LHM / open-book could not cover.
    # T.Limit-derived hotspot is last resort only.
    if ($Fallback) {
        if (-not (Test-ProbePlausibleTemp $result.core_c) -and (Test-ProbePlausibleTemp $Fallback.core_c)) {
            $result.core_c = [math]::Round([double]$Fallback.core_c, 1)
            if ($result.source -eq 'libre-hardware-monitor') { $result.source = "$($Fallback.source)" }
        }
        if (-not (Test-ProbePlausibleTemp $result.memory_c) -and (Test-ProbePlausibleTemp $Fallback.memory_c)) {
            $result.memory_c = [math]::Round([double]$Fallback.memory_c, 1)
        }
        if (-not (Test-ProbePlausibleTemp $result.hot_spot_c) -and (Test-ProbePlausibleTemp $Fallback.hot_spot_c)) {
            $result.hot_spot_c = [math]::Round([double]$Fallback.hot_spot_c, 1)
            $result.hotspot_source = "$($Fallback.hotspot_source)"
        }
        if ($null -ne $Fallback.fan_pct) { $result.fan_pct = $Fallback.fan_pct }
        if ($Fallback.hotspot_limit_c) { $result.limits.hotspot = [double]$Fallback.hotspot_limit_c }
        if ($Fallback.core_limit_c) { $result.limits.core = [double]$Fallback.core_limit_c }
    }

    if ($null -eq $result.fan_pct -and $node) {
        $fans = Select-ProbeSensors -Flat $Flat -Type 'Control' -HardwarePattern ([regex]::Escape($node))
        $f = Get-ProbeSensorValue -Sensors $fans -NamePatterns @('GPU Fan', 'Fan')
        if ($null -ne $f) { $result.fan_pct = $f }
    }

    if (-not (Test-ProbePlausibleTemp $result.hot_spot_c)) {
        $result.hotspot_source = 'unavailable'
    }

    if ((Test-ProbePlausibleTemp $result.core_c) -and (Test-ProbePlausibleTemp $result.hot_spot_c)) {
        $result.hotspot_delta_c = [math]::Round([double]$result.hot_spot_c - [double]$result.core_c, 1)
    }
    $result.headroom_c = New-ProbeHeadroom -Value $result.hot_spot_c -Limit $limits.hotspot
    if ($null -eq $result.headroom_c) {
        $result.headroom_c = New-ProbeHeadroom -Value $result.core_c -Limit $limits.core
    }

    $result.health = Get-ProbeGpuThermalHealth -Gpu $result
    $result.findings = @(Get-ProbeGpuThermalFindings -Gpu $result)

    return $result
}

<#
 Map a Windows display adapter to the LibreHardwareMonitor node that reports its
 sensors. The two rarely use identical strings ("NVIDIA GeForce RTX 4070 Laptop GPU"
 vs "NVIDIA GeForce RTX 4070"), so match on normalized model tokens and require the
 vendor to agree before accepting a partial hit.
#>
function Find-ProbeGpuSensorNode {
    param($Flat, [string]$AdapterName)

    if (-not $Flat -or -not $AdapterName) { return "" }

    $nodes = @{}
    foreach ($s in $Flat) {
        if (-not $s) { continue }
        if ("$($s.hardware_type)" -notmatch '^Gpu') { continue }
        $nodes["$($s.hardware)"] = "$($s.hardware_type)"
    }
    if ($nodes.Keys.Count -eq 0) { return "" }

    $normalize = {
        param($s)
        return ("$s".ToLower() -replace '\(r\)|\(tm\)|nvidia|geforce|amd|radeon|intel|laptop gpu|graphics|\s+|-', '')
    }
    $target = & $normalize $AdapterName
    $adapterVendor = Get-ProbeVendorTag -Name $AdapterName

    foreach ($n in $nodes.Keys) {
        if ((& $normalize $n) -eq $target) { return $n }
    }
    foreach ($n in $nodes.Keys) {
        if ((Get-ProbeVendorTag -Name $n -HardwareType $nodes[$n]) -ne $adapterVendor) { continue }
        $cand = & $normalize $n
        if (-not $cand -or -not $target) { continue }
        if ($cand.Contains($target) -or $target.Contains($cand)) { return $n }
    }
    # Vendor is unique among the sensor nodes, so the mapping is unambiguous.
    $sameVendor = @($nodes.Keys | Where-Object { (Get-ProbeVendorTag -Name $_ -HardwareType $nodes[$_]) -eq $adapterVendor })
    if ($sameVendor.Count -eq 1) { return $sameVendor[0] }

    return ""
}

function Get-ProbeGpuThermalHealth {
    param($Gpu)

    if (-not (Test-ProbePlausibleTemp $Gpu.core_c) -and -not (Test-ProbePlausibleTemp $Gpu.hot_spot_c)) { return 'unknown' }
    $d = $Gpu.hotspot_delta_c
    $limits = $Gpu.limits

    if ($null -ne $d) {
        if ($d -ge $limits.delta_crit) { return 'critical' }
        if ($d -ge $limits.delta_warn) { return 'warn' }
    }
    if ((Test-ProbePlausibleTemp $Gpu.hot_spot_c) -and $Gpu.hot_spot_c -ge $limits.hotspot) { return 'critical' }
    if ((Test-ProbePlausibleTemp $Gpu.memory_c) -and $Gpu.memory_c -ge ($limits.memory - 4)) { return 'warn' }
    if ((Test-ProbePlausibleTemp $Gpu.core_c) -and $Gpu.core_c -ge ($limits.core - 3)) { return 'warn' }
    return 'ok'
}

function Get-ProbeGpuThermalFindings {
    param($Gpu)

    $out = @()
    $limits = $Gpu.limits
    $label = if ($Gpu.hardware) { $Gpu.hardware } else { 'GPU' }

    if ($Gpu.hotspot_source -eq 'unavailable') {
        $out += @{
            severity = 'info'
            code     = 'gpu_hotspot_unavailable'
            title    = "$label hot spot not readable"
            detail   = 'Run the probe as Administrator so PcLabHwMon can open Ring0 and try open-book BAR0 THERM (Blackwell). Some laptop GPUs never expose a junction sensor. See docs/OPEN_BOOK_SENSORS.md.'
        }
    } elseif ($Gpu.hotspot_source -eq 'blackwell_therm_mmio') {
        $out += @{
            severity = 'info'
            code     = 'gpu_hotspot_open_book'
            title    = "$label hot spot via open-book registers"
            detail   = 'Recovered from GPU BAR0 THERM MMIO (not public NVAPI). Treat absolute °C as approximate; watch hotspot−core delta and Therm Spread for cooler/paste issues.'
        }
    } elseif ($Gpu.hotspot_source -eq 'nvidia-smi-tlimit-derived') {
        $out += @{
            severity = 'info'
            code     = 'gpu_hotspot_derived'
            title    = "$label hot spot is estimated"
            detail   = 'Derived from nvidia-smi T.Limit — not a direct junction reading. Open-book MMIO was unavailable.'
        }
    }

    if ($null -ne $Gpu.therm_spread_c -and [double]$Gpu.therm_spread_c -ge 12) {
        $out += @{
            severity = if ([double]$Gpu.therm_spread_c -ge 18) { 'warn' } else { 'info' }
            code     = 'gpu_therm_spread'
            title    = "$label on-die therm spread is $($Gpu.therm_spread_c)C"
            detail   = 'S1–S4 spatial spread from open-book THERM. A wide spread under load can indicate uneven cooler contact or paste.'
        }
    }

    if ($null -ne $Gpu.hotspot_delta_c) {
        $d = $Gpu.hotspot_delta_c
        if ($d -ge $limits.delta_crit) {
            $out += @{
                severity = 'critical'
                code     = 'gpu_hotspot_delta_critical'
                title    = "$label hot spot runs ${d}C above core"
                detail   = 'A spread this wide almost always means the thermal paste has pumped out or the cooler is not seated evenly. Re-paste the die and reseat the heatsink; check the VRAM pads while it is apart.'
            }
        } elseif ($d -ge $limits.delta_warn) {
            $out += @{
                severity = 'warn'
                code     = 'gpu_hotspot_delta_high'
                title    = "$label hot spot is ${d}C above core"
                detail   = "Healthy for this class is under $($limits.delta_warn)C. Watch it under load; if it keeps climbing, plan a re-paste."
            }
        }
    }

    if ((Test-ProbePlausibleTemp $Gpu.memory_c) -and $Gpu.memory_c -ge ($limits.memory - 4)) {
        $out += @{
            severity = 'warn'
            code     = 'gpu_vram_hot'
            title    = "$label VRAM at $($Gpu.memory_c)C"
            detail   = "Memory junction limit is about $($limits.memory)C. Improve case airflow or replace the memory thermal pads with a correctly sized set."
        }
    }

    if ($null -ne $Gpu.headroom_c -and $Gpu.headroom_c -le 3) {
        $out += @{
            severity = 'critical'
            code     = 'gpu_thermal_throttle'
            title    = "$label is at its thermal limit"
            detail   = 'The card is throttling. Clean the fins, verify fan curve, and confirm intake airflow before benchmarking.'
        }
    }

    if ((Test-ProbePlausibleTemp $Gpu.core_c) -and $Gpu.core_c -gt 45 -and ($null -ne $Gpu.fan_pct) -and $Gpu.fan_pct -le 0) {
        $out += @{
            severity = 'warn'
            code     = 'gpu_fan_stopped'
            title    = "$label fans are stopped at $($Gpu.core_c)C"
            detail   = 'Zero-RPM mode is normal below roughly 50C. Above that a stopped fan points at a failed fan header or a stuck bearing.'
        }
    }

    return $out
}

function Get-ProbeCpuThermalFindings {
    param($Cpu, [string]$Model = "")

    $out = @()
    $label = if ($Model) { $Model } else { 'CPU' }

    if ($Cpu.source -eq 'none') {
        $out += @{
            severity = 'warn'
            code     = 'cpu_temp_unavailable'
            title    = 'No CPU temperature source'
            detail   = 'Die temperatures come from model-specific registers that need elevation. Start the probe with Run as administrator, and build PcLabHwMon.exe via scripts/build-pclab-hwmon.ps1.'
        }
        return $out
    }

    if ($Cpu.source -eq 'acpi-thermal-zone') {
        $out += @{
            severity = 'warn'
            code     = 'cpu_temp_acpi_only'
            title    = 'CPU temperature is an ACPI board zone'
            detail   = 'ACPI zones lag the die by 10-20C and often report the chipset instead. Run the probe elevated to get the real package and per-core sensors.'
        }
    }

    if ($null -ne $Cpu.headroom_c -and $Cpu.headroom_c -le 2) {
        $out += @{
            severity = 'critical'
            code     = 'cpu_thermal_throttle'
            title    = "$label is hitting TjMax ($($Cpu.tjmax_c)C)"
            detail   = 'Reseat the cooler with fresh paste, verify the pump or fan is spinning, and confirm the mounting pressure is even.'
        }
    } elseif ($null -ne $Cpu.headroom_c -and $Cpu.headroom_c -le 8) {
        $out += @{
            severity = 'warn'
            code     = 'cpu_thermal_tight'
            title    = "$label has only $($Cpu.headroom_c)C of headroom"
            detail   = 'Fine at idle, but this will throttle in a sustained load. Check cooler class against the CPU power limits.'
        }
    }

    if ($Cpu.per_core_c -and @($Cpu.per_core_c).Count -gt 1) {
        $mx = (@($Cpu.per_core_c) | Measure-Object -Maximum).Maximum
        $mn = (@($Cpu.per_core_c) | Measure-Object -Minimum).Minimum
        $spread = [math]::Round($mx - $mn, 1)
        if ($spread -ge 20) {
            $out += @{
                severity = 'warn'
                code     = 'cpu_core_spread'
                title    = "Core-to-core spread is ${spread}C"
                detail   = 'An uneven spread at idle usually means the cold plate is contacting on one side only. Loosen and re-tighten the bracket in a diagonal pattern.'
            }
        }
    }

    if (@($Cpu.ccd_c).Count -ge 2) {
        $vals = @()
        foreach ($c in $Cpu.ccd_c) { $vals += [double]$c.value_c }
        $d = [math]::Round((($vals | Measure-Object -Maximum).Maximum - ($vals | Measure-Object -Minimum).Minimum), 1)
        if ($d -ge 15) {
            $out += @{
                severity = 'info'
                code     = 'cpu_ccd_imbalance'
                title    = "CCD temperature imbalance of ${d}C"
                detail   = 'Normal on X3D parts where only one chiplet carries the cache. On a non-X3D chip it points at uneven cooler contact.'
            }
        }
    }

    return $out
}
