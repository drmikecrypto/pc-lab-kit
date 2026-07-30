@echo off
title PcLab Probe Server
cd /d "%~dp0"

:: CPU die temps and most motherboard sensors need a kernel helper that only
:: loads when elevated. Self-elevate so an assembler does not have to remember.
net session >nul 2>&1
if %errorlevel% NEQ 0 (
    echo Requesting Administrator so CPU / board sensors can be read...
    powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo Starting PcLab Probe on http://127.0.0.1:18765
echo Running elevated - full thermal coverage enabled.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PcLabProbeServe.ps1"
pause
