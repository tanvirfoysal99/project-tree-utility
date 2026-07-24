@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "SHARED=%~dp0..\src\internal\_shared.ps1"
set "CI_MODE=0"
set "IGNORE_FILE="

if /i "%~1"=="--ci" (
    set "CI_MODE=1"
    shift
)
if defined TREE_CI set "CI_MODE=1"

if /i "%~1"=="--ignore-file" (
    set "IGNORE_FILE=%~2"
    shift
    shift
)

if not exist "%SHARED%" (
    echo [ERROR] _shared.ps1 not found. Place it alongside export.bat.
    exit /b 2
)

if "%CI_MODE%"=="1" goto ci_mode

echo.
echo ============================================
echo   export.bat  ^|  Directory Exporter
echo ============================================
echo.
echo Which directory to export?
echo [1] This directory (where export.bat lives)
echo [2] Enter a custom path
set /p dir_choice="Enter choice (1-2, default 1): "
if "!dir_choice!"=="" set "dir_choice=1"

if "!dir_choice!"=="1" (
    set "SCAN_DIR=%~dp0"
) else (
    set /p SCAN_DIR="Enter full directory path: "
    if "!SCAN_DIR!"=="" (
        echo [ERROR] No path entered.
        exit /b 2
    )
)
if not exist "!SCAN_DIR!" (
    echo [ERROR] Directory not found: !SCAN_DIR!
    exit /b 2
)
if not "!SCAN_DIR:~-1!"=="\" set "SCAN_DIR=!SCAN_DIR!\"

echo.
set /p extra_exclude="Extra folders to exclude (comma-separated, or press Enter to skip): "

echo.
echo Show which items?
echo [1] All (folders + files)
echo [2] Folders only
echo [3] Files only
set /p show_choice="Enter choice (1-3, default 1): "
set "SHOW_MODE=all"
if "!show_choice!"=="2" set "SHOW_MODE=folders"
if "!show_choice!"=="3" set "SHOW_MODE=files"

echo.
<<<<<<< HEAD
set /p depth_choice="Max folder depth (press Enter for default 5): "
if "!depth_choice!"=="" set "depth_choice=5"
set "MAX_DEPTH=!depth_choice!"

echo.
=======
>>>>>>> 46d4b9c9fbbd365c47daec7faeed0746fc47c166
echo Export format:
echo [1] Markdown  ^(.md^)
echo [2] Plain text  ^(.txt^)
echo [3] Importable dash layout  ^(.txt^)
echo [4] JSON tree  ^(.json^)
echo [5] YAML tree  ^(.yaml^)
set /p fmt_choice="Enter choice (1-5, default 1): "
set "FORMAT_TYPE=md"
set "FMT_EXT=.md"
if "!fmt_choice!"=="2" ( set "FORMAT_TYPE=txt" & set "FMT_EXT=.txt" )
if "!fmt_choice!"=="3" ( set "FORMAT_TYPE=importable" & set "FMT_EXT=.txt" )
if "!fmt_choice!"=="4" ( set "FORMAT_TYPE=json" & set "FMT_EXT=.json" )
if "!fmt_choice!"=="5" ( set "FORMAT_TYPE=yaml" & set "FMT_EXT=.yaml" )

echo.
set /p OUT_NAME="Output file name (without extension, or press Enter for 'project_tree'): "
if "!OUT_NAME!"=="" set "OUT_NAME=project_tree"

set /p add_ts="Append timestamp? (y/N): "
if /i "!add_ts!"=="y" (
    for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value 2^>nul') do set "dt=%%I"
    if defined dt set "OUT_NAME=!OUT_NAME!_!dt:~0,4!-!dt:~4,2!-!dt:~6,2!"
)

if "!FORMAT_TYPE!"=="md" (
    set "FINAL_NAME=!OUT_NAME!.md"
) else if "!FORMAT_TYPE!"=="json" (
    set "FINAL_NAME=!OUT_NAME!.json"
) else if "!FORMAT_TYPE!"=="yaml" (
    set "FINAL_NAME=!OUT_NAME!.yaml"
) else (
    set "FINAL_NAME=!OUT_NAME!.txt"
)
set "OUT_FILE=%~dp0!FINAL_NAME!"

echo.
echo [INFO] Scanning directory ...
call :run_export
if errorlevel 1 exit /b %errorlevel%

echo.
set /p do_clip="Copy output to clipboard? (y/N): "
if /i "!do_clip!"=="y" (
    type "!OUT_FILE!" | clip
    echo [OK] Copied to clipboard.
)

echo.
echo ============================================
echo   Done! Saved as: !FINAL_NAME!
echo ============================================

if exist "%~dp0store.bat" (
    echo.
    set /p do_store="Save this result to the project tree library? (y/N): "
    if /i "!do_store!"=="y" (
        call "%~dp0store.bat" SAVE "!OUT_FILE!" "!FORMAT_TYPE!" "export"
    )
)

if /i "!FORMAT_TYPE!"=="importable" (
    echo.
    echo Scaffold this structure into a project?
    echo [1] Yes - launch scaffold.bat now
    echo [2] No  - I am done
    set /p hoff="Enter choice (1-2): "
    if "!hoff!"=="1" (
        if exist "%~dp0scaffold.bat" (
            call "%~dp0scaffold.bat" "!OUT_FILE!" "dash"
        ) else (
            echo [ERROR] scaffold.bat not found in this directory.
        )
    )
)

goto exp_exit

:ci_mode
set "SCAN_DIR=%~1"
set "FORMAT_TYPE=%~2"
set "OUT_FILE=%~3"
set "MAX_DEPTH=%~4"
set "SHOW_MODE=%~5"
set "extra_exclude=%~6"
set "IGNORE_FILE=%~7"

if "%SCAN_DIR%"=="" (
    echo [ERROR] CI mode requires a directory path.
    exit /b 2
)
if "%FORMAT_TYPE%"=="" (
    echo [ERROR] CI mode requires an output format.
    exit /b 2
)
if "%MAX_DEPTH%"=="" set "MAX_DEPTH=5"
if "%SHOW_MODE%"=="" set "SHOW_MODE=all"
if "%extra_exclude%"=="" set "extra_exclude="
set "BASE_ROOT=%~dp0.."
if not "%SCAN_DIR:~1,1%"==":" if not "%SCAN_DIR:~0,2%"=="\\" set "SCAN_DIR=%BASE_ROOT%\%SCAN_DIR%"
if "%OUT_FILE%"=="" (
    if /i "%FORMAT_TYPE%"=="md" (
        set "OUT_FILE=%SCAN_DIR%\project_tree.md"
    ) else if /i "%FORMAT_TYPE%"=="json" (
        set "OUT_FILE=%SCAN_DIR%\project_tree.json"
    ) else if /i "%FORMAT_TYPE%"=="yaml" (
        set "OUT_FILE=%SCAN_DIR%\project_tree.yaml"
    ) else (
        set "OUT_FILE=%SCAN_DIR%\project_tree.txt"
    )
)
if not "%OUT_FILE:~1,1%"==":" if not "%OUT_FILE:~0,2%"=="\\" set "OUT_FILE=%BASE_ROOT%\%OUT_FILE%"

call :run_export
exit /b %errorlevel%

:run_export
<<<<<<< HEAD
set "PTU_ARGS=%TEMP%\ptu_export_args_%RANDOM%.txt"
(
    echo !SCAN_DIR!
    echo !OUT_FILE!
    echo !FORMAT_TYPE!
    echo !MAX_DEPTH!
    echo !SHOW_MODE!
    echo !extra_exclude!
    echo !IGNORE_FILE!
) > "!PTU_ARGS!"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\src\export.ps1" -ArgsFile "!PTU_ARGS!"
set "_ec=%errorlevel%"
del /f /q "!PTU_ARGS!" 2>nul
exit /b %_ec%
=======
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\src\export.ps1" -RootPath "%SCAN_DIR%" -OutputFile "%OUT_FILE%" -OutputFormat "%FORMAT_TYPE%" -MaxDepth %MAX_DEPTH% -ShowMode "%SHOW_MODE%" -ExtraExclude "%extra_exclude%" -IgnoreFile "%IGNORE_FILE%"
exit /b %errorlevel%
>>>>>>> 46d4b9c9fbbd365c47daec7faeed0746fc47c166

:exp_exit
if "%CI_MODE%"=="0" pause
endlocal
