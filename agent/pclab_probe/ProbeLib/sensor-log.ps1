. "$PSScriptRoot\common.ps1"

<#
  Long-run sensor log (HWiNFO-style session JSONL) — hours/days, not only ring buffer.
#>

function Get-ProbeSensorLogDir {
    $dir = Join-Path $env:LOCALAPPDATA "PcLabKit\Probe\sensor-logs"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Get-ProbeSensorLogPath {
    $day = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
    return (Join-Path (Get-ProbeSensorLogDir) ("sensors_$day.jsonl"))
}

function Add-ProbeSensorLogSample {
    param($Sample)
    if (-not $Sample) { return }
    try {
        $path = Get-ProbeSensorLogPath
        $row = @{
            ts = if ($Sample.ts) { [string]$Sample.ts } else { (Get-Date).ToUniversalTime().ToString('o') }
            cpu_temp = $Sample.cpu_temp
            gpu_temp = $Sample.gpu_temp
            gpu_hotspot = $Sample.gpu_hotspot
            cpu_util = $Sample.cpu_util
            gpu_util = $Sample.gpu_util
            fan_rpm = $Sample.fan_rpm
            package_w = $Sample.package_w
            mem_used_gb = $Sample.mem_used_gb
        }
        $line = ($row | ConvertTo-Json -Compress -Depth 4)
        [System.IO.File]::AppendAllText($path, $line + [Environment]::NewLine)
    } catch {}
}

function Get-ProbeSensorLog {
    param(
        [double]$Hours = 24,
        [int]$Limit = 2000,
        [switch]$Csv
    )
    if ($Hours -le 0) { $Hours = 24 }
    if ($Limit -le 0) { $Limit = 500 }
    if ($Limit -gt 20000) { $Limit = 20000 }
    $cutoff = (Get-Date).ToUniversalTime().AddHours(-$Hours)
    $dir = Get-ProbeSensorLogDir
    $files = @(Get-ChildItem -Path $dir -Filter 'sensors_*.jsonl' -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($f in $files) {
        if ($rows.Count -ge $Limit) { break }
        try {
            $lines = Get-Content $f.FullName -ErrorAction SilentlyContinue
            for ($i = $lines.Count - 1; $i -ge 0; $i--) {
                if ($rows.Count -ge $Limit) { break }
                $line = $lines[$i]
                if (-not $line) { continue }
                try {
                    $j = $line | ConvertFrom-Json
                    $ts = $null
                    if ($j.ts) {
                        try { $ts = [datetime]::Parse([string]$j.ts).ToUniversalTime() } catch {}
                    }
                    if ($ts -and $ts -lt $cutoff) { continue }
                    $rows.Add($j)
                } catch {}
            }
        } catch {}
    }
    $ordered = @($rows | Sort-Object { $_.ts })
    if ($Csv) {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine('ts,cpu_temp,gpu_temp,gpu_hotspot,cpu_util,gpu_util,fan_rpm,package_w,mem_used_gb')
        foreach ($r in $ordered) {
            $vals = @(
                $r.ts, $r.cpu_temp, $r.gpu_temp, $r.gpu_hotspot, $r.cpu_util, $r.gpu_util, $r.fan_rpm, $r.package_w, $r.mem_used_gb
            ) | ForEach-Object { if ($null -eq $_) { '' } else { [string]$_ } }
            [void]$sb.AppendLine(($vals -join ','))
        }
        return @{
            ok = $true
            format = 'csv'
            hours = $Hours
            count = $ordered.Count
            csv = $sb.ToString()
            path = $dir
        }
    }
    return @{
        ok = $true
        format = 'json'
        hours = $Hours
        limit = $Limit
        count = $ordered.Count
        samples = $ordered
        path = $dir
        note = 'Long-run JSONL under %LOCALAPPDATA%\PcLabKit\Probe\sensor-logs — ring buffer remains for live UI.'
    }
}
