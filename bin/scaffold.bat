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
set "SCF_VBS=%~dp0_scaffold_vbs_temp.vbs"
set "SCF_PS1=%~dp0_scaffold_ps1_temp.ps1"
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
    for /f "usebackq delims=" %%D in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        ". '%SHARED:\=/%'; Write-Output (Get-StructureFormat -FilePath '!STRUC_FILE:\=/!')"`) do set "STRUC_FORMAT=%%D"

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
if "!USE_TEMPLATE!"=="0" (
    echo [INFO] Running security checks ...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCF_VALIDATE_PS1%" ^
        -StructureFile "!STRUC_FILE!" ^
        -Format "!STRUC_FORMAT!" ^
        -TargetBase "!TARGET_BASE!" ^
        -ProjectName "!PROJECT_NAME!" ^
        -SpaceUnit !SPACE_UNIT!
    if %errorlevel% neq 0 (
        echo [ERROR] Security checks failed. Aborting.
        goto scf_exit
    )
) else (
    echo [INFO] Template mode - security checks use built-in preset definitions.
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

:: ── Step 8: Build + run scaffold PS1 via VBScript ───────────
echo.
echo [INFO] Preparing scaffolding engine ...

call :run_scaffold
if !errorlevel! equ 2 goto scf_exit

:: ── Step 9: Offer real run if dry run was chosen ────────────
if "!DRY_RUN!"=="1" (
    echo.
    set /p go_real="Run for real now and create the project? (y/N): "
    if /i "!go_real!"=="y" (
        set "DRY_RUN=0"
        call :run_scaffold
        if !errorlevel! equ 2 goto scf_exit
    )
)

echo.
echo ============================================
echo   scaffold.bat done.
echo ============================================

goto scf_exit

:: ============================================================
:: Subroutine: run_scaffold
:: Builds the VBS->PS1 pipeline and executes it.
:: ============================================================
:run_scaffold
echo.
set "SCF_DRY_ARG=$false"
if "!DRY_RUN!"=="1" set "SCF_DRY_ARG=$true"
(
echo Set fso = CreateObject^("Scripting.FileSystemObject"^)
echo Set f = fso.OpenTextFile^("%SCF_PS1:\=\\%", 2, True, -1^)
echo f.WriteLine ". '!SHARED:\=/!'"
echo f.WriteLine ""
echo f.WriteLine "function Invoke-Scaffold {"
echo f.WriteLine "    param([string]$StrucFile,[string]$TargetBase,[string]$ProjectName,[string]$OverwriteMode,[bool]$DryRun,[string]$Format,[int]$SpaceUnit,[string]$TemplateName)"
echo f.WriteLine "    $entries = if ($Format -eq 'template') { Read-StructureFile -FilePath $StrucFile -Format $Format -SpaceUnit $SpaceUnit -TemplateName $TemplateName } else { Read-StructureFile -FilePath $StrucFile -Format $Format -SpaceUnit $SpaceUnit }"
echo f.WriteLine "    $ProjectRoot = Join-Path $TargetBase $ProjectName"
echo f.WriteLine "    $foldersCreated = 0; $filesCreated = 0; $skipped = 0"
echo f.WriteLine "    $log = [System.Collections.Generic.List[string]]::new()"
echo f.WriteLine "    $log.Add('scaffold.bat Creation Log'); $log.Add('Project: ' + $ProjectName)"
echo f.WriteLine "    $log.Add('Format : ' + $Format); $log.Add('DryRun : ' + $DryRun)"
echo f.WriteLine "    $log.Add([string]::new('-',45))"
echo f.WriteLine "    if (-not $DryRun -and -not (Test-Path $ProjectRoot)) { New-Item -ItemType Directory -Path $ProjectRoot -Force | Out-Null }"
echo f.WriteLine "    foreach ($e in $entries) {"
echo f.WriteLine "        $relPath = $e.Path.TrimStart('\','/')"
echo f.WriteLine "        if (-not $relPath) { continue }"
echo f.WriteLine "        if (Test-DangerousName -Name $relPath) {"
echo f.WriteLine "            Write-Host ('[SKIP-UNSAFE] ' + $relPath); $skipped++; continue"
echo f.WriteLine "        }"
echo f.WriteLine "        $fullPath = Join-Path $ProjectRoot $relPath"
echo f.WriteLine "        if (-not (Test-SafePath -CandidatePath $fullPath -AllowedBase $ProjectRoot)) {"
echo f.WriteLine "            Write-Host ('[SKIP-UNSAFE PATH] ' + $fullPath); $skipped++; continue"
echo f.WriteLine "        }"
echo f.WriteLine "        if ($e.IsDir) {"
echo f.WriteLine "            if (Test-Path $fullPath) { Write-Host '[SKIP] ' $fullPath; $skipped++ }"
echo f.WriteLine "            else {"
echo f.WriteLine "                Write-Host '[DIR]  ' $fullPath"
echo f.WriteLine "                if (-not $DryRun) { New-Item -ItemType Directory -Path $fullPath -Force | Out-Null }"
echo f.WriteLine "                $foldersCreated++; $log.Add('[DIR]  '+$fullPath)"
echo f.WriteLine "            }"
echo f.WriteLine "        } else {"
echo f.WriteLine "            $shouldWrite = $true"
echo f.WriteLine "            if (Test-Path $fullPath) {"
echo f.WriteLine "                if ($OverwriteMode -eq 'skip') { Write-Host '[SKIP] ' $fullPath; $skipped++; $shouldWrite = $false }"
echo f.WriteLine "                elseif ($OverwriteMode -eq 'ask') {"
echo f.WriteLine "                    $ans = Read-Host ('Overwrite ' + $fullPath + '? (y/N)')"
echo f.WriteLine "                    if ($ans.ToLower() -ne 'y') { Write-Host '[SKIP] ' $fullPath; $skipped++; $shouldWrite = $false }"
echo f.WriteLine "                }"
echo f.WriteLine "            }"
echo f.WriteLine "            if ($shouldWrite) {"
echo f.WriteLine "                $stub = Get-StructureEntryContent -Entry $e -ProjectName $ProjectName -TemplateName $TemplateName"
echo f.WriteLine "                Write-Host '[FILE] ' $fullPath"
echo f.WriteLine "                if (-not $DryRun) { [System.IO.File]::WriteAllText($fullPath, $stub, [System.Text.Encoding]::UTF8) }"
echo f.WriteLine "                $filesCreated++; $log.Add('[FILE] '+$fullPath)"
echo f.WriteLine "            }"
echo f.WriteLine "        }"
echo f.WriteLine "    }"
echo f.WriteLine "    $sep = [string]::new([char]0x2500,45)"
echo f.WriteLine "    Write-Host ''; Write-Host $sep; Write-Host ' SCAFFOLD SUMMARY'; Write-Host $sep"
echo f.WriteLine "    Write-Host (' Folders : ' + $foldersCreated)"
echo f.WriteLine "    Write-Host (' Files   : ' + $filesCreated)"
echo f.WriteLine "    Write-Host (' Skipped : ' + $skipped)"
echo f.WriteLine "    if ($DryRun) { Write-Host ' [DRY RUN] Nothing written to disk.' }"
echo f.WriteLine "    Write-Host $sep"
echo f.WriteLine "    if (-not $DryRun) {"
echo f.WriteLine "        $logPath = Join-Path $ProjectRoot '_creation_log.txt'"
echo f.WriteLine "        [System.IO.File]::WriteAllLines($logPath, $log, [System.Text.Encoding]::UTF8)"
echo f.WriteLine "        Write-Host '[OK] Creation log: _creation_log.txt'"
echo f.WriteLine "    }"
echo f.WriteLine "    return $foldersCreated + $filesCreated"
echo f.WriteLine "}"
echo f.WriteLine ""
echo f.WriteLine "Invoke-Scaffold -StrucFile '!STRUC_FILE!' -TargetBase '!TARGET_BASE!' -ProjectName '!PROJECT_NAME!' -OverwriteMode '!OVERWRITE_MODE!' -DryRun !SCF_DRY_ARG! -Format '!STRUC_FORMAT!' -SpaceUnit !SPACE_UNIT! -TemplateName '!TEMPLATE_NAME!'"
echo f.Close
) > "%SCF_VBS%"

cscript //nologo "%SCF_VBS%"
if %errorlevel% neq 0 (
    echo [ERROR] Failed to generate scaffolding script.
    if exist "%SCF_VBS%" del "%SCF_VBS%"
    exit /b 2
)
if exist "%SCF_VBS%" del "%SCF_VBS%"

if not exist "%SCF_PS1%" (
    echo [ERROR] Scaffolding script was not created.
    exit /b 2
)

if "!DRY_RUN!"=="1" (
    echo ============================================
    echo   DRY RUN - Nothing will be written
    echo ============================================
) else (
    echo ============================================
    echo   Scaffolding project ...
    echo ============================================
)
echo.

powershell -ExecutionPolicy Bypass -File "%SCF_PS1%"
if %errorlevel% neq 0 (
    echo [ERROR] Scaffolding script failed.
    if exist "%SCF_PS1%" del "%SCF_PS1%"
    exit /b 2
)
if exist "%SCF_PS1%" del "%SCF_PS1%"
exit /b 0

:scf_exit
endlocal
pause
