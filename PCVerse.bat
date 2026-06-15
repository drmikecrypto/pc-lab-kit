@echo off
setlocal
cd /d "%~dp0"

set "PHP=php"
if exist "%~dp0runtime\php\php.exe" set "PHP=%~dp0runtime\php\php.exe"

if not exist "vendor\autoload.php" (
  echo PCVerse is not fully installed. Run PCVerse-Setup again.
  pause
  exit /b 1
)

start "" "http://127.0.0.1:8080/diagnostic"
"%PHP%" -S 127.0.0.1:8080 -t public
