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
if "%CI_MODE%"=="0" pause
endlocal
