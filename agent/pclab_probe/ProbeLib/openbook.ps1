. "$PSScriptRoot\common.ps1"

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
            "$($_.source)" -in @('blackwell_therm_mmio', 'blackwell_vram_mmio', 'nvapi_raw', 'adl', 'lhm_intel')
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
