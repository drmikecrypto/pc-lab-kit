#Requires -Version 5.1
<#
.SYNOPSIS
  PcLab Probe - deep Windows hardware scan for PcLab Diagnostic Lab.
  Outputs JSON to stdout or file. No admin required for most data.
#>
param(
    [string]$OutFile = "",
    [switch]$Pretty
)

$ErrorActionPreference = "SilentlyContinue"

function Get-CimSafe {
    param([string]$Class, [string]$Filter = "")
    try {
        if ($Filter) { return Get-CimInstance -ClassName $Class -Filter $Filter }
        return Get-CimInstance -ClassName $Class
    } catch { return @() }
}

function KelvinToC {
    param($k)
    if ($null -eq $k -or $k -le 0) { return $null }
    return [math]::Round(($k / 10.0) - 273.15, 1)
}

# --- Device ---
$cs = Get-CimSafe "Win32_ComputerSystem" | Select-Object -First 1
$bios = Get-CimSafe "Win32_BIOS" | Select-Object -First 1
$enclosure = Get-CimSafe "Win32_SystemEnclosure" | Select-Object -First 1
$chassis = @($enclosure.ChassisTypes)[0]
$isLaptop = $chassis -in @(8, 9, 10, 11, 12, 14, 18, 21)

$device = @{
    form_factor   = if ($isLaptop) { "laptop" } else { "desktop" }
    platform      = "windows"
    manufacturer  = $cs.Manufacturer
    model         = $cs.Model
    system_type   = $cs.SystemType
    total_ram_gb  = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    computer_name = $env:COMPUTERNAME
    chassis_type  = $chassis
}

# --- CPU ---
$cpus = @(Get-CimSafe "Win32_Processor")
$cpu0 = $cpus | Select-Object -First 1
$cpu = @{
    model           = $cpu0.Name.Trim()
    cores           = $cpu0.NumberOfCores
    threads         = $cpu0.NumberOfLogicalProcessors
    base_clock_mhz  = $cpu0.MaxClockSpeed
    current_mhz     = $cpu0.CurrentClockSpeed
    socket          = $cpu0.SocketDesignation
    architecture    = $cpu0.Architecture
    l2_cache_kb     = $cpu0.L2CacheSize
    l3_cache_kb     = $cpu0.L3CacheSize
}

# --- GPU ---
$gpus = @(Get-CimSafe "Win32_VideoController" | Where-Object { $_.Name -and $_.Name -notmatch "Microsoft Basic" })
$gpuList = @()
$primaryVram = 0
foreach ($g in $gpus) {
    $vramBytes = if ($g.AdapterRAM -and $g.AdapterRAM -gt 0 -and $g.AdapterRAM -lt 1TB) { $g.AdapterRAM } else { 0 }
    $vramGb = if ($vramBytes -gt 0) { [math]::Round($vramBytes / 1GB, 2) } else { 0 }
    if ($vramGb -gt $primaryVram) { $primaryVram = $vramGb }
    $gpuList += @{
        name         = $g.Name
        driver       = $g.DriverVersion
        driver_date  = $g.DriverDate
        vram_gb      = $vramGb
        pnp_device_id = $g.PNPDeviceID
        video_mode   = $g.VideoModeDescription
        status       = $g.Status
    }
}

$gpu = @{
    model    = ($gpuList | Select-Object -First 1).name
    vram_gb  = $primaryVram
    adapters = $gpuList
}

# nvidia-smi enrichment
$nvidia = $null
$smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if ($smi) {
    try {
        $q = & nvidia-smi --query-gpu=name,driver_version,memory.total,memory.used,utilization.gpu,utilization.memory,temperature.gpu,power.draw,clocks.sm,pcie.link.gen.current,pcie.link.width.current --format=csv,noheader,nounits 2>$null
        if ($q) {
            $parts = $q -split ",\s*"
            $nvidia = @{
                name            = $parts[0]
                driver          = $parts[1]
                vram_total_mb   = [double]$parts[2]
                vram_used_mb    = [double]$parts[3]
                gpu_util_pct    = [double]$parts[4]
                mem_util_pct    = [double]$parts[5]
                temp_c          = [double]$parts[6]
                power_w         = [double]$parts[7]
                sm_clock_mhz    = [double]$parts[8]
                pcie_gen        = $parts[9]
                pcie_width      = $parts[10]
            }
            if ($nvidia.vram_total_mb -gt 0) {
                $gpu.vram_gb = [math]::Round($nvidia.vram_total_mb / 1024, 2)
                $gpu.model = $nvidia.name
            }
        }
    } catch {}
}

# --- RAM ---
$memBanks = @(Get-CimSafe "Win32_PhysicalMemory")
$ramModules = @()
$totalMem = 0
foreach ($m in $memBanks) {
    $cap = [math]::Round($m.Capacity / 1GB, 2)
    $totalMem += $cap
    $ramModules += @{
        capacity_gb = $cap
        speed_mhz   = $m.Speed
        manufacturer = $m.Manufacturer
        part_number = $m.PartNumber
        form_factor = $m.FormFactor
        bank_label  = $m.BankLabel
    }
}
$ram = @{
    total_gb = if ($totalMem -gt 0) { [math]::Round($totalMem, 1) } else { $device.total_ram_gb }
    modules  = $ramModules
    slots_used = $ramModules.Count
}

# --- Storage ---
$disks = @(Get-CimSafe "Win32_DiskDrive")
$storage = @()
foreach ($d in $disks) {
    $storage += @{
        model      = $d.Model
        interface  = $d.InterfaceType
        size_gb    = [math]::Round($d.Size / 1GB, 1)
        media_type = $d.MediaType
        serial     = $d.SerialNumber
        status     = $d.Status
    }
}

# --- Battery (laptop) ---
$battery = @{}
$bats = @(Get-CimSafe "Win32_Battery")
if ($bats.Count -gt 0) {
    $b = $bats[0]
    $design = $b.DesignCapacity
    $full = $b.FullChargeCapacity
    $healthPct = if ($design -gt 0 -and $full -gt 0) { [math]::Round(100 * $full / $design, 1) } else { $null }
    $battery = @{
        present         = $true
        name            = $b.Name
        chemistry       = $b.Chemistry
        design_capacity = $design
        full_capacity   = $full
        health_percent  = $healthPct
        status          = $b.BatteryStatus
        estimated_charge = $b.EstimatedChargeRemaining
    }
}

# --- Network ---
$network = @()
try {
    $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq "Up"
    foreach ($a in $adapters) {
        $linkMbps = if ($a.LinkSpeed) { [math]::Round($a.LinkSpeed / 1000000, 0) } else { 0 }
        $network += @{
            name          = $a.Name
            interface     = $a.InterfaceDescription
            mac           = $a.MacAddress
            link_speed_mbps = $linkMbps
            media_type    = $a.MediaType
            status        = $a.Status
        }
    }
} catch {
    $nics = @(Get-CimSafe "Win32_NetworkAdapter" | Where-Object { $_.NetEnabled -eq $true -and $_.MACAddress })
    foreach ($n in $nics) {
        $network += @{
            name = $n.Name
            mac  = $n.MACAddress
            adapter_type = $n.AdapterType
        }
    }
}

# --- Motherboard ---
$board = Get-CimSafe "Win32_BaseBoard" | Select-Object -First 1
$motherboard = @{
    manufacturer = $board.Manufacturer
    product      = $board.Product
    version      = $board.Version
    serial       = $board.SerialNumber
}

# --- Sensors (thermal zones) ---
$sensors = @{ cpu_temps_c = @(); throttle_count = 0 }
try {
    $zones = Get-CimSafe "MSAcpi_ThermalZoneTemperature" -Namespace "root/wmi"
    foreach ($z in $zones) {
        $c = KelvinToC $z.CurrentTemperature
        if ($null -ne $c) { $sensors.cpu_temps_c += $c }
    }
    if ($sensors.cpu_temps_c.Count -gt 0) {
        $sensors.cpu_temp_max = ($sensors.cpu_temps_c | Measure-Object -Maximum).Maximum
    }
} catch {}
if ($nvidia -and $nvidia.temp_c) {
    $sensors.gpu_temp_max = $nvidia.temp_c
}

# --- Deep telemetry (CPU/GPU thermal resolver, LHM, etc.) ---
$telemetry = $null
$devices = $null
$drivers = $null
$psu = @{
    note = "PSU wattage not exposed via WMI - enter manually or use OCCT stress data import"
}
try {
    . "$PSScriptRoot\ProbeLib\system.ps1"
    . "$PSScriptRoot\ProbeLib\devices.ps1"
    . "$PSScriptRoot\ProbeLib\drivers.ps1"
    $telemetry = Get-ProbeDeepTelemetry
    # Full PnP + driver advice runs once per /probe so an assembler gets the
    # complete "what is in this box and what still needs a driver" picture.
    $devices = Get-ProbeDeviceInventory
    $drivers = Get-ProbeDriverAdvice -DeviceInventory $devices
    try {
        . "$PSScriptRoot\ProbeLib\dossier.ps1"
        $telemetry.dossier = Get-ProbeSiliconDossier -Telemetry $telemetry -Devices $devices
    } catch {}
} catch {
    $telemetry = @{ error = $_.Exception.Message }
}

# Merge legacy sensors from the thermal resolver (never overwrite a real hot spot
# with a core reading).
$telCpu = if ($telemetry) { $telemetry.cpu } else { $null }
$telGpu = if ($telemetry) { $telemetry.gpu } else { $null }
if ($telCpu -and $telCpu.thermal.package_c) {
    $sensors.cpu_temp_max = $telCpu.thermal.package_c
}
if ($telCpu -and $telCpu.thermal.hotspot_c) {
    $sensors.cpu_hotspot_max = $telCpu.thermal.hotspot_c
}
if ($telGpu -and $telGpu.thermal.core_c) {
    $sensors.gpu_temp_max = $telGpu.thermal.core_c
}
if ($telGpu -and $telGpu.thermal.hot_spot_c) {
    $sensors.gpu_hotspot_max = $telGpu.thermal.hot_spot_c
    $sensors.gpu_hotspot_delta = $telGpu.thermal.hotspot_delta_c
    $sensors.gpu_hotspot_source = $telGpu.thermal.hotspot_source
}
if ($telGpu -and $telGpu.thermal.memory_c) {
    $sensors.gpu_vram_temp = $telGpu.thermal.memory_c
}
if ($telGpu -and $telGpu.nvidia -and $telGpu.nvidia.name -notmatch 'not a valid') {
    $nvidia = $telGpu.nvidia
    if ($telGpu.thermal.hot_spot_c) {
        $nvidia.temp_hotspot_c = $telGpu.thermal.hot_spot_c
        $nvidia.temp_hotspot_source = $telGpu.thermal.hotspot_source
    }
}
if ($telCpu -and $telCpu.architecture) {
    $cpu = @{
        model             = $telCpu.architecture.model
        vendor            = $telCpu.architecture.vendor
        vendor_tag        = $telCpu.architecture.vendor_tag
        codename          = $telCpu.architecture.codename
        cores             = $telCpu.architecture.cores
        threads           = $telCpu.architecture.threads
        performance_cores = $telCpu.architecture.performance_cores
        efficiency_cores  = $telCpu.architecture.efficiency_cores
        hybrid            = $telCpu.architecture.hybrid
        base_clock_mhz    = $telCpu.clocks.base_mhz
        current_mhz       = $telCpu.clocks.current_mhz
        socket            = $telCpu.architecture.socket
        architecture      = $telCpu.architecture.architecture_code
        l2_cache_kb       = $telCpu.architecture.l2_cache_kb
        l3_cache_kb       = $telCpu.architecture.l3_cache_kb
        instruction_sets  = $telCpu.architecture.instruction_sets
        package_c         = $telCpu.thermal.package_c
        hotspot_c         = $telCpu.thermal.hotspot_c
        tjmax_c           = $telCpu.thermal.tjmax_c
    }
}
if ($telemetry -and $telemetry.ram) {
    $ram = $telemetry.ram
}
if ($telemetry -and $telemetry.motherboard) {
    $motherboard = $telemetry.motherboard
}
$gaming = @{}
if ($telemetry -and $telemetry.gaming) {
    $gaming = $telemetry.gaming
}

$elevated = $false
try { $elevated = [bool]$telemetry.elevated } catch {}
if (-not $elevated) {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $elevated = ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {}
}

$biosInfo = @{
    vendor  = $bios.Manufacturer
    version = $bios.SMBIOSBIOSVersion
    date    = $bios.ReleaseDate
}
if ($devices -and $devices.bios) { $biosInfo = $devices.bios }

# Drop the full PnP dump from the main report - it is available on GET /devices.
$devicesSummary = $null
if ($devices) {
    $devicesSummary = @{
        summary      = $devices.summary
        firmware     = $devices.firmware
        motherboard  = $devices.motherboard
        bios         = $devices.bios
        tpm          = $devices.tpm
        secure_boot  = $devices.secure_boot
        monitors     = $devices.monitors
        usb          = @{
            controllers  = $devices.usb.controllers
            hubs         = $devices.usb.hubs
            device_count = $devices.usb.device_count
            devices      = @($devices.usb.devices | Select-Object -First 40)
        }
        audio        = $devices.audio
        bluetooth    = $devices.bluetooth
        pci          = $devices.pci
        system_slots = $devices.system_slots
        ports        = $devices.ports
        battery      = $devices.battery
        problem      = $devices.problem
        driverless   = $devices.driverless
        findings     = $devices.findings
        # Category counts without the full device arrays keep the payload light.
        category_counts = $devices.summary.categories
    }
}

$report = @{
    probe_version = 5
    agent         = "pclab-probe"
    collected_at  = (Get-Date).ToUniversalTime().ToString("o")
    elevated      = $elevated
    device        = $device
    cpu           = $cpu
    gpu           = $gpu
    gpus          = $gpuList
    ram           = $ram
    storage       = $storage
    battery       = $battery
    network       = $network
    motherboard   = $motherboard
    sensors       = $sensors
    nvidia_smi    = $nvidia
    psu           = $psu
    peripherals   = @{
        usb_controllers = if ($devices) { @($devices.usb.controllers).Count } else { @(Get-CimSafe "Win32_USBControllerDevice").Count }
        usb_devices     = if ($devices) { $devices.usb.device_count } else { $null }
        monitors        = if ($devices) { $devices.monitors.count } else { $null }
        pnp_devices     = if ($devices) { $devices.summary.total_devices } else { $null }
        problem_devices = if ($devices) { $devices.summary.problem_devices } else { $null }
        driverless      = if ($devices) { $devices.summary.driverless } else { $null }
    }
    gaming        = $gaming
    bios          = $biosInfo
    thermal       = if ($telemetry) { $telemetry.thermal } else { $null }
    devices       = $devicesSummary
    drivers       = $drivers
    telemetry     = $telemetry
}

$json = if ($Pretty) {
    $report | ConvertTo-Json -Depth 14 -Compress:$false
} else {
    $report | ConvertTo-Json -Depth 14 -Compress
}

if ($OutFile) {
    $json | Out-File -FilePath $OutFile -Encoding utf8
    Write-Host "Wrote $OutFile"
} else {
    Write-Output $json
}
