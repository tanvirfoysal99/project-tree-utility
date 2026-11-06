@echo off
setlocal EnableExtensions DisableDelayedExpansion
if defined PTU_LEGACY goto legacy_entry
if not "%~1"=="" goto cli_entry
if /i "%TREE_CI%"=="1" goto cli_entry
if /i "%TREE_CI%"=="true" goto cli_entry
if /i "%TREE_CI%"=="yes" goto cli_entry
goto legacy_entry
:cli_entry
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\src\cli.ps1" watch %*
exit /b %errorlevel%
:legacy_entry
endlocal
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
