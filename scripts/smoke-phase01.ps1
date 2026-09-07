$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\agent\pclab_probe\ProbeLib\presentmon.ps1"
$p = Get-PresentMonCaptureProfiles
if (-not $p.profiles -or $p.profiles.Count -lt 2) { throw 'profiles missing' }
$s = Get-ProbePresentMonSpikes -FrametimeMs @(16.6, 16.7, 40, 55, 90, 16.6)
if (-not $s.stutter_summary) { throw 'stutter_summary missing' }
Write-Host ("presentmon ok spikes=" + $s.spike_count)

. "$PSScriptRoot\..\agent\pclab_probe\ProbeLib\sensor-trust.ps1"
$t = Get-SensorTrustStatus -Elevated $true -ProbeRoot (Resolve-Path "$PSScriptRoot\..\agent\pclab_probe")
if ($t.honesty_matrix.Count -lt 5) { throw 'matrix short' }
Write-Host ("trust ok matrix=" + $t.honesty_matrix.Count)

. "$PSScriptRoot\..\agent\pclab_probe\ProbeLib\fans.ps1"
$d = Get-DefaultProbeFanCurves
$duty = Get-ProbeFanCurveDuty -TempC 60 -Points $d.curves[0].points
if ($duty -lt 40 -or $duty -gt 70) { throw ("unexpected duty " + $duty) }
Write-Host ("fans ok duty=" + $duty)

. "$PSScriptRoot\..\agent\pclab_probe\ProbeLib\sensor-log.ps1"
Add-ProbeSensorLogSample -Sample @{
    ts = (Get-Date).ToUniversalTime().ToString('o')
    cpu_temp = 40
    gpu_temp = 45
}
$l = Get-ProbeSensorLog -Hours 1 -Limit 10
Write-Host ("log ok count=" + $l.count)
Write-Host 'ALL_OK'
