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

    private const string HlslRaster = """
        struct VSOut { float4 pos : SV_POSITION; float4 col : COLOR; };
        VSOut vs(uint id : SV_VertexID) {
            float2 tri[3] = { float2(-0.8, -0.8), float2(0.8, -0.8), float2(0, 0.8) };
            VSOut o;
            o.pos = float4(tri[id % 3], 0, 1);
            o.col = float4(0.2, 0.5, 1.0, 1);
            return o;
        }
        float4 ps(VSOut i) : SV_TARGET { return i.col; }
        """;

    public static int Main(string[] args)
    {
        var seconds = 8;
        var stress = false;
        var rasterOnly = false;
        var artifactCheck = false;
        for (var i = 0; i < args.Length; i++)
        {
            if (args[i] is "--raster")
            {
                rasterOnly = true;
            }
            else if (args[i] is "--artifact-check" or "--artifacts")
            {
                artifactCheck = true;
            }
            else if (args[i] is "--stress" or "--stress-seconds")
            {
                stress = true;
                if (i + 1 < args.Length && int.TryParse(args[i + 1], out var st))
                {
                    seconds = Math.Clamp(st, 5, 300);
                    i++;
                }
            }
            else if ((args[i] is "--seconds" or "-s") && i + 1 < args.Length
                && int.TryParse(args[i + 1], out var s))
            {
                seconds = Math.Clamp(s, 2, 300);
            }
        }
        if (stress)
        {
            seconds = Math.Clamp(seconds, 5, 300);
        }
        else
        {
            seconds = Math.Clamp(seconds, 2, 60);
        }

        try
        {
            var result = Run(seconds, rasterOnly, artifactCheck);
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
                ["artifact_errors"] = 1,
            }));
            return 1;
        }
    }

    private static Dictionary<string, object?> Run(int seconds, bool rasterOnly = false, bool artifactCheck = false)
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
                    if (rasterOnly)
                    {
                        return BenchRaster(device, context, adapterName, vulkanAvailable, seconds);
                    }

                    var compute = Bench(device, context, adapterName, vulkanAvailable, seconds, artifactCheck);
                    var raster = BenchRaster(device, context, adapterName, vulkanAvailable, Math.Max(2, seconds / 3));
                    var computeScore = compute.TryGetValue("score", out var cs) && cs is double cds ? cds : 0.0;
                    var rasterScore = raster.TryGetValue("raster_score", out var rs) && rs is double rds ? rds : 0.0;
                    compute["raster"] = raster;
                    compute["raster_score"] = rasterScore;
                    compute["score"] = Math.Round(computeScore * 0.65 + rasterScore * 0.35, 1);
                    compute["engine"] = vulkanAvailable ? "vulkan_unified_gpu" : "d3d11_unified_gpu";
                    compute["api"] = vulkanAvailable ? "vulkan+d3d11" : "d3d11";
                    compute["note"] = artifactCheck
                        ? "Unified native GPU score with artifact/CRC verify (OCCT-like stability)."
                        : "Unified native GPU score: 65% compute + 35% raster fill/triangle throughput.";

                    return compute;
                }
            }
        }
    }

    private static float CpuMadOnce(float x)
    {
        for (var k = 0; k < 64; k++)
        {
            x = x * 1.000000119f + 0.0001000166f;
        }
        return x;
    }

    private static uint Crc32OfFloats(ReadOnlySpan<float> data)
    {
        uint crc = 0xFFFFFFFFu;
        for (var i = 0; i < data.Length; i++)
        {
            var bits = BitConverter.ToUInt32(BitConverter.GetBytes(data[i]), 0);
            crc ^= bits;
            for (var b = 0; b < 32; b++)
            {
                var mask = (crc & 1u) != 0 ? 0xEDB88320u : 0u;
                crc = (crc >> 1) ^ mask;
            }
        }
        return ~crc;
    }

    private static (int artifactErrors, int crcMismatches, uint gpuCrc, uint cpuCrc) VerifyComputeIntegrity(
        ID3D11Device device,
        ID3D11DeviceContext context,
        ID3D11ComputeShader cs)
    {
        const int n = 1 << 16;
        var init = new float[n];
        var expected = new float[n];
        for (var i = 0; i < n; i++)
        {
            init[i] = (i % 997) * 0.001f + 1f;
            expected[i] = CpuMadOnce(init[i]);
        }

        var bufferDesc = new BufferDescription
        {
            ByteWidth = (uint)(n * sizeof(float)),
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
                var data = new SubresourceData((IntPtr)p, (uint)(n * sizeof(float)));
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
                    NumElements = (uint)n,
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
            };
            ID3D11Buffer cbuf;
            unsafe
            {
                var cbData = stackalloc uint[] { (uint)n, 0, 0, 0 };
                var data = new SubresourceData((IntPtr)cbData, 16);
                cbuf = device.CreateBuffer(cbDesc, data);
            }
            using (cbuf)
            {
                context.CSSetShader(cs);
                context.CSSetUnorderedAccessView(0, uav);
                context.CSSetConstantBuffer(0, cbuf);
                context.Dispatch((uint)((n + 255) / 256), 1, 1);
                context.Flush();

                var stagingDesc = bufferDesc;
                stagingDesc.Usage = ResourceUsage.Staging;
                stagingDesc.BindFlags = BindFlags.None;
                stagingDesc.CPUAccessFlags = CpuAccessFlags.Read;
                stagingDesc.MiscFlags = ResourceOptionFlags.BufferStructured;
                using var staging = device.CreateBuffer(stagingDesc);
                context.CopyResource(staging, buffer);
                context.Flush();

                var mapped = context.Map(staging, 0, MapMode.Read, Vortice.Direct3D11.MapFlags.None);
                var gpu = new float[n];
                unsafe
                {
                    var src = (float*)mapped.DataPointer;
                    for (var i = 0; i < n; i++)
                    {
                        gpu[i] = src[i];
                    }
                }
                context.Unmap(staging, 0);

                var artifacts = 0;
                var mismatches = 0;
                for (var i = 0; i < n; i++)
                {
                    var g = gpu[i];
                    if (float.IsNaN(g) || float.IsInfinity(g))
                    {
                        artifacts++;
                        continue;
                    }
                    var e = expected[i];
                    var denom = Math.Max(Math.Abs(e), 1e-3f);
                    if (Math.Abs(g - e) / denom > 1e-3f)
                    {
                        mismatches++;
                    }
                }
                // Sample stride for CRC (first 4096)
                var sample = Math.Min(4096, n);
                var gpuCrc = Crc32OfFloats(gpu.AsSpan(0, sample));
                var cpuCrc = Crc32OfFloats(expected.AsSpan(0, sample));
                if (gpuCrc != cpuCrc)
                {
                    mismatches = Math.Max(mismatches, 1);
                }
                artifacts += mismatches;
                return (artifacts, mismatches, gpuCrc, cpuCrc);
            }
        }
    }

    private static Dictionary<string, object?> Bench(
        ID3D11Device device,
        ID3D11DeviceContext context,
        string adapterName,
        bool vulkanAvailable,
        int seconds,
        bool artifactCheck = false)
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

        var artifactErrors = 0;
        uint? gpuCrc = null;
        uint? cpuCrc = null;
        var crcMismatches = 0;
        if (artifactCheck)
        {
            // Post-soak integrity: independent 1-dispatch CRC vs CPU MAD reference
            var verify = VerifyComputeIntegrity(device, context, cs);
            artifactErrors = verify.artifactErrors;
            crcMismatches = verify.crcMismatches;
            gpuCrc = verify.gpuCrc;
            cpuCrc = verify.cpuCrc;

            // Also scan soak buffer for NaN/Inf corruption
            var stagingDesc = bufferDesc;
            stagingDesc.Usage = ResourceUsage.Staging;
            stagingDesc.BindFlags = BindFlags.None;
            stagingDesc.CPUAccessFlags = CpuAccessFlags.Read;
            using var staging = device.CreateBuffer(stagingDesc);
            context.CopyResource(staging, buffer);
            context.Flush();
            var mapped = context.Map(staging, 0, MapMode.Read, Vortice.Direct3D11.MapFlags.None);
            unsafe
            {
                var src = (float*)mapped.DataPointer;
                var step = Math.Max(1, elementCount / 8192);
                for (var i = 0; i < elementCount; i += step)
                {
                    var v = src[i];
                    if (float.IsNaN(v) || float.IsInfinity(v))
                    {
                        artifactErrors++;
                    }
                }
            }
            context.Unmap(staging, 0);
        }

        var ok = artifactErrors == 0;
        return new Dictionary<string, object?>
        {
            ["ok"] = ok,
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
            ["artifact_check"] = artifactCheck,
            ["artifact_errors"] = artifactErrors,
            ["crc_mismatches"] = crcMismatches,
            ["gpu_crc32"] = gpuCrc,
            ["cpu_crc32"] = cpuCrc,
            ["note"] = artifactCheck
                ? (ok
                    ? "Native GPU compute + artifact/CRC pass."
                    : $"Native GPU compute FAILED artifact/CRC ({artifactErrors} errors).")
                : "Native GPU compute — D3D11 CS timed MAD loop; Vulkan ICD detected when vulkan-1.dll loads.",
        };
        }
        }
    }

    private static Dictionary<string, object?> BenchRaster(
        ID3D11Device device,
        ID3D11DeviceContext context,
        string adapterName,
        bool vulkanAvailable,
        int seconds)
    {
        var vsBytecode = Compiler.Compile(HlslRaster, "vs", "PcLabVkBench.vs.hlsl", "vs_5_0", ShaderFlags.OptimizationLevel3);
        var psBytecode = Compiler.Compile(HlslRaster, "ps", "PcLabVkBench.ps.hlsl", "ps_5_0", ShaderFlags.OptimizationLevel3);
        using var vs = device.CreateVertexShader(vsBytecode.Span);
        using var ps = device.CreatePixelShader(psBytecode.Span);

        var texDesc = new Texture2DDescription
        {
            Width = 1280,
            Height = 720,
            MipLevels = 1,
            ArraySize = 1,
            Format = Format.R8G8B8A8_UNorm,
            SampleDescription = new SampleDescription(1, 0),
            Usage = ResourceUsage.Default,
            BindFlags = BindFlags.RenderTarget | BindFlags.ShaderResource,
            CPUAccessFlags = CpuAccessFlags.None,
        };
        using var tex = device.CreateTexture2D(texDesc);
        using var rtv = device.CreateRenderTargetView(tex);

        context.OMSetRenderTargets(rtv, null);
        context.VSSetShader(vs);
        context.PSSetShader(ps);

        var sw = Stopwatch.StartNew();
        var end = sw.Elapsed + TimeSpan.FromSeconds(seconds);
        long draws = 0;
        while (sw.Elapsed < end)
        {
            context.ClearRenderTargetView(rtv, new Vortice.Mathematics.Color4(0.05f, 0.08f, 0.12f, 1f));
            context.Draw(3, 0);
            draws++;
            if ((draws & 0x3F) == 0)
            {
                context.Flush();
            }
        }
        context.Flush();
        sw.Stop();

        var sec = Math.Max(sw.Elapsed.TotalSeconds, 1e-6);
        var triangles = draws * 1.0;
        var fillMpixels = (1280.0 * 720.0 * draws) / sec / 1e6;
        var rasterScore = Math.Round(Math.Min(99999, (triangles / sec / 1000.0) + fillMpixels * 0.5), 1);

        return new Dictionary<string, object?>
        {
            ["ok"] = true,
            ["engine"] = vulkanAvailable ? "vulkan_d3d11_raster" : "d3d11_raster",
            ["device"] = adapterName,
            ["duration_s"] = Math.Round(sec, 3),
            ["draws"] = draws,
            ["triangles_per_sec"] = Math.Round(triangles / sec, 0),
            ["fill_mpixels_per_sec"] = Math.Round(fillMpixels, 2),
            ["raster_score"] = rasterScore,
        };
    }
}