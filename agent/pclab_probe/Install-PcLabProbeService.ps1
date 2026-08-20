#Requires -RunAsAdministrator
<#
  Install PcLab Probe as a Windows Service (always-on telemetry / Rainmeter feed).
  Uses WinSW-style recovery via sc.exe failure actions. Sets PCLAB_PROBE_SERVICE=1.
#>
param(
    [string]$ProbeDir = '',
    [switch]$Uninstall,
    [switch]$Repair
)

$ErrorActionPreference = 'Stop'
$svcName = 'PcLabKitProbe'
$logDir = Join-Path $env:LOCALAPPDATA 'PcLabKit\Probe'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir 'service-install.log'

function Write-SvcLog([string]$msg) {
    $line = "$(Get-Date -Format o) $msg"
    Add-Content -Path $logFile -Value $line -Encoding UTF8
    Write-Host $line
}

if (-not $ProbeDir) {
    $ProbeDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$ProbeDir = (Resolve-Path $ProbeDir).Path
$serve = Join-Path $ProbeDir 'PcLabProbeServe.ps1'
if (-not (Test-Path $serve)) {
    Write-SvcLog "ERROR: PcLabProbeServe.ps1 not found at $serve"
    exit 1
}

$bin = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
# Wrapper sets service env + logs stdout/stderr
$wrapper = Join-Path $ProbeDir 'Run-PcLabProbeService.ps1'
@'
#Requires -Version 5.1
$ErrorActionPreference = "Continue"
$env:PCLAB_PROBE_SERVICE = "1"
$logDir = Join-Path $env:LOCALAPPDATA "PcLabKit\Probe"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$outLog = Join-Path $logDir "service-stdout.log"
$errLog = Join-Path $logDir "service-stderr.log"
$serve = Join-Path $PSScriptRoot "PcLabProbeServe.ps1"
try {
    & $serve *>> $outLog 2>> $errLog
} catch {
    $_ | Out-File -FilePath $errLog -Append -Encoding utf8
    throw
}
'@ | Set-Content -Path $wrapper -Encoding UTF8

$binPath = "`"$bin`" -NoProfile -ExecutionPolicy Bypass -File `"$wrapper`""

if ($Uninstall) {
    $existing = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-SvcLog "Stopping $svcName…"
        Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
        sc.exe delete $svcName | Out-Null
        Start-Sleep -Seconds 1
        Write-SvcLog "Deleted service $svcName"
    } else {
        Write-SvcLog "Service $svcName not installed"
    }
    exit 0
}

$existing = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if ($existing -and -not $Repair) {
    Write-SvcLog "Service $svcName already exists. Use -Repair or -Uninstall."
    exit 1
}

if ($existing -and $Repair) {
    Write-SvcLog "Repair: recreating $svcName"
    Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
    sc.exe delete $svcName | Out-Null
    Start-Sleep -Seconds 2
}

Write-SvcLog "Creating service $svcName → $wrapper"
sc.exe create $svcName binPath= $binPath start= auto DisplayName= "PC Lab Kit Probe" obj= LocalSystem | Out-Null
sc.exe description $svcName "Local hardware probe for PC Lab Kit — sensors, benches, stress, RGB" | Out-Null
# Restart on failure: 5s, 15s, 30s — reset fail count after 86400s
sc.exe failure $svcName reset= 86400 actions= restart/5000/restart/15000/restart/30000 | Out-Null
sc.exe failureflag $svcName 1 | Out-Null

Write-SvcLog "Starting $svcName…"
try {
    Start-Service -Name $svcName
    Write-SvcLog "Service started. Health: http://127.0.0.1:18765/health"
} catch {
    Write-SvcLog "WARN: start failed: $($_.Exception.Message) — check $logDir"
    exit 2
}
exit 0
