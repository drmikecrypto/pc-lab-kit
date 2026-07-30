function Get-ProbeBenchmarkCatalog {
    return @(
        @{ id = 'cpu'; label = 'CPU micro-bench'; seconds_default = 5; max_seconds = 30 }
        @{ id = 'cpu_mt'; label = 'CPU multi-thread'; seconds_default = 8; max_seconds = 45 }
        @{ id = 'memory'; label = 'Memory bandwidth'; seconds_default = 5; max_seconds = 20 }
        @{ id = 'storage'; label = 'Storage (DiskSpd/WinSAT)'; seconds_default = 10; max_seconds = 90 }
        @{ id = 'gpu'; label = 'GPU compute'; seconds_default = 8; max_seconds = 40 }
    )
}

function Invoke-ProbeCpuBenchmark {
    param([int]$Seconds = 5, [switch]$MultiThread)
    $Seconds = [Math]::Max(3, [Math]::Min(45, $Seconds))
    $threads = [Environment]::ProcessorCount
    if (-not $MultiThread) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $end = (Get-Date).AddSeconds($Seconds)
        $ops = 0L
        while ((Get-Date) -lt $end) {
            $acc = 0.0
            for ($i = 0; $i -lt 8000; $i++) {
                $acc += [Math]::Sin($i * 0.013) * [Math]::Cos($i * 0.007)
            }
            if ($acc -ne 0) { $ops++ }
        }
        $sw.Stop()
        $score = if ($sw.Elapsed.TotalSeconds -gt 0) { [math]::Round($ops / $sw.Elapsed.TotalSeconds, 2) } else { 0 }
        return @{
            id = 'cpu'
            label = 'PcLab CPU micro-bench'
            duration_s = [math]::Round($sw.Elapsed.TotalSeconds, 2)
            score = $score
            unit = 'Mops/s'
            threads = 1
            logical_processors = $threads
            method = 'single_thread_trig'
            replaces = @('Cinebench', 'CPU-Z Benchmark', 'Linpack Xtreme')
        }
    }

    $end = (Get-Date).AddSeconds($Seconds)
    $jobs = @()
    for ($t = 0; $t -lt $threads; $t++) {
        $jobs += Start-Job -ScriptBlock {
            param($until)
            $ops = 0L
            while ((Get-Date) -lt $until) {
                $acc = 0.0
                for ($i = 0; $i -lt 6000; $i++) {
                    $acc += [Math]::Sqrt(($i + 1) * 1.0001) * [Math]::Sin($i * 0.01)
                }
                if ($acc -ne 0) { $ops++ }
            }
            return $ops
        } -ArgumentList $end
    }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ((Get-Date) -lt $end) { Start-Sleep -Milliseconds 150 }
    $results = $jobs | Wait-Job | Receive-Job
    $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
    $sw.Stop()
    $totalOps = 0L
    foreach ($r in @($results)) { $totalOps += [long]$r }
    $score = if ($sw.Elapsed.TotalSeconds -gt 0) { [math]::Round($totalOps / $sw.Elapsed.TotalSeconds, 2) } else { 0 }
    return @{
        id = 'cpu_mt'
        label = 'PcLab CPU multi-thread'
        duration_s = [math]::Round($sw.Elapsed.TotalSeconds, 2)
        score = $score
        unit = 'Mops/s'
        threads = $threads
        method = 'multi_thread_jobs'
        replaces = @('Cinebench MT', 'Linpack Xtreme')
    }
}

function Invoke-ProbeMemoryBenchmark {
    param([int]$Seconds = 5)
    $Seconds = [Math]::Max(3, [Math]::Min(20, $Seconds))
    $sizeMb = 64
    $buf = New-Object byte[] ($sizeMb * 1MB)
    (New-Object Random).NextBytes($buf)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $end = (Get-Date).AddSeconds($Seconds)
    $bytes = 0L
    while ((Get-Date) -lt $end) {
        for ($i = 0; $i -lt $buf.Length; $i += 4096) {
            $buf[$i] = ($buf[$i] -bxor 0x5A)
        }
        $bytes += $buf.Length
    }
    $sw.Stop()
    $mbps = if ($sw.Elapsed.TotalSeconds -gt 0) { [math]::Round(($bytes / 1MB) / $sw.Elapsed.TotalSeconds, 1) } else { 0 }
    return @{
        id = 'memory'
        label = 'PcLab memory bandwidth'
        duration_s = [math]::Round($sw.Elapsed.TotalSeconds, 2)
        score = $mbps
        unit = 'MB/s'
        buffer_mb = $sizeMb
        replaces = @('PassMark RAM', 'AIDA64 Cache & Memory')
    }
}

function Find-ProbeDiskSpd {
    $candidates = @(
        (Join-Path $PSScriptRoot '..\tools\DiskSpd\diskspd.exe'),
        (Join-Path $PSScriptRoot '..\tools\diskspd.exe'),
        'diskspd.exe'
    )
    foreach ($c in $candidates) {
        if (Get-Command $c -ErrorAction SilentlyContinue) { return (Get-Command $c).Source }
        if (Test-Path $c) { return (Resolve-Path $c).Path }
    }
    return $null
}

function Invoke-ProbeStorageBenchmark {
    param([string]$Drive = '')
    if (-not $Drive) { $Drive = $env:SystemDrive.TrimEnd(':') }
    $Drive = $Drive.TrimEnd(':').ToUpper()
    $seqRead = $null
    $seqWrite = $null
    $rand4kRead = $null
    $rand4kWrite = $null
    $method = 'file_copy'

    $diskspd = Find-ProbeDiskSpd
    if ($diskspd) {
        $tmp = Join-Path $env:TEMP ("pclab_diskspd_" + [guid]::NewGuid().ToString('n') + ".dat")
        try {
            # Sequential write then read, then 4K random read (short)
            $null = & $diskspd -c64M -d3 -w100 -b64K -o4 -t1 "-f$tmp" 2>&1 | Out-String
            $outW = & $diskspd -d3 -w100 -b64K -o4 -t1 "-f$tmp" 2>&1 | Out-String
            $outR = & $diskspd -d3 -b64K -o4 -t1 "-f$tmp" 2>&1 | Out-String
            $out4 = & $diskspd -d3 -b4K -o8 -t2 -r "-f$tmp" 2>&1 | Out-String
            if ($outW -match 'total:\s+\d+\s+\|\s+\d+\s+\|\s+([\d\.]+)') { $seqWrite = [double]$Matches[1] }
            if ($outR -match 'total:\s+\d+\s+\|\s+\d+\s+\|\s+([\d\.]+)') { $seqRead = [double]$Matches[1] }
            if ($out4 -match 'total:\s+\d+\s+\|\s+\d+\s+\|\s+([\d\.]+)') { $rand4kRead = [double]$Matches[1] }
            if ($seqRead -or $seqWrite) { $method = 'diskspd' }
        } catch {} finally {
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not $seqRead -and -not $seqWrite -and (Get-Command winsat -ErrorAction SilentlyContinue)) {
        try {
            $raw = & winsat disk -drive $Drive 2>&1 | Out-String
            if ($raw -match 'Disk\s+Sequential\s+64\.0\s+Read\s+(\d+\.?\d*)') { $seqRead = [double]$Matches[1] }
            if ($raw -match 'Disk\s+Sequential\s+64\.0\s+Write\s+(\d+\.?\d*)') { $seqWrite = [double]$Matches[1] }
            if ($raw -match 'Disk\s+Random\s+16\.0\s+Read\s+(\d+\.?\d*)') { $rand4kRead = [double]$Matches[1] }
            if ($seqRead -or $seqWrite) { $method = 'winsat' }
        } catch {}
    }
    if (-not $seqRead -and -not $seqWrite) {
        $tmp = Join-Path $env:TEMP ("pclab_bench_" + [guid]::NewGuid().ToString('n') + ".bin")
        try {
            $chunk = 4MB
            $total = 64MB
            $data = New-Object byte[] $chunk
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $stream = [System.IO.File]::Create($tmp)
            for ($w = 0; $w -lt ($total / $chunk); $w++) { $stream.Write($data, 0, $data.Length) }
            $stream.Flush(); $stream.Close()
            $sw.Stop()
            $seqWrite = [math]::Round(($total / 1MB) / $sw.Elapsed.TotalSeconds, 1)
            $sw.Restart()
            $null = [System.IO.File]::ReadAllBytes($tmp)
            $sw.Stop()
            $seqRead = [math]::Round(($total / 1MB) / $sw.Elapsed.TotalSeconds, 1)
            $method = 'file_copy'
        } finally {
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
    }
    return @{
        id = 'storage'
        label = 'PcLab storage benchmark'
        drive = $Drive
        method = $method
        diskspd_available = [bool]$diskspd
        seq_read_mbps = $seqRead
        seq_write_mbps = $seqWrite
        rand_4k_read_mbps = $rand4kRead
        rand_4k_write_mbps = $rand4kWrite
        unit = 'MB/s'
        replaces = @('CrystalDiskMark', 'DiskSpd', 'AS SSD Benchmark')
    }
}

function Invoke-ProbeGpuBenchmark {
    param([int]$Seconds = 8)
    $Seconds = [Math]::Max(3, [Math]::Min(40, $Seconds))
    $method = 'inventory'
    $score = 0
    $detail = @{}

    if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
        try {
            $q = & nvidia-smi --query-gpu=name,memory.total,clocks.max.sm,clocks.max.mem,utilization.gpu --format=csv,noheader,nounits 2>$null
            if ($q) {
                $p = ($q -split "`n")[0] -split ",\s*"
                $mem = [double]$p[1]
                $sm = [double]$p[2]
                $memClk = [double]$p[3]
                # Rough open compute index (not a clone of 3DMark)
                $score = [math]::Round(($mem / 1024.0) * 120 + ($sm / 10.0) + ($memClk / 20.0), 1)
                $method = 'nvidia_smi_index'
                $detail = @{
                    name = $p[0].Trim()
                    memory_mib = $mem
                    sm_clock_mhz = $sm
                    mem_clock_mhz = $memClk
                }
            }
        } catch {}
    }

    # Lightweight CPU-side "compute" loop as fallback / complement (Vulkan SDK not bundled)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $end = (Get-Date).AddSeconds([Math]::Min(4, $Seconds))
    $ops = 0L
    while ((Get-Date) -lt $end) {
        $acc = 0.0
        for ($i = 0; $i -lt 12000; $i++) {
            $acc += [Math]::Tan(($i % 90) + 0.01) * 0.0001
        }
        if ($acc -ne 0) { $ops++ }
    }
    $sw.Stop()
    $cpuSide = if ($sw.Elapsed.TotalSeconds -gt 0) { [math]::Round($ops / $sw.Elapsed.TotalSeconds, 2) } else { 0 }
    if ($score -le 0) {
        $score = $cpuSide
        $method = 'host_compute_proxy'
    }

    return @{
        id = 'gpu'
        label = 'PcLab GPU compute'
        duration_s = [math]::Round($sw.Elapsed.TotalSeconds, 2)
        score = $score
        unit = 'index'
        method = $method
        host_compute_mops = $cpuSide
        detail = $detail
        note = 'Uses NVML/nvidia-smi when present; full Vulkan compute ships with native core. Not a 3DMark clone.'
        replaces = @('Basemark GPU', 'SPECviewperf (workflow)')
    }
}

function Invoke-ProbeBenchmark {
    param([string]$Id = 'cpu', [hashtable]$Options = @{})
    $seconds = 5
    if ($Options.ContainsKey('seconds') -and $Options.seconds) { $seconds = [int]$Options.seconds }
    $drive = ''
    if ($Options.ContainsKey('drive') -and $Options.drive) { $drive = [string]$Options.drive }
    switch ($Id.ToLower()) {
        'cpu' { return Invoke-ProbeCpuBenchmark -Seconds $seconds }
        'cpu_mt' { return Invoke-ProbeCpuBenchmark -Seconds $seconds -MultiThread }
        'memory' { return Invoke-ProbeMemoryBenchmark -Seconds $seconds }
        'storage' { return Invoke-ProbeStorageBenchmark -Drive $drive }
        'gpu' { return Invoke-ProbeGpuBenchmark -Seconds $seconds }
        default { throw "Unknown benchmark: $Id" }
    }
}
