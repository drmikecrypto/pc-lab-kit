# PC Lab Kit batch CLI — Platform Audit + burn-in queue for shop/OEM bay
param(
    [ValidateSet('adaptive', 'quick', 'standard', 'deep', 'soak_15', 'soak_30', 'soak_60')]
    [string]$Profile = 'adaptive',
    [string]$Output = './reports',
    [string]$ProbeBase = 'http://127.0.0.1:18765',
    [string]$LabBase = 'http://127.0.0.1:8080',
    [switch]$Discover,
    [switch]$AuditOnly,
    [switch]$QueueBurnIn,
    [double]$BurnInHours = 0.05,
    [switch]$RunWorker
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

if ($Discover) {
    Write-Host 'Fleet discovery via lab API:'
    Write-Host "  curl $LabBase/api/diagnostic/fleet/discover"
    try {
        $fleet = Invoke-RestMethod -Uri "$LabBase/api/diagnostic/fleet/discover" -TimeoutSec 10
        $fleet | ConvertTo-Json -Depth 6
    } catch {
        Write-Warning $_.Exception.Message
    }
    exit 0
}

New-Item -ItemType Directory -Force -Path $Output | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outDir = (Resolve-Path $Output).Path

function Get-Json($Url) {
    return Invoke-RestMethod -Uri $Url -Method Get -TimeoutSec 120
}

$audit = $null
$plan = $null
try {
    Write-Host "Fetching Platform Audit from $ProbeBase/audit …"
    $audit = Get-Json "$ProbeBase/audit"
    $plan = $audit.adaptive_plan
} catch {
    Write-Warning "Probe audit unavailable ($($_.Exception.Message)) — writing manifest stub only."
}

$jsonPath = Join-Path $outDir "platform-audit-$stamp.json"
$htmlPath = Join-Path $outDir "platform-audit-$stamp.html"

if ($audit) {
    $audit | ConvertTo-Json -Depth 16 | Set-Content -Path $jsonPath -Encoding UTF8

    $cov = if ($audit.fingerprint) { $audit.fingerprint.coverage_score } else { '—' }
    $fpId = if ($audit.fingerprint) { $audit.fingerprint.id } else { '—' }
    $steps = @()
    if ($plan -and $plan.steps) {
        foreach ($s in @($plan.steps)) {
            $steps += "<li><strong>$([System.Net.WebUtility]::HtmlEncode($s.label))</strong> — $([System.Net.WebUtility]::HtmlEncode($s.reason))</li>"
        }
    }
    $drvCount = 0
    if ($audit.driver_actions -and $audit.driver_actions.count) { $drvCount = $audit.driver_actions.count }
    $html = @"
<!DOCTYPE html><html><head><meta charset="utf-8"><title>Platform Audit</title>
<style>body{font-family:Segoe UI,sans-serif;margin:2rem}code{font-size:.85rem}.bar{height:8px;background:#eee;border-radius:4px;overflow:hidden}.bar>span{display:block;height:100%;background:#0d9488}</style>
</head><body>
<h1>PC Lab Kit — Platform Audit</h1>
<p>Generated $stamp · fingerprint <code>$fpId</code></p>
<div class="bar"><span style="width:${cov}%"></span></div>
<p><strong>$cov%</strong> coverage · profile $Profile · driver actions $drvCount</p>
<h2>Adaptive plan</h2>
<ol>$($steps -join "`n")</ol>
<p class="muted">$([System.Net.WebUtility]::HtmlEncode([string]$audit.note))</p>
</body></html>
"@
    Set-Content -Path $htmlPath -Value $html -Encoding UTF8
    Write-Host "Wrote $jsonPath"
    Write-Host "Wrote $htmlPath"
} else {
    $stub = @{
        profile = $Profile
        output  = $outDir
        queued  = (Get-Date).ToUniversalTime().ToString('o')
        note    = 'Start Probe then re-run with -AuditOnly or full batch'
    }
    $stub | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonPath -Encoding UTF8
    Write-Host "Wrote stub $jsonPath"
}

if ($AuditOnly) { exit 0 }

$jobIds = @()
if ($QueueBurnIn) {
    $seconds = [math]::Max(30, [int]($BurnInHours * 3600))
    $body = @{
        targets = @('127.0.0.1:18765')
        profile = $Profile
        duration_hours = $BurnInHours
        duration_seconds = $seconds
        probe_base = $ProbeBase
    } | ConvertTo-Json -Depth 4
    try {
        $resp = Invoke-RestMethod -Uri "$LabBase/api/diagnostic/fleet/burn-in" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 30
        $jobIds = @($resp.job_ids)
        Write-Host "Queued burn-in jobs: $($jobIds -join ', ')"
    } catch {
        Write-Warning "Burn-in queue via API failed ($($_.Exception.Message)) — enqueue via ShopFleetService locally if lab is up."
    }
}

if ($RunWorker -and $jobIds.Count -ge 0) {
    Write-Host 'Running job worker once…'
    & php (Join-Path $root 'bin\job-worker.php') --once --type=burn_in_24h
}

$manifest = @{
    profile     = $Profile
    output      = $outDir
    queued      = (Get-Date).ToUniversalTime().ToString('o')
    audit_json  = $jsonPath
    audit_html  = if (Test-Path $htmlPath) { $htmlPath } else { $null }
    fingerprint = if ($audit) { $audit.fingerprint } else { $null }
    burn_in_jobs = $jobIds
}
$manPath = Join-Path $outDir ("batch-" + $stamp + '.json')
$manifest | ConvertTo-Json -Depth 8 | Set-Content -Path $manPath -Encoding UTF8
Write-Host "Queued batch manifest: $manPath"
Write-Host "Start Full Lab from desktop or: php bin/job-worker.php --once"
