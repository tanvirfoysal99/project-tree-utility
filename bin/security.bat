@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

:: ============================================================
::  security.bat
::  Security, Validation & Guardrails
::  Part of the Project Tree Utility toolkit
::
::  Can be called standalone or by other subcommands.
::
::  Standalone usage:
::    security.bat              - interactive validation menu
::
::  Subcommand usage (called by other .bat files):
::    call security.bat VALIDATE_FILE  "<path>" "<format>"
::    call security.bat VALIDATE_PATH  "<candidatePath>" "<allowedBase>"
::    call security.bat VALIDATE_NAMES "<structureFile>" "<format>"
::    call security.bat VALIDATE_ALL   "<structureFile>" "<format>" "<targetBase>"
::
::  Exit codes when called as subcommand:
::    0 = passed
::    1 = validation failure
::    2 = internal error
:: ============================================================

set "SHARED=%~dp0..\src\internal\_shared.ps1"
if not exist "%SHARED%" (
    echo [ERROR] _shared.ps1 not found. Place it alongside security.bat.
    exit /b 2
)

:: ── Subcommand dispatch ──────────────────────────────────────
if /i "%~1"=="VALIDATE_FILE"  goto sub_validate_file
if /i "%~1"=="VALIDATE_PATH"  goto sub_validate_path
if /i "%~1"=="VALIDATE_NAMES" goto sub_validate_names
if /i "%~1"=="VALIDATE_ALL"   goto sub_validate_all

:: ── Standalone interactive mode ─────────────────────────────
goto interactive

:: ============================================================
:: SUBCOMMAND: VALIDATE_FILE
:: Checks that a structure file exists, is non-empty, and every
:: non-comment line matches the expected format.
:: %2 = file path   %3 = format (dash/tab/treesym/space)
:: ============================================================
:sub_validate_file
set "SEC_FILE=%~2"
set "SEC_FMT=%~3"

if not exist "!SEC_FILE!" (
    echo [SECURITY] File not found: !SEC_FILE!
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    ". '%SHARED:\=/%';" ^
    "$ok = Confirm-StructureFormat -FilePath '!SEC_FILE:\=/!' -Format '!SEC_FMT!';" ^
    "if ($ok) { exit 0 } else { exit 1 }"

if %errorlevel% neq 0 (
    echo [SECURITY] Structure file failed format validation ^(%SEC_FMT%^).
    exit /b 1
)
echo [SECURITY] File validated OK: %SEC_FMT% format.
exit /b 0

:: ============================================================
:: SUBCOMMAND: VALIDATE_PATH
:: Checks a candidate write path is inside the allowed base.
:: Guards against path traversal in structure files.
:: %2 = candidate path   %3 = allowed base
:: ============================================================
:sub_validate_path
set "SEC_CAND=%~2"
set "SEC_BASE=%~3"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    ". '%SHARED:\=/%';" ^
    "$ok = Test-SafePath -CandidatePath '!SEC_CAND:\=/!' -AllowedBase '!SEC_BASE:\=/!';" ^
    "if ($ok) { exit 0 } else { exit 1 }"

if %errorlevel% neq 0 (
    echo [SECURITY] Path traversal detected: !SEC_CAND!
    echo            Write refused - path is outside allowed base.
    exit /b 1
)
exit /b 0

:: ============================================================
:: SUBCOMMAND: VALIDATE_NAMES
:: Scans every entry name in a structure file for dangerous
:: patterns (traversal fragments, reserved names, null bytes).
:: %2 = structure file path   %3 = format
:: ============================================================
:sub_validate_names
set "SEC_FILE=%~2"
set "SEC_FMT=%~3"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    ". '%SHARED:\=/%';" ^
    "$entries = Read-StructureFile -FilePath '!SEC_FILE:\=/!' -Format '!SEC_FMT!';" ^
    "$bad = $entries | Where-Object { Test-DangerousName -Name $_.Name.TrimEnd('/') };" ^
    "if ($bad) {" ^
    "    $bad | ForEach-Object { Write-Host ('[SECURITY] Dangerous name: ' + $_.Name) };" ^
    "    exit 1" ^
    "} else { exit 0 }"

if %errorlevel% neq 0 (
    echo [SECURITY] Structure file contains dangerous entry names. Aborting.
    exit /b 1
)
echo [SECURITY] All entry names are safe.
exit /b 0

:: ============================================================
:: SUBCOMMAND: VALIDATE_ALL
:: Runs all three checks in sequence. This is what scaffold.bat
:: and merge.bat should call before touching disk.
:: %2 = structure file   %3 = format   %4 = target base
:: ============================================================
:sub_validate_all
set "SEC_FILE=%~2"
set "SEC_FMT=%~3"
set "SEC_BASE=%~4"

call "%~f0" VALIDATE_FILE  "!SEC_FILE!" "!SEC_FMT!"
if %errorlevel% neq 0 exit /b 1

call "%~f0" VALIDATE_NAMES "!SEC_FILE!" "!SEC_FMT!"
if %errorlevel% neq 0 exit /b 1

:: Path-level check: verify every resolved path stays inside base
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    ". '%SHARED:\=/%';" ^
    "$entries = Read-StructureFile -FilePath '!SEC_FILE:\=/!' -Format '!SEC_FMT!';" ^
    "$base    = '!SEC_BASE!';" ^
    "$stack   = @{};" ^
    "$failed  = $false;" ^
    "for ($i = 0; $i -lt $entries.Count; $i++) {" ^
    "    $e = $entries[$i];" ^
    "    $parent = if ($e.Depth -eq 1) { $base } else { $stack[$e.Depth - 1] };" ^
    "    if (-not $parent) { $parent = $base };" ^
    "    $full = Join-Path $parent $e.Name.TrimEnd('/');" ^
    "    $stack[$e.Depth] = $full;" ^
    "    if (-not (Test-SafePath -CandidatePath $full -AllowedBase $base)) {" ^
    "        Write-Host ('[SECURITY] Unsafe path: ' + $full);" ^
    "        $failed = $true" ^
    "    }" ^
    "};" ^
    "if ($failed) { exit 1 } else { exit 0 }"

if %errorlevel% neq 0 (
    echo [SECURITY] One or more paths would write outside the target base. Aborting.
    exit /b 1
)

echo [SECURITY] All checks passed.
exit /b 0

:: ============================================================
:: INTERACTIVE MODE
:: ============================================================
:interactive
echo.
echo ============================================
echo   security.bat  ^|  Validation ^& Guardrails
echo ============================================
echo.
echo [1] Validate a structure file
echo [2] Check a path for traversal risk
echo [3] Scan entry names in a structure file
echo [4] Run all checks on a structure file
echo [0] Exit
echo.
set /p sec_choice="Enter choice (0-4): "

if "%sec_choice%"=="0" goto sec_exit
if "%sec_choice%"=="1" goto interactive_file
if "%sec_choice%"=="2" goto interactive_path
if "%sec_choice%"=="3" goto interactive_names
if "%sec_choice%"=="4" goto interactive_all
echo Invalid choice.
goto interactive

:interactive_file
echo.
set /p i_file="Structure file path: "
set /p i_fmt="Format (dash/tab/treesym/space): "
call "%~f0" VALIDATE_FILE "!i_file!" "!i_fmt!"
echo Exit code: !errorlevel!
goto interactive

:interactive_path
echo.
set /p i_cand="Candidate path: "
set /p i_base="Allowed base: "
call "%~f0" VALIDATE_PATH "!i_cand!" "!i_base!"
echo Exit code: !errorlevel!
goto interactive

:interactive_names
echo.
set /p i_file="Structure file path: "
set /p i_fmt="Format (dash/tab/treesym/space): "
call "%~f0" VALIDATE_NAMES "!i_file!" "!i_fmt!"
echo Exit code: !errorlevel!
goto interactive

:interactive_all
echo.
set /p i_file="Structure file path: "
set /p i_fmt="Format (dash/tab/treesym/space): "
set /p i_base="Target base directory: "
call "%~f0" VALIDATE_ALL "!i_file!" "!i_fmt!" "!i_base!"
echo Exit code: !errorlevel!
goto interactive

:sec_exit
endlocal
pause
