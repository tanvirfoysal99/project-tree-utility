@echo off
setlocal EnableExtensions DisableDelayedExpansion
if defined PTU_LEGACY goto legacy_entry
if not "%~1"=="" goto cli_entry
if /i "%TREE_CI%"=="1" goto cli_entry
if /i "%TREE_CI%"=="true" goto cli_entry
if /i "%TREE_CI%"=="yes" goto cli_entry
goto legacy_entry
:cli_entry
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\src\cli.ps1" scaffold %*
exit /b %errorlevel%
:legacy_entry
endlocal
@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

:: ============================================================
::  scaffold.bat
::  Project Scaffolding Engine
::  Part of the Project Tree Utility toolkit
::
::  Reads a structure file and materialises the project on disk.
::
::  Standalone:  double-click or run from any directory.
::  Called by:   tree.bat (router), export.bat (handoff)
::  Arguments:
::    %1 = optional path to structure file
::    %2 = optional format hint (dash/tab/treesym/space)
:: ============================================================

set "SHARED=%~dp0..\src\internal\_shared.ps1"
set "SCF_VALIDATE_PS1=%~dp0..\src\scaffold_validate.ps1"
set "SCF_RESULT=2"

set "SPACE_UNIT=2"
set "DRY_RUN=0"
set "OVERWRITE_MODE=skip"
set "TEMPLATE_NAME="
set "USE_TEMPLATE=0"

if /i "%~1"=="--template" (
    if not "%~2"=="" (
        set "TEMPLATE_NAME=%~2"
        set "USE_TEMPLATE=1"
        echo [INFO] Template preset requested: %~2
    ) else (
        echo [ERROR] --template requires a template name.
        goto scf_exit
    )
)

if not exist "%SHARED%" (
    echo [ERROR] _shared.ps1 not found. Place it alongside scaffold.bat.
    goto scf_exit
)
if not exist "%SCF_VALIDATE_PS1%" (
    echo [ERROR] scaffold_validate.ps1 not found. Place it alongside scaffold.bat.
    goto scf_exit
)

echo.
echo ============================================
echo   scaffold.bat  ^|  Project Scaffolding Engine
echo ============================================

:: ── Step 0: Template picker (interactive mode only) ────────
if "!USE_TEMPLATE!"=="0" if "!STRUC_FILE!"=="" if "%~1"=="" (
    echo.
    echo Use a built-in template preset?
    echo [1] react-vite       - React + Vite + TypeScript
    echo [2] hono-worker      - Hono on Cloudflare Workers
    echo [3] monorepo-pnpm    - pnpm monorepo workspace
    echo [4] No - use a structure file  ^(default^)
    echo.
    set /p tmpl_choice="Enter choice (1-4, or press Enter for option 4): "
    if "!tmpl_choice!"=="1" ( set "TEMPLATE_NAME=react-vite"    & set "USE_TEMPLATE=1" )
    if "!tmpl_choice!"=="2" ( set "TEMPLATE_NAME=hono-worker"   & set "USE_TEMPLATE=1" )
    if "!tmpl_choice!"=="3" ( set "TEMPLATE_NAME=monorepo-pnpm" & set "USE_TEMPLATE=1" )
    if "!USE_TEMPLATE!"=="1" echo [INFO] Template preset selected: !TEMPLATE_NAME!
)

:: ── Step 1: Locate structure file ───────────────────────────
set "STRUC_FILE="

if "!USE_TEMPLATE!"=="0" if not "%~1"=="" (
    if exist "%~1" (
        set "STRUC_FILE=%~1"
        echo [INFO] Structure file supplied: %~1
    ) else (
        echo [WARN] Supplied path not found: %~1
    )
)

if "!USE_TEMPLATE!"=="0" if "!STRUC_FILE!"=="" (
    echo.
    set /p STRUC_FILE="Structure file path (or press Enter for '_struc_file.txt'): "
    if "!STRUC_FILE!"=="" set "STRUC_FILE=_struc_file.txt"
    echo !STRUC_FILE!| findstr /C:"\" >nul
    if errorlevel 1 set "STRUC_FILE=%~dp0!STRUC_FILE!"
)

if "!USE_TEMPLATE!"=="0" if not exist "!STRUC_FILE!" (
    echo [ERROR] File not found: !STRUC_FILE!
    goto scf_exit
)
if "!USE_TEMPLATE!"=="0" echo [OK] File located.

:: ── Step 2: Determine format ────────────────────────────────
set "STRUC_FORMAT="

if "!USE_TEMPLATE!"=="1" (
    set "STRUC_FORMAT=template"
) else if not "%~2"=="" (
    set "STRUC_FORMAT=%~2"
    echo [INFO] Format supplied by caller: %~2
) else (
    for /f "usebackq delims=" %%D in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\src\wrapper_actions.ps1" -Action DetectScaffold`) do set "STRUC_FORMAT=%%D"

    if "!STRUC_FORMAT!"=="empty" (
        echo [ERROR] File is empty or contains only comments.
        goto scf_exit
    )
    if "!STRUC_FORMAT!"=="unknown" (
        echo [INFO] Format not auto-detected.
        echo [1] Dash    [2] Tab    [3] Tree symbols    [4] Fixed spaces
        set /p man_fmt="Enter choice (1-4): "
        if "!man_fmt!"=="1" set "STRUC_FORMAT=dash"
        if "!man_fmt!"=="2" set "STRUC_FORMAT=tab"
        if "!man_fmt!"=="3" set "STRUC_FORMAT=treesym"
        if "!man_fmt!"=="4" (
            set "STRUC_FORMAT=space"
            set /p SPACE_UNIT="Spaces per depth level (default 2): "
            if "!SPACE_UNIT!"=="" set "SPACE_UNIT=2"
        )
        if "!STRUC_FORMAT!"=="" (
            echo [ERROR] No format selected.
            goto scf_exit
        )
    )
    echo [INFO] Detected format: !STRUC_FORMAT!
)

:: ── Step 3: Project name ────────────────────────────────────
echo.
set /p PROJECT_NAME="Project name (used for folder and file stubs, press Enter for 'my-project'): "
if "!PROJECT_NAME!"=="" set "PROJECT_NAME=my-project"

:: ── Step 4: Target directory ────────────────────────────────
echo.
echo Where to create the project?
echo [1] Subfolder here  (alongside scaffold.bat)
echo [2] Custom path
set /p tgt_choice="Enter choice (1-2, default 1): "
if "!tgt_choice!"=="" set "tgt_choice=1"

if "!tgt_choice!"=="1" (
    set "TARGET_BASE=%~dp0"
) else (
    set /p TARGET_BASE="Enter full target path: "
    if "!TARGET_BASE!"=="" (
        echo [ERROR] No path entered.
        goto scf_exit
    )
)
if "!TARGET_BASE:~-1!"=="\" if not "!TARGET_BASE!"=="!TARGET_BASE:~0,3!" set "TARGET_BASE=!TARGET_BASE:~0,-1!"
echo [INFO] Project base: !TARGET_BASE!
echo [INFO] Project folder name: !PROJECT_NAME!

:: ── Step 5: Security check ──────────────────────────────────
echo.
echo [INFO] Running security checks ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\src\wrapper_actions.ps1" -Action ValidateScaffold
if errorlevel 1 (
    set "SCF_RESULT=2"
    echo [ERROR] Security checks failed. Aborting.
    goto scf_exit
)
:: ── Step 6: Dry run? ────────────────────────────────────────
echo.
set /p dry_run="Dry run first (preview without writing)? (y/N): "
if /i "!dry_run!"=="y" set "DRY_RUN=1"

:: ── Step 7: Overwrite mode ──────────────────────────────────
echo.
echo If a file or folder already exists:
echo [1] Skip   [2] Overwrite   [3] Ask each time
set /p ow_choice="Enter choice (1-3, default 1): "
if "!ow_choice!"=="2" set "OVERWRITE_MODE=overwrite"
if "!ow_choice!"=="3" set "OVERWRITE_MODE=ask"

:: Run the permanent backend; all user values arrive through the environment.
call :run_scaffold
set "SCF_RESULT=!errorlevel!"
if not "!SCF_RESULT!"=="0" goto scf_exit
if "!DRY_RUN!"=="1" (
    set /p go_real="Run for real now and create the project? (y/N): "
    if /i "!go_real!"=="y" (
        set "DRY_RUN=0"
        call :run_scaffold
        set "SCF_RESULT=!errorlevel!"
    )
)
goto scf_exit

:run_scaffold
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\src\scaffold.ps1" -FromEnvironment
exit /b %errorlevel%

:scf_exit
pause
endlocal & exit /b %SCF_RESULT%
