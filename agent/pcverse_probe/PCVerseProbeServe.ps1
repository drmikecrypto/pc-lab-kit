#Requires -Version 5.1
<#
  PCVerse Probe Server v4 — ring buffer + telemetry + وخش OC apply/rollback
#>
param(
    [int]$Port = 18765,
    [string]$Prefix = ""
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$probeScript = Join-Path $scriptDir "PCVerseProbe.ps1"
$ocScript = Join-Path $scriptDir "ProbeLib\overclock.ps1"
$rgbScript = Join-Path $scriptDir "ProbeLib\rgb.ps1"
$vakhshScript = Join-Path $scriptDir "ProbeLib\vakhsh-orchestrator.ps1"
$benchScript = Join-Path $scriptDir "ProbeLib\benchmark.ps1"
$stressScript = Join-Path $scriptDir "ProbeLib\stress.ps1"
$script:RingMax = 120
$script:Ring = New-Object System.Collections.Generic.List[object]

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

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($Prefix)

Write-Host "[PCVerse Probe v4] Listening on $Prefix"
Write-Host "  GET /health"
Write-Host "  GET /probe       - full scan"
Write-Host "  GET /telemetry   - fast counters"
Write-Host ('  GET /telemetry/history - sparkline buffer (' + $RingMax + ' samples)')
Write-Host "  GET /oc/status   - OC baseline state"
Write-Host "  POST /oc/apply   - apply OC plan JSON"
Write-Host "  POST /oc/rollback - restore baseline"
Write-Host "  GET /rgb/scan    - detect case/fan/LCD RGB"
Write-Host "  POST /rgb/apply  - apply zone colors/effects"
Write-Host "  POST /rgb/lcd    - upload GIF (local only, base64 JSON)"
Write-Host "  POST /rgb/vakhsh - auto RGB"
Write-Host "  GET /bench/catalog - runnable benchmarks"
Write-Host "  POST /bench/run   - run CPU/memory/storage bench"
Write-Host "  GET /stress/catalog - runnable stress tests"
Write-Host "  POST /stress/run  - run CPU/memory stress"

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
            "/health" {
                $body = '{"ok":true,"agent":"pcverse-probe","version":4,"hwmon":' + (Test-Path (Join-Path $scriptDir "PcVerseHwMon.exe")).ToString().ToLower() + ',"oc":true,"rgb":true}'
            }
            "/probe" {
                $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $probeScript
            }
            "/telemetry" {
                $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$scriptDir\ProbeLib\system.ps1'
`$t = Get-PcverseDeepTelemetry
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
            "/oc/status" {
                $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$ocScript'
`$s = Get-PcverseOcState
`$p = Get-PcverseOcStorePath
@{ state = `$s; baseline_exists = (Test-Path `$p); baseline_path = `$p } | ConvertTo-Json -Depth 5 -Compress }
"@
            }
            "/oc/apply" {
                if ($req.HttpMethod -ne 'POST') { $code = 405; $body = '{"error":"POST required"}'; break }
                $raw = Read-RequestBody $req
                if (-not $raw) { $code = 400; $body = '{"error":"empty body"}'; break }
                $tmpPlan = Join-Path $env:TEMP ("pcverse_oc_plan_" + [guid]::NewGuid().ToString("n") + ".json")
                try {
                    [System.IO.File]::WriteAllText($tmpPlan, $raw, [System.Text.UTF8Encoding]::new($false))
                    $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$ocScript'
`$plan = Get-Content '$tmpPlan' -Raw | ConvertFrom-Json
Invoke-PcverseOverclockApply -Plan `$plan | ConvertTo-Json -Depth 8 -Compress }
"@
                } finally {
                    Remove-Item $tmpPlan -Force -ErrorAction SilentlyContinue
                }
            }
            "/oc/rollback" {
                if ($req.HttpMethod -ne 'POST') { $code = 405; $body = '{"error":"POST required"}'; break }
                $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$ocScript'
Invoke-PcverseOverclockRollback | ConvertTo-Json -Depth 6 -Compress }
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
                $tmp = Join-Path $env:TEMP ("pcverse_rgb_" + [guid]::NewGuid().ToString("n") + ".json")
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
                $tmp = Join-Path $env:TEMP ("pcverse_lcd_" + [guid]::NewGuid().ToString("n") + ".json")
                try {
                    [System.IO.File]::WriteAllText($tmp, $raw, [System.Text.UTF8Encoding]::new($false))
                    $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$rgbScript'
`$j = Get-Content '$tmp' -Raw | ConvertFrom-Json
`$bytes = [Convert]::FromBase64String(`$j.gif_base64)
Save-PcverseLcdGif -DeviceId `$j.device_id -Bytes `$bytes -ExpectedW ([int]`$j.expected_w) -ExpectedH ([int]`$j.expected_h) | ConvertTo-Json -Depth 6 -Compress }
"@
                } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
            }
            "/rgb/vakhsh" {
                if ($req.HttpMethod -ne 'POST') { $code = 405; $body = '{"error":"POST required"}'; break }
                $raw = Read-RequestBody $req
                $tmp = Join-Path $env:TEMP ("pcverse_rgbv_" + [guid]::NewGuid().ToString("n") + ".json")
                try {
                    if ($raw) { [System.IO.File]::WriteAllText($tmp, $raw, [System.Text.UTF8Encoding]::new($false)) } else { '{}' | Set-Content $tmp }
                    $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$vakhshScript'
. '$scriptDir\ProbeLib\system.ps1'
`$payload = Get-Content '$tmp' -Raw | ConvertFrom-Json
`$scan = Get-RgbDeviceScan
`$tel = @{}
if (`$payload.telemetry) { `$tel = `$payload.telemetry } else {
  `$t = Get-PcverseDeepTelemetry
  `$tel = @{ cpu_temp = `$t.cpu.thermal.package_c; gpu_temp = `$t.gpu.thermal.core_c; cpu = `$t.cpu; gpu = `$t.gpu }
}
if (`$payload.plan) { Invoke-VakhshOrchestrate -Payload `$payload | ConvertTo-Json -Depth 12 -Compress }
else { Invoke-VakhshRgbAuto -Telemetry `$tel -Scan `$scan | ConvertTo-Json -Depth 10 -Compress }
"@
                } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
            }
            "/vakhsh/orchestrate" {
                if ($req.HttpMethod -ne 'POST') { $code = 405; $body = '{"error":"POST required"}'; break }
                $raw = Read-RequestBody $req
                if (-not $raw) { $code = 400; $body = '{"error":"empty body"}'; break }
                $tmp = Join-Path $env:TEMP ("pcverse_vkh_" + [guid]::NewGuid().ToString("n") + ".json")
                try {
                    [System.IO.File]::WriteAllText($tmp, $raw, [System.Text.UTF8Encoding]::new($false))
                    $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$vakhshScript'
`$payload = Get-Content '$tmp' -Raw | ConvertFrom-Json
Invoke-VakhshOrchestrate -Payload `$payload | ConvertTo-Json -Depth 12 -Compress }
"@
                } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
            }
            "/bench/catalog" {
                $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$benchScript'
@{ benchmarks = (Get-PcverseBenchmarkCatalog) } | ConvertTo-Json -Depth 6 -Compress }
"@
            }
            "/bench/run" {
                if ($req.HttpMethod -ne 'POST') { $code = 405; $body = '{"error":"POST required"}'; break }
                $raw = Read-RequestBody $req
                $tmp = Join-Path $env:TEMP ("pcverse_bench_" + [guid]::NewGuid().ToString("n") + ".json")
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
Invoke-PcverseBenchmark -Id `$id -Options `$opts | ConvertTo-Json -Depth 8 -Compress }
"@
                } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
            }
            "/stress/catalog" {
                $body = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command @"
& { . '$stressScript'
@{ stress = (Get-PcverseStressCatalog) } | ConvertTo-Json -Depth 6 -Compress }
"@
            }
            "/stress/run" {
                if ($req.HttpMethod -ne 'POST') { $code = 405; $body = '{"error":"POST required"}'; break }
                $raw = Read-RequestBody $req
                $tmp = Join-Path $env:TEMP ("pcverse_stress_" + [guid]::NewGuid().ToString("n") + ".json")
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
Invoke-PcverseStress -Id `$id -Options `$opts | ConvertTo-Json -Depth 8 -Compress }
"@
                } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
            }
            default {
                $code = 404
                $body = '{"error":"not found","routes":["/health","/probe","/telemetry","/telemetry/history","/oc/status","/oc/apply","/oc/rollback","/rgb/scan","/rgb/apply","/rgb/lcd","/rgb/vakhsh","/vakhsh/orchestrate","/bench/catalog","/bench/run","/stress/catalog","/stress/run"]}'
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
