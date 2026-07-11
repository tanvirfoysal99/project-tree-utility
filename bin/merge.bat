@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

:: ============================================================
::  merge.bat
::  Structure File Merger
::  Part of the Project Tree Utility toolkit
::
::  Takes two structure files (any supported format) and merges
::  them into one unified dash-layout output.
::
::  Merge is TREE-AWARE via merge_tree.ps1.
::
::  Merge rules (tree-aware):
::    union    - all unique entries from both, B appended into A
::    a_over_b - A wins on name conflicts, B fills new entries
::    b_over_a - B wins on name conflicts, A fills existing tree
::
::  Standalone:  double-click or run from any directory.
::  Called by:   tree.bat (router), store.bat OPEN (pre-loaded)
::
::  Pre-load env vars (set by store.bat OPEN before calling):
::    MERGE_PRELOAD_A       path to File A
::    MERGE_PRELOAD_FMT_A   format of File A
::    MERGE_PRELOAD_B       path to File B
::    MERGE_PRELOAD_FMT_B   format of File B
:: ============================================================

set "SHARED=%~dp0..\src\internal\_shared.ps1"
set "MERGE_PS1=%~dp0..\src\merge_tree.ps1"
set "DETECTION=%~dp0detection.bat"
set "SPACE_UNIT_A=2"
set "SPACE_UNIT_B=2"

if not exist "%SHARED%" (
    echo [ERROR] _shared.ps1 not found. Place it alongside merge.bat.
    goto mrg_exit
)
if not exist "%MERGE_PS1%" (
    echo [ERROR] merge_tree.ps1 not found. Place it alongside merge.bat.
    goto mrg_exit
)
if not exist "%DETECTION%" (
    echo [ERROR] detection.bat not found. Place it alongside merge.bat.
    goto mrg_exit
)

echo.
echo ============================================
echo   merge.bat  ^|  Structure File Merger
echo   (tree-aware via merge_tree.ps1)
echo ============================================

:: ── Pre-loaded from store.bat OPEN? ─────────────────────────
if not "!MERGE_PRELOAD_A!"=="" (
    if exist "!MERGE_PRELOAD_A!" (
        set "FILE_A=!MERGE_PRELOAD_A!"
        set "FORMAT_A=!MERGE_PRELOAD_FMT_A!"
        echo [INFO] File A pre-loaded from library: !MERGE_PRELOAD_A!
        set "MERGE_PRELOAD_A="
        set "MERGE_PRELOAD_FMT_A="
        goto mrg_step2
    )
)

:: ── Step 1: File A ──────────────────────────────────────────
echo.
echo --- File A (base structure) ---
set /p FILE_A="File path (or press Enter for '_struc_file.txt'): "
if "!FILE_A!"=="" set "FILE_A=_struc_file.txt"
echo !FILE_A!| findstr /C:"\" >nul
if errorlevel 1 set "FILE_A=%~dp0!FILE_A!"

if not exist "!FILE_A!" (
    echo [ERROR] File A not found: !FILE_A!
    goto mrg_exit
)

for /f "usebackq delims=" %%D in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    ". '%SHARED:\=/%'; Write-Output (Get-StructureFormat -FilePath '!FILE_A:\=/!')"`) do set "FORMAT_A=%%D"

if "!FORMAT_A!"=="empty"   ( echo [ERROR] File A is empty. & goto mrg_exit )
if "!FORMAT_A!"=="unknown" ( call :ask_format FORMAT_A SPACE_UNIT_A )
echo [OK] File A: !FORMAT_A! format

call "%~dp0security.bat" VALIDATE_FILE "!FILE_A!" "!FORMAT_A!"
if %errorlevel% neq 0 ( echo [ERROR] File A failed validation. & goto mrg_exit )

:: ── Step 2: File B ──────────────────────────────────────────
:mrg_step2
if not "!MERGE_PRELOAD_B!"=="" (
    if exist "!MERGE_PRELOAD_B!" (
        set "FILE_B=!MERGE_PRELOAD_B!"
        set "FORMAT_B=!MERGE_PRELOAD_FMT_B!"
        echo [INFO] File B pre-loaded from library: !MERGE_PRELOAD_B!
        set "MERGE_PRELOAD_B="
        set "MERGE_PRELOAD_FMT_B="
        goto mrg_step3
    )
)

echo.
echo --- File B (structure to merge in) ---
set /p FILE_B="File path: "
if "!FILE_B!"=="" ( echo [ERROR] File B path is required. & goto mrg_exit )
echo !FILE_B!| findstr /C:"\" >nul
if errorlevel 1 set "FILE_B=%~dp0!FILE_B!"

if not exist "!FILE_B!" (
    echo [ERROR] File B not found: !FILE_B!
    goto mrg_exit
)

for /f "usebackq delims=" %%D in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    ". '%SHARED:\=/%'; Write-Output (Get-StructureFormat -FilePath '!FILE_B:\=/!')"`) do set "FORMAT_B=%%D"

if "!FORMAT_B!"=="empty"   ( echo [ERROR] File B is empty. & goto mrg_exit )
if "!FORMAT_B!"=="unknown" ( call :ask_format FORMAT_B SPACE_UNIT_B )
echo [OK] File B: !FORMAT_B! format

call "%~dp0security.bat" VALIDATE_FILE "!FILE_B!" "!FORMAT_B!"
if %errorlevel% neq 0 ( echo [ERROR] File B failed validation. & goto mrg_exit )

:: ── Step 3: Optional analyse ────────────────────────────────
:mrg_step3
echo.
set /p do_analyse="Analyse both files before merging? (y/N): "
if /i "!do_analyse!"=="y" (
    echo.
    echo [INFO] Analysing File A ...
    call "%DETECTION%" ANALYSE "!FILE_A!" "!FORMAT_A!"
    echo.
    echo [INFO] Analysing File B ...
    call "%DETECTION%" ANALYSE "!FILE_B!" "!FORMAT_B!"
    echo.
    pause
)

:: ── Step 4: Merge strategy ──────────────────────────────────
echo.
echo Merge strategy:
echo [1] Union       - Keep all unique entries from both files
echo [2] A over B    - File A wins on conflicts, B fills gaps
echo [3] B over A    - File B wins on conflicts, A fills gaps
set /p mrg_strategy="Enter choice (1-3, default 1): "
if "!mrg_strategy!"=="2" ( set "STRATEGY=a_over_b" )
if "!mrg_strategy!"=="3" ( set "STRATEGY=b_over_a" )
if "!STRATEGY!"==""       set "STRATEGY=union"

:: ── Step 5: Output file ─────────────────────────────────────
echo.
set /p OUT_NAME="Output file name (without extension, press Enter for 'merged_structure'): "
if "!OUT_NAME!"=="" set "OUT_NAME=merged_structure"
set "OUT_FILE=%~dp0!OUT_NAME!.txt"

:: ── Step 6: Tree-aware merge ────────────────────────────────
echo.
echo [INFO] Running tree-aware merge ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%MERGE_PS1%" ^
    -FileA "!FILE_A!" ^
    -FormatA "!FORMAT_A!" ^
    -FileB "!FILE_B!" ^
    -FormatB "!FORMAT_B!" ^
    -Strategy "!STRATEGY!" ^
    -OutputFile "!OUT_FILE!" ^
    -SpaceUnitA !SPACE_UNIT_A! ^
    -SpaceUnitB !SPACE_UNIT_B!

if %errorlevel% neq 0 (
    echo [ERROR] Merge failed.
    goto mrg_exit
)

:: ── Step 7: Clipboard ───────────────────────────────────────
echo.
set /p do_clip="Copy output to clipboard? (y/N): "
if /i "!do_clip!"=="y" (
    type "!OUT_FILE!" | clip
    echo [OK] Copied to clipboard.
)

:: ── Step 8: Save to library? ────────────────────────────────
if exist "%~dp0store.bat" (
    echo.
    set /p do_store="Save this merged result to the project tree library? (y/N): "
    if /i "!do_store!"=="y" (
        call "%~dp0store.bat" SAVE "!OUT_FILE!" "dash" "merge"
    )
)

:: ── Step 9: Verify result? ──────────────────────────────────
echo.
set /p do_verify="Run verify.bat on the merged output against a live directory? (y/N): "
if /i "!do_verify!"=="y" (
    if exist "%~dp0verify.bat" (
        call "%~dp0verify.bat"
    ) else (
        echo [ERROR] verify.bat not found.
    )
)

:: ── Step 10: Handoff to scaffold? ───────────────────────────
echo.
echo Scaffold the merged structure into a project?
echo [1] Yes - launch scaffold.bat
echo [2] No  - I am done
set /p hoff="Enter choice (1-2): "
if "!hoff!"=="1" (
    if exist "%~dp0scaffold.bat" (
        call "%~dp0scaffold.bat" "!OUT_FILE!" "dash"
    ) else (
        echo [ERROR] scaffold.bat not found.
    )
)

echo.
echo ============================================
echo   merge.bat done.
echo ============================================

goto mrg_exit

:: ============================================================
:: Subroutine: ask_format
:: ============================================================
:ask_format
echo [INFO] Could not auto-detect format for this file.
echo [1] Dash    [2] Tab    [3] Tree symbols    [4] Fixed spaces
set /p _man_fmt="Enter choice (1-4): "
if "!_man_fmt!"=="1" ( set "%~1=dash"    )
if "!_man_fmt!"=="2" ( set "%~1=tab"     )
if "!_man_fmt!"=="3" ( set "%~1=treesym" )
if "!_man_fmt!"=="4" (
    set "%~1=space"
    set /p _sp="Spaces per depth level (default 2): "
    if "!_sp!"=="" set "_sp=2"
    set "%~2=!_sp!"
)
exit /b 0

:mrg_exit
endlocal
pause
