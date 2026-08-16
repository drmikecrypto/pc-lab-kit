using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;
using Vortice.D3DCompiler;
using Vortice.Direct3D;
using Vortice.Direct3D11;
using Vortice.DXGI;
using static Vortice.Direct3D11.D3D11;
using static Vortice.DXGI.DXGI;

namespace PcLabVkBench;

/// <summary>
/// Native GPU compute helper for PC Lab Kit.
/// Uses D3D11 compute for a timed MAD workload; reports Vulkan ICD presence when vulkan-1.dll loads.
/// </summary>
internal static class Program
{
    private const string Hlsl = """
        cbuffer Params : register(b0) {
            uint ElementCount;
            uint Pad0;
            uint Pad1;
            uint Pad2;
        };
        RWStructuredBuffer<float> Data : register(u0);

        [numthreads(256, 1, 1)]
        void main(uint3 id : SV_DispatchThreadID)
        {
            uint i = id.x;
            if (i >= ElementCount) return;
            float x = Data[i];
            [unroll]
            for (int k = 0; k < 64; k++)
            {
                x = mad(x, 1.000000119f, 0.0001000166f);
            }
            Data[i] = x;
        }
        """;

    public static int Main(string[] args)
    {
        var seconds = 8;
        for (var i = 0; i < args.Length; i++)
        {
            if ((args[i] is "--seconds" or "-s") && i + 1 < args.Length
                && int.TryParse(args[i + 1], out var s))
            {
                seconds = Math.Clamp(s, 2, 60);
            }
        }

        try
        {
            var result = Run(seconds);
            Console.WriteLine(JsonSerializer.Serialize(result));
            return result.TryGetValue("ok", out var ok) && ok is true ? 0 : 2;
        }
        catch (Exception ex)
        {
            Console.WriteLine(JsonSerializer.Serialize(new Dictionary<string, object?>
            {
                ["ok"] = false,
                ["error"] = "exception",
                ["message"] = ex.Message,
                ["engine"] = "native_gpu_compute",
            }));
            return 1;
        }
    }

    private static Dictionary<string, object?> Run(int seconds)
    {
        var vulkanAvailable = NativeLibrary.TryLoad("vulkan-1.dll", out var vkLib);
        if (vkLib != 0)
        {
            NativeLibrary.Free(vkLib);
        }

        CreateDXGIFactory1(out IDXGIFactory1 factory).CheckError();
        using (factory)
        {
            factory.EnumAdapters1(0, out IDXGIAdapter1 adapter).CheckError();
            using (adapter)
            {
                var desc = adapter.Description1;
                var adapterName = desc.Description.TrimEnd('\0').Trim();

                D3D11CreateDevice(
                    adapter,
                    DriverType.Unknown,
                    DeviceCreationFlags.None,
                    [FeatureLevel.Level_11_0],
                    out ID3D11Device device,
                    out _,
                    out ID3D11DeviceContext context).CheckError();

                using (device)
                using (context)
                {
                    return Bench(device, context, adapterName, vulkanAvailable, seconds);
                }
            }
        }
    }

    private static Dictionary<string, object?> Bench(
        ID3D11Device device,
        ID3D11DeviceContext context,
        string adapterName,
        bool vulkanAvailable,
        int seconds)
    {
        var bytecode = Compiler.Compile(
            Hlsl,
            entryPoint: "main",
            sourceName: "PcLabVkBench.hlsl",
            profile: "cs_5_0",
            shaderFlags: ShaderFlags.OptimizationLevel3);

        using var cs = device.CreateComputeShader(bytecode.Span);
        const int elementCount = 1 << 20;
        var init = new float[elementCount];
        for (var i = 0; i < init.Length; i++)
        {
            init[i] = (i % 997) * 0.001f + 1f;
        }

        var bufferDesc = new BufferDescription
        {
            ByteWidth = (uint)(elementCount * sizeof(float)),
            Usage = ResourceUsage.Default,
            BindFlags = BindFlags.UnorderedAccess | BindFlags.ShaderResource,
            CPUAccessFlags = CpuAccessFlags.None,
            MiscFlags = ResourceOptionFlags.BufferStructured,
            StructureByteStride = sizeof(float),
        };
        ID3D11Buffer buffer;
        unsafe
        {
            fixed (float* p = init)
            {
                var data = new SubresourceData((IntPtr)p, (uint)(elementCount * sizeof(float)));
                buffer = device.CreateBuffer(bufferDesc, data);
            }
        }
        using (buffer)
        {
        var uavDesc = new UnorderedAccessViewDescription
        {
            Format = Format.Unknown,
            ViewDimension = UnorderedAccessViewDimension.Buffer,
            Buffer = new BufferUnorderedAccessView
            {
                FirstElement = 0,
                NumElements = (uint)elementCount,
                Flags = BufferUnorderedAccessViewFlags.None,
            },
        };
        using var uav = device.CreateUnorderedAccessView(buffer, uavDesc);

        var cbDesc = new BufferDescription
        {
            ByteWidth = 16,
            Usage = ResourceUsage.Default,
            BindFlags = BindFlags.ConstantBuffer,
            CPUAccessFlags = CpuAccessFlags.None,
            MiscFlags = ResourceOptionFlags.None,
            StructureByteStride = 0,
        };
        ID3D11Buffer cbuf;
        unsafe
        {
            var cbData = stackalloc uint[] { (uint)elementCount, 0, 0, 0 };
            var data = new SubresourceData((IntPtr)cbData, 16);
            cbuf = device.CreateBuffer(cbDesc, data);
        }
        using (cbuf)
        {
        context.CSSetShader(cs);
        context.CSSetUnorderedAccessView(0, uav);
        context.CSSetConstantBuffer(0, cbuf);

        var groups = (uint)((elementCount + 255) / 256);
        const double flopsPerElement = 64 * 2.0;
        var sw = Stopwatch.StartNew();
        var end = sw.Elapsed + TimeSpan.FromSeconds(seconds);
        long dispatches = 0;
        while (sw.Elapsed < end)
        {
            context.Dispatch(groups, 1, 1);
            dispatches++;
            if ((dispatches & 0xF) == 0)
            {
                context.Flush();
            }
        }
        context.Flush();
        sw.Stop();

        var secondsActual = Math.Max(sw.Elapsed.TotalSeconds, 1e-6);
        var totalFlops = dispatches * elementCount * flopsPerElement;
        var gflops = totalFlops / secondsActual / 1e9;
        var score = Math.Round(gflops * 100.0, 1);

        return new Dictionary<string, object?>
        {
            ["ok"] = true,
            ["engine"] = vulkanAvailable ? "vulkan_d3d11_compute" : "d3d11_compute",
            ["api"] = vulkanAvailable ? "vulkan+d3d11" : "d3d11",
            ["vulkan_available"] = vulkanAvailable,
            ["device"] = adapterName,
            ["adapter"] = adapterName,
            ["duration_s"] = Math.Round(secondsActual, 3),
            ["score"] = score,
            ["gflops"] = Math.Round(gflops, 3),
            ["unit"] = "index",
            ["dispatches"] = dispatches,
            ["elements"] = elementCount,
            ["note"] = "Native GPU compute — D3D11 CS timed MAD loop; Vulkan ICD detected when vulkan-1.dll loads.",
        };
        }
        }
    }
}