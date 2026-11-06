@echo off
setlocal EnableExtensions DisableDelayedExpansion
if defined PTU_LEGACY goto legacy_entry
if not "%~1"=="" goto cli_entry
if /i "%TREE_CI%"=="1" goto cli_entry
if /i "%TREE_CI%"=="true" goto cli_entry
if /i "%TREE_CI%"=="yes" goto cli_entry
goto legacy_entry
:cli_entry
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\src\cli.ps1" verify %*
exit /b %errorlevel%
:legacy_entry
endlocal
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
