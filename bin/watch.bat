@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "WATCH_PS1=%~dp0..\src\watch.ps1"
if not exist "%WATCH_PS1%" (
    echo [ERROR] watch.ps1 not found. Place it alongside watch.bat.
    exit /b 2
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%WATCH_PS1%" %*
exit /b %errorlevel%
