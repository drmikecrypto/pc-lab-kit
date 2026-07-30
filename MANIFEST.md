# File manifest — PC Lab Kit

Standalone web lab + Windows probe. Refresh with `Get-ChildItem -Recurse -File`.

## agent/

```
agent/pclab_probe/
  PcLabProbe.ps1
  PcLabProbeServe.ps1
  Start-PcLabProbe.bat
  PcLabHwMon.exe                 # built artifact (gitignored)
  PcLabHwMon/Program.cs, PcLabHwMon.csproj
  ProbeLib/*.ps1                 # cpu, gpu, rgb, stress, benchmark, overclock, orchestrator, …
  tools/OpenRGB/README.md
```

## backend (PHP)

```
app/Controllers/DiagnosticController.php
app/Controllers/DiagnosticApiController.php
app/Controllers/DownloadController.php
app/Controllers/SettingsApiController.php
app/Controllers/AppUpdateController.php
app/Services/Diagnostic*.php
app/Services/LabReportExportService.php
app/Services/StressCertificateService.php
app/Services/HardwareKnowledgeGraphService.php
app/Services/ToonSerializer.php
app/Services/AppUpdateService.php
routes/web.php
config/app.php
config/diagnostic.php
config/tool_catalog.php
resources/views/diagnostic.php
resources/views/layout.php
public/assets/js/diagnostic-*.js
public/assets/css/diagnostic-*.css
public/assets/css/lab-shell.css
```

## scripts/

```
scripts/install.ps1 / install.sh
scripts/start.ps1 / start.sh
scripts/bootstrap-build-tools.ps1 / .sh
scripts/build-pclab-hwmon.ps1
scripts/build-agent-bundle.ps1
scripts/fix-ps1-encoding.ps1
scripts/generate_diagnostic_games.php
```

## launchers

```
PcLabKit.bat
PcLabKit
```

## downloads (built, gitignored)

```
public/downloads/pc-lab-kit-probe-windows.zip
```

## Not in this repository

Native Qt desktop, Windows/Linux installers, and Flutter/mobile clients were removed so this kit stands alone.
