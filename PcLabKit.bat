@echo off
setlocal
cd /d "%~dp0"

set "PHP=php"
if exist "%~dp0runtime\php\php.exe" set "PHP=%~dp0runtime\php\php.exe"

if not exist "vendor\autoload.php" (
  echo PC Lab Kit is not installed yet.
  echo Run: .\scripts\install.ps1
  pause
  exit /b 1
)

if not exist ".env" if exist ".env.example" copy /Y ".env.example" ".env" >nul

if not exist "storage\database" mkdir "storage\database"
if not exist "storage\cache" mkdir "storage\cache"
if not exist "storage\settings" mkdir "storage\settings"

"%PHP%" bin\migrate.php >nul 2>&1

start "" "http://127.0.0.1:8080/diagnostic"
"%PHP%" -S 127.0.0.1:8080 -t public
