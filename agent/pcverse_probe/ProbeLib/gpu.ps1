. "$PSScriptRoot\common.ps1"

function Get-ProbeGpuTelemetry {
    $adapters = @(Get-CimSafe "Win32_VideoController" | Where-Object { $_.Name -and $_.Name -notmatch "Microsoft Basic" })
    $list = @()
    foreach ($g in $adapters) {
        $vramBytes = if ($g.AdapterRAM -and $g.AdapterRAM -gt 0 -and $g.AdapterRAM -lt 1TB) { $g.AdapterRAM } else { 0 }
        $list += @{
            name          = $g.Name
            driver        = $g.DriverVersion
            driver_date   = $g.DriverDate
            vram_gb       = if ($vramBytes -gt 0) { [math]::Round($vramBytes / 1GB, 2) } else { 0 }
            pnp_device_id = $g.PNPDeviceID
            video_mode    = $g.VideoModeDescription
            adapter_ram   = $vramBytes
        }
    }

    $nvidia = $null
    $smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($smi) {
        try {
            $fields = @(
                'name','driver_version','pstate',
                'clocks.gr','clocks.mem','clocks.max.graphics','clocks.max.mem',
                'temperature.gpu','temperature.memory',
                'power.draw','power.limit','power.default_limit',
                'utilization.gpu','utilization.memory','utilization.encoder','utilization.decoder',
                'memory.total','memory.used','memory.free',
                'pcie.link.gen.current','pcie.link.gen.max','pcie.link.width.current','pcie.link.width.max',
                'fan.speed','clocks.sm'
            ) -join ','
            $q = & nvidia-smi --query-gpu=$fields --format=csv,noheader,nounits 2>$null
            if ($q -and $q -notmatch 'not a valid field') {
                $p = $q -split ",\s*"
                $nvidia = @{
                    name              = $p[0]
                    driver            = $p[1]
                    pstate            = $p[2]
                    core_clock_mhz    = [double]$p[3]
                    mem_clock_mhz     = [double]$p[4]
                    core_clock_max    = [double]$p[5]
                    mem_clock_max     = [double]$p[6]
                    temp_core_c       = [double]$p[7]
                    temp_vram_c       = [double]$p[8]
                    power_draw_w      = [double]$p[9]
                    power_limit_w     = [double]$p[10]
                    power_default_w   = [double]$p[11]
                    gpu_util_pct      = [double]$p[12]
                    mem_util_pct      = [double]$p[13]
                    encoder_util_pct  = [double]$p[14]
                    decoder_util_pct  = [double]$p[15]
                    vram_total_mb     = [double]$p[16]
                    vram_used_mb      = [double]$p[17]
                    vram_free_mb      = [double]$p[18]
                    pcie_gen          = $p[19]
                    pcie_gen_max      = $p[20]
                    pcie_width        = $p[21]
                    pcie_width_max    = $p[22]
                    fan_speed_pct     = [double]$p[23]
                    sm_clock_mhz      = [double]$p[24]
                }
            } else {
                $q2 = & nvidia-smi --query-gpu=name,driver_version,memory.total,memory.used,utilization.gpu,utilization.memory,temperature.gpu,power.draw,clocks.sm,pcie.link.gen.current,pcie.link.width.current --format=csv,noheader,nounits 2>$null
                if ($q2) {
                    $p = $q2 -split ",\s*"
                    $nvidia = @{
                        name = $p[0]; driver = $p[1]
                        vram_total_mb = [double]$p[2]; vram_used_mb = [double]$p[3]
                        gpu_util_pct = [double]$p[4]; mem_util_pct = [double]$p[5]
                        temp_core_c = [double]$p[6]; power_draw_w = [double]$p[7]
                        sm_clock_mhz = [double]$p[8]; pcie_gen = $p[9]; pcie_width = $p[10]
                    }
                }
            }
        } catch {}
    }

    # GPU Engine utilization (Windows perf)
    $engines = @()
    try {
        $eng = Get-Counter "\GPU Engine(*)\Utilization Percentage" -MaxSamples 1 -ErrorAction SilentlyContinue
        foreach ($s in $eng.CounterSamples) {
            if ($s.CookedValue -le 0) { continue }
            $engines += @{
                engine = $s.InstanceName
                util_pct = [math]::Round($s.CookedValue, 1)
            }
        }
        $engines = $engines | Sort-Object { $_.util_pct } -Descending | Select-Object -First 12
    } catch {}

    $vramCounters = Get-CounterSafe @(
        '\GPU Adapter Memory(*)\Dedicated Usage',
        '\GPU Adapter Memory(*)\Shared Usage'
    )

    $nv = if ($nvidia) { $nvidia } else { @{} }

    return @{
        adapters = $list
        primary  = if ($list.Count) { $list[0].name } else { $null }
        nvidia   = $nvidia
        clocks = @{
            core_mhz  = $nv.core_clock_mhz
            mem_mhz   = $nv.mem_clock_mhz
            sm_mhz    = $nv.sm_clock_mhz
            max_core  = $nv.core_clock_max
            max_mem   = $nv.mem_clock_max
        }
        power = @{
            draw_w    = $nv.power_draw_w
            limit_w   = $nv.power_limit_w
            default_w = $nv.power_default_w
        }
        thermal = @{
            core_c  = $nv.temp_core_c
            vram_c  = $nv.temp_vram_c
            fan_pct = $nv.fan_speed_pct
        }
        memory = @{
            vram_total_mb     = $nv.vram_total_mb
            vram_used_mb      = $nv.vram_used_mb
            vram_free_mb      = $nv.vram_free_mb
            util_pct          = $nv.mem_util_pct
            dedicated_bytes   = ($vramCounters.Values | Measure-Object -Maximum).Maximum
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
    }
}
