. "$PSScriptRoot\common.ps1"

function Resolve-RamDieType {
    param([string]$PartNumber)
    $pn = ($PartNumber -replace '\s','').ToUpper()
    if ($pn -eq '') { return $null }

    $rules = @(
        @{ re = 'BCPB|BCPV|BCTD|BCTB|BCRC|BCT0|BCT1|K4AAG085WB|K4A8G085WB|HMA81GU6AFR8N|M378A'; die = 'Samsung B-die'; vendor = 'Samsung' }
        @{ re = 'CBCRC|CBCPC|CBCPB|CBCPV|M391A|HMAA1GS6CJR6N'; die = 'Samsung C-die/E-die'; vendor = 'Samsung' }
        @{ re = 'M386A|M378A2K43CB2|KVR|Kingston'; die = 'Various (check part)'; vendor = 'Kingston' }
        @{ re = 'CT16G4SFRA|CT8G4DFRA|CT32G4DFRA|CT2K|CT16G4DFD32A'; die = 'Micron / Crucial (E-die/B-die era)'; vendor = 'Crucial' }
        @{ re = 'F4-3200C14|F4-3600C15|F4-4000C15|F4-4133C19'; die = 'Samsung B-die (common G.Skill)'; vendor = 'G.Skill' }
        @{ re = 'F4-3600C16|F4-3200C16'; die = 'Hynix C-die / mixed'; vendor = 'G.Skill' }
        @{ re = 'HMAA|HMA8|HMA81|HMCG|HMCC'; die = 'SK Hynix'; vendor = 'Hynix' }
        @{ re = 'CMW|CMK|CMT|CMH'; die = 'Corsair (vendor bin varies)'; vendor = 'Corsair' }
        @{ re = 'BLD|BLT|BL8|BL16'; die = 'Crucial Ballistix'; vendor = 'Crucial' }
        @{ re = 'AX4U|AX5U'; die = 'ADATA XPG'; vendor = 'ADATA' }
    )
    foreach ($r in $rules) {
        if ($pn -match $r.re) {
            return @{ die_type = $r.die; vendor_hint = $r.vendor; confidence = 'heuristic' }
        }
    }
    return @{ die_type = 'Unknown'; vendor_hint = $null; confidence = 'low' }
}

function Parse-CpuZMemoryBlock {
    param([string]$Text)
    $profiles = @()
    $blocks = [regex]::Split($Text, '(?=Memory Slot #|SPD slot #|DIMM #)')
    foreach ($block in $blocks) {
        if ($block -notmatch 'Memory|SPD|DIMM|Module Size') { continue }
        $profile = @{
            slot = if ($block -match '#(\d+)') { $Matches[1] } else { $null }
            manufacturer = ([regex]::Match($block, '(?im)Module Manufacturer\s+(.+)$')).Groups[1].Value.Trim()
            part_number = ([regex]::Match($block, '(?im)(?:Part Number|Module Part Number)\s+(.+)$')).Groups[1].Value.Trim()
            speed_mhz = ([regex]::Match($block, '(?im)(?:Max Bandwidth|Configured Clock Speed|Frequency)\s+([^\r\n]+)')).Groups[1].Value.Trim()
            size = ([regex]::Match($block, '(?im)(?:Module Size|Size)\s+(.+)$')).Groups[1].Value.Trim()
        }
        $timingMatch = [regex]::Match($block, '@\s*(\d+)\s*MHz\s+(\d+)-(\d+)-(\d+)-(\d+)\s+([\d.]+)\s*V')
        if ($timingMatch.Success) {
            $profile.timings = @{
                frequency_mhz = [int]$timingMatch.Groups[1].Value
                cl = [int]$timingMatch.Groups[2].Value
                trcd = [int]$timingMatch.Groups[3].Value
                trp = [int]$timingMatch.Groups[4].Value
                tras = [int]$timingMatch.Groups[5].Value
                voltage = [double]$timingMatch.Groups[6].Value
                command_rate = '1T'
            }
        }
        if ($profile.part_number -or $profile.timings) {
            $die = Resolve-RamDieType $profile.part_number
            $profile.die_type = $die.die_type
            $profile.die_confidence = $die.confidence
            $profiles += $profile
        }
    }
    return $profiles
}

function Find-CpuZExports {
    $paths = @()
    $roots = @(
        [Environment]::GetFolderPath('MyDocuments'),
        (Join-Path $env:USERPROFILE 'Downloads'),
        (Join-Path $env:USERPROFILE 'Desktop')
    )
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem -Path $root -Filter '*.txt' -ErrorAction SilentlyContinue | Where-Object {
            $_.Length -lt 5MB -and $_.LastWriteTime -gt (Get-Date).AddDays(-30)
        } | ForEach-Object {
            $head = Get-Content $_.FullName -TotalCount 40 -ErrorAction SilentlyContinue
            if ($head -match 'CPU-Z|Memory Slot|SPD') { $paths += $_.FullName }
        }
    }
    return $paths | Select-Object -First 3
}

function Get-RamSpdTelemetry {
    $modules = @(Get-CimSafe "Win32_PhysicalMemory")
    $enriched = @()
    foreach ($m in $modules) {
        $pn = ($m.PartNumber -replace '\x00','').Trim()
        $die = Resolve-RamDieType $pn
        $enriched += @{
            capacity_gb = [math]::Round($m.Capacity / 1GB, 2)
            speed_mhz = $m.Speed
            configured_mhz = $m.ConfiguredClockSpeed
            manufacturer = ($m.Manufacturer -replace '\x00','').Trim()
            part_number = $pn
            bank_label = $m.BankLabel
            die_type = $die.die_type
            die_confidence = $die.confidence
            timings = $null
        }
    }

    # CPU-Z auto-import (most recent)
    $cpuzProfiles = @()
    foreach ($f in (Find-CpuZExports)) {
        try {
            $txt = Get-Content $f -Raw -ErrorAction Stop
            $parsed = Parse-CpuZMemoryBlock $txt
            if ($parsed.Count -gt 0) {
                $cpuzProfiles = $parsed
                break
            }
        } catch {}
    }

    # Merge CPU-Z timings into modules by part number / slot order
    if ($cpuzProfiles.Count -gt 0) {
        for ($i = 0; $i -lt $enriched.Count; $i++) {
            $cz = $cpuzProfiles[[math]::Min($i, $cpuzProfiles.Count - 1)]
            if ($cz.timings) { $enriched[$i].timings = $cz.timings }
            if ($cz.die_type -and $cz.die_type -ne 'Unknown') { $enriched[$i].die_type = $cz.die_type }
            if ($cz.part_number) { $enriched[$i].part_number = $cz.part_number }
        }
    }

    # XMP profile estimate from speed tier when timings still missing
    foreach ($mod in $enriched) {
        if ($mod.timings) { continue }
        $mhz = 0
        if ($mod.configured_mhz) { $mhz = [int]$mod.configured_mhz }
        elseif ($mod.speed_mhz) { $mhz = [int]$mod.speed_mhz }
        if ($mhz -ge 3200) {
            $mod.timings = @{ frequency_mhz = $mhz; cl = 16; trcd = 18; trp = 18; tras = 38; note = 'Estimated JEDEC/XMP tier — run CPU-Z for exact' }
        } elseif ($mhz -ge 2667) {
            $mod.timings = @{ frequency_mhz = $mhz; cl = 18; trcd = 18; trp = 18; tras = 44; note = 'Estimated DDR4-2667' }
        } elseif ($mhz -ge 2400) {
            $mod.timings = @{ frequency_mhz = $mhz; cl = 17; trcd = 17; trp = 17; tras = 39; note = 'Estimated DDR4-2400' }
        }
    }

    $primary = $enriched | Select-Object -First 1
    return @{
        modules = $enriched
        primary_timings = $primary.timings
        primary_die = $primary.die_type
        cpuz_auto_import = ($cpuzProfiles.Count -gt 0)
        source = if ($cpuzProfiles.Count) { 'smbios+cpuz' } else { 'smbios+heuristic' }
    }
}
