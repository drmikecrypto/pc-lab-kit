#Requires -Version 5.1
<#
  PcLab Probe Server v5 - thermal resolver + full device inventory + driver advisor
#>
param(
    [int]$Port = 18765,
    [string]$Prefix = ""
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$probeScript = Join-Path $scriptDir "PcLabProbe.ps1"
$ocScript = Join-Path $scriptDir "ProbeLib\overclock.ps1"
$rgbScript = Join-Path $scriptDir "ProbeLib\rgb.ps1"
$orchestratorScript = Join-Path $scriptDir "ProbeLib\orchestrator.ps1"
$benchScript = Join-Path $scriptDir "ProbeLib\benchmark.ps1"
$stressScript = Join-Path $scriptDir "ProbeLib\stress.ps1"
$suiteScript = Join-Path $scriptDir "ProbeLib\suite.ps1"
$devicesScript = Join-Path $scriptDir "ProbeLib\devices.ps1"
$driversScript = Join-Path $scriptDir "ProbeLib\drivers.ps1"
. $suiteScript
$script:RingMax = 120
$script:Ring = New-Object System.Collections.Generic.List[object]

# Single source of truth: drives the startup banner, the "/" status page and the 404 hint,
# so the three can never drift out of sync again.
$script:Routes = @(
    @{ method = 'GET';  path = '/health';             desc = 'liveness + capability flags' }
    @{ method = 'GET';  path = '/probe';              desc = 'full scan (hardware + thermals + drivers)' }
    @{ method = 'GET';  path = '/telemetry';          desc = 'fast counters' }
    @{ method = 'GET';  path = '/telemetry/history';  desc = "sparkline buffer ($script:RingMax samples)" }
    @{ method = 'GET';  path = '/devices';            desc = 'full PnP / PCI / USB / monitor inventory' }
    @{ method = 'GET';  path = '/drivers';            desc = 'driver advisor + install queue (?wu=1 optional WU scan)' }
    @{ method = 'POST'; path = '/drivers/install';    desc = 'one-click install matched package (confirm required)' }
    @{ method = 'GET';  path = '/drivers/install/status'; desc = 'install job status (?job=)' }
    @{ method = 'GET';  path = '/thermal';            desc = 'CPU/GPU hotspot summary' }
    @{ method = 'GET';  path = '/oc/status';          desc = 'OC baseline state' }
    @{ method = 'POST'; path = '/oc/preflight';       desc = 'idle+load thermal sample before apply' }
    @{ method = 'POST'; path = '/oc/apply';           desc = 'apply OC plan JSON' }
    @{ method = 'POST'; path = '/oc/watch';           desc = 'post-apply monitor + optional auto-rollback' }
    @{ method = 'POST'; path = '/oc/rollback';        desc = 'restore baseline' }
    @{ method = 'GET';  path = '/rgb/scan';           desc = 'detect case/fan/LCD RGB' }
    @{ method = 'POST'; path = '/rgb/apply';          desc = 'apply zone colors/effects' }
    @{ method = 'POST'; path = '/rgb/lcd';            desc = 'upload GIF (local only, base64 JSON)' }
    @{ method = 'POST'; path = '/rgb/auto';         desc = 'auto RGB' }
    @{ method = 'POST'; path = '/orchestrate'; desc = 'full setup (RGB + fan + LCD)' }
    @{ method = 'GET';  path = '/bench/catalog';      desc = 'runnable benchmarks' }
    @{ method = 'POST'; path = '/bench/run';          desc = 'CPU / CPU-MT / memory / storage / GPU bench' }
    @{ method = 'GET';  path = '/stress/catalog';     desc = 'runnable stress tests' }
    @{ method = 'POST'; path = '/stress/run';         desc = 'CPU / memory / GPU / combined / quick stress' }
    @{ method = 'POST'; path = '/suite/start';       desc = 'start Full Lab suite (async)' }
    @{ method = 'GET';  path = '/suite/status';      desc = 'suite progress / result' }
    @{ method = 'POST'; path = '/suite/cancel';      desc = 'cancel running suite' }
    @{ method = 'GET';  path = '/launchers';          desc = 'detect installed third-party stress tools' }
    @{ method = 'POST'; path = '/launchers/run';     desc = 'launch external stress tool with telemetry overlay' }
)

function Test-ProbeElevated {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Add-RingSample($sample) {
    $script:Ring.Add($sample)
    while ($script:Ring.Count -gt $script:RingMax) {
        $script:Ring.RemoveAt(0)
    }
}

function Read-RequestBody($req) {
    if (-not $req.HasEntityBody) { return "" }
    $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
    return $reader.ReadToEnd()
}

if (-not $Prefix) {
    $Prefix = "http://127.0.0.1:$Port/"
}

$elevated = Test-ProbeElevated
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($Prefix)

Write-Host "[PcLab Probe v5] Listening on $Prefix"
Write-Host ("  elevated = " + $elevated)
if (-not $elevated) {
    Write-Host "  WARN: not running as Administrator - CPU die temps and some board sensors will be missing."
    Write-Host "  Restart via Start-PcLabProbe.bat (it self-elevates) for full thermal coverage."
}
foreach ($r in $script:Routes) {
    Write-Host ("  {0,-4} {1,-22} - {2}" -f $r.method, $r.path, $r.desc)
}

try {
    $listener.Start()
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $req = $context.Request
        $res = $context.Response
        $path = $req.Url.LocalPath.TrimEnd("/").ToLower()
        if ($path -eq "") { $path = "/" }

        $body = ""
        $code = 200
        $ctype = "application/json; charset=utf-8"

        switch ($path) {
            "/" {
                # Browsers land here first; a bare 404 reads like a crash, so serve a status page.
                $ctype = "text/html; charset=utf-8"
                $elevBadge = if ($elevated) { "<span class='ok'>elevated</span>" } else { "<span class='warn'>not elevated - CPU die temps unavailable</span>" }
                $rows = ""
                foreach ($r in $script:Routes) {
                    $target = if ($r.method -eq 'GET') { "<a href='$($r.path)'>$($r.path)</a>" } else { "<code>$($r.path)</code>" }
                    $rows += "<tr><td class='m $($r.method.ToLower())'>$($r.method)</td><td>$target</td><td>$($r.desc)</td></tr>"
                }
                $body = @"
<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<title>PcLab Probe v5</title>
<style>
:root{color-scheme:dark}
body{margin:0;padding:2.5rem 1.5rem;background:#0b0f14;color:#e6edf3;font:15px/1.55 "Segoe UI",system-ui,sans-serif}
main{max-width:820px;margin:0 auto}
h1{margin:0 0 .25rem;font-size:1.5rem;letter-spacing:-.01em}
.sub{color:#8b98a5;font-size:.9rem;margin:0 0 1.5rem}
.ok{color:#3fb950}.warn{color:#d29922}
table{width:100%;border-collapse:collapse;margin-top:.5rem}
td{padding:.5rem .6rem;border-bottom:1px solid #1c2430;vertical-align:top}
td.m{width:3.5rem;font:600 12px ui-monospace,monospace}
td.m.get{color:#58a6ff}td.m.post{color:#d2a8ff}
a{color:#58a6ff;text-decoration:none}a:hover{text-decoration:underline}
code{color:#c9d1d9;font:13px ui-monospace,monospace}
.foot{margin-top:2rem;color:#6e7b8b;font-size:.82rem}
</style></head><body><main>
<h1>PcLab Probe <span class="ok">v5</span></h1>
<p class="sub">Listening on $Prefix &middot; $elevBadge &middot; telemetry buffer $RingMax samples</p>
<table>$rows</table>
<p class="foot">Local-first agent. Nothing leaves this machine. GET links are safe to click;
POST endpoints expect a JSON body from the PcLab web lab.</p>
</main></body></html>
"@
            }
            "/health" {
                $hwmon = (Test-Path (Join-Path $scriptDir "PcLabHwMon.exe")).ToString().ToLower()
                $body = '{"ok":true,"agent":"pclab-probe","version":5,"hwmon":' + $hwmon + ',"elevated":' + $elevated.ToString().ToLower() + ',"oc":true,"rgb":true,"devices":true,"drivers":true,"suite":true,"launchers":true}'
            }
            "/probe" {
                $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $probeScript
            }
            "/telemetry" {
                $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$scriptDir\ProbeLib\system.ps1'
`$t = Get-ProbeDeepTelemetry
. '$scriptDir\ProbeLib\system.ps1'
`$snap = Get-TelemetrySnapshot
`$t | Add-Member -NotePropertyName '_snapshot' -NotePropertyValue `$snap -Force
`$t | ConvertTo-Json -Depth 12 -Compress }
"@
                try {
                    $parsed = $body | ConvertFrom-Json
                    if ($parsed._snapshot) { Add-RingSample $parsed._snapshot }
                } catch {}
            }
            "/telemetry/history" {
                $body = ($script:Ring | ConvertTo-Json -Compress)
                if (-not $body) { $body = "[]" }
            }
            "/devices" {
                $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$devicesScript'
Get-ProbeDeviceInventory | ConvertTo-Json -Depth 12 -Compress }
"@
            }
            "/drivers" {
                $qs = $req.Url.Query
                $wu = ($qs -match '[?&]wu=1(&|$)' -or $qs -match '^\?wu=1$' -or $qs -eq '?wu=1')
                if ($wu) {
                    $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$driversScript'
Get-ProbeDriverReport -IncludeWuScan | ConvertTo-Json -Depth 12 -Compress }
"@
                } else {
                    $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$driversScript'
Get-ProbeDriverReport | ConvertTo-Json -Depth 12 -Compress }
"@
                }
            }
            "/drivers/install" {
                if ($req.HttpMethod -ne 'POST') { $code = 405; $body = '{"error":"POST required"}'; break }
                $raw = Read-RequestBody $req
                if (-not $raw) { $code = 400; $body = '{"error":"empty body"}'; break }
                $tmp = Join-Path $env:TEMP ("pclab_drv_inst_" + [guid]::NewGuid().ToString("n") + ".json")
                try {
                    [System.IO.File]::WriteAllText($tmp, $raw, [System.Text.UTF8Encoding]::new($false))
                    $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$driversScript'
`$j = Get-Content '$tmp' -Raw | ConvertFrom-Json
`$confirm = `$false
if (`$null -ne `$j.confirm) { `$confirm = [bool]`$j.confirm }
Start-ProbeDriverInstall -InstanceId "`$(`$j.instance_id)" -QueueId "`$(`$j.queue_id)" -Category "`$(`$j.category)" -Confirm:`$confirm | ConvertTo-Json -Depth 10 -Compress }
"@
                } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
            }
            "/drivers/install/status" {
                $job = ''
                if ($req.Url.Query -match 'job=([a-fA-F0-9]+)') { $job = $Matches[1] }
                $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$driversScript'
Get-ProbeDriverInstallStatus -JobId '$job' | ConvertTo-Json -Depth 10 -Compress }
"@
            }
            "/thermal" {
                $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$scriptDir\ProbeLib\system.ps1'
`$t = Get-ProbeDeepTelemetry
@{ elevated = `$t.elevated; thermal = `$t.thermal; cpu = `$t.cpu.thermal; gpu = `$t.gpu.thermal; gpus = `$t.gpu.gpus } | ConvertTo-Json -Depth 10 -Compress }
"@
            }
            "/oc/status" {
                $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$ocScript'
`$s = Get-ProbeOcState
`$p = Get-ProbeOcStorePath
@{ state = `$s; baseline_exists = (Test-Path `$p); baseline_path = `$p } | ConvertTo-Json -Depth 5 -Compress }
"@
            }
            "/oc/preflight" {
                if ($req.HttpMethod -ne 'POST') { $code = 405; $body = '{"error":"POST required"}'; break }
                $raw = Read-RequestBody $req
                $tmp = Join-Path $env:TEMP ("pclab_oc_pre_" + [guid]::NewGuid().ToString("n") + ".json")
                try {
                    if (-not $raw) { $raw = '{}' }
                    [System.IO.File]::WriteAllText($tmp, $raw, [System.Text.UTF8Encoding]::new($false))
                    $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$ocScript'
`$j = Get-Content '$tmp' -Raw | ConvertFrom-Json
`$idle = if (`$j.idle_seconds) { [int]`$j.idle_seconds } else { 15 }
`$load = if (`$j.load_seconds) { [int]`$j.load_seconds } else { 15 }
Invoke-ProbeOcPreflight -IdleSeconds `$idle -LoadSeconds `$load | ConvertTo-Json -Depth 8 -Compress }
"@
                } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
            }
            "/oc/apply" {
                if ($req.HttpMethod -ne 'POST') { $code = 405; $body = '{"error":"POST required"}'; break }
                $raw = Read-RequestBody $req
                if (-not $raw) { $code = 400; $body = '{"error":"empty body"}'; break }
                $tmpPlan = Join-Path $env:TEMP ("pclab_oc_plan_" + [guid]::NewGuid().ToString("n") + ".json")
                try {
                    [System.IO.File]::WriteAllText($tmpPlan, $raw, [System.Text.UTF8Encoding]::new($false))
                    $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$ocScript'
`$plan = Get-Content '$tmpPlan' -Raw | ConvertFrom-Json
Invoke-ProbeOverclockApply -Plan `$plan | ConvertTo-Json -Depth 8 -Compress }
"@
                } finally {
                    Remove-Item $tmpPlan -Force -ErrorAction SilentlyContinue
                }
            }
            "/oc/watch" {
                if ($req.HttpMethod -ne 'POST') { $code = 405; $body = '{"error":"POST required"}'; break }
                $raw = Read-RequestBody $req
                $tmp = Join-Path $env:TEMP ("pclab_oc_watch_" + [guid]::NewGuid().ToString("n") + ".json")
                try {
                    if (-not $raw) { $raw = '{}' }
                    [System.IO.File]::WriteAllText($tmp, $raw, [System.Text.UTF8Encoding]::new($false))
                    $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$ocScript'
`$j = Get-Content '$tmp' -Raw | ConvertFrom-Json
`$sec = if (`$j.seconds) { [int]`$j.seconds } else { 120 }
`$cpu = if (`$j.cpu_limit) { [double]`$j.cpu_limit } else { 95 }
`$gpu = if (`$j.gpu_limit) { [double]`$j.gpu_limit } else { 90 }
`$br = if (`$j.breach_seconds) { [int]`$j.breach_seconds } else { 30 }
`$auto = `$true
if (`$null -ne `$j.auto_rollback) { `$auto = [bool]`$j.auto_rollback }
if (`$auto) {
  Invoke-ProbeOcWatch -Seconds `$sec -CpuLimit `$cpu -GpuLimit `$gpu -BreachSeconds `$br -AutoRollback | ConvertTo-Json -Depth 8 -Compress
} else {
  Invoke-ProbeOcWatch -Seconds `$sec -CpuLimit `$cpu -GpuLimit `$gpu -BreachSeconds `$br | ConvertTo-Json -Depth 8 -Compress
} }
"@
                } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
            }
            "/oc/rollback" {
                if ($req.HttpMethod -ne 'POST') { $code = 405; $body = '{"error":"POST required"}'; break }
                $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$ocScript'
Invoke-ProbeOverclockRollback | ConvertTo-Json -Depth 6 -Compress }
"@
            }
            "/rgb/scan" {
                $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$rgbScript'
Get-RgbDeviceScan | ConvertTo-Json -Depth 10 -Compress }
"@
            }
            "/rgb/apply" {
                if ($req.HttpMethod -ne 'POST') { $code = 405; $body = '{"error":"POST required"}'; break }
                $raw = Read-RequestBody $req
                if (-not $raw) { $code = 400; $body = '{"error":"empty body"}'; break }
                $tmp = Join-Path $env:TEMP ("pclab_rgb_" + [guid]::NewGuid().ToString("n") + ".json")
                try {
                    [System.IO.File]::WriteAllText($tmp, $raw, [System.Text.UTF8Encoding]::new($false))
                    $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$rgbScript'
`$s = Get-Content '$tmp' -Raw | ConvertFrom-Json
Invoke-RgbApplySettings -Settings `$s | ConvertTo-Json -Depth 8 -Compress }
"@
                } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
            }
            "/rgb/lcd" {
                if ($req.HttpMethod -ne 'POST') { $code = 405; $body = '{"error":"POST required"}'; break }
                $raw = Read-RequestBody $req
                if (-not $raw) { $code = 400; $body = '{"error":"empty body"}'; break }
                $tmp = Join-Path $env:TEMP ("pclab_lcd_" + [guid]::NewGuid().ToString("n") + ".json")
                try {
                    [System.IO.File]::WriteAllText($tmp, $raw, [System.Text.UTF8Encoding]::new($false))
                    $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$rgbScript'
`$j = Get-Content '$tmp' -Raw | ConvertFrom-Json
`$bytes = [Convert]::FromBase64String(`$j.gif_base64)
Save-ProbeLcdGif -DeviceId `$j.device_id -Bytes `$bytes -ExpectedW ([int]`$j.expected_w) -ExpectedH ([int]`$j.expected_h) | ConvertTo-Json -Depth 6 -Compress }
"@
                } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
            }
            "/rgb/auto" {
                if ($req.HttpMethod -ne 'POST') { $code = 405; $body = '{"error":"POST required"}'; break }
                $raw = Read-RequestBody $req
                $tmp = Join-Path $env:TEMP ("pclab_rgbv_" + [guid]::NewGuid().ToString("n") + ".json")
                try {
                    if ($raw) { [System.IO.File]::WriteAllText($tmp, $raw, [System.Text.UTF8Encoding]::new($false)) } else { '{}' | Set-Content $tmp }
                    $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$orchestratorScript'
. '$scriptDir\ProbeLib\system.ps1'
`$payload = Get-Content '$tmp' -Raw | ConvertFrom-Json
`$scan = Get-RgbDeviceScan
`$tel = @{}
if (`$payload.telemetry) { `$tel = `$payload.telemetry } else {
  `$t = Get-ProbeDeepTelemetry
  `$tel = @{ cpu_temp = `$t.cpu.thermal.package_c; gpu_temp = `$t.gpu.thermal.core_c; gpu_hotspot = `$t.gpu.thermal.hot_spot_c; cpu = `$t.cpu; gpu = `$t.gpu }
}
if (`$payload.plan) { Invoke-ProbeOrchestrate -Payload `$payload | ConvertTo-Json -Depth 12 -Compress }
else { Invoke-ProbeRgbAuto -Telemetry `$tel -Scan `$scan | ConvertTo-Json -Depth 10 -Compress }
"@
                } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
            }
            "/orchestrate" {
                if ($req.HttpMethod -ne 'POST') { $code = 405; $body = '{"error":"POST required"}'; break }
                $raw = Read-RequestBody $req
                if (-not $raw) { $code = 400; $body = '{"error":"empty body"}'; break }
                $tmp = Join-Path $env:TEMP ("pclab_vkh_" + [guid]::NewGuid().ToString("n") + ".json")
                try {
                    [System.IO.File]::WriteAllText($tmp, $raw, [System.Text.UTF8Encoding]::new($false))
                    $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$orchestratorScript'
`$payload = Get-Content '$tmp' -Raw | ConvertFrom-Json
Invoke-ProbeOrchestrate -Payload `$payload | ConvertTo-Json -Depth 12 -Compress }
"@
                } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
            }
            "/bench/catalog" {
                $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$benchScript'
@{ benchmarks = (Get-ProbeBenchmarkCatalog) } | ConvertTo-Json -Depth 6 -Compress }
"@
            }
            "/bench/run" {
                if ($req.HttpMethod -ne 'POST') { $code = 405; $body = '{"error":"POST required"}'; break }
                $raw = Read-RequestBody $req
                $tmp = Join-Path $env:TEMP ("pclab_bench_" + [guid]::NewGuid().ToString("n") + ".json")
                try {
                    if (-not $raw) { $raw = '{"id":"cpu"}' }
                    [System.IO.File]::WriteAllText($tmp, $raw, [System.Text.UTF8Encoding]::new($false))
                    $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$benchScript'
`$j = Get-Content '$tmp' -Raw | ConvertFrom-Json
`$id = if (`$j.id) { [string]`$j.id } else { 'cpu' }
`$opts = @{}
if (`$j.seconds) { `$opts.seconds = [int]`$j.seconds }
if (`$j.drive) { `$opts.drive = [string]`$j.drive }
Invoke-ProbeBenchmark -Id `$id -Options `$opts | ConvertTo-Json -Depth 8 -Compress }
"@
                } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
            }
            "/stress/catalog" {
                $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$stressScript'
@{ stress = (Get-ProbeStressCatalog) } | ConvertTo-Json -Depth 6 -Compress }
"@
            }
            "/stress/run" {
                if ($req.HttpMethod -ne 'POST') { $code = 405; $body = '{"error":"POST required"}'; break }
                $raw = Read-RequestBody $req
                $tmp = Join-Path $env:TEMP ("pclab_stress_" + [guid]::NewGuid().ToString("n") + ".json")
                try {
                    if (-not $raw) { $raw = '{"id":"cpu"}' }
                    [System.IO.File]::WriteAllText($tmp, $raw, [System.Text.UTF8Encoding]::new($false))
                    $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$stressScript'
`$j = Get-Content '$tmp' -Raw | ConvertFrom-Json
`$id = if (`$j.id) { [string]`$j.id } else { 'cpu' }
`$opts = @{}
if (`$j.seconds) { `$opts.seconds = [int]`$j.seconds }
if (`$j.percent) { `$opts.percent = [int]`$j.percent }
Invoke-ProbeStress -Id `$id -Options `$opts | ConvertTo-Json -Depth 8 -Compress }
"@
                } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
            }
            "/suite/start" {
                if ($req.HttpMethod -ne 'POST') { $code = 405; $body = '{"error":"POST required"}'; break }
                $raw = Read-RequestBody $req
                $profile = 'standard'
                try {
                    if ($raw) {
                        $j = $raw | ConvertFrom-Json
                        if ($j.profile) { $profile = [string]$j.profile }
                    }
                } catch {}
                $body = (Start-ProbeSuiteJob -Profile $profile -ScriptDir $scriptDir | ConvertTo-Json -Depth 10 -Compress)
            }
            "/suite/status" {
                $body = (Get-ProbeSuiteStatus | ConvertTo-Json -Depth 12 -Compress)
            }
            "/suite/cancel" {
                if ($req.HttpMethod -ne 'POST') { $code = 405; $body = '{"error":"POST required"}'; break }
                $body = (Stop-ProbeSuiteJob | ConvertTo-Json -Depth 8 -Compress)
            }
            "/launchers" {
                $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$scriptDir\ProbeLib\launchers.ps1'
Get-ProbeExternalLaunchers | ConvertTo-Json -Depth 8 -Compress }
"@
            }
            "/launchers/run" {
                if ($req.HttpMethod -ne 'POST') { $code = 405; $body = '{"error":"POST required"}'; break }
                $raw = Read-RequestBody $req
                $tmp = Join-Path $env:TEMP ("pclab_launch_" + [guid]::NewGuid().ToString("n") + ".json")
                try {
                    if (-not $raw) { $raw = '{}' }
                    [System.IO.File]::WriteAllText($tmp, $raw, [System.Text.UTF8Encoding]::new($false))
                    $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$scriptDir\ProbeLib\launchers.ps1'
. '$stressScript'
`$j = Get-Content '$tmp' -Raw | ConvertFrom-Json
Invoke-ProbeExternalLauncher -Request `$j | ConvertTo-Json -Depth 10 -Compress }
"@
                } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
            }
            default {
                $code = 404
                $body = @{
                    error   = 'not found'
                    path    = $path
                    version = 5
                    hint    = 'Open http://127.0.0.1:' + $Port + '/ for the endpoint index.'
                    routes  = @($script:Routes | ForEach-Object { $_.method + ' ' + $_.path })
                } | ConvertTo-Json -Depth 4 -Compress
            }
        }

        $res.StatusCode = $code
        $res.ContentType = $ctype
        $res.Headers.Add("Access-Control-Allow-Origin", "*")
        $res.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        $res.Headers.Add("Access-Control-Allow-Headers", "Content-Type")
        if ($req.HttpMethod -eq 'OPTIONS') {
            $res.StatusCode = 204
            $buf = @()
        } else {
            $buf = [System.Text.Encoding]::UTF8.GetBytes($body)
        }
        $res.ContentLength64 = $buf.Length
        if ($buf.Length -gt 0) {
            $res.OutputStream.Write($buf, 0, $buf.Length)
        }
        $res.Close()
    }
} finally {
    $listener.Stop()
}
