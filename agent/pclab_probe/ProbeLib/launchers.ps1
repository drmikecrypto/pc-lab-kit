# Detect / launch optional third-party stress tools the user already installed.

function Get-ProbeExternalLaunchers {
    $candidates = @(
        @{
            id = 'prime95'
            label = 'Prime95'
            paths = @(
                "${env:ProgramFiles}\Prime95\prime95.exe",
                "${env:ProgramFiles(x86)}\Prime95\prime95.exe",
                "$env:USERPROFILE\Desktop\prime95.exe",
                "$env:USERPROFILE\Downloads\prime95\prime95.exe"
            )
        }
        @{
            id = 'occt'
            label = 'OCCT'
            paths = @(
                "${env:ProgramFiles}\OCCT\OCCT.exe",
                "${env:LocalAppData}\Programs\OCCT\OCCT.exe",
                "$env:USERPROFILE\Desktop\OCCT.exe"
            )
        }
        @{
            id = 'testmem5'
            label = 'TestMem5'
            paths = @(
                "${env:ProgramFiles}\TestMem5\TM5.exe",
                "$env:USERPROFILE\Desktop\TM5.exe",
                "$env:USERPROFILE\Downloads\TestMem5\TM5.exe"
            )
        }
    )

    $found = @()
    foreach ($c in $candidates) {
        $hit = $null
        foreach ($p in $c.paths) {
            if ($p -and (Test-Path -LiteralPath $p)) { $hit = $p; break }
        }
        $found += @{
            id = $c.id
            label = $c.label
            installed = [bool]$hit
            path = $hit
            note = if ($hit) { 'Detected locally — launch overlays Probe telemetry' } else { 'Not found — install separately to enable launcher' }
        }
    }
    return @{ ok = $true; launchers = $found; engine = 'pclab-probe' }
}

function Invoke-ProbeExternalLauncher {
    param($Request)

    $id = if ($Request.id) { [string]$Request.id } else { '' }
    $seconds = 120
    if ($Request.seconds) { $seconds = [Math]::Max(30, [Math]::Min(600, [int]$Request.seconds)) }

    $catalog = Get-ProbeExternalLaunchers
    $tool = $null
    foreach ($l in @($catalog.launchers)) {
        if ($l.id -eq $id) { $tool = $l; break }
    }
    if (-not $tool -or -not $tool.installed -or -not $tool.path) {
        return @{
            ok = $false
            error = 'not_installed'
            message = "Tool '$id' was not found. Install it, then retry."
            launchers = $catalog.launchers
        }
    }

    $samples = New-Object System.Collections.Generic.List[object]
    $proc = $null
    try {
        $proc = Start-Process -FilePath $tool.path -PassThru -WindowStyle Normal -ErrorAction Stop
    } catch {
        return @{ ok = $false; error = 'launch_failed'; message = $_.Exception.Message }
    }

    $end = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $end) {
        if ($proc.HasExited) { break }
        try {
            if (Get-Command Get-ProbeStressThermalSample -ErrorAction SilentlyContinue) {
                $samples.Add((Get-ProbeStressThermalSample))
            }
        } catch {}
        Start-Sleep -Seconds 5
    }

    $exited = $false
    try {
        if (-not $proc.HasExited) {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            $exited = $true
        }
    } catch {}

    $whea = 0
    foreach ($s in $samples) { $whea += [int]($s.whea_errors) }

    return @{
        ok = $true
        id = $id
        label = $tool.label
        path = $tool.path
        duration_s = $seconds
        stopped_by_lab = $exited
        samples = @($samples)
        whea_errors = $whea
        status = if ($whea -gt 0) { 'failed' } else { 'ok' }
        note = 'External tool launched with Probe thermal overlay. PC Lab Kit does not bundle proprietary stress suites.'
    }
}
