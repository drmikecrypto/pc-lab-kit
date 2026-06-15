#Requires -Version 5.1
<#
.SYNOPSIS
  PCVerse Probe — deep Windows hardware scan for PCVerse Diagnostic Lab.
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

# --- USB / peripherals count ---
$usb = @(Get-CimSafe "Win32_USBControllerDevice")
$pnp = @(Get-CimSafe "Win32_PnPEntity" | Where-Object { $_.Present -eq $true -and $_.Name })
$peripherals = @{
    usb_controllers = $usb.Count
    pnp_devices     = $pnp.Count
    sample_devices  = @($pnp | Select-Object -First 15 | ForEach-Object { $_.Name })
}

# --- PSU (estimate from system, no direct WMI) ---
$psu = @{
    note = "PSU wattage not exposed via WMI - enter manually or use OCCT stress data import"
}

# --- Deep telemetry v3 ---
$telemetry = $null
try {
    . "$PSScriptRoot\ProbeLib\system.ps1"
    $telemetry = Get-PcverseDeepTelemetry
} catch {
    $telemetry = @{ error = $_.Exception.Message }
}

# Merge legacy sensors from telemetry
if ($telemetry.cpu.thermal.package_c) {
    $sensors.cpu_temp_max = $telemetry.cpu.thermal.package_c
}
if ($telemetry.gpu.thermal.core_c) {
    $sensors.gpu_temp_max = $telemetry.gpu.thermal.core_c
} elseif ($telemetry.gpu.nvidia -and $telemetry.gpu.nvidia.temp_core_c) {
    $sensors.gpu_temp_max = $telemetry.gpu.nvidia.temp_core_c
}
if ($telemetry.gpu.nvidia -and $telemetry.gpu.nvidia.name -notmatch 'not a valid') {
    $nvidia = $telemetry.gpu.nvidia
}
if ($telemetry.ram) {
    $ram = $telemetry.ram
}
$gaming = @{}
if ($telemetry.gaming) {
    $gaming = $telemetry.gaming
}

$report = @{
    probe_version = 4
    agent         = "pcverse-probe"
    collected_at  = (Get-Date).ToUniversalTime().ToString("o")
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
    peripherals   = $peripherals
    gaming        = $gaming
    bios          = @{
        vendor = $bios.Manufacturer
        version = $bios.SMBIOSBIOSVersion
        date = $bios.ReleaseDate
    }
    telemetry     = $telemetry
}

$json = if ($Pretty) {
    $report | ConvertTo-Json -Depth 12 -Compress:$false
} else {
    $report | ConvertTo-Json -Depth 12 -Compress
}

if ($OutFile) {
    $json | Out-File -FilePath $OutFile -Encoding utf8
    Write-Host "Wrote $OutFile"
} else {
    Write-Output $json
}
