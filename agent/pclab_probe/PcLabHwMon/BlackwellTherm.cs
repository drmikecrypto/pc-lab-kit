namespace PcLabHwMon;

/// <summary>
/// NVIDIA Blackwell THERM open-book decode + BAR0 MMIO reader.
/// Offsets from public community research (Igor Lab / TIMBER-style reporting).
/// Not official NVAPI; not MODS.
/// </summary>
internal static class BlackwellTherm
{
    public const uint NvidiaVendorId = 0x10DE;
    public const uint ThermScratchOffset = 0xAD00BC;
    public const uint ThermSensorFieldOffset = 0xAD0A90;
    public const uint ThermScratchExpected = 0x000000FFu;
    public const uint TempHeaderMask = 0xFFFF0000u;
    public const uint ValidFlag = 0x40000000u;
    public const uint LockSentinel = 0xFF00u;
    public const double TempMinC = 0.0;
    public const double TempMaxC = 130.0;

    public sealed class ChannelSet
    {
        public required string HardwareName { get; init; }
        public required string PciBdf { get; init; }
        public ulong Bar0 { get; init; }
        public double?[] Channels { get; init; } = new double?[6]; // S1..S6
        public double? HotSpotC { get; init; }
        public double? SpreadC { get; init; }
        public string Source => "blackwell_therm_mmio";
    }

    /// <summary>Q8.8 decode with validity + lock rejection (TIMBER-style /256, not /32).</summary>
    public static double? DecodeQ88(uint raw)
    {
        if ((raw & TempHeaderMask) != ValidFlag)
            return null;
        var lower = raw & 0xFFFFu;
        if (lower == LockSentinel)
            return null;
        var c = lower / 256.0;
        if (c <= TempMinC || c >= TempMaxC)
            return null;
        return Math.Round(c, 3);
    }

    /// <summary>
    /// Primary Hot Spot: prefer S5 when it matches max(S1..S4); else max(S1..S4).
    /// </summary>
    public static (double? hotspot, double? spread) SelectHotSpot(double?[] channels)
    {
        var spatial = new List<double>();
        for (var i = 0; i < 4 && i < channels.Length; i++)
        {
            if (channels[i] is double d) spatial.Add(d);
        }
        if (spatial.Count == 0)
            return (null, null);

        var maxSpatial = spatial.Max();
        var spread = Math.Round(maxSpatial - spatial.Min(), 2);
        double? s5 = channels.Length > 4 ? channels[4] : null;
        var hotspot = s5 is double s5v && Math.Abs(s5v - maxSpatial) < 0.15
            ? s5v
            : maxSpatial;
        return (Math.Round(hotspot, 3), spread);
    }

    public static List<ChannelSet> TryReadAll(IEnumerable<string> gpuHardwareNames)
    {
        var results = new List<ChannelSet>();
        if (!Ring0Bridge.IsOpen)
            return results;

        var names = gpuHardwareNames.Where(n => !string.IsNullOrWhiteSpace(n)).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        var nameIdx = 0;
        foreach (var gpu in Ring0Bridge.EnumerateNvidiaDisplayBars())
        {
            if (!Ring0Bridge.ReadMemoryUInt32(gpu.Bar0 + ThermScratchOffset, out var scratch))
                continue;
            if (scratch != ThermScratchExpected)
                continue;

            var channels = new double?[6];
            var any = false;
            for (var i = 0; i < 6; i++)
            {
                if (!Ring0Bridge.ReadMemoryUInt32(gpu.Bar0 + ThermSensorFieldOffset + (ulong)(i * 4), out var raw))
                    continue;
                var decoded = DecodeQ88(raw);
                channels[i] = decoded;
                if (decoded is not null) any = true;
            }
            if (!any)
                continue;

            var (hot, spread) = SelectHotSpot(channels);
            var hwName = nameIdx < names.Count ? names[nameIdx] : $"NVIDIA GPU {gpu.PciBdf}";
            nameIdx++;
            results.Add(new ChannelSet
            {
                HardwareName = hwName,
                PciBdf = gpu.PciBdf,
                Bar0 = gpu.Bar0,
                Channels = channels,
                HotSpotC = hot,
                SpreadC = spread,
            });
        }

        return results;
    }

    /// <summary>
    /// Merge open-book channels into flat sensor list; replace bogus LHM Hot Spot / 255 readings.
    /// </summary>
    public static void MergeIntoFlat(List<object> flat, List<ChannelSet> sets, out bool openBookActive)
    {
        openBookActive = false;
        if (sets.Count == 0) return;
        openBookActive = true;

        foreach (var set in sets)
        {
            // Drop bogus NVAPI lock / core-clone hotspot and 255 memory for this GPU node.
            flat.RemoveAll(item =>
            {
                var hw = Prop(item, "hardware");
                var name = Prop(item, "name");
                var type = Prop(item, "type");
                if (!string.Equals(type, "Temperature", StringComparison.OrdinalIgnoreCase)) return false;
                if (!string.Equals(hw, set.HardwareName, StringComparison.OrdinalIgnoreCase)) return false;
                if (name is null) return false;
                if (name.Contains("Hot Spot", StringComparison.OrdinalIgnoreCase) ||
                    name.Contains("HotSpot", StringComparison.OrdinalIgnoreCase))
                    return true;
                if (name.Contains("Memory Junction", StringComparison.OrdinalIgnoreCase) ||
                    name.Equals("GPU Memory", StringComparison.OrdinalIgnoreCase))
                {
                    var v = item.GetType().GetProperty("value")?.GetValue(item);
                    if (v is double d && d >= 250) return true;
                }
                return false;
            });

            void Add(string name, double? value, string? extra = null)
            {
                if (value is null) return;
                flat.Add(new
                {
                    hardware = set.HardwareName,
                    hardware_type = "GpuNvidia",
                    name,
                    type = "Temperature",
                    value = value.Value,
                    min = (double?)null,
                    max = (double?)null,
                    unit = "°C",
                    source = set.Source,
                    confidence = "register_raw",
                    open_book = true,
                    pci_bdf = set.PciBdf,
                    note = extra,
                });
            }

            Add("GPU Hot Spot", set.HotSpotC, "Open-book BAR0 THERM (not NVAPI)");
            var labels = new[] { "GPU Therm S1", "GPU Therm S2", "GPU Therm S3", "GPU Therm S4", "GPU Therm Max", "GPU Therm Ref" };
            for (var i = 0; i < 6; i++)
                Add(labels[i], set.Channels[i]);
            if (set.SpreadC is double sp)
            {
                flat.Add(new
                {
                    hardware = set.HardwareName,
                    hardware_type = "GpuNvidia",
                    name = "GPU Therm Spread",
                    type = "Temperature",
                    value = sp,
                    min = (double?)null,
                    max = (double?)null,
                    unit = "°C",
                    source = set.Source,
                    confidence = "register_raw",
                    open_book = true,
                    pci_bdf = set.PciBdf,
                    note = "S1–S4 spatial spread (paste/cooler seating signal)",
                });
            }
        }
    }

    private static string? Prop(object item, string name) =>
        item.GetType().GetProperty(name)?.GetValue(item)?.ToString();
}
