using System.Text;

namespace PcLabHwMon;

/// <summary>
/// 256-byte PCI configuration dump for display and NVMe storage functions (silicon identity).
/// </summary>
internal static class PciConfigDump
{
    public sealed class Dump
    {
        public required string PciBdf { get; init; }
        public required uint VendorId { get; init; }
        public required uint DeviceId { get; init; }
        public uint SubsystemVendorId { get; init; }
        public uint SubsystemId { get; init; }
        public uint Revision { get; init; }
        public uint ClassCode { get; init; }
        public required string Role { get; init; }
        public required string ConfigHex { get; init; }
        public string Source => "pci_config";
    }

    public static List<Dump> ReadSelectedFunctions()
    {
        var list = new List<Dump>();
        if (!Ring0Bridge.IsOpen) return list;
        foreach (var fn in Ring0Bridge.EnumerateSelectedPciFunctions())
        {
            var bytes = new byte[256];
            var ok = true;
            for (uint off = 0; off < 256; off += 4)
            {
                if (!Ring0Bridge.ReadPciConfig(fn.PciAddress, off, out var dword))
                {
                    ok = false;
                    break;
                }
                bytes[off] = (byte)(dword & 0xFF);
                bytes[off + 1] = (byte)((dword >> 8) & 0xFF);
                bytes[off + 2] = (byte)((dword >> 16) & 0xFF);
                bytes[off + 3] = (byte)((dword >> 24) & 0xFF);
            }
            if (!ok) continue;
            uint sub = BitConverter.ToUInt32(bytes, 0x2C);
            list.Add(new Dump
            {
                PciBdf = fn.PciBdf,
                VendorId = fn.VendorId,
                DeviceId = fn.DeviceId,
                SubsystemVendorId = sub & 0xFFFF,
                SubsystemId = (sub >> 16) & 0xFFFF,
                Revision = bytes[8],
                ClassCode = ((uint)bytes[11] << 16) | ((uint)bytes[10] << 8) | bytes[9],
                Role = fn.Role,
                ConfigHex = Convert.ToHexString(bytes),
            });
        }
        return list;
    }

    /// <summary>Backward-compatible alias used by older call sites. </summary>
    public static List<Dump> ReadNvidiaDisplays() =>
        ReadSelectedFunctions().Where(d => d.VendorId == 0x10DE && d.Role == "display").ToList();
}
