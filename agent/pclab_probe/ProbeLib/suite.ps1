# Full Lab suite runner — long jobs with cancel + status file.
# Dot-sourced from PcLabProbeServe.ps1

function Get-ProbeSuiteStatePath {
    $dir = Join-Path $env:LOCALAPPDATA 'PC Lab Kit\suite'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return (Join-Path $dir 'current.json')
}

function Get-ProbeSuiteCancelPath {
    $dir = Join-Path $env:LOCALAPPDATA 'PC Lab Kit\suite'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return (Join-Path $dir 'cancel.flag')
}

function Write-ProbeSuiteState {
    param([hashtable]$State)
    $path = Get-ProbeSuiteStatePath
    $State.updated_at = (Get-Date).ToUniversalTime().ToString('o')
    ($State | ConvertTo-Json -Depth 12 -Compress) | Set-Content -Path $path -Encoding UTF8
}

function Read-ProbeSuiteState {
    $path = Get-ProbeSuiteStatePath
    if (-not (Test-Path $path)) {
        return @{ status = 'idle'; progress = 0; step = 'idle' }
    }
    try {
        return (Get-Content $path -Raw | ConvertFrom-Json)
    } catch {
        return @{ status = 'idle'; progress = 0; step = 'idle'; error = 'corrupt_state' }
    }
}

function Test-ProbeSuiteCancelled {
    return (Test-Path (Get-ProbeSuiteCancelPath))
}

function Get-ProbeSuiteProfiles {
    return @{
        quick = @{
            id = 'quick'
            label = 'Quick Lab'
            benches = @('cpu')
            stress_id = 'quick'
            stress_seconds = 60
        }
        standard = @{
            id = 'standard'
            label = 'Full Lab'
            benches = @('cpu', 'cpu_mt', 'cpu_cache', 'memory', 'storage', 'gpu')
            stress_id = 'combined'
            stress_seconds = 180
        }
        deep = @{
            id = 'deep'
            label = 'Deep Lab'
            benches = @('cpu', 'cpu_mt', 'cpu_cache', 'memory', 'storage', 'gpu')
            stress_id = 'combined'
            stress_seconds = 300
        }
    }
}

function Start-ProbeSuiteJob {
    param(
        [string]$Profile = 'standard',
        [string]$ScriptDir
    )
    $profiles = Get-ProbeSuiteProfiles
    if (-not $profiles.ContainsKey($Profile)) { $Profile = 'standard' }
    $p = $profiles[$Profile]

    $cur = Read-ProbeSuiteState
    if ($cur.status -eq 'running') {
        return @{ ok = $false; error = 'already_running'; job = $cur }
    }

    Remove-Item (Get-ProbeSuiteCancelPath) -Force -ErrorAction SilentlyContinue
    $jobId = [guid]::NewGuid().ToString('n').Substring(0, 16)
    $state = @{
        ok = $true
        id = $jobId
        profile = $Profile
        label = $p.label
        status = 'running'
        progress = 1
        step = 'starting'
        cancel_requested = $false
        benches = @()
        stress = $null
        samples = @()
        probe = $null
        duration_s = $null
        error = $null
        started_at = (Get-Date).ToUniversalTime().ToString('o')
    }
    Write-ProbeSuiteState $state

    $benchList = ($p.benches -join ',')
    $stressId = $p.stress_id
    $stressSec = [int]$p.stress_seconds

    Start-Job -Name "pclab-suite-$jobId" -ScriptBlock {
        param($ScriptDir, $JobId, $Profile, $BenchCsv, $StressId, $StressSec, $StatePath, $CancelPath)

        function Write-State($obj) {
            $obj.updated_at = (Get-Date).ToUniversalTime().ToString('o')
            ($obj | ConvertTo-Json -Depth 14 -Compress) | Set-Content -Path $StatePath -Encoding UTF8
        }
        function Cancelled { return (Test-Path $CancelPath) }

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $state = @{
            ok = $true
            id = $JobId
            profile = $Profile
            status = 'running'
            progress = 5
            step = 'probe'
            cancel_requested = $false
            benches = @()
            stress = $null
            samples = @()
            probe = $null
            duration_s = $null
            error = $null
            started_at = (Get-Date).ToUniversalTime().ToString('o')
        }
        Write-State $state

        try {
            . (Join-Path $ScriptDir 'PcLabProbe.ps1')
            # PcLabProbe.ps1 may output JSON when run as file; for suite we call collector differently.
        } catch {}

        try {
            $probeOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'PcLabProbe.ps1') 2>$null
            if ($probeOut) {
                try { $state.probe = ($probeOut | ConvertFrom-Json) } catch { $state.probe = @{ raw = $true } }
            }
            $state.progress = 20
            $state.step = 'benches'
            Write-State $state
        } catch {
            $state.error = "probe_failed: $($_.Exception.Message)"
        }

        if (Cancelled) {
            $state.status = 'cancelled'; $state.step = 'cancelled'; $state.cancel_requested = $true
            Write-State $state; return
        }

        . (Join-Path $ScriptDir 'ProbeLib\benchmark.ps1')
        . (Join-Path $ScriptDir 'ProbeLib\stress.ps1')

        $benches = @()
        $benchIds = @($BenchCsv -split ',' | Where-Object { $_ })
        $i = 0
        foreach ($bid in $benchIds) {
            if (Cancelled) {
                $state.status = 'cancelled'; $state.step = 'cancelled'; $state.cancel_requested = $true
                $state.benches = $benches
                Write-State $state; return
            }
            $i++
            $state.step = "bench:$bid"
            $state.progress = [int](20 + (40 * $i / [Math]::Max(1, $benchIds.Count)))
            Write-State $state
            try {
                $opts = @{ seconds = 5 }
                if ($bid -eq 'storage') { $opts.seconds = 8 }
                if ($bid -eq 'gpu') { $opts.seconds = 6 }
                $benches += ,(Invoke-ProbeBenchmark -Id $bid -Options $opts)
            } catch {
                $benches += ,@{ id = $bid; error = $_.Exception.Message; status = 'failed' }
            }
        }
        $state.benches = $benches
        $state.progress = 65
        $state.step = 'stress'
        Write-State $state

        if (Cancelled) {
            $state.status = 'cancelled'; $state.step = 'cancelled'; $state.cancel_requested = $true
            Write-State $state; return
        }

        $samples = New-Object System.Collections.Generic.List[object]
        try {
            $stressResult = Invoke-ProbeStress -Id $StressId -Options @{ seconds = $StressSec }
            $state.stress = $stressResult
            if ($stressResult.samples) {
                foreach ($s in @($stressResult.samples)) { $samples.Add($s) }
            } else {
                $samples.Add((Get-ProbeStressThermalSample))
            }
        } catch {
            $state.stress = @{ id = $StressId; status = 'failed'; error = $_.Exception.Message }
            $samples.Add((Get-ProbeStressThermalSample))
        }
        $state.samples = @($samples)
        $sw.Stop()
        $state.duration_s = [math]::Round($sw.Elapsed.TotalSeconds, 1)
        $state.progress = 100
        $state.step = 'done'
        $state.status = if ($state.error) { 'failed' } else { 'completed' }
        Write-State $state
    } -ArgumentList $ScriptDir, $jobId, $Profile, $benchList, $stressId, $stressSec, (Get-ProbeSuiteStatePath), (Get-ProbeSuiteCancelPath) | Out-Null

    return @{ ok = $true; job = (Read-ProbeSuiteState) }
}

function Stop-ProbeSuiteJob {
    $flag = Get-ProbeSuiteCancelPath
    '1' | Set-Content -Path $flag -Encoding ASCII
    Get-Job -Name 'pclab-suite-*' -ErrorAction SilentlyContinue | Stop-Job -PassThru | Remove-Job -Force -ErrorAction SilentlyContinue
    $state = Read-ProbeSuiteState
    if ($state -is [pscustomobject]) {
        $h = @{}
        $state.PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value }
        $state = $h
    }
    if ($state.status -eq 'running') {
        $state.status = 'cancelled'
        $state.step = 'cancelled'
        $state.cancel_requested = $true
        Write-ProbeSuiteState $state
    }
    return @{ ok = $true; job = (Read-ProbeSuiteState) }
}

function Get-ProbeSuiteStatus {
    return @{ ok = $true; job = (Read-ProbeSuiteState) }
}
