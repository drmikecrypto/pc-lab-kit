# Full Lab suite runner - long jobs with cancel, checkpoints, and resume.
# Dot-sourced from PcLabProbeServe.ps1
. "$PSScriptRoot\adaptive-plan.ps1"

function Get-ProbeSuiteDir {
    $dir = Join-Path $env:LOCALAPPDATA 'PcLabKit\Probe\suite'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Get-ProbeSuiteStatePath {
    return (Join-Path (Get-ProbeSuiteDir) 'current.json')
}

function Get-ProbeSuiteCancelPath {
    return (Join-Path (Get-ProbeSuiteDir) 'cancel.flag')
}

function Get-ProbeSuiteCheckpointPath {
    param([string]$JobId)
    return (Join-Path (Get-ProbeSuiteDir) ("checkpoint-$JobId.json"))
}

function Write-ProbeSuiteState {
    param([hashtable]$State)
    $path = Get-ProbeSuiteStatePath
    $State.updated_at = (Get-Date).ToUniversalTime().ToString('o')
    if (-not $State.resume_token -and $State.id) {
        $State.resume_token = [string]$State.id
    }
    ($State | ConvertTo-Json -Depth 14 -Compress) | Set-Content -Path $path -Encoding UTF8
    if ($State.id) {
        $cp = Get-ProbeSuiteCheckpointPath -JobId ([string]$State.id)
        ($State | ConvertTo-Json -Depth 14 -Compress) | Set-Content -Path $cp -Encoding UTF8
    }
}

function Read-ProbeSuiteState {
    $path = Get-ProbeSuiteStatePath
    if (-not (Test-Path $path)) {
        return @{ status = 'idle'; progress = 0; step = 'idle'; completed_steps = @(); resumable = $false }
    }
    try {
        $obj = Get-Content $path -Raw | ConvertFrom-Json
        return ConvertTo-ProbeSuiteHashtable $obj
    } catch {
        return @{ status = 'idle'; progress = 0; step = 'idle'; error = 'corrupt_state'; completed_steps = @(); resumable = $false }
    }
}

function ConvertTo-ProbeSuiteHashtable {
    param($Obj)
    if ($null -eq $Obj) { return @{} }
    if ($Obj -is [hashtable]) { return $Obj }
    $h = @{}
    if ($Obj -is [System.Collections.IDictionary]) {
        foreach ($k in $Obj.Keys) { $h[[string]$k] = $Obj[$k] }
        return $h
    }
    $Obj.PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value }
    return $h
}

function Test-ProbeSuiteCancelled {
    return (Test-Path (Get-ProbeSuiteCancelPath))
}

function Get-ProbeSuiteProfiles {
    return @{
        adaptive = @{
            id = 'adaptive'
            label = 'Adaptive Lab'
            benches = @()
            stress_id = 'combined'
            stress_seconds = 180
            adaptive = $true
        }
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
            stress_id = 'oracle'
            stress_seconds = 300
        }
        soak_15 = @{
            id = 'soak_15'
            label = 'Soak 15 min'
            benches = @('cpu', 'memory', 'storage', 'gpu')
            stress_id = 'combined'
            stress_seconds = 900
        }
        soak_30 = @{
            id = 'soak_30'
            label = 'Soak 30 min'
            benches = @('cpu', 'memory', 'storage', 'gpu')
            stress_id = 'combined'
            stress_seconds = 1800
        }
        soak_60 = @{
            id = 'soak_60'
            label = 'Soak 60 min'
            benches = @('cpu', 'memory', 'storage', 'gpu')
            stress_id = 'oracle'
            stress_seconds = 3600
        }
    }
}

function Test-ProbeSuiteResumable {
    param($State)
    $s = ConvertTo-ProbeSuiteHashtable $State
    $st = [string]$s.status
    if ($st -eq 'running') { return $true }
    if ($st -in @('interrupted', 'failed') -and $s.benches) { return $true }
    if ($st -eq 'completed' -and -not $s.finalized) { return $true }
    return $false
}

function Start-ProbeSuiteJob {
    param(
        [string]$Profile = 'adaptive',
        [string]$ScriptDir,
        [switch]$Resume,
        [string]$ResumeToken = ''
    )

    if ($Resume -or $ResumeToken) {
        return Resume-ProbeSuiteJob -ScriptDir $ScriptDir -ResumeToken $ResumeToken
    }

    $profiles = Get-ProbeSuiteProfiles
    if (-not $profiles.ContainsKey($Profile)) { $Profile = 'adaptive' }
    $p = $profiles[$Profile]

    $plan = $null
    if ($Profile -eq 'adaptive' -or $p.adaptive) {
        try {
            . (Join-Path $ScriptDir 'ProbeLib\devices.ps1')
            . (Join-Path $ScriptDir 'ProbeLib\adaptive-plan.ps1')
            $inv = Get-ProbeDeviceInventory
            $plan = Get-ProbeAdaptiveLabPlan -Fingerprint $inv.fingerprint -Devices $inv -Platform $inv.platform
            $p = @{
                id = 'adaptive'
                label = $plan.label
                benches = @($plan.benches)
                stress_id = if ($plan.stress_id) { $plan.stress_id } else { 'combined' }
                stress_seconds = if ($plan.stress_seconds) { [int]$plan.stress_seconds } else { 0 }
                adaptive = $true
            }
        } catch {
            $plan = @{ error = $_.Exception.Message; id = 'adaptive' }
            $p = $profiles['standard']
            $Profile = 'standard'
        }
    }

    $cur = Read-ProbeSuiteState
    if ($cur.status -eq 'running') {
        return @{ ok = $false; error = 'already_running'; job = $cur; resumable = $true }
    }

    Remove-Item (Get-ProbeSuiteCancelPath) -Force -ErrorAction SilentlyContinue
    $jobId = [guid]::NewGuid().ToString('n').Substring(0, 16)
    $state = @{
        ok = $true
        id = $jobId
        resume_token = $jobId
        profile = $Profile
        label = $p.label
        status = 'running'
        progress = 1
        step = 'starting'
        cancel_requested = $false
        benches = @()
        completed_steps = @()
        stress = $null
        samples = @()
        probe = $null
        plan = $plan
        duration_s = $null
        error = $null
        resumable = $true
        started_at = (Get-Date).ToUniversalTime().ToString('o')
    }
    Write-ProbeSuiteState $state

    $benchList = ($p.benches -join ',')
    $stressId = $p.stress_id
    $stressSec = [int]$p.stress_seconds
    $planJson = if ($plan) { ($plan | ConvertTo-Json -Depth 10 -Compress) } else { '' }
    $skipCsv = ''

    Invoke-ProbeSuiteWorker -ScriptDir $ScriptDir -JobId $jobId -Profile $Profile `
        -BenchCsv $benchList -StressId $stressId -StressSec $stressSec `
        -PlanJson $planJson -SkipBenchCsv $skipCsv -ExistingBenchesJson '' `
        -ExistingProbeJson '' -ExistingSamplesJson ''

    return @{ ok = $true; job = (Read-ProbeSuiteState); plan = $plan }
}

function Resume-ProbeSuiteJob {
    param(
        [string]$ScriptDir,
        [string]$ResumeToken = ''
    )
    $cur = Read-ProbeSuiteState
    if ($ResumeToken -and $cur.id -and $cur.id -ne $ResumeToken) {
        $cp = Get-ProbeSuiteCheckpointPath -JobId $ResumeToken
        if (Test-Path $cp) {
            try { $cur = ConvertTo-ProbeSuiteHashtable (Get-Content $cp -Raw | ConvertFrom-Json) } catch {}
        }
    }
    if (-not (Test-ProbeSuiteResumable $cur)) {
        return @{ ok = $false; error = 'nothing_to_resume'; job = $cur }
    }
    if ($cur.status -eq 'running') {
        $jobs = Get-Job -Name "pclab-suite-$($cur.id)" -ErrorAction SilentlyContinue
        if ($jobs) {
            return @{ ok = $true; job = $cur; resumed = $false; already_running = $true }
        }
        $cur.status = 'interrupted'
        $cur.step = 'interrupted'
        Write-ProbeSuiteState $cur
    }

    Remove-Item (Get-ProbeSuiteCancelPath) -Force -ErrorAction SilentlyContinue
    $jobId = [string]$cur.id
    if (-not $jobId) { $jobId = [guid]::NewGuid().ToString('n').Substring(0, 16) }

    $doneBenches = @()
    if ($cur.benches) {
        foreach ($b in @($cur.benches)) {
            if ($b -is [string]) { $doneBenches += $b }
            elseif ($b.id) { $doneBenches += [string]$b.id }
        }
    }
    $completed = @()
    if ($cur.completed_steps) { $completed = @($cur.completed_steps) }

    $profiles = Get-ProbeSuiteProfiles
    $Profile = if ($cur.profile) { [string]$cur.profile } else { 'standard' }
    $p = if ($profiles.ContainsKey($Profile)) { $profiles[$Profile] } else { $profiles['standard'] }
    $plan = $cur.plan
    $benchIds = @($p.benches)
    if ($plan -and $plan.benches) { $benchIds = @($plan.benches) }
    $remaining = @($benchIds | Where-Object { $doneBenches -notcontains $_ -and ("bench:$_") -notin $completed })
    $stressDone = ($completed -contains 'stress') -or ($null -ne $cur.stress -and $cur.stress.status -and $cur.stress.status -ne 'running')
    $stressId = if ($stressDone) { '' } else {
        if ($plan -and $plan.stress_id) { [string]$plan.stress_id }
        elseif ($p.stress_id) { [string]$p.stress_id }
        else { 'combined' }
    }
    $stressSec = if ($plan -and $plan.stress_seconds) { [int]$plan.stress_seconds }
        elseif ($p.stress_seconds) { [int]$p.stress_seconds }
        else { 180 }

    $cur.status = 'running'
    $cur.step = 'resuming'
    $cur.resumable = $true
    $cur.resume_token = $jobId
    $cur.error = $null
    Write-ProbeSuiteState $cur

    $benchesJson = if ($cur.benches) { ($cur.benches | ConvertTo-Json -Depth 10 -Compress) } else { '[]' }
    $probeJson = if ($cur.probe) { ($cur.probe | ConvertTo-Json -Depth 10 -Compress) } else { '' }
    $samplesJson = if ($cur.samples) { ($cur.samples | ConvertTo-Json -Depth 8 -Compress) } else { '[]' }
    $planJson = if ($plan) { ($plan | ConvertTo-Json -Depth 10 -Compress) } else { '' }

    Invoke-ProbeSuiteWorker -ScriptDir $ScriptDir -JobId $jobId -Profile $Profile `
        -BenchCsv ($remaining -join ',') -StressId $stressId -StressSec $stressSec `
        -PlanJson $planJson -SkipBenchCsv ($doneBenches -join ',') `
        -ExistingBenchesJson $benchesJson -ExistingProbeJson $probeJson -ExistingSamplesJson $samplesJson

    return @{ ok = $true; job = (Read-ProbeSuiteState); resumed = $true }
}

function Invoke-ProbeSuiteWorker {
    param(
        [string]$ScriptDir,
        [string]$JobId,
        [string]$Profile,
        [string]$BenchCsv,
        [string]$StressId,
        [int]$StressSec,
        [string]$PlanJson,
        [string]$SkipBenchCsv,
        [string]$ExistingBenchesJson,
        [string]$ExistingProbeJson,
        [string]$ExistingSamplesJson
    )

    $statePath = Get-ProbeSuiteStatePath
    $cancelPath = Get-ProbeSuiteCancelPath
    $cpPath = Get-ProbeSuiteCheckpointPath -JobId $JobId

    Start-Job -Name "pclab-suite-$JobId" -ScriptBlock {
        param($ScriptDir, $JobId, $Profile, $BenchCsv, $StressId, $StressSec, $StatePath, $CancelPath, $CpPath,
              $PlanJson, $SkipBenchCsv, $ExistingBenchesJson, $ExistingProbeJson, $ExistingSamplesJson)

        function Write-State($obj) {
            $obj.updated_at = (Get-Date).ToUniversalTime().ToString('o')
            $obj.resume_token = $JobId
            $obj.resumable = ($obj.status -eq 'running' -or $obj.status -eq 'interrupted' -or ($obj.status -eq 'completed' -and -not $obj.finalized))
            $json = ($obj | ConvertTo-Json -Depth 14 -Compress)
            $json | Set-Content -Path $StatePath -Encoding UTF8
            $json | Set-Content -Path $CpPath -Encoding UTF8
        }
        function Cancelled { return (Test-Path $CancelPath) }

        $planObj = $null
        if ($PlanJson) { try { $planObj = $PlanJson | ConvertFrom-Json } catch {} }

        $benches = @()
        if ($ExistingBenchesJson) {
            try {
                $eb = $ExistingBenchesJson | ConvertFrom-Json
                if ($eb) { $benches = @($eb) }
            } catch {}
        }
        $completed = New-Object System.Collections.Generic.List[string]
        foreach ($b in $benches) {
            $bid = if ($b.id) { [string]$b.id } else { $null }
            if ($bid) { [void]$completed.Add("bench:$bid") }
        }

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $state = @{
            ok = $true
            id = $JobId
            resume_token = $JobId
            profile = $Profile
            status = 'running'
            progress = 5
            step = 'probe'
            cancel_requested = $false
            benches = $benches
            completed_steps = @($completed)
            stress = $null
            samples = @()
            probe = $null
            plan = $planObj
            duration_s = $null
            error = $null
            resumable = $true
            started_at = (Get-Date).ToUniversalTime().ToString('o')
        }
        if ($ExistingProbeJson) {
            try { $state.probe = ($ExistingProbeJson | ConvertFrom-Json) } catch {}
            if ($state.probe) {
                $state.progress = 20
                $state.step = 'benches'
                if (-not ($completed -contains 'probe')) { [void]$completed.Add('probe') }
                $state.completed_steps = @($completed)
            }
        }
        if ($ExistingSamplesJson) {
            try {
                $es = $ExistingSamplesJson | ConvertFrom-Json
                if ($es) { $state.samples = @($es) }
            } catch {}
        }
        Write-State $state

        if ($planObj -and $planObj.gated) {
            if (-not $state.probe) {
                try {
                    $probeOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'PcLabProbe.ps1') 2>$null
                    if ($probeOut) {
                        try { $state.probe = ($probeOut | ConvertFrom-Json) } catch { $state.probe = @{ raw = $true } }
                    }
                } catch {
                    $state.error = "probe_failed: $($_.Exception.Message)"
                }
            }
            $sw.Stop()
            $state.duration_s = [math]::Round($sw.Elapsed.TotalSeconds, 1)
            $state.progress = 100
            $state.step = 'gated'
            $state.status = 'completed'
            $state.gate_reason = $planObj.gate_reason
            $state.completed_steps = @('probe', 'gated')
            Write-State $state
            return
        }

        if (-not $state.probe) {
            try {
                $probeOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ScriptDir 'PcLabProbe.ps1') 2>$null
                if ($probeOut) {
                    try { $state.probe = ($probeOut | ConvertFrom-Json) } catch { $state.probe = @{ raw = $true } }
                }
                $state.progress = 20
                $state.step = 'benches'
                [void]$completed.Add('probe')
                $state.completed_steps = @($completed)
                Write-State $state
            } catch {
                $state.error = "probe_failed: $($_.Exception.Message)"
                $state.status = 'interrupted'
                $state.step = 'interrupted'
                Write-State $state
                return
            }
        }

        if (Cancelled) {
            $state.status = 'cancelled'; $state.step = 'cancelled'; $state.cancel_requested = $true
            $state.completed_steps = @($completed)
            Write-State $state; return
        }

        . (Join-Path $ScriptDir 'ProbeLib\benchmark.ps1')
        . (Join-Path $ScriptDir 'ProbeLib\stress.ps1')

        $benchIds = @($BenchCsv -split ',' | Where-Object { $_ })
        $skip = @($SkipBenchCsv -split ',' | Where-Object { $_ })
        $i = 0
        $total = [Math]::Max(1, $benchIds.Count + $skip.Count)
        foreach ($bid in $benchIds) {
            if (Cancelled) {
                $state.status = 'cancelled'; $state.step = 'cancelled'; $state.cancel_requested = $true
                $state.benches = $benches
                $state.completed_steps = @($completed)
                Write-State $state; return
            }
            $i++
            $state.step = "bench:$bid"
            $state.progress = [int](20 + (40 * ($skip.Count + $i) / $total))
            Write-State $state
            try {
                $opts = @{ seconds = 5 }
                if ($bid -eq 'storage') { $opts.seconds = 8 }
                if ($bid -eq 'gpu') { $opts.seconds = 6 }
                $row = Invoke-ProbeBenchmark -Id $bid -Options $opts
                $benches += ,$row
            } catch {
                $benches += ,@{ id = $bid; error = $_.Exception.Message; status = 'failed' }
            }
            [void]$completed.Add("bench:$bid")
            $state.benches = $benches
            $state.completed_steps = @($completed)
            Write-State $state
        }
        $state.benches = $benches
        $state.progress = 65
        $state.step = 'stress'
        $state.completed_steps = @($completed)
        Write-State $state

        if (Cancelled) {
            $state.status = 'cancelled'; $state.step = 'cancelled'; $state.cancel_requested = $true
            Write-State $state; return
        }

        $samples = New-Object System.Collections.Generic.List[object]
        if ($state.samples) { foreach ($s in @($state.samples)) { $samples.Add($s) } }

        if ($StressId -and $StressSec -gt 0) {
            try {
                $stressResult = Invoke-ProbeStress -Id $StressId -Options @{ seconds = $StressSec }
                $state.stress = $stressResult
                if ($StressId -eq 'oracle') {
                    $state.stress_mode = 'stability_oracle'
                }
                if ($stressResult.samples) {
                    foreach ($s in @($stressResult.samples)) { $samples.Add($s) }
                } else {
                    $samples.Add((Get-ProbeStressThermalSample))
                }
            } catch {
                $state.stress = @{ id = $StressId; status = 'failed'; error = $_.Exception.Message }
                $samples.Add((Get-ProbeStressThermalSample))
            }
            [void]$completed.Add('stress')
        } else {
            if (-not ($completed -contains 'stress')) {
                $state.stress = @{ id = $null; status = 'skipped'; reason = 'no_stress_in_plan_or_already_done' }
            }
        }
        $state.samples = @($samples)
        $state.completed_steps = @($completed)
        $sw.Stop()
        $state.duration_s = [math]::Round($sw.Elapsed.TotalSeconds, 1)
        $state.progress = 100
        $state.step = 'done'
        $state.status = if ($state.error) { 'failed' } else { 'completed' }
        Write-State $state
    } -ArgumentList $ScriptDir, $JobId, $Profile, $BenchCsv, $StressId, $StressSec, $statePath, $cancelPath, $cpPath,
        $PlanJson, $SkipBenchCsv, $ExistingBenchesJson, $ExistingProbeJson, $ExistingSamplesJson | Out-Null
}

function Stop-ProbeSuiteJob {
    $flag = Get-ProbeSuiteCancelPath
    '1' | Set-Content -Path $flag -Encoding ASCII
    Get-Job -Name 'pclab-suite-*' -ErrorAction SilentlyContinue | Stop-Job -PassThru | Remove-Job -Force -ErrorAction SilentlyContinue
    $state = Read-ProbeSuiteState
    if ($state.status -eq 'running') {
        $state.status = 'cancelled'
        $state.step = 'cancelled'
        $state.cancel_requested = $true
        # Preserve benches/samples for possible finalize of partial work
        if ($state.benches -or $state.probe) {
            $state.resumable = $true
            $state.status = 'interrupted'
            $state.step = 'interrupted'
        }
        Write-ProbeSuiteState $state
    }
    return @{ ok = $true; job = (Read-ProbeSuiteState) }
}

function Get-ProbeSuiteStatus {
    $job = Read-ProbeSuiteState
    $job.resumable = [bool](Test-ProbeSuiteResumable $job)
    if (-not $job.resume_token -and $job.id) { $job.resume_token = [string]$job.id }
    if (-not $job.completed_steps) { $job.completed_steps = @() }
    return @{ ok = $true; job = $job }
}

function Clear-ProbeSuiteCheckpoint {
    param([string]$JobId = '')
    $cur = Read-ProbeSuiteState
    $id = if ($JobId) { $JobId } else { [string]$cur.id }
    if ($id) {
        Remove-Item (Get-ProbeSuiteCheckpointPath -JobId $id) -Force -ErrorAction SilentlyContinue
    }
    Remove-Item (Get-ProbeSuiteCancelPath) -Force -ErrorAction SilentlyContinue
    $idle = @{ status = 'idle'; progress = 0; step = 'idle'; completed_steps = @(); resumable = $false }
    $path = Get-ProbeSuiteStatePath
    ($idle | ConvertTo-Json -Depth 4 -Compress) | Set-Content -Path $path -Encoding UTF8
    return @{ ok = $true; job = $idle }
}
