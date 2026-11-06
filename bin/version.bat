@echo off
setlocal EnableExtensions DisableDelayedExpansion
if defined PTU_LEGACY goto legacy_entry
if not "%~1"=="" goto cli_entry
if /i "%TREE_CI%"=="1" goto cli_entry
if /i "%TREE_CI%"=="true" goto cli_entry
if /i "%TREE_CI%"=="yes" goto cli_entry
goto legacy_entry
:cli_entry
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\src\cli.ps1" version %*
exit /b %errorlevel%
:legacy_entry
endlocal
@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "VERSION_PS1=%~dp0..\src\version.ps1"
if not exist "%VERSION_PS1%" (
    echo [ERROR] version.ps1 not found.
    exit /b 2
)

set "CI_MODE=0"
if /i "%~1"=="--ci"            set "CI_MODE=1"
if defined TREE_CI                set "CI_MODE=1"
if /i "%~1"=="--check"         goto do_check
if /i "%~1"=="--check-update"  goto do_check

if "%CI_MODE%"=="1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%VERSION_PS1%" -Ci
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%VERSION_PS1%"
)
goto ver_exit

:do_check
if "%CI_MODE%"=="1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%VERSION_PS1%" -CheckUpdate -Ci
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%VERSION_PS1%" -CheckUpdate
)

:ver_exit
set "VERSION_RESULT=%errorlevel%"
if "%CI_MODE%"=="0" pause
endlocal & exit /b %VERSION_RESULT%
