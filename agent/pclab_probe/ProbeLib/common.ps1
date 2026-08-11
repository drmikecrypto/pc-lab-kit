# PcLab Probe shared helpers
function Get-CimSafe {
    param([string]$Class, [string]$Filter = "", [string]$Namespace = "")
    try {
        $params = @{ ClassName = $Class; ErrorAction = 'Stop' }
        if ($Filter) { $params.Filter = $Filter }
        if ($Namespace) { $params.Namespace = $Namespace }
        return @(Get-CimInstance @params)
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

# ---------------------------------------------------------------------------
# Win32 interop
# ---------------------------------------------------------------------------

<#
 Compiled once per session. Everything here is admin-free:
   IsProcessorFeaturePresent  - real ISA support instead of guessing from the model name
   GetSystemCpuSetInformation - per-logical-processor efficiency class, which is how
                                Intel P-cores and E-cores (and AMD's classic vs compact
                                Zen cores) are told apart without CPUID access
   IsUserAnAdmin              - LHM needs elevation to read CPU die temperatures
#>
function Initialize-ProbeNativeInterop {
    if ('ProbeNative' -as [type]) { return }
    Add-Type -ErrorAction SilentlyContinue -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class ProbeNative
{
    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool IsProcessorFeaturePresent(uint feature);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetSystemCpuSetInformation(
        IntPtr information, uint bufferLength, out uint returnedLength, IntPtr process, uint flags);

    [DllImport("kernel32.dll")]
    public static extern IntPtr GetCurrentProcess();

    public struct CpuSetEntry
    {
        public int LogicalProcessorIndex;
        public int CoreIndex;
        public int EfficiencyClass;
        public int NumaNode;
        public int LastLevelCacheIndex;
        public int Group;
    }

    // SYSTEM_CPU_SET_INFORMATION: Size(4) Type(4) Id(4) Group(2) LogicalProcessorIndex(1)
    // CoreIndex(1) LastLevelCacheIndex(1) NumaNodeIndex(1) EfficiencyClass(1) AllFlags(1)
    public static CpuSetEntry[] GetCpuSets()
    {
        uint needed = 0;
        GetSystemCpuSetInformation(IntPtr.Zero, 0, out needed, GetCurrentProcess(), 0);
        if (needed == 0) return new CpuSetEntry[0];

        IntPtr buffer = Marshal.AllocHGlobal((int)needed);
        try
        {
            uint written = 0;
            if (!GetSystemCpuSetInformation(buffer, needed, out written, GetCurrentProcess(), 0))
                return new CpuSetEntry[0];

            var list = new System.Collections.Generic.List<CpuSetEntry>();
            int offset = 0;
            while (offset < (int)written)
            {
                int size = Marshal.ReadInt32(buffer, offset);
                if (size <= 0) break;
                int type = Marshal.ReadInt32(buffer, offset + 4);
                if (type == 0)
                {
                    list.Add(new CpuSetEntry
                    {
                        Group = Marshal.ReadInt16(buffer, offset + 12),
                        LogicalProcessorIndex = Marshal.ReadByte(buffer, offset + 14),
                        CoreIndex = Marshal.ReadByte(buffer, offset + 15),
                        LastLevelCacheIndex = Marshal.ReadByte(buffer, offset + 16),
                        NumaNode = Marshal.ReadByte(buffer, offset + 17),
                        EfficiencyClass = Marshal.ReadByte(buffer, offset + 18)
                    });
                }
                offset += size;
            }
            return list.ToArray();
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }
}
"@
}

function Test-ProbeElevated {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Get-ProbeProcessorFeatures {
    Initialize-ProbeNativeInterop
    if (-not ('ProbeNative' -as [type])) { return @() }

    $features = [ordered]@{
        'SSE'      = 6
        'SSE2'     = 10
        'SSE3'     = 13
        'SSSE3'    = 36
        'SSE4.1'   = 37
        'SSE4.2'   = 38
        'AVX'      = 39
        'AVX2'     = 40
        'AVX-512F' = 41
        'RDRAND'   = 28
        'RDTSCP'   = 32
        'RDPID'    = 33
        'CX16'     = 14
        'NX/DEP'   = 12
        'SLAT'     = 20
        'VT-x/AMD-V (firmware)' = 21
    }
    $out = @()
    foreach ($k in $features.Keys) {
        try {
            if ([ProbeNative]::IsProcessorFeaturePresent([uint32]$features[$k])) { $out += $k }
        } catch {}
    }
    return @($out)
}

<#
 Group logical processors by physical core and efficiency class.
 EfficiencyClass 0 is the most power-efficient tier, so the highest class is the
 performance tier. A single class means a homogeneous CPU.
#>
function Get-ProbeCoreTopology {
    Initialize-ProbeNativeInterop
    $result = @{
        hybrid           = $false
        physical_cores   = 0
        logical_cores    = 0
        performance_cores = 0
        efficiency_cores = 0
        classes          = @()
        smt_cores        = 0
    }
    if (-not ('ProbeNative' -as [type])) { return $result }

    $sets = @()
    try { $sets = @([ProbeNative]::GetCpuSets()) } catch { return $result }
    if ($sets.Count -eq 0) { return $result }

    $result.logical_cores = $sets.Count
    $byCore = @{}
    foreach ($s in $sets) {
        $key = "$($s.Group):$($s.CoreIndex)"
        if (-not $byCore.ContainsKey($key)) { $byCore[$key] = @() }
        $byCore[$key] += $s
    }
    $result.physical_cores = $byCore.Keys.Count

    $classCounts = @{}
    foreach ($key in $byCore.Keys) {
        $ec = $byCore[$key][0].EfficiencyClass
        if (-not $classCounts.ContainsKey($ec)) { $classCounts[$ec] = @{ cores = 0; threads = 0 } }
        $classCounts[$ec].cores++
        $classCounts[$ec].threads += $byCore[$key].Count
        if ($byCore[$key].Count -gt 1) { $result.smt_cores++ }
    }

    $classes = @()
    foreach ($ec in ($classCounts.Keys | Sort-Object -Descending)) {
        $classes += @{
            efficiency_class = [int]$ec
            cores            = $classCounts[$ec].cores
            threads          = $classCounts[$ec].threads
        }
    }
    $result.classes = @($classes)

    if ($classCounts.Keys.Count -gt 1) {
        $result.hybrid = $true
        $top = ($classCounts.Keys | Measure-Object -Maximum).Maximum
        foreach ($ec in $classCounts.Keys) {
            if ($ec -eq $top) { $result.performance_cores += $classCounts[$ec].cores }
            else { $result.efficiency_cores += $classCounts[$ec].cores }
        }
    } else {
        $result.performance_cores = $result.physical_cores
    }

    return $result
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

<#
 Typed field for Hardware Reference: never pretend a heuristic is silicon-measured.
 confidence: measured | vendor_table | heuristic | unavailable
#>
function New-ProbeField {
    param(
        $Value,
        [ValidateSet('measured', 'vendor_table', 'heuristic', 'unavailable')]
        [string]$Confidence = 'measured',
        [string]$Source = '',
        [string]$Note = ''
    )
    if ($null -eq $Value -or "$Value" -eq '') {
        return @{
            value      = $null
            confidence = 'unavailable'
            source     = if ($Source) { $Source } else { $null }
            note       = if ($Note) { $Note } else { $null }
        }
    }
    return @{
        value      = $Value
        confidence = $Confidence
        source     = if ($Source) { $Source } else { $null }
        note       = if ($Note) { $Note } else { $null }
    }
}

function Get-ProbeFieldValue {
    param($Field)
    if ($null -eq $Field) { return $null }
    if ($Field -is [hashtable] -and $Field.ContainsKey('value')) { return $Field.value }
    if ($Field -is [pscustomobject] -and $null -ne $Field.PSObject.Properties['value']) { return $Field.value }
    return $Field
}
