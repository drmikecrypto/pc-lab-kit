# PcLabVkBench — native GPU compute helper

Place the built binary next to the probe:

```
agent/pclab_probe/PcLabVkBench.exe
```

Build (requires .NET 8 SDK):

```powershell
.\scripts\build-pclab-vkbench.ps1
```

The probe runs `PcLabVkBench.exe --seconds N` and expects JSON on stdout (`engine`: `vulkan_d3d11_compute` or `d3d11_compute`).

When the helper is missing, GPU bench falls back to NVML/`nvidia-smi` then host proxy — UI treats that as **fallback**, not the primary path.
