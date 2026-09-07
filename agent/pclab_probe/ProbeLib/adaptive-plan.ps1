# Adaptive lab plan - compile hardware-specific Full Lab steps from fingerprint + inventory
# Dot-sourced from suite.ps1 / PcLabProbeServe.ps1

function Get-ProbeAdaptiveLabPlan {
    param(
        $Fingerprint = $null,
        $Devices = $null,
        $Platform = $null,
        $Telemetry = $null,
        [string]$Template = 'adaptive'
    )

    if (-not $Devices -and (Get-Command Get-ProbeDeviceInventory -ErrorAction SilentlyContinue)) {
        . "$PSScriptRoot\devices.ps1"
        $Devices = Get-ProbeDeviceInventory -Telemetry $Telemetry
    }
    if (-not $Platform -and $Devices -and $Devices.platform) { $Platform = $Devices.platform }
    if (-not $Fingerprint -and $Devices -and $Devices.fingerprint) { $Fingerprint = $Devices.fingerprint }
    if (-not $Fingerprint -and (Get-Command Get-ProbeMachineFingerprint -ErrorAction SilentlyContinue)) {
        . "$PSScriptRoot\platform.ps1"
        $Fingerprint = Get-ProbeMachineFingerprint -Platform $Platform -Devices $Devices -Telemetry $Telemetry
    }

    $steps = [System.Collections.Generic.List[object]]::new()
    $findings = [System.Collections.Generic.List[object]]::new()
    $gated = $false
    $gateReason = $null

    $driverless = 0
    if ($Devices -and $Devices.summary) { $driverless = [int]$Devices.summary.driverless }
    $chipsetMissing = $false
    $networkMissing = $false
    $gpuMissing = $false
    foreach ($d in @($Devices.driverless)) {
        $n = "$($d.name)$($d.category)"
        if ($n -match 'chipset|SMBus|LPC|Host Bridge|PCI Express Root|MEI|Management Engine|PSP') { $chipsetMissing = $true }
        if ($n -match 'Ethernet|LAN|Wi-?Fi|Wireless|Network|Bluetooth') { $networkMissing = $true }
        if ($n -match 'NVIDIA|GeForce|Radeon|Display|VGA|3D') { $gpuMissing = $true }
    }
    # Soft-gate: network missing alone does not block, but chipset / mass driverless does
    if ($chipsetMissing -or $driverless -ge 5) {
        $gated = $true
        $gateReason = if ($chipsetMissing) {
            'Chipset / platform driver missing - run Drivers action plan before Full Lab soak'
        } else {
            "$driverless driverless devices - prefer inventory + driver fix before long stress"
        }
        $findings.Add(@{
            severity = 'warn'
            code     = 'adaptive_gate_drivers'
            title    = 'Lab gated pending drivers'
            detail   = $gateReason
        })
    } elseif ($networkMissing) {
        $findings.Add(@{
            severity = 'warn'
            code     = 'adaptive_network_driver'
            title    = 'Network driver missing'
            detail   = 'Lab continues offline; install LAN/Wi-Fi after chipset for Windows Update / vendor packages'
        })
    }
    if ($gpuMissing -and -not $gated) {
        $findings.Add(@{
            severity = 'warn'
            code     = 'adaptive_gpu_driver'
            title    = 'GPU driver missing'
            detail   = 'GPU bench may fall back or fail until vendor package is installed'
        })
    }

    $steps.Add(@{
        id            = 'inventory'
        kind          = 'inventory'
        label         = 'Platform inventory'
        params        = @{ include_platform = $true }
        reason        = 'Capture PnP, SMBIOS, UEFI/TPM, and coverage before benches'
        hardware_refs = @('platform', 'pnp')
        order         = 10
    })

    if ($gated) {
        $steps.Add(@{
            id            = 'drivers_gate'
            kind          = 'sensor'
            label         = 'Driver gate (review)'
            params        = @{ action = 'driver_action_plan' }
            reason        = $gateReason
            hardware_refs = @('drivers')
            order         = 15
            gate          = $true
        })
        # Inventory-only profile when heavily gated
        return @{
            id            = 'adaptive'
            label         = 'Adaptive Lab (inventory-first)'
            template      = $Template
            gated         = $true
            gate_reason   = $gateReason
            steps         = @($steps | Sort-Object { $_.order })
            benches       = @()
            stress_id     = $null
            stress_seconds = 0
            findings      = @($findings)
            fingerprint_id = if ($Fingerprint) { $Fingerprint.id } else { $null }
            coverage_score = if ($Fingerprint) { $Fingerprint.coverage_score } else { $null }
            form_factor   = if ($Fingerprint) { $Fingerprint.form_factor } else { 'desktop' }
            duration_hint_min = 3
            collected_at  = (Get-Date).ToUniversalTime().ToString('o')
        }
    }

    $cores = 0
    try {
        $cpu = Get-CimSafe Win32_Processor | Select-Object -First 1
        if ($cpu) { $cores = [int]$cpu.NumberOfLogicalProcessors }
    } catch {}
    if ($cores -le 0 -and $Telemetry -and $Telemetry.cpu -and $Telemetry.cpu.architecture) {
        $cores = [int]($Telemetry.cpu.architecture.threads)
    }

    $hasDiscreteGpu = if ($Fingerprint) { [bool]$Fingerprint.has_discrete_gpu } else { $false }
    $nvmeCount = if ($Fingerprint) { [int]$Fingerprint.nvme_count } else { 0 }
    $diskCount = if ($Fingerprint) { [int]$Fingerprint.disk_count } else { 0 }
    $isLaptop = if ($Fingerprint -and $Fingerprint.form_factor -eq 'laptop') { $true } else { $false }
    $hasHdd = $false
    foreach ($d in @($Platform.storage)) {
        if ("$($d.media_type)" -match 'HDD|Unspecified' -and -not $d.is_nvme) { $hasHdd = $true }
        if ("$($d.bus_type)" -match 'SATA|ATA' -and -not $d.is_nvme) { $hasHdd = $true }
    }

    $benches = [System.Collections.Generic.List[string]]::new()
    $benches.Add('cpu')
    $steps.Add(@{
        id = 'bench:cpu'; kind = 'bench'; label = 'CPU single-thread'
        params = @{ id = 'cpu' }
        reason = 'Baseline single-thread throughput for this CPU'
        hardware_refs = @('cpu')
        order = 20
    })

    if ($cores -ge 8) {
        $benches.Add('cpu_mt')
        $steps.Add(@{
            id = 'bench:cpu_mt'; kind = 'bench'; label = 'CPU multi-thread'
            params = @{ id = 'cpu_mt' }
            reason = "$cores logical processors - multi-thread bench unlocked"
            hardware_refs = @('cpu')
            order = 25
        })
        $benches.Add('cpu_cache')
        $steps.Add(@{
            id = 'bench:cpu_cache'; kind = 'bench'; label = 'CPU cache'
            params = @{ id = 'cpu_cache' }
            reason = 'Cache hierarchy check on high-core silicon'
            hardware_refs = @('cpu')
            order = 28
        })
    } else {
        $benches.Add('cpu_mt')
        $steps.Add(@{
            id = 'bench:cpu_mt'; kind = 'bench'; label = 'CPU multi-thread'
            params = @{ id = 'cpu_mt' }
            reason = 'Verify MT scaling even on lower core counts'
            hardware_refs = @('cpu')
            order = 25
        })
    }

    $benches.Add('memory')
    $steps.Add(@{
        id = 'bench:memory'; kind = 'bench'; label = 'Memory bandwidth'
        params = @{ id = 'memory' }
        reason = 'RAM bandwidth / latency vs SMBIOS module inventory'
        hardware_refs = @('ram', 'smbios')
        order = 30
    })

    if ($diskCount -gt 0) {
        $benches.Add('storage')
        $storageReason = if ($nvmeCount -ge 2) {
            "$nvmeCount NVMe drives - sequential + multi-disk storage bench"
        } elseif ($hasHdd) {
            'HDD present - longer storage endurance step (not NVMe-class timing)'
        } elseif ($nvmeCount -eq 1) {
            'Single NVMe - sequential read/write profile'
        } else {
            'Storage present - sequential profile'
        }
        $steps.Add(@{
            id = 'bench:storage'; kind = 'bench'; label = 'Storage'
            params = @{
                id = 'storage'
                nvme_count = $nvmeCount
                multi_disk = ($nvmeCount -ge 2)
                endurance_extra_s = if ($hasHdd) { 120 } else { 0 }
            }
            reason = $storageReason
            hardware_refs = @('storage')
            order = 40
        })
    }

    if ($hasDiscreteGpu) {
        $gpuVendor = 'unknown'
        foreach ($p in @($Platform.pci_config)) {
            $ven = "$($p.vendor_id)".ToUpperInvariant()
            if ($ven -eq '10DE') { $gpuVendor = 'nvidia'; break }
            if ($ven -eq '1002') { $gpuVendor = 'amd'; break }
            if ($ven -eq '8086') { $gpuVendor = 'intel' }
        }
        $benches.Add('gpu')
        $steps.Add(@{
            id = 'bench:gpu'; kind = 'bench'; label = 'GPU compute'
            params = @{ id = 'gpu'; vendor = $gpuVendor }
            reason = "Discrete GPU ($gpuVendor) - Vulkan/compute arena"
            hardware_refs = @('gpu')
            order = 50
        })
    } else {
        $findings.Add(@{
            severity = 'info'
            code     = 'adaptive_skip_gpu'
            title    = 'GPU soak skipped'
            detail   = 'No discrete GPU fingerprint - iGPU-only systems skip heavy GPU bench/stress'
        })
    }

    # Open-book sensor snapshot when elevated Ring0 available
    if ($Fingerprint -and $Fingerprint.elevated) {
        $steps.Add(@{
            id = 'sensor:openbook'
            kind = 'sensor'
            label = 'Open Book sensors'
            params = @{ include_openbook = $true }
            reason = 'Elevated probe - capture Ring0 / BAR0 open-book channels before stress'
            hardware_refs = @('gpu', 'ec_board')
            order = 52
        })
    }

    if ($isLaptop -and $Devices -and @($Devices.battery).Count -gt 0) {
        $onBattery = $false
        try {
            foreach ($b in @($Devices.battery)) {
                if ("$($b.battery_status)$($b.status)" -match 'Discharging|Battery') { $onBattery = $true }
            }
        } catch {}
        $steps.Add(@{
            id = 'sensor:battery'
            kind = 'sensor'
            label = 'Battery / AC path'
            params = @{ sample_battery = $true; prefer_ac = $true }
            reason = if ($onBattery) {
                'Laptop on battery - prefer AC for Full Lab thermal truth'
            } else {
                'Laptop with battery - sample AC vs battery thermal path'
            }
            hardware_refs = @('battery')
            order = 55
        })
    }

    # Storage wear finding (does not gate)
    $stressSecHint = $null
    foreach ($d in @($Platform.storage)) {
        if ($null -ne $d.wear -and [int]$d.wear -ge 90) {
            $findings.Add(@{
                severity = 'warn'
                code     = 'storage_wear_high'
                title    = "Storage wear $($d.wear)%"
                detail   = "$($d.friendly_name) reports high wear - endurance stress kept short"
            })
            if ($hasHdd -eq $false) { $stressSecHint = 120 }
        }
    }

    $stressId = 'combined'
    $stressSec = 180
    if ($hasDiscreteGpu -and $cores -ge 12) {
        $stressId = 'oracle'
        $stressSec = 300
        $reason = 'High-core + discrete GPU - Stability Oracle soak'
    } elseif ($hasDiscreteGpu) {
        $stressId = 'combined'
        $stressSec = 180
        $reason = 'Discrete GPU - combined CPU/GPU stress'
    } elseif ($isLaptop) {
        $stressId = 'quick'
        $stressSec = 90
        $reason = 'Laptop form factor - shorter thermal soak'
    } else {
        $stressId = 'combined'
        $stressSec = 120
        $reason = 'Desktop without discrete GPU - moderate CPU stress'
    }
    if ($hasHdd) { $stressSec = [math]::Max($stressSec, 240) }
    if ($stressSecHint) { $stressSec = [math]::Min($stressSec, [int]$stressSecHint) }

    $steps.Add(@{
        id = 'stress'
        kind = 'stress'
        label = "Stress: $stressId"
        params = @{ id = $stressId; seconds = $stressSec }
        reason = $reason
        hardware_refs = @('cpu', $(if ($hasDiscreteGpu) { 'gpu' } else { $null })) | Where-Object { $_ }
        order = 80
    })

    if ($Fingerprint -and $Fingerprint.coverage_score -lt 50) {
        $findings.Add(@{
            severity = 'info'
            code     = 'adaptive_low_coverage'
            title    = "Platform coverage $($Fingerprint.coverage_score)%"
            detail   = 'Elevate Probe for fuller PCI/EC planes - benches still run'
        })
    }
    if ($Platform -and $Platform.tpm -and $Platform.tpm.present -and $Platform.uefi -and $null -ne $Platform.uefi.secure_boot -and -not $Platform.uefi.secure_boot) {
        $findings.Add(@{
            severity = 'info'
            code     = 'secure_boot_off'
            title    = 'Secure Boot off'
            detail   = 'Finding only - does not fail stress'
        })
    }
    if ($Platform -and $Platform.uefi -and $Platform.uefi.setup_mode -eq $true) {
        $findings.Add(@{
            severity = 'warn'
            code     = 'uefi_setup_mode'
            title    = 'UEFI Setup Mode'
            detail   = 'Secure Boot keys may not be enrolled - shop policy finding only'
        })
    }

    $hint = [math]::Round(2 + ($benches.Count * 1.5) + ($stressSec / 60.0), 0)

    return @{
        id             = 'adaptive'
        label          = 'Adaptive Lab'
        template       = $Template
        gated          = $false
        gate_reason    = $null
        steps          = @($steps | Sort-Object { $_.order })
        benches        = @($benches)
        stress_id      = $stressId
        stress_seconds = $stressSec
        findings       = @($findings)
        fingerprint_id = if ($Fingerprint) { $Fingerprint.id } else { $null }
        coverage_score = if ($Fingerprint) { $Fingerprint.coverage_score } else { $null }
        form_factor    = if ($Fingerprint) { $Fingerprint.form_factor } else { 'desktop' }
        has_discrete_gpu = $hasDiscreteGpu
        nvme_count     = $nvmeCount
        duration_hint_min = [int]$hint
        collected_at   = (Get-Date).ToUniversalTime().ToString('o')
    }
}
