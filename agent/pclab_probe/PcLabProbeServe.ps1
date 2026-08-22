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
$script:ProbeStartedAt = Get-Date
$script:ProbeLastError = $null
$script:ServiceMode = [bool]($env:PCLAB_PROBE_SERVICE -eq '1' -or $env:PCLAB_PROBE_SERVICE -eq 'true')
$script:ProbeAuthToken = $env:PCLAB_PROBE_TOKEN
if (-not $script:ProbeAuthToken) {
    $tokDir = Join-Path $env:LOCALAPPDATA 'PcLabKit\Probe'
    if (-not (Test-Path $tokDir)) { New-Item -ItemType Directory -Path $tokDir -Force | Out-Null }
    $tokFile = Join-Path $tokDir 'auth.token'
    if (Test-Path $tokFile) {
        $script:ProbeAuthToken = (Get-Content $tokFile -Raw).Trim()
    } else {
        $script:ProbeAuthToken = [guid]::NewGuid().ToString('n')
        Set-Content -Path $tokFile -Value $script:ProbeAuthToken -Encoding ASCII
    }
}

# Single source of truth: drives the startup banner, the "/" status page and the 404 hint,
# so the three can never drift out of sync again.
$script:Routes = @(
    @{ method = 'GET';  path = '/health';             desc = 'liveness + capability flags + sensor trust' }
    @{ method = 'GET';  path = '/probe';              desc = 'full scan (hardware + thermals + drivers)' }
    @{ method = 'GET';  path = '/telemetry';          desc = 'fast counters' }
    @{ method = 'GET';  path = '/telemetry/stream';   desc = 'SSE live sensor stream (~5 Hz)' }
    @{ method = 'GET';  path = '/telemetry/history';  desc = "sparkline buffer ($script:RingMax samples)" }
    @{ method = 'GET';  path = '/integrations/hwinfo-sm'; desc = 'write JSON sensor feed (HWiNFO-style names; not binary SM)' }
    @{ method = 'GET';  path = '/storage/smart';      desc = 'SMART / NVMe reliability panel' }
    @{ method = 'POST'; path = '/storage/smart/self-test'; desc = 'enqueue SMART self-test (smartctl)' }
    @{ method = 'GET';  path = '/presentmon/capture'; desc = 'PresentMon session → 1%/0.1% lows (?seconds=)' }
    @{ method = 'GET';  path = '/devices';            desc = 'full PnP / PCI / USB / monitor inventory' }
    @{ method = 'GET';  path = '/drivers';            desc = 'driver advisor + install queue (?wu=1 optional WU scan)' }
    @{ method = 'POST'; path = '/drivers/install';    desc = 'one-click install matched package (confirm required)' }
    @{ method = 'GET';  path = '/drivers/install/status'; desc = 'install job status (?job=)' }
    @{ method = 'GET';  path = '/thermal';            desc = 'CPU/GPU hotspot summary' }
    @{ method = 'GET';  path = '/openbook';           desc = 'open-book recovered sensors (BAR0 / NVAPI raw / ADL)' }
    @{ method = 'GET';  path = '/oc/status';          desc = 'OC baseline state' }
    @{ method = 'POST'; path = '/oc/preflight';       desc = 'idle+load thermal sample before apply' }
    @{ method = 'POST'; path = '/oc/apply';           desc = 'apply OC plan JSON' }
    @{ method = 'POST'; path = '/oc/watch';           desc = 'post-apply monitor + optional auto-rollback' }
    @{ method = 'POST'; path = '/oc/rollback';        desc = 'restore baseline' }
    @{ method = 'GET';  path = '/rgb/scan';           desc = 'detect case/fan/LCD RGB' }
    @{ method = 'POST'; path = '/rgb/apply';          desc = 'apply zone colors/effects' }
    @{ method = 'POST'; path = '/rgb/lcd';            desc = 'upload GIF (local cache + OpenRGB push attempt)' }
    @{ method = 'POST'; path = '/rgb/stop';           desc = 'stop blink timers / set zones off' }
    @{ method = 'POST'; path = '/rgb/auto';           desc = 'auto RGB' }
    @{ method = 'POST'; path = '/rgb/stop-vendors';  desc = 'stop competing vendor RGB processes (confirm)' }
    @{ method = 'POST'; path = '/orchestrate'; desc = 'full setup (RGB + fan + LCD)' }
    @{ method = 'GET';  path = '/bench/catalog';      desc = 'runnable benchmarks' }
    @{ method = 'POST'; path = '/bench/run';          desc = 'CPU / CPU-MT / memory / storage / GPU bench' }
    @{ method = 'GET';  path = '/stress/catalog';     desc = 'runnable stress tests' }
    @{ method = 'POST'; path = '/stress/run';         desc = 'CPU / memory / GPU / combined / quick / oracle stress' }
    @{ method = 'POST'; path = '/stress/oracle/start'; desc = 'adaptive stability oracle ramp' }
    @{ method = 'POST'; path = '/suite/start';       desc = 'start Full Lab suite (async; default profile=adaptive; resume=1 to resume)' }
    @{ method = 'GET';  path = '/suite/plan';        desc = 'preview adaptive lab plan for this machine' }
    @{ method = 'GET';  path = '/suite/status';      desc = 'suite progress / result + resume_token' }
    @{ method = 'POST'; path = '/suite/cancel';      desc = 'cancel / interrupt running suite (preserves checkpoints)' }
    @{ method = 'POST'; path = '/suite/discard';     desc = 'discard suite checkpoint' }
    @{ method = 'GET';  path = '/audit';              desc = 'platform audit JSON (fingerprint + plan + drivers)' }
    @{ method = 'GET';  path = '/launchers';          desc = 'detect installed third-party stress tools' }
    @{ method = 'POST'; path = '/launchers/run';     desc = 'launch external stress tool with telemetry overlay' }
    @{ method = 'GET';  path = '/repair/catalog';     desc = 'OS maintenance tools (SFC/DISM/pnputil)' }
    @{ method = 'POST'; path = '/repair/run';         desc = 'run OS maintenance tool (confirm + elevated)' }
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

        # Mutating routes require the per-install probe token (header / Bearer only).
        $mutating = $req.HttpMethod -eq 'POST' -and $path -match '^/(suite|stress|oc|rgb|bench|drivers/install|orchestrate|launchers|storage|repair)/'
        if ($mutating -and $script:ProbeAuthToken) {
            $tok = $req.Headers['X-PcLab-Token']
            if (-not $tok) { $tok = $req.Headers['Authorization'] -replace '^Bearer\s+', '' }
            if (-not $tok -or $tok -ne $script:ProbeAuthToken) {
                $code = 401
                $body = '{"ok":false,"error":"unauthorized","message":"X-PcLab-Token required for mutating routes"}'
                $res.StatusCode = $code
                $res.ContentType = $ctype
                $res.Headers.Add("Access-Control-Allow-Origin", "http://127.0.0.1")
                $res.Headers.Add("Access-Control-Allow-Headers", "Content-Type, X-PcLab-Token, Authorization")
                $buf = [System.Text.Encoding]::UTF8.GetBytes($body)
                $res.ContentLength64 = $buf.Length
                $res.OutputStream.Write($buf, 0, $buf.Length)
                $res.Close()
                continue
            }
        }

        if ($path -eq "/telemetry/stream" -and $req.HttpMethod -eq 'GET') {
            $res.StatusCode = 200
            $res.ContentType = "text/event-stream; charset=utf-8"
            $sseOrigin = $req.Headers['Origin']
            if ($sseOrigin -match '^https?://(127\.0\.0\.1|localhost)(:\d+)?$') {
                $res.Headers.Add("Access-Control-Allow-Origin", $sseOrigin)
                $res.Headers.Add("Access-Control-Allow-Credentials", "true")
            } else {
                $res.Headers.Add("Access-Control-Allow-Origin", "http://127.0.0.1")
            }
            $res.Headers.Add("Cache-Control", "no-cache")
            $res.SendChunked = $true
            $enc = [System.Text.Encoding]::UTF8
            $stream = $res.OutputStream
            $ticks = 0
            . (Join-Path $scriptDir 'ProbeLib\system.ps1')
            try {
                while ($ticks -lt 600 -and $listener.IsListening) {
                    $snap = Get-TelemetrySnapshot
                    if ($snap) { Add-RingSample $snap }
                    $payload = ($snap | ConvertTo-Json -Compress)
                    if (-not $payload) { $payload = '{}' }
                    $line = "data: $payload`n`n"
                    $bytes = $enc.GetBytes($line)
                    $stream.Write($bytes, 0, $bytes.Length)
                    $stream.Flush()
                    Start-Sleep -Milliseconds 200
                    $ticks++
                }
            } catch {}
            try { $stream.Close() } catch {}
            try { $res.Close() } catch {}
            continue
        }

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
                $vkbench = (Test-Path (Join-Path $scriptDir "PcLabVkBench.exe")).ToString().ToLower()
                $obCount = 0
                $statusFile = Join-Path $env:TEMP 'pclab_openbook_status.json'
                if (Test-Path $statusFile) {
                    try {
                        $st = Get-Content $statusFile -Raw | ConvertFrom-Json
                        $obCount = [int]$st.count
                    } catch {}
                }
                $uptime = [math]::Round(((Get-Date) - $script:ProbeStartedAt).TotalSeconds, 1)
                $lastErr = if ($script:ProbeLastError) { ($script:ProbeLastError -replace '"','\"') } else { '' }
                $svc = $script:ServiceMode.ToString().ToLower()
                $authRequired = ([bool]$script:ProbeAuthToken).ToString().ToLower()
                . (Join-Path $scriptDir 'ProbeLib\sensor-trust.ps1')
                $trust = Get-SensorTrustStatus -Elevated $elevated -ServiceMode $script:ServiceMode -ProbeRoot $scriptDir
                $conflictsJson = '[]'
                if ($trust.competing_tools -and @($trust.competing_tools).Count -gt 0) {
                    $conflictsJson = (@($trust.competing_tools) | ConvertTo-Json -Compress)
                    if (-not $conflictsJson.StartsWith('[')) { $conflictsJson = '[' + $conflictsJson + ']' }
                }
                $trustMsg = if ($trust.message) { ($trust.message -replace '\\','\\' -replace '"','\"') } else { '' }
                $opStory = ($trust.operator_story -replace '\\','\\' -replace '"','\"')
                $body = '{"ok":true,"agent":"pclab-probe","version":6,"hwmon":' + $hwmon + ',"vkbench":' + $vkbench + ',"open_book":true,"open_book_count":' + $obCount + ',"elevated":' + $elevated.ToString().ToLower() + ',"oc":true,"rgb":true,"devices":true,"drivers":true,"suite":true,"launchers":true,"uptime_s":' + $uptime + ',"pid":' + $PID + ',"service_mode":' + $svc + ',"last_error":' + $(if ($lastErr) { '"' + $lastErr + '"' } else { 'null' }) + ',"auth_required":' + $authRequired + ',"ring0":' + $elevated.ToString().ToLower() + ',"sensor_trust":{"backend":"' + $trust.backend + '","trust_mode":"' + $trust.trust_mode + '","ring0_path":' + $trust.ring0_path.ToString().ToLower() + ',"conflict":' + $trust.conflict.ToString().ToLower() + ',"competing_tools":' + $conflictsJson + ',"message":' + $(if ($trustMsg) { '"' + $trustMsg + '"' } else { 'null' }) + ',"operator_story":"' + $opStory + '","winring0_shipped":false}}'
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
                try {
                    . (Join-Path $scriptDir 'ProbeLib\system.ps1')
                    $rust = Get-PcLabCoreHistory
                    if ($rust -and $rust.Count -gt 0) {
                        $ps = $body | ConvertFrom-Json
                        if (-not $ps) { $ps = @() }
                        $merged = @($ps) + @($rust)
                        if ($merged.Count -gt $script:RingMax) {
                            $merged = $merged[($merged.Count - $script:RingMax)..($merged.Count - 1)]
                        }
                        $body = ($merged | ConvertTo-Json -Compress)
                    }
                } catch {}
            }
            "/integrations/hwinfo-sm" {
                $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$scriptDir\ProbeLib\system.ps1'
. '$scriptDir\ProbeLib\hwinfo-sm.ps1'
`$snap = Get-TelemetrySnapshot
Write-PcLabHwInfoSharedMemory -Telemetry `$snap | ConvertTo-Json -Compress }
"@
            }
            "/storage/smart" {
                $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$scriptDir\ProbeLib\memory.ps1'
. '$scriptDir\ProbeLib\platform.ps1'
`$tel = Get-ProbeStorageTelemetry
`$nvme = Get-ProbeNvmeSmartDetailed
@{ ok = `$true; storage = `$tel; nvme_detailed = `$nvme } | ConvertTo-Json -Depth 10 -Compress }
"@
            }
            "/storage/smart/self-test" {
                if ($req.HttpMethod -ne 'POST') { $code = 405; $body = '{"error":"POST required"}'; break }
                $raw = Read-RequestBody $req
                $tmp = Join-Path $env:TEMP ("pclab_smart_" + [guid]::NewGuid().ToString("n") + ".json")
                try {
                    if (-not $raw) { $raw = '{}' }
                    [System.IO.File]::WriteAllText($tmp, $raw, [System.Text.UTF8Encoding]::new($false))
                    $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$scriptDir\ProbeLib\memory.ps1'
`$j = Get-Content '$tmp' -Raw | ConvertFrom-Json
`$dev = if (`$j.device) { [string]`$j.device } else { '' }
`$typ = if (`$j.type) { [string]`$j.type } else { 'short' }
Invoke-ProbeSmartSelfTest -Device `$dev -Type `$typ | ConvertTo-Json -Depth 6 -Compress }
"@
                } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
            }
            "/presentmon/capture" {
                $sec = 10
                if ($req.Url.Query -match 'seconds=(\d+)') { $sec = [int]$Matches[1] }
                $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$scriptDir\ProbeLib\presentmon.ps1'
Get-ProbePresentMonTelemetry -TimedSeconds $sec | ConvertTo-Json -Depth 8 -Compress }
"@
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
@{ elevated = `$t.elevated; thermal = `$t.thermal; cpu = `$t.cpu.thermal; gpu = `$t.gpu.thermal; gpus = `$t.gpu.gpus; open_book = `$t.open_book } | ConvertTo-Json -Depth 10 -Compress }
"@
            }
            "/openbook" {
                $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$scriptDir\ProbeLib\system.ps1'
. '$scriptDir\ProbeLib\openbook.ps1'
Get-ProbeOpenBookPayload | ConvertTo-Json -Depth 12 -Compress }
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
`$ogi = -1
if (`$null -ne `$j.openrgb_index) { `$ogi = [int]`$j.openrgb_index }
Save-ProbeLcdGif -DeviceId `$j.device_id -Bytes `$bytes -ExpectedW ([int]`$j.expected_w) -ExpectedH ([int]`$j.expected_h) -OpenRgbIndex `$ogi | ConvertTo-Json -Depth 8 -Compress }
"@
                } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
            }
            "/rgb/stop" {
                if ($req.HttpMethod -ne 'POST') { $code = 405; $body = '{"error":"POST required"}'; break }
                $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$rgbScript'
Invoke-RgbStop | ConvertTo-Json -Depth 6 -Compress }
"@
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
            "/rgb/stop-vendors" {
                if ($req.HttpMethod -ne 'POST') { $code = 405; $body = '{"error":"POST required"}'; break }
                $raw = Read-RequestBody $req
                $tmp = Join-Path $env:TEMP ("pclab_rgbkill_" + [guid]::NewGuid().ToString("n") + ".json")
                try {
                    if (-not $raw) { $raw = '{}' }
                    [System.IO.File]::WriteAllText($tmp, $raw, [System.Text.UTF8Encoding]::new($false))
                    $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$rgbScript'
`$j = Get-Content '$tmp' -Raw | ConvertFrom-Json
`$c = `$false
if (`$null -ne `$j.confirm) { `$c = [bool]`$j.confirm }
Invoke-RgbStopVendorProcesses -Confirm:`$c | ConvertTo-Json -Depth 6 -Compress }
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
if (`$j.gpu_mode) { `$opts.gpu_mode = [string]`$j.gpu_mode }
Invoke-ProbeStress -Id `$id -Options `$opts | ConvertTo-Json -Depth 8 -Compress }
"@
                } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
            }
            "/stress/oracle/start" {
                if ($req.HttpMethod -ne 'POST') { $code = 405; $body = '{"error":"POST required"}'; break }
                $raw = Read-RequestBody $req
                $tmp = Join-Path $env:TEMP ("pclab_oracle_" + [guid]::NewGuid().ToString("n") + ".json")
                try {
                    if (-not $raw) { $raw = '{}' }
                    [System.IO.File]::WriteAllText($tmp, $raw, [System.Text.UTF8Encoding]::new($false))
                    $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$stressScript'
`$j = Get-Content '$tmp' -Raw | ConvertFrom-Json
`$opts = @{}
if (`$j.step_seconds) { `$opts.step_seconds = [int]`$j.step_seconds }
if (`$j.cpu_temp_max) { `$opts.cpu_temp_max = [double]`$j.cpu_temp_max }
if (`$j.gpu_temp_max) { `$opts.gpu_temp_max = [double]`$j.gpu_temp_max }
if (`$j.gpu_hotspot_max) { `$opts.gpu_hotspot_max = [double]`$j.gpu_hotspot_max }
Invoke-ProbeStabilityOracle -Options `$opts | ConvertTo-Json -Depth 10 -Compress }
"@
                } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
            }
            "/suite/start" {
                if ($req.HttpMethod -ne 'POST') { $code = 405; $body = '{"error":"POST required"}'; break }
                $raw = Read-RequestBody $req
                $profile = 'adaptive'
                $doResume = $false
                $resumeToken = ''
                try {
                    if ($raw) {
                        $j = $raw | ConvertFrom-Json
                        if ($j.profile) { $profile = [string]$j.profile }
                        if ($j.resume -eq $true -or $j.resume -eq 1 -or [string]$j.resume -eq '1') { $doResume = $true }
                        if ($j.resume_token) { $resumeToken = [string]$j.resume_token; $doResume = $true }
                    }
                } catch {}
                if ($doResume) {
                    $body = (Resume-ProbeSuiteJob -ScriptDir $scriptDir -ResumeToken $resumeToken | ConvertTo-Json -Depth 10 -Compress)
                } else {
                    $body = (Start-ProbeSuiteJob -Profile $profile -ScriptDir $scriptDir | ConvertTo-Json -Depth 10 -Compress)
                }
            }
            "/suite/discard" {
                if ($req.HttpMethod -ne 'POST') { $code = 405; $body = '{"error":"POST required"}'; break }
                $raw = Read-RequestBody $req
                $jid = ''
                try {
                    if ($raw) {
                        $j = $raw | ConvertFrom-Json
                        if ($j.id) { $jid = [string]$j.id }
                        elseif ($j.resume_token) { $jid = [string]$j.resume_token }
                    }
                } catch {}
                $body = (Clear-ProbeSuiteCheckpoint -JobId $jid | ConvertTo-Json -Depth 6 -Compress)
            }
            "/suite/plan" {
                . (Join-Path $scriptDir 'ProbeLib\devices.ps1')
                . (Join-Path $scriptDir 'ProbeLib\adaptive-plan.ps1')
                $inv = Get-ProbeDeviceInventory
                $plan = Get-ProbeAdaptiveLabPlan -Fingerprint $inv.fingerprint -Devices $inv -Platform $inv.platform
                $body = (@{ ok = $true; plan = $plan; fingerprint = $inv.fingerprint } | ConvertTo-Json -Depth 12 -Compress)
            }
            "/audit" {
                . (Join-Path $scriptDir 'ProbeLib\devices.ps1')
                . (Join-Path $scriptDir 'ProbeLib\drivers.ps1')
                . (Join-Path $scriptDir 'ProbeLib\adaptive-plan.ps1')
                $inv = Get-ProbeDeviceInventory
                $drv = Get-ProbeDriverAdvice -DeviceInventory $inv
                $plan = Get-ProbeAdaptiveLabPlan -Fingerprint $inv.fingerprint -Devices $inv -Platform $inv.platform
                $audit = @{
                    schema = 'pclab-platform-audit-v1'
                    generated_at = (Get-Date).ToUniversalTime().ToString('o')
                    fingerprint = $inv.fingerprint
                    platform = $inv.platform
                    gaps = $inv.fingerprint.gaps
                    adaptive_plan = $plan
                    driver_actions = $drv.action_plan
                    inventory_summary = $inv.summary
                    note = 'Read-only platform audit — no firmware flash'
                }
                $body = ($audit | ConvertTo-Json -Depth 14 -Compress)
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
            "/repair/catalog" {
                $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$scriptDir\ProbeLib\repair.ps1'
Get-ProbeRepairCatalog | ConvertTo-Json -Depth 6 -Compress }
"@
            }
            "/repair/run" {
                if ($req.HttpMethod -ne 'POST') { $code = 405; $body = '{"error":"POST required"}'; break }
                $raw = Read-RequestBody $req
                $tmp = Join-Path $env:TEMP ("pclab_repair_" + [guid]::NewGuid().ToString("n") + ".json")
                try {
                    if (-not $raw) { $raw = '{}' }
                    [System.IO.File]::WriteAllText($tmp, $raw, [System.Text.UTF8Encoding]::new($false))
                    $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$scriptDir\ProbeLib\repair.ps1'
`$j = Get-Content '$tmp' -Raw | ConvertFrom-Json
`$id = if (`$j.id) { [string]`$j.id } else { '' }
`$c = `$false
if (`$null -ne `$j.confirm) { `$c = [bool]`$j.confirm }
Invoke-ProbeRepairTool -Id `$id -Confirm:`$c | ConvertTo-Json -Depth 6 -Compress }
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
        $origin = $req.Headers['Origin']
        if ($origin -match '^https?://(127\.0\.0\.1|localhost)(:\d+)?$') {
            $res.Headers.Add("Access-Control-Allow-Origin", $origin)
            $res.Headers.Add("Access-Control-Allow-Credentials", "true")
        } else {
            $res.Headers.Add("Access-Control-Allow-Origin", "http://127.0.0.1")
        }
        $res.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        $res.Headers.Add("Access-Control-Allow-Headers", "Content-Type, X-PcLab-Token, Authorization")
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
