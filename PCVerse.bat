@echo off
setlocal
cd /d "%~dp0"

if exist "%~dp0bin\pcverse.exe" (
  start "" "%~dp0bin\pcverse.exe"
  exit /b 0
)

set "NATIVE=%~dp0native\build\apps\pcverse\Release\pcverse.exe"
if exist "%NATIVE%" (
  start "" "%NATIVE%"
  exit /b 0
)

set "PHP=php"
if exist "%~dp0runtime\php\php.exe" set "PHP=%~dp0runtime\php\php.exe"

if not exist "vendor\autoload.php" (
  echo PCVerse is not fully installed. Run PCVerse-Setup again.
  echo.
  echo Dev: build native desktop with  scripts\build-native-desktop.ps1
  pause
  exit /b 1
)

start "" "http://127.0.0.1:8080/diagnostic"
"%PHP%" -S 127.0.0.1:8080 -t public
