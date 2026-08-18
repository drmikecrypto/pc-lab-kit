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
}
