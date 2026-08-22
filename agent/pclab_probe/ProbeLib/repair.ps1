. "$PSScriptRoot\common.ps1"

<#
  OS maintenance wrappers — Windows SFC / DISM / pnputil.
  Clearly labeled maintenance, not a PC Lab Kit "magic fix".
#>

function Get-ProbeRepairCatalog {
    $elevated = $false
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $elevated = ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {}

    return @{
        ok = $true
        elevated = $elevated
        label = 'OS maintenance (not a magic fix)'
        note = 'These invoke Windows system tools. They repair OS files / drivers — not hardware faults.'
        tools = @(
            @{
                id = 'sfc'
                label = 'SFC /scannow'
                description = 'System File Checker — scan and repair protected Windows files'
                requires_elevated = $true
                estimated_minutes = 15
            }
            @{
                id = 'dism'
                label = 'DISM RestoreHealth'
                description = 'DISM /Online /Cleanup-Image /RestoreHealth — repair component store'
                requires_elevated = $true
                estimated_minutes = 30
            }
            @{
                id = 'pnputil_scan'
                label = 'pnputil /scan-devices'
                description = 'Rescan PnP devices (driver hardware detection)'
                requires_elevated = $true
                estimated_minutes = 1
            }
        )
    }
}

function Invoke-ProbeRepairTool {
    param(
        [Parameter(Mandatory)][string]$Id,
        [switch]$Confirm
    )
    if (-not $Confirm) {
        return @{
            ok = $false
            error = 'confirm_required'
            note = 'Pass confirm=true. These are Windows OS maintenance tools, not PC Lab Kit diagnostics.'
        }
    }

    $elevated = $false
    try {
        $wid = [Security.Principal.WindowsIdentity]::GetCurrent()
        $elevated = ([Security.Principal.WindowsPrincipal]$wid).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {}
    if (-not $elevated) {
        return @{
            ok = $false
            error = 'elevation_required'
            note = 'Restart Probe as Administrator to run SFC / DISM / pnputil.'
        }
    }

    $idLower = $Id.ToLower()
    $cmd = $null
    $args = @()
    switch ($idLower) {
        'sfc' {
            $cmd = Join-Path $env:SystemRoot 'System32\sfc.exe'
            $args = @('/scannow')
        }
        'dism' {
            $cmd = Join-Path $env:SystemRoot 'System32\DISM.exe'
            $args = @('/Online', '/Cleanup-Image', '/RestoreHealth')
        }
        'pnputil_scan' {
            $cmd = Join-Path $env:SystemRoot 'System32\pnputil.exe'
            $args = @('/scan-devices')
        }
        default {
            return @{ ok = $false; error = 'unknown_tool'; note = "Unknown repair id: $Id" }
        }
    }

    if (-not (Test-Path $cmd)) {
        return @{ ok = $false; error = 'tool_missing'; path = $cmd }
    }

    $started = Get-Date
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $cmd
        $psi.Arguments = ($args -join ' ')
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        $stdout = $p.StandardOutput.ReadToEnd()
        $stderr = $p.StandardError.ReadToEnd()
        $p.WaitForExit()
        $tail = (($stdout + "`n" + $stderr) -replace '\s+$', '')
        if ($tail.Length -gt 4000) { $tail = $tail.Substring($tail.Length - 4000) }
        return @{
            ok = ($p.ExitCode -eq 0)
            id = $idLower
            exit_code = $p.ExitCode
            duration_s = [Math]::Round(((Get-Date) - $started).TotalSeconds, 1)
            output_tail = $tail
            note = 'OS maintenance finished. Review Windows logs if exit_code != 0. This is not a hardware certificate.'
        }
    } catch {
        return @{
            ok = $false
            id = $idLower
            error = $_.Exception.Message
            note = 'Failed to start Windows maintenance tool.'
        }
    }
}
