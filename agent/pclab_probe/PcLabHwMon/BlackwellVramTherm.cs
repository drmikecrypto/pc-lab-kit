namespace PcLabHwMon;

/// <summary>
/// Scan THERM-adjacent BAR0 windows for extra Q8.8 temps (VRAM junction / memory).
/// Community maps vary by die; we keep candidates that decode as valid temps and
/// are not already used as Hot Spot S1–S6.
/// </summary>
internal static class BlackwellVramTherm
{
    // Scan after the known S1–S6 field (0xAD0A90 + 24 bytes) through a modest window.
    public const uint ScanStart = 0xAD0AA8;
    public const uint ScanEnd = 0xAD0B40;
    public const int MaxChips = 16;

    public sealed class VramSet
    {
        public required string HardwareName { get; init; }
        public required string PciBdf { get; init; }
        public double? JunctionC { get; init; }
        public List<(uint Offset, double C, uint Raw)> Chips { get; init; } = [];
        public string Source => "blackwell_vram_mmio";
    }

    public static List<VramSet> TryReadAll(IReadOnlyList<BlackwellTherm.ChannelSet> thermSets)
    {
        var results = new List<VramSet>();
        if (!Ring0Bridge.IsOpen) return results;

        var usedOffsets = new HashSet<uint>();
        for (uint o = BlackwellTherm.ThermSensorFieldOffset; o < BlackwellTherm.ThermSensorFieldOffset + 24; o += 4)
            usedOffsets.Add(o);

        foreach (var therm in thermSets)
        {
            var chips = new List<(uint Offset, double C, uint Raw)>();
            for (uint off = ScanStart; off < ScanEnd && chips.Count < MaxChips; off += 4)
            {
                if (usedOffsets.Contains(off)) continue;
                if (!Ring0Bridge.ReadMemoryUInt32(therm.Bar0 + off, out var raw))
                    continue;
                var decoded = BlackwellTherm.DecodeQ88(raw);
                if (decoded is null) continue;
                // Skip values that simply duplicate Hot Spot / Ref (same silicon, not VRAM).
                if (therm.HotSpotC is double hs && Math.Abs(decoded.Value - hs) < 0.2)
                    continue;
                if (therm.Channels.Length > 5 && therm.Channels[5] is double s6 && Math.Abs(decoded.Value - s6) < 0.2)
                    continue;
                chips.Add((off, decoded.Value, raw));
            }
            if (chips.Count == 0) continue;
            results.Add(new VramSet
            {
                HardwareName = therm.HardwareName,
                PciBdf = therm.PciBdf,
                JunctionC = chips.Max(c => c.C),
                Chips = chips,
            });
        }

        return results;
    }

    public static void MergeIntoFlat(List<object> flat, List<VramSet> sets)
    {
        foreach (var set in sets)
        {
            void Add(string name, double value, uint? raw = null, string? extra = null)
            {
                flat.Add(new
                {
                    hardware = set.HardwareName,
                    hardware_type = "GpuNvidia",
                    name,
                    type = "Temperature",
                    value,
                    min = (double?)null,
                    max = (double?)null,
                    unit = "°C",
                    source = set.Source,
                    confidence = "register_raw",
                    open_book = true,
                    pci_bdf = set.PciBdf,
                    raw_hex = raw.HasValue ? $"0x{raw.Value:X8}" : null,
                    note = extra,
                });
            }

            if (set.JunctionC is double j)
                Add("GPU Memory Junction", Math.Round(j, 3), extra: "Open-book BAR0 THERM scan (max of decoded memory candidates)");

            var i = 1;
            foreach (var chip in set.Chips)
            {
                Add($"GPU VRAM Chip {i}", Math.Round(chip.C, 3), chip.Raw, $"offset 0x{chip.Offset:X}");
                i++;
            }
        }
    }
}
