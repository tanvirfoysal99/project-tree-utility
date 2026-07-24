@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "CI_MODE=0"
if /i "%~1"=="--ci" (
    set "CI_MODE=1"
    shift
)
if defined TREE_CI set "CI_MODE=1"

set "VERIFY_PS1=%~dp0..\src\verify.ps1"
if not exist "%VERIFY_PS1%" (
    echo [ERROR] verify.ps1 not found. Place it alongside verify.bat.
    exit /b 2
)

if "%CI_MODE%"=="1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%VERIFY_PS1%" -Ci %1 %2 %3 %4 %5 %6 %7 %8 %9
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%VERIFY_PS1%" %*
)
exit /b %errorlevel%
