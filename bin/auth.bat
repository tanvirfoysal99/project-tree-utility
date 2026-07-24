@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "AUTH_PS1=%~dp0..\src\auth.ps1"
if not exist "%AUTH_PS1%" (
    echo [ERROR] auth.ps1 not found. Place it alongside auth.bat.
    exit /b 2
)

set "CI_MODE=0"
if /i "%~1"=="--ci" (
    set "CI_MODE=1"
    shift
)
if defined TREE_CI set "CI_MODE=1"

if /i "%~1"=="store" goto do_store
if /i "%~1"=="clear" goto do_clear

if "%CI_MODE%"=="1" (
    echo [ERROR] CI mode requires an explicit action: store or clear.
    exit /b 2
)

echo.
echo ============================================
echo   auth.bat  ^|  Credential Vault
echo ============================================
echo.
echo [1] Store token
echo [2] Clear token
echo [0] Exit
set /p choice="Enter choice (0-2): "
if "%choice%"=="1" goto do_store
if "%choice%"=="2" goto do_clear
goto auth_exit

:do_store
set "TARGET=%~2"
set "USERNAME=%~3"
set "SECRET=%~4"
    if "%TARGET%"=="" (
        if "%CI_MODE%"=="1" (
            echo [ERROR] CI mode requires a credential target.
            exit /b 2
        )
        set /p TARGET="Credential target (e.g. git:https://gitlab.com): "
    )
if "%TARGET%"=="" (
    echo [ERROR] Credential target is required.
    goto auth_exit
)
if "%USERNAME%"=="" set "USERNAME=oauth2"

if "%CI_MODE%"=="1" (
    if "%SECRET%"=="" (
        echo [ERROR] CI mode requires the secret as an argument.
        exit /b 2
    )
    powershell -NoProfile -ExecutionPolicy Bypass -File "%AUTH_PS1%" -Action store -Target "%TARGET%" -Username "%USERNAME%" -Secret "%SECRET%" -Ci
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%AUTH_PS1%" -Action store -Target "%TARGET%" -Username "%USERNAME%"
)
goto auth_exit

:do_clear
set "TARGET=%~2"
    if "%TARGET%"=="" (
        if "%CI_MODE%"=="1" (
            echo [ERROR] CI mode requires a credential target.
            exit /b 2
        )
        set /p TARGET="Credential target to remove: "
    )
if "%TARGET%"=="" (
    echo [ERROR] Credential target is required.
    goto auth_exit
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%AUTH_PS1%" -Action clear -Target "%TARGET%"

:auth_exit
if "%CI_MODE%"=="1" exit /b %errorlevel%
endlocal
pause
