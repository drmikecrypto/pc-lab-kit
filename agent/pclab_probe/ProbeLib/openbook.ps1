. "$PSScriptRoot\common.ps1"

function Get-ProbeRegisterCatalog {
    if ($script:ProbeRegisterCatalog) { return $script:ProbeRegisterCatalog }
    $path = Join-Path (Split-Path -Parent $PSScriptRoot) 'data\register-catalog.json'
    if (Test-Path $path) {
        try {
            $raw = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
            $script:ProbeRegisterCatalog = $raw
            return $script:ProbeRegisterCatalog
        } catch {}
    }
    $script:ProbeRegisterCatalog = [pscustomobject]@{ version = 0; registers = @(); provenance_tags = @() }
    return $script:ProbeRegisterCatalog
}

<#
 PCIe negotiated link vs slot capability — flags x8-in-x16 and Gen downgrade.
#>
function Get-ProbePcieLinkTruth {
    $links = @()
    $warnings = @()

    if (Get-Command Get-NvidiaGpuList -ErrorAction SilentlyContinue) {
        . "$PSScriptRoot\gpu.ps1"
    }
    if (Get-Command Get-NvidiaGpuList -ErrorAction SilentlyContinue) {
        foreach ($g in @(Get-NvidiaGpuList)) {
            $genCur = $null; $genMax = $null; $wCur = $null; $wMax = $null
            if ($g.pcie_gen) { try { $genCur = [int]$g.pcie_gen } catch {} }
            if ($g.pcie_gen_max) { try { $genMax = [int]$g.pcie_gen_max } catch {} }
            if ($g.pcie_width) { try { $wCur = [int]$g.pcie_width } catch {} }
            if ($g.pcie_width_max) { try { $wMax = [int]$g.pcie_width_max } catch {} }
            $row = @{
                device       = [string]$g.name
                role         = 'gpu'
                pci_bdf      = if ($g.pci_bus_id) { [string]$g.pci_bus_id } else { $null }
                gen_current  = $genCur
                gen_max      = $genMax
                width_current = $wCur
                width_max    = $wMax
                source       = 'nvidia-smi'
                confidence   = 'measured'
            }
            if ($wMax -and $wCur -and $wCur -lt $wMax) {
                $msg = "GPU $($g.name) running x$wCur / max x$wMax — check slot, riser, or BIOS."
                $row.warning = $msg
                $warnings += $msg
            }
            if ($genMax -and $genCur -and $genCur -lt $genMax) {
                $msg = "GPU $($g.name) PCIe Gen$genCur / max Gen$genMax — lane or chipset limit."
                if (-not $row.warning) { $row.warning = $msg }
                $warnings += $msg
            }
            $links += $row
        }
    }

    foreach ($d in @(Get-CimSafe Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object {
        $_.PNPDeviceID -match '^PCI\\' -and "$($_.Name)" -match 'NVMe|SSD|Storage'
    })) {
        $links += @{
            device = [string]$d.Name
            role   = 'storage'
            instance_id = [string]$d.PNPDeviceID
            source = 'cim'
            confidence = 'inventory'
            note = 'NVMe link speed requires elevated driver query; inventory only.'
        }
    }

    return @{
        links    = @($links)
        warnings = @($warnings | Select-Object -Unique)
        count    = @($links).Count
    }
}

function Get-ProbeOpenBookPayload {
    param($Telemetry = $null, $Devices = $null)

    if (-not $Telemetry) {
        if (Get-Command Get-ProbeDeepTelemetry -ErrorAction SilentlyContinue) {
            . "$PSScriptRoot\system.ps1"
            $Telemetry = Get-ProbeDeepTelemetry
        }
    }
    if (-not $Devices -and (Get-Command Get-ProbeDeviceInventory -ErrorAction SilentlyContinue)) {
        . "$PSScriptRoot\devices.ps1"
        $Devices = Get-ProbeDeviceInventory
    }

    $catalog = Get-ProbeOpenBookCatalog -HwMon $Telemetry
    $regCat = Get-ProbeRegisterCatalog
    $pcie = Get-ProbePcieLinkTruth
    $dossier = $null
    if (Get-Command Get-ProbeSiliconDossier -ErrorAction SilentlyContinue) {
        . "$PSScriptRoot\dossier.ps1"
        $dossier = Get-ProbeSiliconDossier -Telemetry $Telemetry -Devices $Devices
    }

    $provenance = @{}
    foreach ($s in @($catalog.sensors)) {
        $tag = [string]$s.source
        if ($tag) { $provenance[$tag] = 1 + [int]($provenance[$tag]) }
    }
    foreach ($tag in @($regCat.provenance_tags)) {
        if (-not $provenance.ContainsKey([string]$tag)) { $provenance[[string]$tag] = 0 }
    }

    return @{
        open_book         = $catalog
        register_catalog  = @{
            version = [int]($regCat.version)
            register_count = @($regCat.registers).Count
            provenance_tags = @($regCat.provenance_tags)
        }
        pcie              = $pcie
        dossier           = $dossier
        thermal           = if ($Telemetry) { $Telemetry.thermal } else { $null }
        provenance_counts = $provenance
        provenance_total  = @($provenance.Keys).Count
    }
}

<#
 Normalize HwMon/LHM open-book sensors into a flat catalog for Hardware Reference.
 Each row: name, value, unit, source, confidence, optional raw_hex / pci_bdf.
#>
function Get-ProbeOpenBookCatalog {
    param($HwMon)

    $rows = @()
    if (-not $HwMon) {
        return @{ available = $false; count = 0; sensors = @(); note = 'HwMon payload missing' }
    }

    $fromHw = @($HwMon.open_book)
    if ($fromHw.Count -eq 0 -and $HwMon.sensors_flat) {
        $fromHw = @($HwMon.sensors_flat | Where-Object {
            $_.open_book -eq $true -or
            "$($_.source)" -in @('blackwell_therm_mmio', 'blackwell_vram_mmio', 'nvapi_raw', 'adl', 'lhm_intel', 'intel_peci', 'register_catalog')
        })
    }

    foreach ($s in $fromHw) {
        if (-not $s) { continue }
        $v = $null
        if ($null -ne $s.value) { $v = [double]$s.value }
        elseif ($null -ne $s.hotspot_c) { $v = [double]$s.hotspot_c }
        $rows += @{
            name          = if ($s.name) { [string]$s.name } else { 'GPU Hot Spot' }
            value         = $v
            unit          = if ($s.unit) { [string]$s.unit } else { '°C' }
            source        = if ($s.source) { [string]$s.source } else { 'open_book' }
            raw_hex       = if ($s.raw_hex) { [string]$s.raw_hex } else { $null }
            pci_bdf       = if ($s.pci_bdf) { [string]$s.pci_bdf } else { $null }
            confidence    = if ($s.confidence) { [string]$s.confidence } else { 'register_raw' }
            hardware      = if ($s.hardware) { [string]$s.hardware } else { $null }
            hardware_type = if ($s.hardware_type) { [string]$s.hardware_type } else { $null }
            open_book     = $true
        }
    }

    $env = $HwMon.environment
    $result = @{
        available        = $rows.Count -gt 0
        count            = $rows.Count
        sensors          = $rows
        open_book_therm  = if ($env) { [bool]$env.open_book_therm } else { [bool]$HwMon.open_book_therm }
        open_book_vram   = if ($env) { [bool]$env.open_book_vram } else { $false }
        elevated         = if ($env) { [bool]$env.elevated } elseif ($HwMon.elevated) { [bool]$HwMon.elevated } else { $false }
        note             = if ($rows.Count -eq 0) { 'No open-book GPU sensors this sample. Elevate Probe for Ring0 BAR0 / LHM ADL.' } else { $null }
    }

    try {
        $statusPath = Join-Path $env:TEMP 'pclab_openbook_status.json'
        @{
            count    = $result.count
            elevated = $result.elevated
            therm    = $result.open_book_therm
            vram     = $result.open_book_vram
            at       = (Get-Date).ToUniversalTime().ToString('o')
        } | ConvertTo-Json -Compress | Set-Content -Path $statusPath -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}

    return $result
}
