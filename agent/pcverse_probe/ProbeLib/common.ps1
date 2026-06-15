# PCVerse Probe shared helpers
function Get-CimSafe {
    param([string]$Class, [string]$Filter = "", [string]$Namespace = "")
    try {
        $params = @{ ClassName = $Class }
        if ($Filter) { $params.Filter = $Filter }
        if ($Namespace) { $params.Namespace = $Namespace }
        return Get-CimInstance @params
    } catch { return @() }
}

function KelvinToC {
    param($k)
    if ($null -eq $k -or $k -le 0) { return $null }
    return [math]::Round(($k / 10.0) - 273.15, 1)
}

function Get-CounterSafe {
    param([string[]]$Paths, [int]$SampleInterval = 1)
    try {
        $r = Get-Counter -Counter $Paths -SampleInterval $SampleInterval -MaxSamples 1 -ErrorAction Stop
        $out = @{}
        foreach ($s in $r.CounterSamples) {
            $short = ($s.Path -replace '^\\\\[^\\]+\\', '\\').ToLower()
            $out[$short] = [math]::Round([double]$s.CookedValue, 3)
        }
        return $out
    } catch { return @{} }
}

function Parse-FeatureSet {
    param([uint32]$FeatureSet)
    $bits = @{
        fpu     = 0x0001; vme = 0x0002; de = 0x0004; pse = 0x0008
        tsc     = 0x0010; msr = 0x0020; pae = 0x0040; mce = 0x0080
        cx8     = 0x0100; apic = 0x0200; sep = 0x0800; mtrr = 0x1000
        pge     = 0x2000; mca = 0x4000; cmov = 0x8000; pat = 0x10000
        pse36   = 0x20000; psn = 0x40000; clfs = 0x80000; ds = 0x200000
        acpi    = 0x400000; mmx = 0x800000; fxsr = 0x1000000; sse = 0x2000000
        sse2    = 0x4000000; ss = 0x8000000; htt = 0x10000000; tm = 0x20000000
        pbe     = 0x80000000
    }
    $found = @()
    foreach ($k in $bits.Keys) {
        if ($FeatureSet -band $bits[$k]) { $found += $k.ToUpper() }
    }
    return $found
}

function Guess-InstructionSets {
    param([string]$Model, $CpuWmi = $null)
    $sets = @()
    $m = $Model.ToLower()
    if ($m -match 'intel|amd|core|ryzen|xeon') {
        $sets += @('SSE', 'SSE2', 'SSE3', 'SSSE3', 'SSE4.1', 'SSE4.2', 'AES-NI')
    }
    if ($m -match 'avx512|xeon|core i[79]|ryzen 9|threadripper|epyc') { $sets += 'AVX-512' }
    elseif ($m -match 'ryzen|core i[357]|xeon|threadripper|fx-|i[357]-') { $sets += 'AVX2' }
    if ($m -match 'intel|amd') { $sets += 'AVX' }
    if ($CpuWmi) {
        if ($CpuWmi.VMMonitorModeExtensions) { $sets += 'VT-x' }
        if ($CpuWmi.SecondLevelAddressTranslationExtensions) { $sets += 'SLAT/EPT' }
        if ($CpuWmi.NumberOfLogicalProcessors -gt $CpuWmi.NumberOfCores) { $sets += 'SMT/HT' }
    }
    return ($sets | Select-Object -Unique)
}
