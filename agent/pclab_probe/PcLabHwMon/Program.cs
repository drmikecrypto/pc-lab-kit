using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text.Json;
using LibreHardwareMonitor.Hardware;

var elevated = new WindowsPrincipal(WindowsIdentity.GetCurrent())
    .IsInRole(WindowsBuiltInRole.Administrator);

var computer = new Computer
{
    IsCpuEnabled = true,
    IsGpuEnabled = true,
    IsMemoryEnabled = true,
    IsMotherboardEnabled = true,
    IsControllerEnabled = true,
    IsNetworkEnabled = true,
    IsStorageEnabled = true,
    IsPsuEnabled = true,
    IsBatteryEnabled = true,
};

computer.Open();
try
{
    foreach (var hw in computer.Hardware)
    {
        hw.Update();
        foreach (var sub in hw.SubHardware)
        {
            sub.Update();
        }
    }

    var flat = FlatSensors(computer);
    var report = new Dictionary<string, object?>
    {
        ["collector"] = "pclab-hwmon",
        ["collected_at"] = DateTime.UtcNow.ToString("o"),
        ["environment"] = new
        {
            elevated,
            // Ring-0 sensors (CPU package, board SuperIO) only appear when elevated.
            // Exposing the flag lets the probe tell the assembler why CPU temps are missing
            // instead of silently falling back to ACPI zones.
            ring0_available = elevated,
            process_arch = RuntimeInformation.ProcessArchitecture.ToString(),
            os_arch = RuntimeInformation.OSArchitecture.ToString(),
            clr = RuntimeInformation.FrameworkDescription,
        },
        ["hardware"] = computer.Hardware.Select(HardwareNode).ToList(),
        ["sensors_flat"] = flat,
        ["by_type"] = SensorsByType(flat),
        ["resolved"] = ResolveThermals(flat),
    };

    var opts = new JsonSerializerOptions { WriteIndented = false };
    Console.WriteLine(JsonSerializer.Serialize(report, opts));
}
finally
{
    computer.Close();
}

static object HardwareNode(IHardware hw)
{
    foreach (var sub in hw.SubHardware)
    {
        sub.Update();
    }

    return new
    {
        type = hw.HardwareType.ToString(),
        name = hw.Name,
        identifier = hw.Identifier.ToString(),
        sensors = hw.Sensors.Select(SensorDto).ToList(),
        subhardware = hw.SubHardware.Select(HardwareNode).ToList(),
    };
}

static object SensorDto(ISensor s) => new
{
    id = s.Identifier.ToString(),
    name = s.Name,
    type = s.SensorType.ToString(),
    value = s.Value,
    min = s.Min,
    max = s.Max,
    unit = UnitLabel(s.SensorType),
};

static string UnitLabel(SensorType t) => t switch
{
    SensorType.Temperature => "°C",
    SensorType.Clock => "MHz",
    SensorType.Voltage => "V",
    SensorType.Current => "A",
    SensorType.Power => "W",
    SensorType.Fan => "RPM",
    SensorType.Frequency => "Hz",
    SensorType.Data => "GB",
    SensorType.SmallData => "MB",
    SensorType.Throughput => "B/s",
    SensorType.Load => "%",
    SensorType.Control => "%",
    SensorType.Level => "%",
    SensorType.Factor => "x",
    SensorType.Energy => "mWh",
    SensorType.Noise => "dBA",
    _ => "",
};

static List<object> FlatSensors(Computer computer)
{
    var list = new List<object>();
    foreach (var hw in computer.Hardware)
    {
        Collect(hw, list);
    }
    return list;
}

static void Collect(IHardware hw, List<object> list)
{
    foreach (var s in hw.Sensors)
    {
        if (s.Value is null) continue;
        list.Add(new
        {
            hardware = hw.Name,
            hardware_type = hw.HardwareType.ToString(),
            name = s.Name,
            type = s.SensorType.ToString(),
            value = Math.Round(s.Value.Value, 3),
            min = s.Min.HasValue ? Math.Round(s.Min.Value, 3) : (double?)null,
            max = s.Max.HasValue ? Math.Round(s.Max.Value, 3) : (double?)null,
            unit = UnitLabel(s.SensorType),
        });
    }
    foreach (var sub in hw.SubHardware)
    {
        sub.Update();
        Collect(sub, list);
    }
}

static Dictionary<string, List<object>> SensorsByType(List<object> flat)
{
    var map = new Dictionary<string, List<object>>(StringComparer.OrdinalIgnoreCase);
    foreach (var item in flat)
    {
        var type = item.GetType().GetProperty("type")?.GetValue(item)?.ToString() ?? "Other";
        if (!map.ContainsKey(type)) map[type] = new List<object>();
        map[type].Add(item);
    }
    return map;
}

/// <summary>
/// Pre-resolved thermal summary so callers that cannot run PowerShell still get
/// hot spot and package numbers without re-implementing the name matching.
/// The PowerShell thermal.ps1 resolver remains the authoritative source of truth
/// for the probe; this is a convenience mirror for the native Qt path.
/// </summary>
static object ResolveThermals(List<object> flat)
{
    double? Pick(string hardwareType, params string[] names)
    {
        foreach (var name in names)
        {
            foreach (var item in flat)
            {
                var t = Prop(item, "type");
                var hw = Prop(item, "hardware_type");
                var n = Prop(item, "name");
                if (!string.Equals(t, "Temperature", StringComparison.OrdinalIgnoreCase)) continue;
                if (!string.IsNullOrEmpty(hardwareType) &&
                    !string.Equals(hw, hardwareType, StringComparison.OrdinalIgnoreCase) &&
                    !(hw?.StartsWith(hardwareType, StringComparison.OrdinalIgnoreCase) ?? false))
                    continue;
                if (n is null) continue;
                if (n.Equals(name, StringComparison.OrdinalIgnoreCase) ||
                    System.Text.RegularExpressions.Regex.IsMatch(n, name, System.Text.RegularExpressions.RegexOptions.IgnoreCase))
                {
                    var v = item.GetType().GetProperty("value")?.GetValue(item);
                    if (v is double d) return d;
                }
            }
        }
        return null;
    }

    static string? Prop(object item, string name) =>
        item.GetType().GetProperty(name)?.GetValue(item)?.ToString();

    var cpuPackage = Pick("Cpu", "^CPU Package$", "^Package$", "Core \\(Tctl/Tdie\\)", "Core \\(Tdie\\)", "Core \\(Tctl\\)");
    var cpuHotspot = Pick("Cpu", "^Core Max$", "Hot ?Spot");
    var gpuCore = Pick("Gpu", "^GPU Core$", "^GPU Temperature$");
    var gpuHotspot = Pick("Gpu", "^GPU Hot ?Spot$", "Hot ?Spot", "^GPU Junction$");
    var gpuMemory = Pick("Gpu", "^GPU Memory Junction$", "^GPU Memory$", "Memory Junction");

    return new
    {
        cpu_package_c = cpuPackage,
        cpu_hotspot_c = cpuHotspot ?? cpuPackage,
        gpu_core_c = gpuCore,
        gpu_hot_spot_c = gpuHotspot,
        gpu_memory_c = gpuMemory,
        hotspot_delta_c = (gpuCore.HasValue && gpuHotspot.HasValue)
            ? Math.Round(gpuHotspot.Value - gpuCore.Value, 1)
            : (double?)null,
    };
}
