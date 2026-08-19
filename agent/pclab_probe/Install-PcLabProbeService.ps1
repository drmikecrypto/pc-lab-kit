#Requires -RunAsAdministrator
<#
  Install PcLab Probe as a Windows Service (always-on telemetry / Rainmeter feed).
  Uses sc.exe + NSSM-style wrapper via PowerShell service account LocalSystem.
#>
param(
    [string]$ProbeDir = (Split-Path -Parent $MyInvocation.MyCommand.Path) + '\..\agent\pclab_probe'
)

$ProbeDir = (Resolve-Path $ProbeDir).Path
$serve = Join-Path $ProbeDir 'PcLabProbeServe.ps1'
$svcName = 'PcLabKitProbe'
$bin = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$args = "-NoProfile -ExecutionPolicy Bypass -File `"$serve`""

$existing = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Service $svcName already exists. Use: sc.exe delete $svcName"
    exit 1
}

sc.exe create $svcName binPath= "$bin $args" start= auto DisplayName= "PC Lab Kit Probe"
sc.exe description $svcName "Local hardware probe for PC Lab Kit — sensors, benches, RGB"
Write-Host "Created service $svcName. Start with: sc.exe start $svcName"
