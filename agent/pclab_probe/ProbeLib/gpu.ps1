. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\thermal.ps1"

# ---------------------------------------------------------------------------
# nvidia-smi
# ---------------------------------------------------------------------------

function Invoke-NvidiaSmiQuery {
    param([string]$Fields)

    $out = & nvidia-smi --query-gpu=$Fields --format=csv,noheader,nounits 2>$null
    if (-not $out) { return @() }
    $lines = @($out) | Where-Object { "$_".Trim() -and "$_" -notmatch 'not a valid field|NVIDIA-SMI has failed' }
    return @($lines)
}

function ConvertTo-NvNumber {
    param($Raw)
    $t = "$Raw".Trim()
    if (-not $t -or $t -match '^(N/A|\[N/A\]|Not Supported|\[Not Supported\]|Unknown)$') { return $null }
    $v = 0.0
    if ([double]::TryParse($t, [ref]$v)) { return $v }
    return $null
}

function ConvertTo-NvText {
    param($Raw)
    $t = "$Raw".Trim()
    if (-not $t -or $t -match '^(N/A|\[N/A\]|Not Supported|\[Not Supported\])$') { return $null }
    return $t
}

<#
 nvidia-smi never exposes the junction ("hot spot") sensor directly. What newer
 drivers do expose is T.Limit: how many degrees remain before the card throttles,
 measured against the hottest on-die sensor. Given the family's throttle ceiling we
 can work backwards to an approximate hot spot, which is far better than nothing on
 machines where the NVAPI path is blocked. It is always tagged as derived so the UI
 can show it as an estimate rather than a measurement.
#>
function Get-NvidiaSmiTemperatureDetail {
    param([int]$Index = 0, [string]$Name = "")

    $result = @{
        current_c        = $null
        memory_c         = $null
        tlimit_c         = $null
        shutdown_c       = $null
        slowdown_c       = $null
        max_operating_c  = $null
        target_c         = $null
        hot_spot_c       = $null
        hotspot_source   = 'unavailable'
    }

    $raw = & nvidia-smi -i $Index -q -d TEMPERATURE 2>$null
    if (-not $raw) { return $result }
    $text = ($raw -join "`n")

    $grab = {
        param([string]$Pattern)
        $m = [regex]::Match($text, $Pattern + '\s*:\s*(-?[\d\.]+|N/A)', 'IgnoreCase')
        if (-not $m.Success) { return $null }
        return (ConvertTo-NvNumber $m.Groups[1].Value)
    }

    $result.current_c       = & $grab 'GPU Current Temp'
    $result.memory_c        = & $grab 'Memory Current Temp'
    $result.shutdown_c      = & $grab 'GPU Shutdown Temp'
    $result.slowdown_c      = & $grab 'GPU Slowdown Temp'
    $result.max_operating_c = & $grab 'GPU Max Operating Temp'
    $result.target_c        = & $grab 'GPU Target Temperature'
    $result.tlimit_c        = & $grab 'GPU T\.Limit Temp'

    if ($null -ne $result.tlimit_c) {
        $limits = Get-ProbeGpuThermalLimits -Name $Name -Vendor 'nvidia'
        $ceiling = $limits.hotspot
        $shutdownDelta = & $grab 'GPU Shutdown T\.Limit Temp'
        if ($null -ne $shutdownDelta -and $shutdownDelta -lt 0) {
            # Shutdown sits below the throttle point by this many degrees, which pins
            # the ceiling more accurately than the family table.
            $ceiling = $limits.hotspot + $shutdownDelta
        }
        $derived = [math]::Round($ceiling - $result.tlimit_c, 1)
        if (Test-ProbePlausibleTemp $derived) {
            $result.hot_spot_c = $derived
            $result.hotspot_source = 'nvidia-smi-tlimit-derived'
        }
    }

    return $result
}

function Get-NvidiaGpuList {
    if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) { return @() }

    $full = @(
        'index','name','uuid','driver_version','vbios_version','pstate','compute_cap',
        'clocks.gr','clocks.mem','clocks.max.graphics','clocks.max.mem','clocks.sm',
        'temperature.gpu','temperature.memory',
        'power.draw','power.limit','power.default_limit','power.max_limit',
        'utilization.gpu','utilization.memory','utilization.encoder','utilization.decoder',
        'memory.total','memory.used','memory.free',
        'pcie.link.gen.current','pcie.link.gen.max','pcie.link.width.current','pcie.link.width.max',
        'fan.speed','clocks_event_reasons.active','ecc.errors.corrected.volatile.total'
    )
    $lines = Invoke-NvidiaSmiQuery -Fields ($full -join ',')
    $schema = $full

    if ($lines.Count -eq 0) {
        # Older drivers reject the newer field names; fall back to the stable subset.
        $schema = @(
            'index','name','driver_version','memory.total','memory.used','utilization.gpu',
            'utilization.memory','temperature.gpu','power.draw','clocks.sm',
            'pcie.link.gen.current','pcie.link.width.current','fan.speed'
        )
        $lines = Invoke-NvidiaSmiQuery -Fields ($schema -join ',')
    }
    if ($lines.Count -eq 0) { return @() }

    $map = @{
        'index' = 'index'; 'name' = 'name'; 'uuid' = 'uuid'; 'driver_version' = 'driver'
        'vbios_version' = 'vbios'; 'pstate' = 'pstate'; 'compute_cap' = 'compute_capability'
        'clocks.gr' = 'core_clock_mhz'; 'clocks.mem' = 'mem_clock_mhz'
        'clocks.max.graphics' = 'core_clock_max'; 'clocks.max.mem' = 'mem_clock_max'
        'clocks.sm' = 'sm_clock_mhz'
        'temperature.gpu' = 'temp_core_c'; 'temperature.memory' = 'temp_vram_c'
        'power.draw' = 'power_draw_w'; 'power.limit' = 'power_limit_w'
        'power.default_limit' = 'power_default_w'; 'power.max_limit' = 'power_max_w'
        'utilization.gpu' = 'gpu_util_pct'; 'utilization.memory' = 'mem_util_pct'
        'utilization.encoder' = 'encoder_util_pct'; 'utilization.decoder' = 'decoder_util_pct'
        'memory.total' = 'vram_total_mb'; 'memory.used' = 'vram_used_mb'; 'memory.free' = 'vram_free_mb'
        'pcie.link.gen.current' = 'pcie_gen'; 'pcie.link.gen.max' = 'pcie_gen_max'
        'pcie.link.width.current' = 'pcie_width'; 'pcie.link.width.max' = 'pcie_width_max'
        'fan.speed' = 'fan_speed_pct'
        'clocks_event_reasons.active' = 'throttle_reasons_hex'
        'ecc.errors.corrected.volatile.total' = 'ecc_corrected'
    }
    $numeric = @(
        'core_clock_mhz','mem_clock_mhz','core_clock_max','mem_clock_max','sm_clock_mhz',
        'temp_core_c','temp_vram_c','power_draw_w','power_limit_w','power_default_w','power_max_w',
        'gpu_util_pct','mem_util_pct','encoder_util_pct','decoder_util_pct',
        'vram_total_mb','vram_used_mb','vram_free_mb','fan_speed_pct','ecc_corrected','index'
    )

    $gpus = @()
    foreach ($line in $lines) {
        $parts = "$line" -split ",\s*"
        $g = @{}
        for ($i = 0; $i -lt $schema.Count -and $i -lt $parts.Count; $i++) {
            $key = $map[$schema[$i]]
            if (-not $key) { continue }
            if ($numeric -contains $key) { $g[$key] = ConvertTo-NvNumber $parts[$i] }
            else { $g[$key] = ConvertTo-NvText $parts[$i] }
        }
        if (-not $g.name) { continue }
        $idx = if ($null -ne $g.index) { [int]$g.index } else { 0 }
        $g.index = $idx
        $g.temperature_detail = Get-NvidiaSmiTemperatureDetail -Index $idx -Name "$($g.name)"
        $g.throttle_reasons = @(Get-NvidiaThrottleReasons $g.throttle_reasons_hex)
        $gpus += $g
    }
    return @($gpus)
}

<# Decode the nvidia-smi clock-event bitmask into plain language. #>
function Get-NvidiaThrottleReasons {
    param($Hex)

    $t = ConvertTo-NvText $Hex
    if (-not $t) { return @() }
    $val = 0
    try {
        if ($t -match '^0x') { $val = [Convert]::ToInt64($t.Substring(2), 16) }
        else { $val = [Convert]::ToInt64($t) }
    } catch { return @() }
    if ($val -le 0) { return @() }

    $bits = [ordered]@{
        0x0000000002 = 'GPU is idle'
        0x0000000004 = 'Applications clocks setting'
        0x0000000008 = 'Power cap reached'
        0x0000000020 = 'Hardware slowdown (thermal or power)'
        0x0000000040 = 'Sync boost'
        0x0000000080 = 'Software thermal slowdown'
        0x0000000100 = 'Hardware thermal slowdown'
        0x0000000200 = 'Hardware power-brake slowdown'
        0x0000000400 = 'Display clock setting'
    }
    $out = @()
    foreach ($k in $bits.Keys) {
        if ($val -band [int64]$k) { $out += $bits[$k] }
    }
    return @($out)
}

# ---------------------------------------------------------------------------
# Windows adapter inventory
# ---------------------------------------------------------------------------

function Get-ProbeGpuAdapters {
    $adapters = @(Get-CimSafe "Win32_VideoController" | Where-Object { $_.Name -and $_.Name -notmatch "Microsoft Basic" })
    $list = @()
    foreach ($g in $adapters) {
        # AdapterRAM is a 32-bit field, so anything at or above 4 GB reports garbage.
        $vramBytes = 0
        if ($g.AdapterRAM -and $g.AdapterRAM -gt 0 -and $g.AdapterRAM -lt 1TB) { $vramBytes = [int64]$g.AdapterRAM }
        $qwordVram = Get-GpuVramFromRegistry -PnpDeviceId "$($g.PNPDeviceID)"
        if ($qwordVram -gt $vramBytes) { $vramBytes = $qwordVram }

        $list += @{
            name          = "$($g.Name)".Trim()
            vendor        = (Get-ProbeVendorTag -Name "$($g.Name)")
            driver        = $g.DriverVersion
            driver_date   = $g.DriverDate
            vram_gb       = if ($vramBytes -gt 0) { [math]::Round($vramBytes / 1GB, 2) } else { 0 }
            pnp_device_id = $g.PNPDeviceID
            video_mode    = $g.VideoModeDescription
            adapter_ram   = $vramBytes
            status        = $g.Status
            availability  = $g.Availability
            is_integrated = ("$($g.Name)" -match 'UHD|Iris|Vega \d|Radeon\(TM\) Graphics|Graphics Adapter|integrated')
        }
    }
    return @($list)
}

<# Win32_VideoController truncates VRAM at 4 GB; the driver key holds the true value. #>
function Get-GpuVramFromRegistry {
    param([string]$PnpDeviceId)

    if (-not $PnpDeviceId) { return 0 }
    try {
        $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        foreach ($key in (Get-ChildItem $base -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' })) {
            $p = Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue
            if (-not $p) { continue }
            if ("$($p.MatchingDeviceId)" -and $PnpDeviceId.ToLower().Replace('\', '#') -notmatch [regex]::Escape("$($p.MatchingDeviceId)".ToLower())) {
                if ($PnpDeviceId.ToLower() -notmatch [regex]::Escape("$($p.MatchingDeviceId)".ToLower())) { continue }
            }
            if ($p.'HardwareInformation.qwMemorySize') { return [int64]$p.'HardwareInformation.qwMemorySize' }
            if ($p.'HardwareInformation.MemorySize') {
                $raw = $p.'HardwareInformation.MemorySize'
                if ($raw -is [byte[]]) { return [BitConverter]::ToUInt32($raw, 0) }
                return [int64]$raw
            }
        }
    } catch {}
    return 0
}

# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

function Get-ProbeGpuTelemetry {
    param($HwmonFlat = $null, $AmdTelemetry = $null)

    $adapters = Get-ProbeGpuAdapters
    $nvList = @(Get-NvidiaGpuList)
    $nvidia = if ($nvList.Count -gt 0) { $nvList[0] } else { $null }

    # GPU Engine utilization (works for every vendor, including iGPUs).
    $engines = @()
    try {
        $eng = Get-Counter "\GPU Engine(*)\Utilization Percentage" -MaxSamples 1 -ErrorAction SilentlyContinue
        foreach ($s in $eng.CounterSamples) {
            if ($s.CookedValue -le 0) { continue }
            $engines += @{ engine = $s.InstanceName; util_pct = [math]::Round($s.CookedValue, 1) }
        }
        $engines = @($engines | Sort-Object { $_.util_pct } -Descending | Select-Object -First 12)
    } catch {}

    $vramCounters = Get-CounterSafe @(
        '\GPU Adapter Memory(*)\Dedicated Usage',
        '\GPU Adapter Memory(*)\Shared Usage'
    )

    # Build one normalized record per physical GPU, thermals resolved per vendor.
    $gpus = @()
    foreach ($a in $adapters) {
        $vendor = $a.vendor
        $nv = $null
        foreach ($candidate in $nvList) {
            if ($vendor -eq 'nvidia' -and (Test-GpuNameMatch -AdapterName $a.name -SmiName "$($candidate.name)")) { $nv = $candidate; break }
        }
        if (-not $nv -and $vendor -eq 'nvidia' -and $nvList.Count -eq 1) { $nv = $nvList[0] }

        $fallback = $null
        if ($nv) {
            $detail = $nv.temperature_detail
            $fallback = @{
                source           = 'nvidia-smi'
                core_c           = $nv.temp_core_c
                memory_c         = $nv.temp_vram_c
                hot_spot_c       = if ($detail) { $detail.hot_spot_c } else { $null }
                hotspot_source   = if ($detail) { $detail.hotspot_source } else { 'unavailable' }
                fan_pct          = $nv.fan_speed_pct
                core_limit_c     = if ($detail) { $detail.max_operating_c } else { $null }
                hotspot_limit_c  = $null
            }
            if ($detail -and $null -eq $fallback.core_c) { $fallback.core_c = $detail.current_c }
            if ($detail -and $null -eq $fallback.memory_c) { $fallback.memory_c = $detail.memory_c }
        } elseif ($vendor -eq 'amd' -and $AmdTelemetry -and $AmdTelemetry.available) {
            $fallback = @{
                source         = 'rocm-smi'
                core_c         = $AmdTelemetry.temp_c
                memory_c       = $AmdTelemetry.mem_temp_c
                hot_spot_c     = $AmdTelemetry.junction_c
                hotspot_source = 'rocm-smi'
                fan_pct        = $AmdTelemetry.fan_pct
            }
        }

        $sensorNode = Find-ProbeGpuSensorNode -Flat $HwmonFlat -AdapterName $a.name
        $thermal = Resolve-ProbeGpuThermal -Flat $HwmonFlat -HardwareName $a.name -SensorNode $sensorNode -Fallback $fallback

        $entry = @{
            name           = $a.name
            vendor         = $vendor
            is_integrated  = $a.is_integrated
            driver         = $a.driver
            driver_date    = $a.driver_date
            pnp_device_id  = $a.pnp_device_id
            vram_gb        = $a.vram_gb
            thermal        = $thermal
            throttling     = @()
        }
        if ($nv) {
            $entry.nvidia = $nv
            $entry.vbios = $nv.vbios
            $entry.throttling = @($nv.throttle_reasons)
            if ($nv.vram_total_mb -gt 0) { $entry.vram_gb = [math]::Round($nv.vram_total_mb / 1024, 2) }
        }
        $gpus += $entry
    }

    # The discrete card is what the user cares about; prefer it over an iGPU.
    $primaryEntry = $null
    foreach ($g in $gpus) { if (-not $g.is_integrated) { $primaryEntry = $g; break } }
    if (-not $primaryEntry -and $gpus.Count -gt 0) { $primaryEntry = $gpus[0] }

    $nv = if ($nvidia) { $nvidia } else { @{} }
    $primaryThermal = if ($primaryEntry) { $primaryEntry.thermal } else { (Resolve-ProbeGpuThermal -Flat $HwmonFlat) }

    return @{
        adapters = $adapters
        gpus     = @($gpus)
        primary  = if ($primaryEntry) { $primaryEntry.name } elseif ($adapters.Count) { $adapters[0].name } else { $null }
        vendor   = if ($primaryEntry) { $primaryEntry.vendor } else { 'unknown' }
        nvidia   = $nvidia
        nvidia_all = @($nvList)
        clocks = @{
            core_mhz = $nv.core_clock_mhz
            mem_mhz  = $nv.mem_clock_mhz
            sm_mhz   = $nv.sm_clock_mhz
            max_core = $nv.core_clock_max
            max_mem  = $nv.mem_clock_max
        }
        power = @{
            draw_w    = $nv.power_draw_w
            limit_w   = $nv.power_limit_w
            default_w = $nv.power_default_w
            max_w     = $nv.power_max_w
        }
        thermal = @{
            core_c          = $primaryThermal.core_c
            hot_spot_c      = $primaryThermal.hot_spot_c
            hotspot_delta_c = $primaryThermal.hotspot_delta_c
            hotspot_source  = $primaryThermal.hotspot_source
            memory_c        = $primaryThermal.memory_c
            vram_c          = $primaryThermal.memory_c
            vr_c            = $primaryThermal.vr_c
            fan_pct         = $primaryThermal.fan_pct
            headroom_c      = $primaryThermal.headroom_c
            limits          = $primaryThermal.limits
            health          = $primaryThermal.health
            source          = $primaryThermal.source
        }
        memory = @{
            vram_total_mb   = $nv.vram_total_mb
            vram_used_mb    = $nv.vram_used_mb
            vram_free_mb    = $nv.vram_free_mb
            util_pct        = $nv.mem_util_pct
            dedicated_bytes = ($vramCounters.Values | Measure-Object -Maximum).Maximum
        }
        pcie = @{
            gen_current = $nv.pcie_gen
            gen_max     = $nv.pcie_gen_max
            width       = $nv.pcie_width
            width_max   = $nv.pcie_width_max
        }
        render = @{
            gpu_util_pct     = $nv.gpu_util_pct
            engines          = @($engines)
            encoder_util_pct = $nv.encoder_util_pct
            decoder_util_pct = $nv.decoder_util_pct
        }
        throttling = if ($primaryEntry) { @($primaryEntry.throttling) } else { @() }
        findings   = @($primaryThermal.findings)
    }
}

<# nvidia-smi trims marketing suffixes, so compare on the model tokens only. #>
function Test-GpuNameMatch {
    param([string]$AdapterName, [string]$SmiName)

    if (-not $AdapterName -or -not $SmiName) { return $false }
    $norm = {
        param($s)
        return ("$s".ToLower() -replace 'nvidia|geforce|laptop gpu|\(r\)|\(tm\)|\s+', '')
    }
    $a = & $norm $AdapterName
    $b = & $norm $SmiName
    if (-not $a -or -not $b) { return $false }
    return ($a -eq $b -or $a.Contains($b) -or $b.Contains($a))
}
