@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

:: ============================================================
:: tree.bat
:: Main entry point and router
:: Project Tree Utility v2.2.0
::
:: Zero external dependencies (batch + PowerShell only).
:: Project structure:
::   tree.bat              - this router (run this)
::   bin\*.bat             - CLI entry points
::   src\*.ps1            - Core backend logic
::   src\internal\_shared.ps1 - Shared library (never run directly)
::   data\store_data.json  - Library index
::   data\store_trees\     - Saved structure file copies
:: ============================================================

set "PROJECT_ROOT=%~dp0"
set "BIN_DIR=%PROJECT_ROOT%bin\"
set "SRC_DIR=%PROJECT_ROOT%src\"
set "DATA_DIR=%PROJECT_ROOT%data\"

set "CI_MODE=0"
if /i "%~1"=="--ci" (
    set "CI_MODE=1"
    set "TREE_CI=1"
    shift
)

:: Direct subcommand passthrough
if /i "%~1"=="import"   ( call "%BIN_DIR%import.bat"   %2 %3 %4 %5 %6 %7 %8 %9 & goto done )
if /i "%~1"=="export"   ( call "%BIN_DIR%export.bat"   %2 %3 %4 %5 %6 %7 %8 %9 & goto done )
if /i "%~1"=="merge"    ( call "%BIN_DIR%merge.bat"    %2 %3 %4 %5 %6 %7 %8 %9 & goto done )
if /i "%~1"=="scaffold" ( call "%BIN_DIR%scaffold.bat" %2 %3 %4 %5 %6 %7 %8 %9 & goto done )
if /i "%~1"=="verify"   ( call "%BIN_DIR%verify.bat"   %2 %3 %4 %5 %6 %7 %8 %9 & goto done )
if /i "%~1"=="security" ( call "%BIN_DIR%security.bat" %2 %3 %4 %5 %6 %7 %8 %9 & goto done )
if /i "%~1"=="gittree"  ( call "%BIN_DIR%git_tree.bat" %2 %3 %4 %5 %6 %7 %8 %9 & goto done )
if /i "%~1"=="auth"     ( call "%BIN_DIR%auth.bat"     %2 %3 %4 %5 %6 %7 %8 %9 & goto done )
if /i "%~1"=="library"  ( call "%BIN_DIR%store.bat"    %2 %3 %4 %5 %6 %7 %8 %9 & goto done )
if /i "%~1"=="watch"    ( call "%BIN_DIR%watch.bat"    %2 %3 %4 %5 %6 %7 %8 %9 & goto done )
if /i "%~1"=="version"  ( call "%BIN_DIR%version.bat"  %2 %3 %4 %5 %6 %7 %8 %9 & goto done )

:: ?????? Check all toolkit files are present ???????????????????????????????????????????????????????????????
set "MISSING="
if not exist "%SRC_DIR%internal\_shared.ps1"           set "MISSING=!MISSING! _shared.ps1"
if not exist "%BIN_DIR%detection.bat"                 set "MISSING=!MISSING! detection.bat"
if not exist "%BIN_DIR%security.bat"                  set "MISSING=!MISSING! security.bat"
if not exist "%BIN_DIR%import.bat"                    set "MISSING=!MISSING! import.bat"
if not exist "%BIN_DIR%export.bat"                    set "MISSING=!MISSING! export.bat"
if not exist "%BIN_DIR%merge.bat"                     set "MISSING=!MISSING! merge.bat"
if not exist "%SRC_DIR%merge_tree.ps1"                set "MISSING=!MISSING! merge_tree.ps1"
if not exist "%BIN_DIR%scaffold.bat"                   set "MISSING=!MISSING! scaffold.bat"
if not exist "%SRC_DIR%scaffold_validate.ps1"         set "MISSING=!MISSING! scaffold_validate.ps1"
if not exist "%BIN_DIR%verify.bat"                    set "MISSING=!MISSING! verify.bat"
if not exist "%BIN_DIR%watch.bat"                     set "MISSING=!MISSING! watch.bat"
if not exist "%SRC_DIR%watch.ps1"                     set "MISSING=!MISSING! watch.ps1"
if not exist "%BIN_DIR%git_tree.bat"                  set "MISSING=!MISSING! git_tree.bat"
if not exist "%SRC_DIR%git_tree.ps1"                  set "MISSING=!MISSING! git_tree.ps1"
if not exist "%SRC_DIR%verify.ps1"                    set "MISSING=!MISSING! verify.ps1"
if not exist "%BIN_DIR%store.bat"                     set "MISSING=!MISSING! store.bat"
if not exist "%SRC_DIR%store.ps1"                     set "MISSING=!MISSING! store.ps1"
if not exist "%BIN_DIR%version.bat"                  set "MISSING=!MISSING! version.bat"
if not exist "%SRC_DIR%version.ps1"                  set "MISSING=!MISSING! version.ps1"

:main_menu
cls
echo.
echo  ============================================
echo    Project Tree Utility  v2.2.0
echo    Batch + PowerShell
echo    Made by Tanvir Foysal Toshin
echo    Gmail: tanvirfoysaltoshin@gmail.com
echo  ============================================
echo.
if not "!MISSING!"=="" (
    echo  [WARN] Missing toolkit files:!MISSING!
    echo  Some options below may not work.
    echo.
)
echo   -- TOOLS --
echo   [ 1 ]   Import            - convert any structure file format
echo   [ 2 ]   Export            - scan a live directory to file
echo   [ 3 ]   Merge             - combine two structure files
echo   [ 4 ]   Scaffold          - create a project from a structure file
echo   [ 5 ]   Verify            - compare structure file vs live directory
echo   [ 6 ]   Security          - validate ^& guardrail checks
echo   [ 7 ]   Git Tree          - export tree from GitHub / GitLab repo
echo   [ 8 ]   Version           - show version and check for updates
echo.
echo   -- LIBRARY --
echo   [ 9 ]   View Library      - list all saved project trees
echo   [ 10 ]  Open / Use Tree   - load a saved tree into any tool
echo   [ 11 ]  Rename Tree       - rename a saved entry
echo   [ 12 ]  Delete Tree       - remove a saved entry
echo   [ 13 ]  Delete All        - purge the entire library
echo.
echo   [ 0 ]   Exit
echo.
set /p main_choice="  Enter choice (0-13): "

if "!main_choice!"=="0"  goto done
if "!main_choice!"=="1"  ( call "%BIN_DIR%import.bat"         & goto post_return )
if "!main_choice!"=="2"  ( call "%BIN_DIR%export.bat"         & goto post_return )
if "!main_choice!"=="3"  ( call "%BIN_DIR%merge.bat"          & goto post_return )
if "!main_choice!"=="4"  ( call "%BIN_DIR%scaffold.bat"       & goto post_return )
if "!main_choice!"=="5"  ( call "%BIN_DIR%verify.bat"         & goto post_return )
if "!main_choice!"=="6"  ( call "%BIN_DIR%security.bat"       & goto post_return )
if "!main_choice!"=="7"  ( call "%BIN_DIR%git_tree.bat"       & goto post_return )
if "!main_choice!"=="8"  ( call "%BIN_DIR%version.bat"        & goto post_return )
if "!main_choice!"=="9"  ( call "%BIN_DIR%store.bat" LIST     & goto post_return )
if "!main_choice!"=="10" ( call "%BIN_DIR%store.bat" OPEN     & goto post_return )
if "!main_choice!"=="11" ( call "%BIN_DIR%store.bat" RENAME   & goto post_return )
if "!main_choice!"=="12" ( call "%BIN_DIR%store.bat" DELETE   & goto post_return )
if "!main_choice!"=="13" ( call "%BIN_DIR%store.bat" PURGE    & goto post_return )

echo   Invalid choice. Please try again.
timeout /t 1 /nobreak >nul
goto main_menu

:post_return
echo.
echo  ============================================
echo   Back to main menu? (press any key)
echo  ============================================
pause >nul
goto main_menu

:done
endlocal
