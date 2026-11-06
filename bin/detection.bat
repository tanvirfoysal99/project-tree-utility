@echo off
setlocal EnableExtensions DisableDelayedExpansion
if defined PTU_LEGACY goto legacy_entry
if not "%~1"=="" goto cli_entry
if /i "%TREE_CI%"=="1" goto cli_entry
if /i "%TREE_CI%"=="true" goto cli_entry
if /i "%TREE_CI%"=="yes" goto cli_entry
goto legacy_entry
:cli_entry
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\src\cli.ps1" detection %*
exit /b %errorlevel%
:legacy_entry
endlocal
@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

:: ============================================================
::  detection.bat
::  Tree-Aware Structure Analyser & Relationship Detector
::  Part of the Project Tree Utility toolkit
::
::  Subcommand usage (called by merge.bat):
::    call detection.bat BUILD_TREE "<fileA>" "<fmtA>" "<fileB>" "<fmtB>" "<strategy>" "<outFile>"
::    call detection.bat ANALYSE    "<file>"  "<fmt>"
::
::  Standalone: double-click for interactive menu.
::
::  Exit codes: 0=success  1=failure  2=internal error
:: ============================================================

set "SHARED=%~dp0..\src\internal\_shared.ps1"

if not exist "%SHARED%" (
    echo [ERROR] _shared.ps1 not found alongside detection.bat.
    exit /b 2
)

:: ── Subcommand dispatch ──────────────────────────────────────
if /i "%~1"=="BUILD_TREE" goto sub_build_tree
if /i "%~1"=="ANALYSE"    goto sub_analyse
goto interactive

:: ============================================================
:: SUBCOMMAND: BUILD_TREE
:: Tree-aware merge through the permanent PowerShell backend.
:: %2=fileA  %3=fmtA  %4=fileB  %5=fmtB  %6=strategy  %7=outFile
:: ============================================================
:sub_build_tree
set "DT_FILE_A=%~2"
set "DT_FMT_A=%~3"
set "DT_FILE_B=%~4"
set "DT_FMT_B=%~5"
set "DT_STRATEGY=%~6"
set "DT_OUT=%~7"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\src\detection.ps1" -Action Merge
exit /b %errorlevel%

:sub_analyse
set "DT_FILE=%~2"
set "DT_FMT=%~3"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\src\detection.ps1" -Action Analyse
exit /b %errorlevel%
:interactive
echo.
echo ============================================
echo   detection.bat  ^|  Tree Relationship Analyser
echo ============================================
echo.
echo [1] Analyse a structure file
echo [2] Diagnose a merge  ^(analyse both files^)
echo [3] Run tree-aware merge
echo [0] Exit
echo.
set /p det_choice="Enter choice (0-3): "

if "!det_choice!"=="0" goto det_exit
if "!det_choice!"=="1" goto ia_analyse
if "!det_choice!"=="2" goto ia_diagnose
if "!det_choice!"=="3" goto ia_merge
echo Invalid choice.
goto interactive

:ia_analyse
echo.
set /p ia_file="Structure file path (or press Enter for '_struc_file.txt'): "
if "!ia_file!"=="" set "ia_file=_struc_file.txt"
echo !ia_file!| findstr /C:"\" >nul
if errorlevel 1 set "ia_file=%~dp0!ia_file!"
if not exist "!ia_file!" ( echo [ERROR] File not found. & goto interactive )
call :detect_format "!ia_file!" ia_fmt
call "%~f0" ANALYSE "!ia_file!" "!ia_fmt!"
echo. & pause
goto interactive

:ia_diagnose
echo.
echo --- File A ---
set /p ia_fileA="File A path: "
echo !ia_fileA!| findstr /C:"\" >nul
if errorlevel 1 set "ia_fileA=%~dp0!ia_fileA!"
if not exist "!ia_fileA!" ( echo [ERROR] Not found. & goto interactive )
call :detect_format "!ia_fileA!" ia_fmtA
echo.
echo --- File B ---
set /p ia_fileB="File B path: "
echo !ia_fileB!| findstr /C:"\" >nul
if errorlevel 1 set "ia_fileB=%~dp0!ia_fileB!"
if not exist "!ia_fileB!" ( echo [ERROR] Not found. & goto interactive )
call :detect_format "!ia_fileB!" ia_fmtB
echo.
echo ============================================
echo   ANALYSIS: FILE A
echo ============================================
call "%~f0" ANALYSE "!ia_fileA!" "!ia_fmtA!"
echo.
echo ============================================
echo   ANALYSIS: FILE B
echo ============================================
call "%~f0" ANALYSE "!ia_fileB!" "!ia_fmtB!"
echo. & pause
goto interactive

:ia_merge
echo.
echo --- File A (base) ---
set /p ia_fileA="File A path: "
echo !ia_fileA!| findstr /C:"\" >nul
if errorlevel 1 set "ia_fileA=%~dp0!ia_fileA!"
if not exist "!ia_fileA!" ( echo [ERROR] Not found. & goto interactive )
call :detect_format "!ia_fileA!" ia_fmtA
echo.
echo --- File B (merge in) ---
set /p ia_fileB="File B path: "
echo !ia_fileB!| findstr /C:"\" >nul
if errorlevel 1 set "ia_fileB=%~dp0!ia_fileB!"
if not exist "!ia_fileB!" ( echo [ERROR] Not found. & goto interactive )
call :detect_format "!ia_fileB!" ia_fmtB
echo.
echo [1] Union  [2] A over B  [3] B over A
set /p ia_strat="Strategy (1-3, default 1): "
if "!ia_strat!"=="2" ( set "ia_strategy=a_over_b" ) else if "!ia_strat!"=="3" ( set "ia_strategy=b_over_a" ) else set "ia_strategy=union"
echo.
set /p ia_out="Output filename (no extension, press Enter for 'merged_structure'): "
if "!ia_out!"=="" set "ia_out=merged_structure"
set "ia_outfile=%~dp0!ia_out!.txt"
call "%~f0" BUILD_TREE "!ia_fileA!" "!ia_fmtA!" "!ia_fileB!" "!ia_fmtB!" "!ia_strategy!" "!ia_outfile!"
if not errorlevel 1 (
    echo.
    set /p do_clip="Copy to clipboard? (y/N): "
    if /i "!do_clip!"=="y" ( type "!ia_outfile!" | clip & echo [OK] Copied. )
    echo.
    set /p do_scaffold="Scaffold this structure? (y/N): "
    if /i "!do_scaffold!"=="y" (
        if exist "%~dp0scaffold.bat" ( call "%~dp0scaffold.bat" "!ia_outfile!" "dash" ) else echo [ERROR] scaffold.bat not found.
    )
)
echo. & pause
goto interactive

:: ============================================================
:: Subroutine: detect_format
:: %1 = file path   %2 = variable name to receive format
:: ============================================================
:detect_format
set "_df_file=%~1"
set "_df_var=%~2"
for /f "usebackq delims=" %%F in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\src\wrapper_actions.ps1" -Action DetectAnalysis`) do set "_df_result=%%F"
if "!_df_result!"=="unknown" (
    echo [INFO] Format not auto-detected. Select:
    echo [1] Dash  [2] Tab  [3] Tree symbols  [4] Fixed spaces
    set /p _df_man="Choice (1-4): "
    if "!_df_man!"=="1" set "_df_result=dash"
    if "!_df_man!"=="2" set "_df_result=tab"
    if "!_df_man!"=="3" set "_df_result=treesym"
    if "!_df_man!"=="4" set "_df_result=space"
)
set "%_df_var%=!_df_result!"
echo [OK] Format: !_df_result!
exit /b 0

:det_exit
endlocal
pause
