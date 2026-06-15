. "$PSScriptRoot\common.ps1"

function Get-ProbeCstateTelemetry {
    $cstates = @()
    $pstates = @()
    $residency = @{}

    # Collect all Processor Information idle/utility counters
    try {
        $counters = @(
            '\Processor Information(_Total)\% Processor Utility',
            '\Processor Information(_Total)\% Idle Time',
            '\Processor Information(_Total)\Processor Frequency',
            '\Processor(_Total)\% C1 Time',
            '\Processor(_Total)\% C2 Time',
            '\Processor(_Total)\% C3 Time',
            '\Processor(_Total)\% DPC Time',
            '\Processor(_Total)\% Interrupt Time'
        )
        $sample = Get-CounterSafe $counters
        foreach ($key in $sample.Keys) {
            if ($key -match 'c1 time') { $residency['C1_pct'] = $sample[$key] }
            if ($key -match 'c2 time') { $residency['C2_pct'] = $sample[$key] }
            if ($key -match 'c3 time') { $residency['C3_pct'] = $sample[$key] }
            if ($key -match 'idle time') { $residency['idle_pct'] = $sample[$key] }
            if ($key -match 'processor utility') { $residency['c0_active_pct'] = $sample[$key] }
        }
    } catch {}

    # Idle State instances (C-state residency on modern Intel/AMD)
    try {
        $idle = Get-Counter "\Processor Information(_Total)\Idle State" -MaxSamples 1 -ErrorAction SilentlyContinue
        foreach ($s in $idle.CounterSamples) {
            $name = $s.InstanceName
            if ($name -match '_Total|Idle') { continue }
            $cstates += @{
                state = $name
                residency_pct = [math]::Round($s.CookedValue, 2)
            }
        }
    } catch {}

    # Processor Power module — P-state / idle demotion
    try {
        $pwr = Get-Counter "\Processor Power(_Total)\*" -MaxSamples 1 -ErrorAction SilentlyContinue
        foreach ($s in $pwr.CounterSamples) {
            if ($s.CookedValue -le 0) { continue }
            $pstates += @{
                metric = ($s.Path -replace '.*\\','')
                value = [math]::Round($s.CookedValue, 3)
            }
        }
        $pstates = $pstates | Select-Object -First 16
    } catch {}

    # ACPI sleep states available
    $acpi = @()
    try {
        $pc = powercfg /a 2>&1
        foreach ($line in $pc) {
            if ($line -match '^\s*(\S.+?)\s+\((Available|Not Available|Unavailable)\)') {
                $acpi += @{ state = $Matches[1].Trim(); available = ($Matches[2] -eq 'Available') }
            }
        }
    } catch {}

    # 3-sample residency snapshot (1s interval) for stability
    $series = @()
    for ($i = 0; $i -lt 3; $i++) {
        $snap = Get-CounterSafe @(
            '\Processor Information(_Total)\% Processor Utility',
            '\Processor(_Total)\% C1 Time'
        )
        $series += @{
            t = $i
            active_pct = $snap['\\processor information(_total)\% processor utility']
            c1_pct = $snap['\\processor(_total)\% c1 time']
        }
        if ($i -lt 2) { Start-Sleep -Seconds 1 }
    }

    $deepC = ($cstates | Where-Object { $_.state -match 'C[6-7]|CC6|CC7|Parked' } | Measure-Object -Property residency_pct -Sum).Sum
    if (-not $deepC) {
        $deepC = $residency['idle_pct']
    }

    return @{
        cstates = $cstates
        residency_summary = $residency
        pstates = $pstates
        acpi_sleep = $acpi
        residency_series = $series
        deep_idle_pct = [math]::Round([double]$deepC, 2)
        source = 'perf_counters+powercfg'
    }
}
