@echo off
title PCVerse Probe Server
cd /d "%~dp0"
echo Starting PCVerse Probe on http://127.0.0.1:18765
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PCVerseProbeServe.ps1"
pause
