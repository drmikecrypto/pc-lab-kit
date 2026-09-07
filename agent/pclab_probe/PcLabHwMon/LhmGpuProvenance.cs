using LibreHardwareMonitor.Hardware;

namespace PcLabHwMon;

/// <summary>
/// Tag LHM GPU sensors with honest provenance so Ada/older NVAPI raw,
/// AMD ADL junction, and Intel Arc stay distinguishable from MMIO open-book.
/// </summary>
internal static class LhmGpuProvenance
{
    public static void TagGpuSensors(List<object> flat)
    {
        for (var i = 0; i < flat.Count; i++)
        {
            var item = flat[i];
            var hwType = Prop(item, "hardware_type") ?? "";
            var name = Prop(item, "name") ?? "";
            var type = Prop(item, "type") ?? "";
            if (!type.Equals("Temperature", StringComparison.OrdinalIgnoreCase))
                continue;
            if (!hwType.StartsWith("Gpu", StringComparison.OrdinalIgnoreCase))
                continue;

            var alreadyOpen = BoolProp(item, "open_book");
            if (alreadyOpen) continue;

            var source = hwType switch
            {
                "GpuNvidia" => "nvapi_raw",
                "GpuAmd" => "adl",
                "GpuIntel" => "lhm_intel",
                _ => "libre-hardware-monitor",
            };

            var value = DoubleProp(item, "value");
            var locked = value is >= 250;
            var confidence = locked ? "lock_or_invalid" : "measured";

            flat[i] = new
            {
                hardware = Prop(item, "hardware"),
                hardware_type = hwType,
                name,
                type,
                value,
                min = DoubleProp(item, "min"),
                max = DoubleProp(item, "max"),
                unit = Prop(item, "unit") ?? "°C",
                source,
                confidence,
                open_book = !locked && (name.Contains("Hot Spot", StringComparison.OrdinalIgnoreCase)
                    || name.Contains("Junction", StringComparison.OrdinalIgnoreCase)
                    || name.Contains("HotSpot", StringComparison.OrdinalIgnoreCase)),
                pci_bdf = Prop(item, "pci_bdf"),
                note = locked ? "NVAPI/LHM lock (255) — ignored" : $"LHM {source}",
            };
        }
    }

    public static List<object> CatalogFromFlat(List<object> flat)
    {
        var list = new List<object>();
        foreach (var item in flat)
        {
            var open = BoolProp(item, "open_book");
            var src = Prop(item, "source") ?? "";
            if (!open && src is not ("blackwell_therm_mmio" or "blackwell_vram_mmio" or "nvapi_raw" or "adl" or "lhm_intel"))
                continue;
            if (!string.Equals(Prop(item, "type"), "Temperature", StringComparison.OrdinalIgnoreCase))
                continue;
            list.Add(new
            {
                name = Prop(item, "name"),
                value = DoubleProp(item, "value"),
                unit = Prop(item, "unit") ?? "°C",
                source = src,
                raw_hex = Prop(item, "raw_hex"),
                pci_bdf = Prop(item, "pci_bdf"),
                confidence = Prop(item, "confidence") ?? "register_raw",
                hardware = Prop(item, "hardware"),
                hardware_type = Prop(item, "hardware_type"),
                open_book = open,
            });
        }
        return list;
    }

    private static string? Prop(object item, string name) =>
        item.GetType().GetProperty(name)?.GetValue(item)?.ToString();

    private static bool BoolProp(object item, string name)
    {
        var v = item.GetType().GetProperty(name)?.GetValue(item);
        return v is true;
    }

    private static double? DoubleProp(object item, string name)
    {
        var v = item.GetType().GetProperty(name)?.GetValue(item);
        return v switch
        {
            double d => d,
            float f => f,
            int i => i,
            _ => null,
        };
    }
}
