@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

:: ============================================================
::  store.bat
::  Project Tree Library  -  CRUD Dispatcher
::  Part of the Project Tree Utility toolkit
::
::  Subcommand usage (called by tree.bat and other tools):
::    call store.bat SAVE   "<file>" "<format>" "<source>"
::    call store.bat LIST
::    call store.bat OPEN
::    call store.bat RENAME
::    call store.bat DELETE
::    call store.bat PURGE
::
::  Standalone:  double-click or call with no arguments for
::               the interactive library menu.
::
::  Exit codes: 0=success  1=failure  2=internal error
:: ============================================================

set "STORE_PS1=%~dp0..\src\store.ps1"
set "SHARED=%~dp0..\src\internal\_shared.ps1"

if not exist "%STORE_PS1%" (
    echo [ERROR] store.ps1 not found alongside store.bat.
    exit /b 2
)
if not exist "%SHARED%" (
    echo [ERROR] _shared.ps1 not found alongside store.bat.
    exit /b 2
)

:: ── Subcommand dispatch ──────────────────────────────────────
:: ST_MODE controls end-of-action behaviour:
::   sub  = called by another bat, exit /b when done
::   menu = standalone interactive, loop back to menu
set "ST_MODE=sub"

if /i "%~1"=="SAVE"   goto sub_save
if /i "%~1"=="LIST"   goto sub_list
if /i "%~1"=="OPEN"   goto action_open
if /i "%~1"=="RENAME" goto action_rename
if /i "%~1"=="DELETE" goto action_delete
if /i "%~1"=="PURGE"  goto action_purge
set "ST_MODE=menu"
goto interactive

:: ============================================================
:: SUBCOMMAND: SAVE
:: ============================================================
:sub_save
set "SV_FILE=%~2"
set "SV_FMT=%~3"
set "SV_SRC=%~4"

if not exist "!SV_FILE!" (
    echo [ERROR] File not found: !SV_FILE!
    exit /b 1
)
if "!SV_FMT!"=="" set "SV_FMT=dash"
if "!SV_SRC!"=="" set "SV_SRC=unknown"

echo.
set /p SV_NAME="Enter a name for this library entry: "
if "!SV_NAME!"=="" (
    echo [INFO] No name entered. Skipping save.
    exit /b 0
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    ". '%STORE_PS1:\=/%';" ^
    "Add-TreeEntry -SourceFile '!SV_FILE:\=/!' -UserName '!SV_NAME!' -Format '!SV_FMT!' -Source '!SV_SRC!'" ^
    "| Out-Null"

exit /b %errorlevel%

:: ============================================================
:: SUBCOMMAND: LIST
:: ============================================================
:sub_list
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    ". '%STORE_PS1:\=/%';" ^
    "Remove-MissingEntries;" ^
    "Show-LibraryTable | Out-Null"
echo.
pause
exit /b 0

:: ============================================================
:: INTERACTIVE MODE
:: ============================================================
:interactive
echo.
echo ============================================
echo   store.bat  ^|  Project Tree Library
echo ============================================
echo.
echo [1]  View library
echo [2]  Open / use a saved tree
echo [3]  Rename a saved tree
echo [4]  Delete a saved tree
echo [5]  Delete ALL  ^(purge^)
echo [0]  Exit
echo.
set /p st_choice="Enter choice (0-5): "

if "!st_choice!"=="0" goto st_exit
if "!st_choice!"=="1" goto menu_list
if "!st_choice!"=="2" goto action_open
if "!st_choice!"=="3" goto action_rename
if "!st_choice!"=="4" goto action_delete
if "!st_choice!"=="5" goto action_purge
echo Invalid choice.
goto interactive

:menu_list
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    ". '%STORE_PS1:\=/%';" ^
    "Remove-MissingEntries;" ^
    "Show-LibraryTable | Out-Null"
echo.
pause
goto interactive

:: ============================================================
:: ACTION: OPEN
:: Shows table, picks a tree, then shows the action submenu.
:: Reached from both subcommand dispatch and interactive menu.
:: ============================================================
:action_open
echo.
echo ============================================
echo   LIBRARY  -  Select a tree
echo ============================================

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    ". '%STORE_PS1:\=/%'; Remove-MissingEntries; Show-LibraryTable | Out-Null"

echo.
set "OPEN_NUM="
set /p OPEN_NUM="Select a tree (number, or press Enter to cancel): "
if "!OPEN_NUM!"=="" goto action_open_end

set "OPEN_NAME="
set "OPEN_FILE="
set "OPEN_FMT="
set "OPEN_ORPHAN=False"

for /f "usebackq delims=" %%L in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    ". '%STORE_PS1:\=/%';" ^
    "$sel = Resolve-TreeSelection -Number !OPEN_NUM!;" ^
    "if ($null -eq $sel) { Write-Output 'NOTFOUND' } else {" ^
    "    Write-Output ('NAME=' + $sel.Name);" ^
    "    Write-Output ('FILE=' + $sel.FilePath);" ^
    "    Write-Output ('FMT='  + $sel.Format);" ^
    "    Write-Output ('ORPHAN=' + $sel.IsOrphan)" ^
    "}"`) do (
    set "OPEN_LINE=%%L"
    if "!OPEN_LINE!"=="NOTFOUND" (
        echo [ERROR] Invalid selection.
        goto action_open_end
    )
    if "!OPEN_LINE:~0,5!"=="NAME=" set "OPEN_NAME=!OPEN_LINE:~5!"
    if "!OPEN_LINE:~0,5!"=="FILE=" set "OPEN_FILE=!OPEN_LINE:~5!"
    if "!OPEN_LINE:~0,4!"=="FMT="  set "OPEN_FMT=!OPEN_LINE:~4!"
    if "!OPEN_LINE:~0,7!"=="ORPHAN=" set "OPEN_ORPHAN=!OPEN_LINE:~7!"
)

if "!OPEN_NAME!"=="" ( echo [ERROR] Could not resolve selection. & goto action_open_end )
if not exist "!OPEN_FILE!" ( echo [ERROR] File missing: !OPEN_FILE! & goto action_open_end )

echo.
echo ============================================
echo   Selected: !OPEN_NAME!
echo ============================================
echo.
echo What do you want to do with this tree?
echo [1]  Scaffold
echo [2]  Export / convert format
echo [3]  Merge with another tree
echo [4]  Verify against a live directory
echo [5]  Security check
echo [6]  View raw content
if "!OPEN_ORPHAN!"=="True" echo [7]  Register this file properly
echo [0]  Back
echo.
set /p OPEN_ACT="Enter choice: "

if "!OPEN_ACT!"=="0" goto action_open_end

if "!OPEN_ACT!"=="1" (
    if exist "%~dp0scaffold.bat" (
        call "%~dp0scaffold.bat" "!OPEN_FILE!" "!OPEN_FMT!"
    ) else ( echo [ERROR] scaffold.bat not found. )
    goto action_open_end
)

if "!OPEN_ACT!"=="2" (
    if exist "%~dp0import.bat" (
        set "IMPORT_PRELOAD_FILE=!OPEN_FILE!"
        set "IMPORT_PRELOAD_FMT=!OPEN_FMT!"
        call "%~dp0import.bat"
    ) else ( echo [ERROR] import.bat not found. )
    goto action_open_end
)

if "!OPEN_ACT!"=="3" goto action_open_merge

if "!OPEN_ACT!"=="4" (
    if exist "%~dp0verify.bat" (
        set "VERIFY_PRELOAD_FILE=!OPEN_FILE!"
        call "%~dp0verify.bat"
    ) else ( echo [ERROR] verify.bat not found. )
    goto action_open_end
)

if "!OPEN_ACT!"=="5" (
    if exist "%~dp0security.bat" (
        call "%~dp0security.bat" VALIDATE_ALL "!OPEN_FILE!" "!OPEN_FMT!" "%~dp0"
    ) else ( echo [ERROR] security.bat not found. )
    goto action_open_end
)

if "!OPEN_ACT!"=="6" (
    echo.
    echo ── !OPEN_NAME! ──────────────────────────────────────
    type "!OPEN_FILE!" | more
    echo.
    goto action_open_end
)

if "!OPEN_ACT!"=="7" (
    if "!OPEN_ORPHAN!"=="True" (
        echo.
        set "REG_NAME="
        set /p REG_NAME="Enter a name (or press Enter to use '!OPEN_NAME!'): "
        if "!REG_NAME!"=="" set "REG_NAME=!OPEN_NAME!"
        powershell -NoProfile -ExecutionPolicy Bypass -Command ^
            ". '%STORE_PS1:\=/%';" ^
            "$o = [ordered]@{ Name='!OPEN_NAME!'; FilePath='!OPEN_FILE:\=/!'; Format='!OPEN_FMT!'; EntryCount='?' };" ^
            "Register-OrphanFile -Orphan $o -UserName '!REG_NAME!'"
    ) else (
        echo [INFO] This entry is already registered.
    )
    goto action_open_end
)

echo Invalid choice.

:action_open_end
echo.
pause
if "!ST_MODE!"=="menu" goto interactive
exit /b 0

:: ── OPEN sub-action: merge with a second tree ────────────────
:action_open_merge
set "OM_FILE_A=!OPEN_FILE!"
set "OM_FMT_A=!OPEN_FMT!"
set "OM_NAME_A=!OPEN_NAME!"

echo.
echo ============================================
echo   MERGE  -  Select second tree (File B)
echo ============================================
echo   File A (base): !OM_NAME_A!
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    ". '%STORE_PS1:\=/%'; Show-LibraryTable | Out-Null"

echo.
set "OM_NUM="
set /p OM_NUM="Select second tree (number), or press Enter to type a path manually: "

set "OM_FILE_B="
set "OM_FMT_B="

if "!OM_NUM!"=="" (
    set /p OM_FILE_B="File B path: "
    echo !OM_FILE_B!| findstr /C:"\" >nul
    if errorlevel 1 set "OM_FILE_B=%~dp0!OM_FILE_B!"
    if not exist "!OM_FILE_B!" ( echo [ERROR] File not found. & goto action_open_end )
    for /f "usebackq delims=" %%D in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        ". '%SHARED:\=/%'; Write-Output (Get-StructureFormat -FilePath '!OM_FILE_B:\=/!')"`) do set "OM_FMT_B=%%D"
    if "!OM_FMT_B!"=="unknown" set "OM_FMT_B=dash"
) else (
    for /f "usebackq delims=" %%L in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        ". '%STORE_PS1:\=/%';" ^
        "$sel = Resolve-TreeSelection -Number !OM_NUM!;" ^
        "if ($null -eq $sel) { Write-Output 'NOTFOUND' } else {" ^
        "    Write-Output ('FILE=' + $sel.FilePath);" ^
        "    Write-Output ('FMT='  + $sel.Format)" ^
        "}"`) do (
        set "OM_LINE=%%L"
        if "!OM_LINE!"=="NOTFOUND" ( echo [ERROR] Invalid selection. & goto action_open_end )
        if "!OM_LINE:~0,5!"=="FILE=" set "OM_FILE_B=!OM_LINE:~5!"
        if "!OM_LINE:~0,4!"=="FMT="  set "OM_FMT_B=!OM_LINE:~4!"
    )
)

if "!OM_FILE_B!"=="" ( echo [ERROR] No second file selected. & goto action_open_end )

if exist "%~dp0merge.bat" (
    set "MERGE_PRELOAD_A=!OM_FILE_A!"
    set "MERGE_PRELOAD_FMT_A=!OM_FMT_A!"
    set "MERGE_PRELOAD_B=!OM_FILE_B!"
    set "MERGE_PRELOAD_FMT_B=!OM_FMT_B!"
    call "%~dp0merge.bat"
) else (
    echo [ERROR] merge.bat not found.
)
goto action_open_end

:: ============================================================
:: ACTION: RENAME
:: ============================================================
:action_rename
echo.
echo ============================================
echo   RENAME  -  Select a tree
echo ============================================

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    ". '%STORE_PS1:\=/%'; Remove-MissingEntries; Show-LibraryTable | Out-Null"

echo.
set "RN_NUM="
set /p RN_NUM="Select a tree to rename (number, or press Enter to cancel): "
if "!RN_NUM!"=="" goto action_rename_end

set "RN_OLD="
for /f "usebackq delims=" %%L in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    ". '%STORE_PS1:\=/%';" ^
    "$sel = Resolve-TreeSelection -Number !RN_NUM!;" ^
    "if ($null -eq $sel) { Write-Output 'NOTFOUND' } else { Write-Output ('NAME=' + $sel.Name) }"`) do (
    set "RN_LINE=%%L"
    if "!RN_LINE!"=="NOTFOUND" ( echo [ERROR] Invalid selection. & goto action_rename_end )
    if "!RN_LINE:~0,5!"=="NAME=" set "RN_OLD=!RN_LINE:~5!"
)

if "!RN_OLD!"=="" ( echo [ERROR] Could not resolve selection. & goto action_rename_end )

echo.
echo   Current name: !RN_OLD!
set "RN_NEW="
set /p RN_NEW="New name (or press Enter to cancel): "
if "!RN_NEW!"=="" ( echo [INFO] Cancelled. & goto action_rename_end )

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    ". '%STORE_PS1:\=/%';" ^
    "Rename-TreeEntry -NameOrId '!RN_OLD!' -NewName '!RN_NEW!'"

:action_rename_end
echo.
pause
if "!ST_MODE!"=="menu" goto interactive
exit /b 0

:: ============================================================
:: ACTION: DELETE
:: ============================================================
:action_delete
echo.
echo ============================================
echo   DELETE  -  Select a tree
echo ============================================

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    ". '%STORE_PS1:\=/%'; Remove-MissingEntries; Show-LibraryTable | Out-Null"

echo.
set "DL_NUM="
set /p DL_NUM="Select a tree to delete (number, or press Enter to cancel): "
if "!DL_NUM!"=="" goto action_delete_end

set "DL_NAME="
for /f "usebackq delims=" %%L in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    ". '%STORE_PS1:\=/%';" ^
    "$sel = Resolve-TreeSelection -Number !DL_NUM!;" ^
    "if ($null -eq $sel) { Write-Output 'NOTFOUND' } else { Write-Output ('NAME=' + $sel.Name) }"`) do (
    set "DL_LINE=%%L"
    if "!DL_LINE!"=="NOTFOUND" ( echo [ERROR] Invalid selection. & goto action_delete_end )
    if "!DL_LINE:~0,5!"=="NAME=" set "DL_NAME=!DL_LINE:~5!"
)

if "!DL_NAME!"=="" ( echo [ERROR] Could not resolve selection. & goto action_delete_end )

echo.
echo   About to delete: !DL_NAME!
set /p DL_CONFIRM="Are you sure? This cannot be undone. (y/N): "
if /i not "!DL_CONFIRM!"=="y" ( echo [INFO] Cancelled. & goto action_delete_end )

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    ". '%STORE_PS1:\=/%';" ^
    "Remove-TreeEntry -NameOrId '!DL_NAME!'"

:action_delete_end
echo.
pause
if "!ST_MODE!"=="menu" goto interactive
exit /b 0

:: ============================================================
:: ACTION: PURGE
:: ============================================================
:action_purge
echo.
echo ============================================
echo   PURGE  -  Delete ALL saved trees
echo ============================================
echo.
echo   [WARN] This will permanently delete every saved tree
echo   from the library AND all files in store_trees\.
echo   There is no recovery.
echo.
set /p PG_C1="Type YES to confirm: "
if not "!PG_C1!"=="YES" ( echo [INFO] Cancelled. & goto action_purge_end )
set /p PG_C2="Type YES again to confirm: "
if not "!PG_C2!"=="YES" ( echo [INFO] Cancelled. & goto action_purge_end )

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    ". '%STORE_PS1:\=/%';" ^
    "$dir = '%~dp0..\data\store_trees';" ^
    "if (Test-Path $dir) { Remove-Item -Path $dir -Recurse -Force };" ^
    "$json = '%~dp0..\data\store_data.json';" ^
    "if (Test-Path $json) { Remove-Item -Path $json -Force };" ^
    "Write-Host '[OK] Library purged.'"

:action_purge_end
echo.
pause
if "!ST_MODE!"=="menu" goto interactive
exit /b 0

:st_exit
endlocal
pause
