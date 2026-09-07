. "$PSScriptRoot\common.ps1"
. "$PSScriptRoot\hwmon.ps1"

<#
  Fan curves v1 — discover RPM/Control sensors, stage curves locally,
  evaluate duty from temps. Live SuperIO write is honesty-gated until PawnIO.
#>

function Get-ProbeFansDataDir {
    $dir = Join-Path $env:LOCALAPPDATA "PcLabKit\Probe"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Get-ProbeFanCurvesPath {
    return (Join-Path (Get-ProbeFansDataDir) "fan-curves.json")
}

function Get-DefaultProbeFanCurves {
    return @{
        engine = 'pclab_fans_v1'
        version = 1
        strategy = 'max_of_sensors'
        hysteresis_c = 3
        response_sec = 4
        sensors = @('cpu_package', 'gpu_core', 'gpu_hotspot')
        curves = @(
            @{
                id = 'case'
                name = 'Case fans'
                sensor = 'max'
                points = @(@{ t = 40; duty = 25 }, @{ t = 55; duty = 40 }, @{ t = 65; duty = 65 }, @{ t = 75; duty = 85 }, @{ t = 85; duty = 100 })
            }
            @{
                id = 'gpu'
                name = 'GPU fan (if controllable)'
                sensor = 'gpu'
                points = @(@{ t = 50; duty = 30 }, @{ t = 70; duty = 55 }, @{ t = 80; duty = 80 }, @{ t = 88; duty = 100 })
            }
        )
        apply = @{
            mode = 'staged_json'
            superio_write = $false
            note = 'Curves are saved locally and evaluated for preview duty. Live SuperIO/PWM apply requires elevated PawnIO/HwMon write path (Phase 2). Import JSON into Fan Control if you need write today.'
        }
        fan_control_import_note = 'Fan Control > Setup > Import (or place points manually from this file)'
    }
}

function Get-ProbeFanInventory {
    $hwmon = Get-ProbeHwMonTelemetry
    $flat = @()
    if ($hwmon.available -and $hwmon.sensors_flat) {
        $flat = @($hwmon.sensors_flat)
    }
    $fans = @()
    $controls = @()
    $temps = @()
    foreach ($s in $flat) {
        $row = @{
            hardware = [string]$s.hardware
            hardware_type = [string]$s.hardware_type
            name = [string]$s.name
            type = [string]$s.type
            value = if ($null -ne $s.value) { [math]::Round([double]$s.value, 1) } else { $null }
            unit = [string]$s.unit
        }
        if ($s.type -eq 'Fan') { $fans += $row }
        elseif ($s.type -eq 'Control') { $controls += $row }
        elseif ($s.type -eq 'Temperature') { $temps += $row }
    }
    $elevated = $false
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $elevated = ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {}
    return @{
        ok = $true
        available = [bool]$hwmon.available
        elevated = $elevated
        fan_count = $fans.Count
        control_count = $controls.Count
        fans = $fans
        controls = $controls
        temps_sample = @($temps | Select-Object -First 24)
        apply_capability = @{
            read_rpm = ($fans.Count -gt 0)
            read_duty = ($controls.Count -gt 0)
            write_pwm = $false
            backend = if ($hwmon.available) { 'pclab_hwmon_lhm' } else { 'none' }
            honesty = 'v1 reads LHM Fan/Control sensors and stages curves. Does not write SuperIO PWM yet.'
        }
        note = if (-not $hwmon.available) {
            'PcLabHwMon unavailable - fan inventory empty until elevated helper is present.'
        } elseif ($fans.Count -eq 0) {
            'No Fan sensors reported. Close competing Ring0 tools or check motherboard SuperIO support.'
        } else { $null }
    }
}

function Get-ProbeFanCurves {
    $path = Get-ProbeFanCurvesPath
    if (Test-Path $path) {
        try {
            $j = Get-Content $path -Raw | ConvertFrom-Json
            return @{
                ok = $true
                path = $path
                staged = $true
                curves = $j
            }
        } catch {
            return @{ ok = $false; error = $_.Exception.Message; path = $path }
        }
    }
    $def = Get-DefaultProbeFanCurves
    return @{
        ok = $true
        path = $path
        staged = $false
        curves = $def
        note = 'Defaults - save to stage locally'
    }
}

function Save-ProbeFanCurves {
    param($Body)
    $path = Get-ProbeFanCurvesPath
    $payload = Get-DefaultProbeFanCurves
    if ($Body) {
        if ($Body.strategy) { $payload.strategy = [string]$Body.strategy }
        if ($null -ne $Body.hysteresis_c) { $payload.hysteresis_c = [double]$Body.hysteresis_c }
        if ($null -ne $Body.response_sec) { $payload.response_sec = [double]$Body.response_sec }
        if ($Body.sensors) { $payload.sensors = @($Body.sensors) }
        if ($Body.curves) {
            $norm = @()
            foreach ($c in @($Body.curves)) {
                $pts = @()
                foreach ($p in @($c.points)) {
                    if ($p -is [System.Array] -or $p -is [object[]]) {
                        $pts += @{ t = [double]$p[0]; duty = [double]$p[1] }
                    } elseif ($p.t -ne $null) {
                        $pts += @{ t = [double]$p.t; duty = [double]$p.duty }
                    } elseif ($p.PSObject.Properties['0']) {
                        $pts += @{ t = [double]$p.'0'; duty = [double]$p.'1' }
                    }
                }
                $norm += @{
                    id = if ($c.id) { [string]$c.id } else { 'curve' }
                    name = if ($c.name) { [string]$c.name } elseif ($c.name_fa) { [string]$c.name_fa } else { 'Fan curve' }
                    sensor = if ($c.sensor) { [string]$c.sensor } else { 'max' }
                    points = $pts
                }
            }
            if ($norm.Count -gt 0) { $payload.curves = $norm }
        }
    }
    $payload.updated_at = (Get-Date).ToUniversalTime().ToString('o')
    ($payload | ConvertTo-Json -Depth 10) | Set-Content -Path $path -Encoding UTF8
    return @{
        ok = $true
        path = $path
        staged = $true
        apply = $payload.apply
        curves = $payload
        note = $payload.apply.note
    }
}

function Get-ProbeFanCurveDuty {
    param(
        [double]$TempC,
        $Points
    )
    $pts = @($Points)
    if ($pts.Count -eq 0) { return 40 }
    $ordered = @($pts | Sort-Object { [double]$_.t })
    if ($TempC -le [double]$ordered[0].t) { return [math]::Round([double]$ordered[0].duty, 0) }
    $last = $ordered[$ordered.Count - 1]
    if ($TempC -ge [double]$last.t) { return [math]::Round([double]$last.duty, 0) }
    for ($i = 0; $i -lt ($ordered.Count - 1); $i++) {
        $a = $ordered[$i]
        $b = $ordered[$i + 1]
        $t0 = [double]$a.t; $t1 = [double]$b.t
        if ($TempC -ge $t0 -and $TempC -le $t1) {
            $span = [Math]::Max(0.001, $t1 - $t0)
            $f = ($TempC - $t0) / $span
            $duty = [double]$a.duty + $f * ([double]$b.duty - [double]$a.duty)
            return [math]::Round($duty, 0)
        }
    }
    return [math]::Round([double]$last.duty, 0)
}

function Invoke-ProbeFanCurveEvaluate {
    . "$PSScriptRoot\system.ps1"
    $inv = Get-ProbeFanInventory
    $cur = Get-ProbeFanCurves
    $snap = $null
    try { $snap = Get-TelemetrySnapshot } catch {}
    $cpu = if ($snap -and $null -ne $snap.cpu_temp) { [double]$snap.cpu_temp } else { $null }
    $gpu = if ($snap -and $null -ne $snap.gpu_temp) { [double]$snap.gpu_temp } else { $null }
    $hot = if ($snap -and $null -ne $snap.gpu_hotspot) { [double]$snap.gpu_hotspot } else { $null }
    $ref = @($cpu, $gpu, $hot) | Where-Object { $null -ne $_ }
    $maxT = if ($ref.Count -gt 0) { ($ref | Measure-Object -Maximum).Maximum } else { 45.0 }
    $evaluated = @()
    foreach ($c in @($cur.curves.curves)) {
        $t = $maxT
        if ($c.sensor -eq 'gpu' -and $null -ne $gpu) { $t = $gpu }
        elseif ($c.sensor -eq 'cpu' -and $null -ne $cpu) { $t = $cpu }
        $duty = Get-ProbeFanCurveDuty -TempC $t -Points $c.points
        $evaluated += @{
            id = $c.id
            name = $c.name
            sensor_c = [math]::Round($t, 1)
            target_duty_pct = $duty
        }
    }
    return @{
        ok = $true
        inventory = @{
            fan_count = $inv.fan_count
            control_count = $inv.control_count
            fans = $inv.fans
            apply_capability = $inv.apply_capability
        }
        temps = @{ cpu_c = $cpu; gpu_c = $gpu; gpu_hotspot_c = $hot; ref_c = [math]::Round($maxT, 1) }
        evaluated = $evaluated
        apply = @{
            mode = 'preview_only'
            written = $false
            note = 'Preview duty only - SuperIO PWM write not enabled in fans v1'
        }
        curves_path = $cur.path
        staged = $cur.staged
    }
}

function Set-ProbeFanCurvesApply {
    param($Body, [switch]$Confirm)
    $saved = Save-ProbeFanCurves -Body $Body
    $eval = Invoke-ProbeFanCurveEvaluate
    $confirm = $Confirm -or ($Body -and ($Body.confirm -eq $true -or $Body.confirm -eq 'true'))
    return @{
        ok = $true
        saved = $saved
        evaluate = $eval
        applied = $false
        confirm_required = -not $confirm
        honesty = if ($confirm) {
            'Confirmed staging only - no SuperIO write. Target duties computed for shop preview / Fan Control handoff.'
        } else {
            'Pass confirm=true to acknowledge staging. Live PWM write remains Phase 2 (PawnIO / elevated Control write).'
        }
    }
}
