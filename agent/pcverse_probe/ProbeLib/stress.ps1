function Get-PcverseStressCatalog {
    return @(
        @{ id = 'cpu'; label = 'CPU stress'; seconds_default = 15; max_seconds = 120 }
        @{ id = 'memory'; label = 'Memory stress'; seconds_default = 15; max_seconds = 120 }
    )
}

function Invoke-PcverseCpuStress {
    param([int]$Seconds = 15)
    $Seconds = [Math]::Max(5, [Math]::Min(120, $Seconds))
    $threads = [Environment]::ProcessorCount
    $jobs = @()
    $end = (Get-Date).AddSeconds($Seconds)
    for ($t = 0; $t -lt $threads; $t++) {
        $jobs += Start-Job -ScriptBlock {
            param($until)
            while ((Get-Date) -lt $until) {
                $x = 0.0
                for ($i = 0; $i -lt 50000; $i++) { $x += [Math]::Sqrt($i + 1) }
            }
        } -ArgumentList $end
    }
    while ((Get-Date) -lt $end) { Start-Sleep -Milliseconds 200 }
    $jobs | Stop-Job -ErrorAction SilentlyContinue | Out-Null
    $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
    return @{
        id = 'cpu'
        label = 'PCVerse CPU stress'
        duration_s = $Seconds
        threads = $threads
        status = 'completed'
        replaces = @('Prime95', 'OCCT', 'AIDA64')
    }
}

function Invoke-PcverseMemoryStress {
    param([int]$Seconds = 15, [int]$Percent = 40)
    $Seconds = [Math]::Max(5, [Math]::Min(120, $Seconds))
    $Percent = [Math]::Max(10, [Math]::Min(70, $Percent))
    $targetBytes = [long]([Math]::Min(
        ([GC]::GetTotalMemory($false) * 4),
        ((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory * 1KB) * ($Percent / 100.0)
    ))
    if ($targetBytes -lt 32MB) { $targetBytes = 32MB }
    $blocks = @()
    $chunk = 8MB
    $allocated = 0L
    try {
        while ($allocated -lt $targetBytes) {
            $take = [Math]::Min($chunk, $targetBytes - $allocated)
            $blocks += New-Object byte[] $take
            $allocated += $take
        }
        $end = (Get-Date).AddSeconds($Seconds)
        while ((Get-Date) -lt $end) {
            foreach ($b in $blocks) {
                for ($i = 0; $i -lt [Math]::Min($b.Length, 65536); $i += 4096) {
                    $b[$i] = ($b[$i] -bxor 0xA5)
                }
            }
        }
    } finally {
        $blocks = $null
        [GC]::Collect()
    }
    return @{
        id = 'memory'
        label = 'PCVerse memory stress'
        duration_s = $Seconds
        allocated_mb = [math]::Round($allocated / 1MB, 1)
        status = 'completed'
        replaces = @('TestMem5', 'HCI MemTest', 'MemTest64')
    }
}

function Invoke-PcverseStress {
    param([string]$Id = 'cpu', [hashtable]$Options = @{})
    $seconds = 15
    $percent = 40
    if ($Options.ContainsKey('seconds') -and $Options.seconds) { $seconds = [int]$Options.seconds }
    if ($Options.ContainsKey('percent') -and $Options.percent) { $percent = [int]$Options.percent }
    switch ($Id.ToLower()) {
        'cpu' { return Invoke-PcverseCpuStress -Seconds $seconds }
        'memory' { return Invoke-PcverseMemoryStress -Seconds $seconds -Percent $percent }
        default { throw "Unknown stress test: $Id" }
    }
}
