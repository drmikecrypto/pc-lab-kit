# PCVerse Native (v2)

C++20 core + Qt 6 desktop. Replaces the PHP/browser lab.

See **[ARCHITECTURE.md](ARCHITECTURE.md)** for the full redesign.

## Build (early scaffold)

Requirements: CMake 3.20+, C++20 compiler, Git (for FetchContent deps).

```powershell
cd native
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
.\build\Release\pcverse_cli.exe --check-update
```

```bash
cd native
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
./build/pcverse_cli --check-update
```

## Layout

| Path | Role |
|------|------|
| `core/` | Hardware, bench, stress, AI client, GitHub update |
| `apps/pcverse_cli/` | Dev CLI until Qt shell lands |
| `probe/` | Elevated sensor/stress service (stub) |
