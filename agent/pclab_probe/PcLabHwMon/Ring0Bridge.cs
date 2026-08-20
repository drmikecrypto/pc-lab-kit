using System.Reflection;

namespace PcLabHwMon;

/// <summary>
/// Thin reflection bridge to LibreHardwareMonitor's internal Ring0
/// (same kernel helper already loaded when Computer.Open runs elevated).
/// </summary>
internal static class Ring0Bridge
{
    private static readonly Type? Ring0Type =
        typeof(LibreHardwareMonitor.Hardware.Computer).Assembly.GetType("LibreHardwareMonitor.Hardware.Ring0");

    private static readonly PropertyInfo? IsOpenProp = Ring0Type?.GetProperty("IsOpen", BindingFlags.Public | BindingFlags.Static);
    private static readonly MethodInfo? GetPciAddressMethod = Ring0Type?.GetMethod("GetPciAddress", BindingFlags.Public | BindingFlags.Static);
    private static readonly MethodInfo? ReadPciConfigMethod = Ring0Type?.GetMethod("ReadPciConfig", BindingFlags.Public | BindingFlags.Static);
    private static readonly MethodInfo? ReadMemoryUintMethod = Ring0Type?
        .GetMethods(BindingFlags.Public | BindingFlags.Static)
        .Where(m => m.Name == "ReadMemory" && m.IsGenericMethodDefinition)
        .Select(m => new { Method = m, Params = m.GetParameters() })
        .Where(x => x.Params.Length == 2 &&
                    x.Params[0].ParameterType == typeof(ulong) &&
                    x.Params[1].ParameterType.IsByRef &&
                    !x.Params[1].ParameterType.GetElementType()!.IsArray)
        .Select(x => x.Method.MakeGenericMethod(typeof(uint)))
        .FirstOrDefault();

    public static bool IsOpen =>
        IsOpenProp?.GetValue(null) is bool b && b;

    public static uint GetPciAddress(byte bus, byte device, byte function)
    {
        if (GetPciAddressMethod is null) return 0xFFFFFFFFu;
        return (uint)(GetPciAddressMethod.Invoke(null, [bus, device, function]) ?? 0xFFFFFFFFu);
    }

    public static bool ReadPciConfig(uint pciAddress, uint regAddress, out uint value)
    {
        value = 0;
        if (ReadPciConfigMethod is null) return false;
        object[] args = [pciAddress, regAddress, value];
        var ok = ReadPciConfigMethod.Invoke(null, args) is true;
        value = (uint)args[2];
        return ok;
    }

    public static bool ReadMemoryUInt32(ulong address, out uint value)
    {
        value = 0;
        if (ReadMemoryUintMethod is null) return false;
        object[] args = [address, value];
        var ok = ReadMemoryUintMethod.Invoke(null, args) is true;
        value = (uint)args[1];
        return ok;
    }

    public sealed class NvidiaGpuBar
    {
        public required string PciBdf { get; init; }
        public required uint PciAddress { get; init; }
        public required ulong Bar0 { get; init; }
        public required uint DeviceId { get; init; }
    }

    public static bool TryReadBar0(uint pciAddress, out ulong bar0)
    {
        bar0 = 0;
        if (!ReadPciConfig(pciAddress, 0x10, out var barLo))
            return false;
        if ((barLo & 0x1) != 0)
            return false;
        var type = (barLo >> 1) & 0x3;
        ulong addr = barLo & 0xFFFFFFF0u;
        if (type == 0x2)
        {
            if (!ReadPciConfig(pciAddress, 0x14, out var barHi))
                return false;
            addr |= ((ulong)barHi) << 32;
        }
        bar0 = addr;
        return bar0 != 0;
    }

    /// <summary>Enumerate NVIDIA display controllers with a mapped BAR0.</summary>
    public static List<NvidiaGpuBar> EnumerateNvidiaDisplayBars()
    {
        var results = new List<NvidiaGpuBar>();
        if (!IsOpen) return results;
        for (int bus = 0; bus < 256; bus++)
        {
            for (byte dev = 0; dev < 32; dev++)
            {
                for (byte fn = 0; fn < 8; fn++)
                {
                    var pci = GetPciAddress((byte)bus, dev, fn);
                    if (!ReadPciConfig(pci, 0, out var idReg) || idReg == 0xFFFFFFFFu || idReg == 0)
                        continue;
                    if ((idReg & 0xFFFF) != 0x10DE)
                        continue;
                    if (!ReadPciConfig(pci, 0x08, out var classReg))
                        continue;
                    if (((classReg >> 24) & 0xFF) != 0x03)
                        continue;
                    if (!TryReadBar0(pci, out var bar0) || bar0 == 0)
                        continue;
                    results.Add(new NvidiaGpuBar
                    {
                        PciBdf = $"{bus:X2}:{dev:X2}.{fn}",
                        PciAddress = pci,
                        Bar0 = bar0,
                        DeviceId = (idReg >> 16) & 0xFFFF,
                    });
                }
            }
        }
        return results;
    }

    public sealed class SelectedPciFunction
    {
        public required string PciBdf { get; init; }
        public required uint PciAddress { get; init; }
        public required uint VendorId { get; init; }
        public required uint DeviceId { get; init; }
        public required string Role { get; init; }
    }

    /// <summary>
    /// Display (class 0x03) and NVMe storage (class 0x01 subclass 0x08) functions for 256-byte config dumps.
    /// Caps at 12 devices — identity, not a full bus analyzer.
    /// </summary>
    public static List<SelectedPciFunction> EnumerateSelectedPciFunctions(int max = 12)
    {
        var results = new List<SelectedPciFunction>();
        if (!IsOpen) return results;
        for (int bus = 0; bus < 256 && results.Count < max; bus++)
        {
            for (byte dev = 0; dev < 32 && results.Count < max; dev++)
            {
                for (byte fn = 0; fn < 8 && results.Count < max; fn++)
                {
                    var pci = GetPciAddress((byte)bus, dev, fn);
                    if (!ReadPciConfig(pci, 0, out var idReg) || idReg == 0xFFFFFFFFu || idReg == 0)
                        continue;
                    if (!ReadPciConfig(pci, 0x08, out var classReg))
                        continue;
                    var baseClass = (classReg >> 24) & 0xFF;
                    var subClass = (classReg >> 16) & 0xFF;
                    string? role = null;
                    if (baseClass == 0x03)
                        role = "display";
                    else if (baseClass == 0x01 && subClass == 0x08)
                        role = "nvme";
                    if (role is null)
                        continue;
                    results.Add(new SelectedPciFunction
                    {
                        PciBdf = $"{bus:X2}:{dev:X2}.{fn}",
                        PciAddress = pci,
                        VendorId = idReg & 0xFFFF,
                        DeviceId = (idReg >> 16) & 0xFFFF,
                        Role = role,
                    });
                }
            }
        }
        return results;
    }
}
