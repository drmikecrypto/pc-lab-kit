# Native benchmark arena — CPU / memory / storage / GPU (PcLabVkBench primary).
# Dot-sourced from PcLabProbeServe.ps1

function Get-ProbeBenchmarkCatalog {
    return @(
        @{ id = 'cpu'; label = 'Native CPU single-thread'; seconds_default = 5; max_seconds = 30 }
        @{ id = 'cpu_mt'; label = 'Native CPU multi-thread'; seconds_default = 8; max_seconds = 45 }
        @{ id = 'cpu_cache'; label = 'Native CPU cache/latency'; seconds_default = 6; max_seconds = 30 }
        @{ id = 'memory'; label = 'Native memory bandwidth'; seconds_default = 5; max_seconds = 20 }
        @{ id = 'storage'; label = 'Native storage (DiskSpd CDM)'; seconds_default = 10; max_seconds = 90 }
        @{ id = 'gpu'; label = 'Native GPU compute'; seconds_default = 8; max_seconds = 40 }
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
            label = 'PcLab native CPU single-thread'
            duration_s = [math]::Round($sw.Elapsed.TotalSeconds, 2)
            score = $score
            unit = 'Mops/s'
            threads = 1
            logical_processors = $threads
            method = 'single_thread_trig'
            engine = 'native_cpu_st'
            replaces = @('Cinebench ST', 'CPU-Z Benchmark', 'Linpack Xtreme')
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
        label = 'PcLab native CPU multi-thread'
        duration_s = [math]::Round($sw.Elapsed.TotalSeconds, 2)
        score = $score
        unit = 'Mops/s'
        threads = $threads
        method = 'multi_thread_jobs'
        engine = 'native_cpu_mt'
        replaces = @('Cinebench MT', 'Linpack Xtreme')
    }
}

function Invoke-ProbeCpuCacheBenchmark {
    param([int]$Seconds = 6)
    $Seconds = [Math]::Max(3, [Math]::Min(30, $Seconds))
    # Working-set sizes aim at L1 / L2 / L3-ish + DRAM (element = 8 bytes int64)
    $profiles = @(
        @{ name = 'l1'; kib = 32 }
        @{ name = 'l2'; kib = 256 }
        @{ name = 'l3'; kib = 4096 }
        @{ name = 'dram'; kib = 16384 }
    )
    $latenciesNs = @{}
    $scores = @{}
    $swAll = [System.Diagnostics.Stopwatch]::StartNew()
    $budgetPer = [Math]::Max(0.6, $Seconds / $profiles.Count)

    foreach ($p in $profiles) {
        $n = [Math]::Max(1024, [int](($p.kib * 1024) / 8))
        $arr = New-Object long[] $n
        # Coprime stride ring (fast init; still defeats simple prefetch)
        $stride = 17L
        if (($n % 17) -eq 0) { $stride = 19L }
        for ($i = 0L; $i -lt $n; $i++) {
            $arr[$i] = ($i + $stride) % $n
        }

        $steps = 0L
        $end = (Get-Date).AddSeconds($budgetPer)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $cursor = 0L
        while ((Get-Date) -lt $end) {
            for ($k = 0; $k -lt 4096; $k++) {
                $cursor = $arr[$cursor]
            }
            $steps += 4096
        }
        $sw.Stop()
        $ns = if ($steps -gt 0 -and $sw.Elapsed.TotalSeconds -gt 0) {
            [math]::Round(($sw.Elapsed.TotalSeconds * 1e9) / $steps, 2)
        } else { 0 }
        $latenciesNs[$p.name] = $ns
        # Higher score = lower latency (index)
        $scores[$p.name] = if ($ns -gt 0) { [math]::Round(10000.0 / $ns, 2) } else { 0 }
    }
    $swAll.Stop()
    $composite = [math]::Round(
        (0.35 * [double]$scores['l1']) +
        (0.30 * [double]$scores['l2']) +
        (0.25 * [double]$scores['l3']) +
        (0.10 * [double]$scores['dram']), 2)

    return @{
        id = 'cpu_cache'
        label = 'PcLab native CPU cache / latency'
        duration_s = [math]::Round($swAll.Elapsed.TotalSeconds, 2)
        score = $composite
        unit = 'index'
        method = 'pointer_chase'
        engine = 'native_cpu_cache'
        latency_ns = $latenciesNs
        sub_scores = $scores
        replaces = @('AIDA64 Cache', 'SiSoftware Sandra Cache')
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
        label = 'PcLab native memory bandwidth'
        duration_s = [math]::Round($sw.Elapsed.TotalSeconds, 2)
        score = $mbps
        bandwidth_mb_s = $mbps
        unit = 'MB/s'
        buffer_mb = $sizeMb
        engine = 'native_memory'
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

function Find-ProbeVkBench {
    $candidates = @(
        (Join-Path $PSScriptRoot '..\PcLabVkBench.exe'),
        (Join-Path $PSScriptRoot '..\tools\PcLabVkBench\PcLabVkBench.exe'),
        (Join-Path $PSScriptRoot '..\PcLabVkBench\bin\PcLabVkBench.exe')
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return (Resolve-Path $c).Path }
    }
    return $null
}

function Get-DiskSpdTotalMbps {
    param([string]$Output)
    # DiskSpd table: total | MiB/s in third numeric column of "total:" line
    if ($Output -match 'total:\s+\d+\s+\|\s+\d+\s+\|\s+([\d\.]+)') {
        return [double]$Matches[1]
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
    $profiles = $null
    $method = 'file_copy'

    $diskspd = Find-ProbeDiskSpd
    if ($diskspd) {
        $tmp = Join-Path $env:TEMP ("pclab_diskspd_" + [guid]::NewGuid().ToString('n') + ".dat")
        try {
            # Create 1 GiB test file once (CDM-like working set; shorter duration for lab UX)
            $null = & $diskspd -c1G -d1 -w100 -b1M -o1 -t1 "-f$tmp" 2>&1 | Out-String

            # CrystalDiskMark-like presets (read then write where applicable)
            $seq1mQ8R = & $diskspd -d5 -b1M -o8 -t1 "-f$tmp" 2>&1 | Out-String
            $seq1mQ8W = & $diskspd -d5 -w100 -b1M -o8 -t1 "-f$tmp" 2>&1 | Out-String
            $seq1mQ1R = & $diskspd -d5 -b1M -o1 -t1 "-f$tmp" 2>&1 | Out-String
            $seq1mQ1W = & $diskspd -d5 -w100 -b1M -o1 -t1 "-f$tmp" 2>&1 | Out-String
            $rnd4kQ32R = & $diskspd -d5 -b4K -o32 -t1 -r "-f$tmp" 2>&1 | Out-String
            $rnd4kQ32W = & $diskspd -d5 -w100 -b4K -o32 -t1 -r "-f$tmp" 2>&1 | Out-String
            $rnd4kQ1R = & $diskspd -d5 -b4K -o1 -t1 -r "-f$tmp" 2>&1 | Out-String
            $rnd4kQ1W = & $diskspd -d5 -w100 -b4K -o1 -t1 -r "-f$tmp" 2>&1 | Out-String

            $profiles = @{
                'SEQ1M_Q8T1' = @{
                    read_mbps = (Get-DiskSpdTotalMbps $seq1mQ8R)
                    write_mbps = (Get-DiskSpdTotalMbps $seq1mQ8W)
                }
                'SEQ1M_Q1T1' = @{
                    read_mbps = (Get-DiskSpdTotalMbps $seq1mQ1R)
                    write_mbps = (Get-DiskSpdTotalMbps $seq1mQ1W)
                }
                'RND4K_Q32T1' = @{
                    read_mbps = (Get-DiskSpdTotalMbps $rnd4kQ32R)
                    write_mbps = (Get-DiskSpdTotalMbps $rnd4kQ32W)
                }
                'RND4K_Q1T1' = @{
                    read_mbps = (Get-DiskSpdTotalMbps $rnd4kQ1R)
                    write_mbps = (Get-DiskSpdTotalMbps $rnd4kQ1W)
                }
            }
            $seqRead = $profiles['SEQ1M_Q8T1'].read_mbps
            $seqWrite = $profiles['SEQ1M_Q8T1'].write_mbps
            $rand4kRead = $profiles['RND4K_Q32T1'].read_mbps
            $rand4kWrite = $profiles['RND4K_Q32T1'].write_mbps
            if ($seqRead -or $seqWrite -or $rand4kRead) { $method = 'diskspd_cdm' }
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

    $score = 0.0
    if ($seqRead) { $score += [double]$seqRead }
    if ($seqWrite) { $score += [double]$seqWrite }
    if ($rand4kRead) { $score += [double]$rand4kRead * 8 }
    $score = [math]::Round($score, 1)

    return @{
        id = 'storage'
        label = 'PcLab native storage (CDM-like)'
        drive = $Drive
        method = $method
        engine = if ($method -eq 'diskspd_cdm') { 'diskspd_cdm' } else { $method }
        diskspd_available = [bool]$diskspd
        score = $score
        seq_read_mbps = $seqRead
        seq_write_mbps = $seqWrite
        seq_read_mb_s = $seqRead
        seq_write_mb_s = $seqWrite
        rand_4k_read_mbps = $rand4kRead
        rand_4k_write_mbps = $rand4kWrite
        profiles = $profiles
        unit = 'MB/s'
        note = 'Place Microsoft DiskSpd at agent/pclab_probe/tools/DiskSpd/diskspd.exe for CDM-like SEQ1M/RND4K presets.'
        replaces = @('CrystalDiskMark', 'DiskSpd', 'AS SSD Benchmark')
    }
}

function Invoke-ProbeGpuBenchmarkFallback {
    param([int]$Seconds = 8)
    $method = 'inventory'
    $score = 0
    $detail = @{}
    $fallback = 'nvml_or_host'

    if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
        try {
            $q = & nvidia-smi --query-gpu=name,memory.total,clocks.max.sm,clocks.max.mem,utilization.gpu --format=csv,noheader,nounits 2>$null
            if ($q) {
                $p = ($q -split "`n")[0] -split ",\s*"
                $mem = [double]$p[1]
                $sm = [double]$p[2]
                $memClk = [double]$p[3]
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
        label = 'PcLab GPU compute (fallback)'
        duration_s = [math]::Round($sw.Elapsed.TotalSeconds, 2)
        score = $score
        unit = 'index'
        method = $method
        engine = $method
        primary = $false
        fallback = $fallback
        host_compute_mops = $cpuSide
        detail = $detail
        note = 'Fallback path — PcLabVkBench.exe missing. Install native GPU helper for Vulkan/D3D11 compute scores.'
        replaces = @('Basemark GPU', 'SPECviewperf (workflow)')
    }
}

function Invoke-ProbeGpuBenchmark {
    param([int]$Seconds = 8)
    $Seconds = [Math]::Max(3, [Math]::Min(40, $Seconds))
    $vk = Find-ProbeVkBench
    if ($vk) {
        try {
            $raw = & $vk --seconds $Seconds 2>&1 | Out-String
            $line = ($raw -split "`r?`n" | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1)
            if ($line) {
                $j = $line | ConvertFrom-Json
                if ($j.ok -eq $true -or $j.score) {
                    return @{
                        id = 'gpu'
                        label = 'PcLab native GPU compute'
                        duration_s = [double]($j.duration_s)
                        score = [math]::Round([double]$j.score, 1)
                        gflops = if ($null -ne $j.gflops) { [double]$j.gflops } else { $null }
                        unit = if ($j.unit) { [string]$j.unit } else { 'index' }
                        method = [string]$j.engine
                        engine = [string]$j.engine
                        api = [string]$j.api
                        vulkan_available = [bool]$j.vulkan_available
                        device = [string]$j.device
                        adapter = [string]$j.adapter
                        primary = $true
                        fallback = $false
                        detail = @{
                            name = [string]$j.device
                            dispatches = $j.dispatches
                            elements = $j.elements
                        }
                        note = if ($j.note) { [string]$j.note } else { 'Native GPU compute via PcLabVkBench (D3D11 CS; Vulkan ICD when present).' }
                        replaces = @('Basemark GPU', 'FurMark (score only)', '3DMark (compute workflow)')
                    }
                }
            }
        } catch {
            # fall through to NVML/host
        }
    }
    return Invoke-ProbeGpuBenchmarkFallback -Seconds $Seconds
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
        'cpu_cache' { return Invoke-ProbeCpuCacheBenchmark -Seconds $seconds }
        'memory' { return Invoke-ProbeMemoryBenchmark -Seconds $seconds }
        'storage' { return Invoke-ProbeStorageBenchmark -Drive $drive }
        'gpu' { return Invoke-ProbeGpuBenchmark -Seconds $seconds }
        default { throw "Unknown benchmark: $Id" }
    }
}
