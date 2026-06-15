function Get-PcverseBenchmarkCatalog {
    return @(
        @{ id = 'cpu'; label = 'CPU benchmark'; seconds_default = 5; max_seconds = 30 }
        @{ id = 'memory'; label = 'Memory bandwidth'; seconds_default = 5; max_seconds = 20 }
        @{ id = 'storage'; label = 'Storage benchmark'; seconds_default = 10; max_seconds = 60 }
    )
}

function Invoke-PcverseCpuBenchmark {
    param([int]$Seconds = 5)
    $Seconds = [Math]::Max(3, [Math]::Min(30, $Seconds))
    $threads = [Environment]::ProcessorCount
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
        label = 'PCVerse CPU benchmark'
        duration_s = [math]::Round($sw.Elapsed.TotalSeconds, 2)
        score = $score
        unit = 'Mops/s'
        threads = $threads
        replaces = @('Cinebench', 'CPU-Z Benchmark', 'Linpack Xtreme')
    }
}

function Invoke-PcverseMemoryBenchmark {
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
        label = 'PCVerse memory bandwidth'
        duration_s = [math]::Round($sw.Elapsed.TotalSeconds, 2)
        score = $mbps
        unit = 'MB/s'
        buffer_mb = $sizeMb
        replaces = @('PassMark RAM', 'AIDA64 Cache & Memory')
    }
}

function Invoke-PcverseStorageBenchmark {
    param([string]$Drive = '')
    if (-not $Drive) { $Drive = $env:SystemDrive.TrimEnd(':') }
    $Drive = $Drive.TrimEnd(':').ToUpper()
    $seqRead = $null
    $seqWrite = $null
    $method = 'file_copy'
    if (Get-Command winsat -ErrorAction SilentlyContinue) {
        try {
            $raw = & winsat disk -drive $Drive 2>&1 | Out-String
            if ($raw -match 'Disk\s+Sequential\s+64\.0\s+Read\s+(\d+\.?\d*)') { $seqRead = [double]$Matches[1] }
            if ($raw -match 'Disk\s+Sequential\s+64\.0\s+Write\s+(\d+\.?\d*)') { $seqWrite = [double]$Matches[1] }
            if ($seqRead -or $seqWrite) { $method = 'winsat' }
        } catch {}
    }
    if (-not $seqRead -and -not $seqWrite) {
        $tmp = Join-Path $env:TEMP ("pcverse_bench_" + [guid]::NewGuid().ToString('n') + ".bin")
        try {
            $chunk = 4MB
            $total = 32MB
            $data = New-Object byte[] $chunk
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $stream = [System.IO.File]::Create($tmp)
            for ($w = 0; $w -lt ($total / $chunk); $w++) { $stream.Write($data, 0, $data.Length) }
            $stream.Close()
            $sw.Stop()
            $seqWrite = [math]::Round(($total / 1MB) / $sw.Elapsed.TotalSeconds, 1)
            $sw.Restart()
            $null = [System.IO.File]::ReadAllBytes($tmp)
            $sw.Stop()
            $seqRead = [math]::Round(($total / 1MB) / $sw.Elapsed.TotalSeconds, 1)
        } finally {
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
    }
    return @{
        id = 'storage'
        label = 'PCVerse storage benchmark'
        drive = $Drive
        method = $method
        seq_read_mbps = $seqRead
        seq_write_mbps = $seqWrite
        unit = 'MB/s'
        replaces = @('CrystalDiskMark', 'DiskSpd', 'AS SSD Benchmark')
    }
}

function Invoke-PcverseBenchmark {
    param([string]$Id = 'cpu', [hashtable]$Options = @{})
    $seconds = 5
    if ($Options.ContainsKey('seconds') -and $Options.seconds) { $seconds = [int]$Options.seconds }
    $drive = ''
    if ($Options.ContainsKey('drive') -and $Options.drive) { $drive = [string]$Options.drive }
    switch ($Id.ToLower()) {
        'cpu' { return Invoke-PcverseCpuBenchmark -Seconds $seconds }
        'memory' { return Invoke-PcverseMemoryBenchmark -Seconds $seconds }
        'storage' { return Invoke-PcverseStorageBenchmark -Drive $drive }
        default { throw "Unknown benchmark: $Id" }
    }
}
