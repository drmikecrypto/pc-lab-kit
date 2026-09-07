$files = @(
  'f:\StartUps\pc-lab-kit\agent\pclab_probe\ProbeLib\presentmon.ps1',
  'f:\StartUps\pc-lab-kit\agent\pclab_probe\ProbeLib\fans.ps1',
  'f:\StartUps\pc-lab-kit\agent\pclab_probe\ProbeLib\sensor-log.ps1',
  'f:\StartUps\pc-lab-kit\agent\pclab_probe\ProbeLib\sensor-trust.ps1',
  'f:\StartUps\pc-lab-kit\agent\pclab_probe\PcLabProbeServe.ps1'
)
foreach ($f in $files) {
  $tok = $null
  $errs = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tok, [ref]$errs)
  if ($errs -and $errs.Count -gt 0) {
    Write-Host ("FAIL " + $f)
    $errs | ForEach-Object { Write-Host $_.ToString() }
    exit 1
  }
  Write-Host ("OK " + (Split-Path $f -Leaf))
}
Write-Host 'PARSE_OK'
