@echo off
setlocal EnableExtensions DisableDelayedExpansion
if defined PTU_LEGACY goto legacy_entry
if not "%~1"=="" goto cli_entry
if /i "%TREE_CI%"=="1" goto cli_entry
if /i "%TREE_CI%"=="true" goto cli_entry
if /i "%TREE_CI%"=="yes" goto cli_entry
goto legacy_entry
:cli_entry
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\src\cli.ps1" import %*
exit /b %errorlevel%
:legacy_entry
endlocal
@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

:: ============================================================
::  import.bat
::  Structure File Importer & Format Converter
::  Part of the Project Tree Utility toolkit
::
::  Reads any supported structure file format, validates it,
::  and converts it to a chosen output format.
::
::  Standalone:  double-click or run from any directory.
::  Called by:   tree.bat (router)
::  Pre-loaded:  store.bat OPEN sets IMPORT_PRELOAD_FILE and
::               IMPORT_PRELOAD_FMT to skip steps 1-2.
:: ============================================================

set "SHARED=%~dp0..\src\internal\_shared.ps1"
set "IMP_RESULT=2"
set "SPACE_UNIT=2"

if not exist "%SHARED%" (
    echo [ERROR] _shared.ps1 not found. Place it alongside import.bat.
    goto imp_exit
)

echo.
echo ============================================
echo   import.bat  ^|  Structure File Importer
echo ============================================

:: ── Pre-loaded from store.bat OPEN? ─────────────────────────
if not "!IMPORT_PRELOAD_FILE!"=="" (
    if exist "!IMPORT_PRELOAD_FILE!" (
        set "IMP_FILE=!IMPORT_PRELOAD_FILE!"
        set "IMP_FORMAT=!IMPORT_PRELOAD_FMT!"
        echo [INFO] Using library file: !IMPORT_PRELOAD_FILE!
        set "IMPORT_PRELOAD_FILE="
        set "IMPORT_PRELOAD_FMT="
        goto imp_step3
    )
)

:: ── Step 1: Locate the file ─────────────────────────────────
echo.
set /p IMP_FILE="Enter file name or path to import (or press Enter for '_struc_file.txt'): "
if "!IMP_FILE!"=="" set "IMP_FILE=_struc_file.txt"

echo !IMP_FILE!| findstr /C:"\" >nul
if errorlevel 1 set "IMP_FILE=%~dp0!IMP_FILE!"

if not exist "!IMP_FILE!" (
    echo [ERROR] File not found: !IMP_FILE!
    goto imp_exit
)
echo [OK] File located: !IMP_FILE!

:: ── Step 2: Detect format ───────────────────────────────────
echo.
for /f "usebackq delims=" %%D in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\src\wrapper_actions.ps1" -Action DetectImport`) do set "IMP_DETECTED=%%D"

set "IMP_FORMAT="

if "!IMP_DETECTED!"=="empty" (
    echo [ERROR] File is empty or contains only comments/blank lines.
    goto imp_exit
)
if "!IMP_DETECTED!"=="dash"    ( echo [INFO] Detected: Dash layout  & set "IMP_FORMAT=dash"    )
if "!IMP_DETECTED!"=="tab"     ( echo [INFO] Detected: Tab-indented & set "IMP_FORMAT=tab"     )
if "!IMP_DETECTED!"=="treesym" ( echo [INFO] Detected: Tree-style   & set "IMP_FORMAT=treesym" )
if "!IMP_DETECTED!"=="json" set "IMP_FORMAT=json"
if "!IMP_DETECTED!"=="yaml" set "IMP_FORMAT=yaml"

if "!IMP_FORMAT!"=="" (
    echo [INFO] Format not auto-detected. Please specify:
    echo [1] Dash count     ^(- folder, -- file^)
    echo [2] Tab indent     ^(one tab per level^)
    echo [3] Tree symbols   ^(tree /f style^)
    echo [4] Fixed spaces   ^(N spaces per level^)
    set /p man_fmt="Enter choice (1-4): "
    if "!man_fmt!"=="1" set "IMP_FORMAT=dash"
    if "!man_fmt!"=="2" set "IMP_FORMAT=tab"
    if "!man_fmt!"=="3" set "IMP_FORMAT=treesym"
    if "!man_fmt!"=="4" (
        set "IMP_FORMAT=space"
        set /p SPACE_UNIT="Spaces per depth level (default 2): "
        if "!SPACE_UNIT!"=="" set "SPACE_UNIT=2"
    )
    if "!IMP_FORMAT!"=="" (
        echo [ERROR] No format selected.
        goto imp_exit
    )
)

:: ── Step 3: Validate via security.bat ───────────────────────
:imp_step3
echo.
call "%~dp0security.bat" VALIDATE_FILE "!IMP_FILE!" "!IMP_FORMAT!"
if errorlevel 1 (
    echo [ERROR] Validation failed. Check the file and re-run.
    goto imp_exit
)

:: ── Step 4: Choose output format ────────────────────────────
echo.
echo Convert to which output format?
echo [1] Markdown  ^(.md^)
echo [2] Plain text  ^(.txt^)
echo [3] Importable dash layout  ^(.txt^)
echo [4] View summary only  ^(no file output^)
set /p out_fmt="Enter choice (1-4): "

if "!out_fmt!"=="1" ( set "OUT_TYPE=md"         & set "OUT_EXT=.md"  )
if "!out_fmt!"=="2" ( set "OUT_TYPE=txt"        & set "OUT_EXT=.txt" )
if "!out_fmt!"=="3" ( set "OUT_TYPE=importable" & set "OUT_EXT=.txt" )
if "!out_fmt!"=="4" ( set "OUT_TYPE=summary"    & set "OUT_EXT="     )
if "!OUT_TYPE!"=="" (
    echo Invalid choice. Defaulting to plain text.
    set "OUT_TYPE=txt"
    set "OUT_EXT=.txt"
)

:: ── Step 5: Output filename ─────────────────────────────────
if not "!OUT_TYPE!"=="summary" (
    echo.
    set /p OUT_NAME="Output file name (without extension, or press Enter for 'imported_structure'): "
    if "!OUT_NAME!"=="" set "OUT_NAME=imported_structure"
    set "OUT_FILE=%~dp0!OUT_NAME!!OUT_EXT!"
)

:: ── Step 6: Generate output via PowerShell ──────────────────
echo.
echo [INFO] Processing ...

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\src\wrapper_actions.ps1" -Action ConvertImport

if errorlevel 1 (
    echo [ERROR] Processing failed.
    goto imp_exit
)
set "IMP_RESULT=0"

:: ── Step 7: Clipboard ───────────────────────────────────────
if not "!OUT_TYPE!"=="summary" (
    echo.
    set /p do_clip="Copy output to clipboard? (y/N): "
    if /i "!do_clip!"=="y" (
        type "!OUT_FILE!" | clip
        echo [OK] Copied to clipboard.
    )
)

:: ── Step 8: Save to library? ────────────────────────────────
if not "!OUT_TYPE!"=="summary" (
    if exist "%~dp0store.bat" (
        echo.
        set /p do_store="Save this result to the project tree library? (y/N): "
        if /i "!do_store!"=="y" (
            call "%~dp0store.bat" SAVE "!OUT_FILE!" "!IMP_FORMAT!" "import"
        )
    )
)

echo.
echo ============================================
echo   import.bat done.
echo ============================================

:imp_exit
pause
endlocal & exit /b %IMP_RESULT%
