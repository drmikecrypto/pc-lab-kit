# DiskSpd (optional)

Place the Microsoft [DiskSpd](https://github.com/microsoft/diskspd) binary here for CrystalDiskMark-like storage profiles:

```
agent/pclab_probe/tools/DiskSpd/diskspd.exe
```

When present, `Invoke-ProbeStorageBenchmark` runs:

| Profile | Meaning |
|---------|---------|
| SEQ1M Q8T1 | Sequential 1 MiB, queue depth 8, 1 thread |
| SEQ1M Q1T1 | Sequential 1 MiB, queue depth 1, 1 thread |
| RND4K Q32T1 | Random 4 KiB, queue depth 32, 1 thread |
| RND4K Q1T1 | Random 4 KiB, queue depth 1, 1 thread |

Without DiskSpd, the probe falls back to WinSAT or a file-copy estimate.
