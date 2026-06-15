using System.Text.Json;
using LibreHardwareMonitor.Hardware;

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

    var report = new Dictionary<string, object?>
    {
        ["collector"] = "pcverse-hwmon",
        ["collected_at"] = DateTime.UtcNow.ToString("o"),
        ["hardware"] = computer.Hardware.Select(HardwareNode).ToList(),
        ["sensors_flat"] = FlatSensors(computer),
        ["by_type"] = SensorsByType(computer),
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
            unit = UnitLabel(s.SensorType),
        });
    }
    foreach (var sub in hw.SubHardware)
    {
        sub.Update();
        Collect(sub, list);
    }
}

static Dictionary<string, List<object>> SensorsByType(Computer computer)
{
    var map = new Dictionary<string, List<object>>(StringComparer.OrdinalIgnoreCase);
    foreach (var item in FlatSensors(computer))
    {
        var type = item.GetType().GetProperty("type")?.GetValue(item)?.ToString() ?? "Other";
        if (!map.ContainsKey(type)) map[type] = new List<object>();
        map[type].Add(item);
    }
    return map;
}
