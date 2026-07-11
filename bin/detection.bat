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
set "DET_VBS=%~dp0_det_vbs_temp.vbs"
set "DET_PS1=%~dp0_det_ps1_temp.ps1"

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
:: Tree-aware merge — generates and runs a PS1 via VBScript.
:: %2=fileA  %3=fmtA  %4=fileB  %5=fmtB  %6=strategy  %7=outFile
:: ============================================================
:sub_build_tree
set "DT_FILE_A=%~2"
set "DT_FMT_A=%~3"
set "DT_FILE_B=%~4"
set "DT_FMT_B=%~5"
set "DT_STRATEGY=%~6"
set "DT_OUT=%~7"

(
echo Set fso = CreateObject^("Scripting.FileSystemObject"^)
echo Set f = fso.OpenTextFile^("%DET_PS1:\=\\%", 2, True, -1^)
echo f.WriteLine ". '!SHARED:\=/!'"
echo f.WriteLine ""
echo f.WriteLine "function Build-Tree {"
echo f.WriteLine "    param([System.Collections.Generic.List[object]]$Entries)"
echo f.WriteLine "    $root  = @{ Name='__ROOT__'; Depth=0; Children=[System.Collections.Generic.List[object]]::new() }"
echo f.WriteLine "    $stack = [System.Collections.Generic.List[object]]::new()"
echo f.WriteLine "    $stack.Add($root)"
echo f.WriteLine "    foreach ($e in $Entries) {"
echo f.WriteLine "        $node = @{ Name=$e.Name; Depth=$e.Depth; Children=[System.Collections.Generic.List[object]]::new() }"
echo f.WriteLine "        while ($stack.Count -gt 1 -and $stack[$stack.Count-1].Depth -ge $e.Depth) {"
echo f.WriteLine "            $stack.RemoveAt($stack.Count-1)"
echo f.WriteLine "        }"
echo f.WriteLine "        $stack[$stack.Count-1].Children.Add($node)"
echo f.WriteLine "        $stack.Add($node)"
echo f.WriteLine "    }"
echo f.WriteLine "    return $root"
echo f.WriteLine "}"
echo f.WriteLine ""
echo f.WriteLine "function Merge-Trees {"
echo f.WriteLine "    param($ANode, $BNode, [string]$Strategy)"
echo f.WriteLine "    $aByName = @{}"
echo f.WriteLine "    foreach ($child in $ANode.Children) {"
echo f.WriteLine "        $key = $child.Name.ToLower().TrimEnd('/')"
echo f.WriteLine "        $aByName[$key] = $child"
echo f.WriteLine "    }"
echo f.WriteLine "    foreach ($bChild in $BNode.Children) {"
echo f.WriteLine "        $key = $bChild.Name.ToLower().TrimEnd('/')"
echo f.WriteLine "        if ($aByName.ContainsKey($key)) {"
echo f.WriteLine "            if ($Strategy -eq 'b_over_a') { $aByName[$key].Name = $bChild.Name }"
echo f.WriteLine "            Merge-Trees -ANode $aByName[$key] -BNode $bChild -Strategy $Strategy"
echo f.WriteLine "        } else {"
echo f.WriteLine "            $ANode.Children.Add($bChild)"
echo f.WriteLine "        }"
echo f.WriteLine "    }"
echo f.WriteLine "}"
echo f.WriteLine ""
echo f.WriteLine "function Flatten-Tree {"
echo f.WriteLine "    param($Node, [int]$Depth = 0)"
echo f.WriteLine "    $result = [System.Collections.Generic.List[string]]::new()"
echo f.WriteLine "    foreach ($child in $Node.Children) {"
echo f.WriteLine "        $result.Add(('-' * ($Depth + 1)) + ' ' + $child.Name)"
echo f.WriteLine "        foreach ($s in (Flatten-Tree -Node $child -Depth ($Depth + 1))) { $result.Add($s) }"
echo f.WriteLine "    }"
echo f.WriteLine "    return $result"
echo f.WriteLine "}"
echo f.WriteLine ""
echo f.WriteLine "$eA = Read-StructureFile -FilePath '!DT_FILE_A:\=/!' -Format '!DT_FMT_A!'"
echo f.WriteLine "$eB = Read-StructureFile -FilePath '!DT_FILE_B:\=/!' -Format '!DT_FMT_B!'"
echo f.WriteLine "$tA = Build-Tree -Entries $eA"
echo f.WriteLine "$tB = Build-Tree -Entries $eB"
echo f.WriteLine "Merge-Trees -ANode $tA -BNode $tB -Strategy '!DT_STRATEGY!'"
echo f.WriteLine "$flat = Flatten-Tree -Node $tA"
echo f.WriteLine "$sep = [string]::new([char]0x2500, 45)"
echo f.WriteLine "Write-Host $sep"
echo f.WriteLine "Write-Host '  TREE-AWARE MERGE SUMMARY'"
echo f.WriteLine "Write-Host $sep"
echo f.WriteLine "Write-Host ('  File A entries : ' + $eA.Count)"
echo f.WriteLine "Write-Host ('  File B entries : ' + $eB.Count)"
echo f.WriteLine "Write-Host ('  Merged total   : ' + $flat.Count)"
echo f.WriteLine "Write-Host ('  Strategy       : !DT_STRATEGY!')"
echo f.WriteLine "Write-Host $sep"
echo f.WriteLine "[System.IO.File]::WriteAllLines('!DT_OUT:\=/!', $flat, [System.Text.Encoding]::UTF8)"
echo f.WriteLine "Write-Host '[OK] Saved: !DT_OUT!'"
echo f.Close
) > "%DET_VBS%"

cscript //nologo "%DET_VBS%"
if %errorlevel% neq 0 (
    echo [ERROR] Failed to generate merge script.
    if exist "%DET_VBS%" del "%DET_VBS%"
    exit /b 2
)
if exist "%DET_VBS%" del "%DET_VBS%"

if not exist "%DET_PS1%" (
    echo [ERROR] Merge script was not created.
    exit /b 2
)

powershell -ExecutionPolicy Bypass -File "%DET_PS1%"
set "DT_RESULT=%errorlevel%"
if exist "%DET_PS1%" del "%DET_PS1%"

if %DT_RESULT% neq 0 (
    echo [ERROR] Merge script failed.
    exit /b 1
)
exit /b 0

:: ============================================================
:: SUBCOMMAND: ANALYSE
:: Parses a structure file and displays full ancestry tree.
:: %2 = file path   %3 = format
:: ============================================================
:sub_analyse
set "DT_FILE=%~2"
set "DT_FMT=%~3"

(
echo Set fso = CreateObject^("Scripting.FileSystemObject"^)
echo Set f = fso.OpenTextFile^("%DET_PS1:\=\\%", 2, True, -1^)
echo f.WriteLine ". '!SHARED:\=/!'"
echo f.WriteLine ""
echo f.WriteLine "function Build-AnalysisTree {"
echo f.WriteLine "    param([System.Collections.Generic.List[object]]$Entries)"
echo f.WriteLine "    $root  = @{ Name='__ROOT__'; Depth=0; AncestryPath=''; Children=[System.Collections.Generic.List[object]]::new() }"
echo f.WriteLine "    $stack = [System.Collections.Generic.List[object]]::new()"
echo f.WriteLine "    $stack.Add($root)"
echo f.WriteLine "    foreach ($e in $Entries) {"
echo f.WriteLine "        while ($stack.Count -gt 1 -and $stack[$stack.Count-1].Depth -ge $e.Depth) {"
echo f.WriteLine "            $stack.RemoveAt($stack.Count-1)"
echo f.WriteLine "        }"
echo f.WriteLine "        $pPath = $stack[$stack.Count-1].AncestryPath"
echo f.WriteLine "        $myPath = if ($pPath) { $pPath + '/' + $e.Name.TrimEnd('/') } else { $e.Name.TrimEnd('/') }"
echo f.WriteLine "        $node = @{ Name=$e.Name; Depth=$e.Depth; AncestryPath=$myPath; Children=[System.Collections.Generic.List[object]]::new() }"
echo f.WriteLine "        $stack[$stack.Count-1].Children.Add($node)"
echo f.WriteLine "        $stack.Add($node)"
echo f.WriteLine "    }"
echo f.WriteLine "    return $root"
echo f.WriteLine "}"
echo f.WriteLine ""
echo f.WriteLine "function Print-AnalysisTree {"
echo f.WriteLine "    param($Node, [int]$Depth = 0)"
echo f.WriteLine "    foreach ($child in $Node.Children) {"
echo f.WriteLine "        $dashes  = '-' * ($Depth + 1)"
echo f.WriteLine "        $typeTag = if ($child.Children.Count -gt 0) { '[DIR] ' } else { '[---] ' }"
echo f.WriteLine "        Write-Host ($dashes + ' ' + $typeTag + $child.Name)"
echo f.WriteLine "        Write-Host ('       ' + ('  ' * $Depth) + 'path: ' + $child.AncestryPath)"
echo f.WriteLine "        Print-AnalysisTree -Node $child -Depth ($Depth + 1)"
echo f.WriteLine "    }"
echo f.WriteLine "}"
echo f.WriteLine ""
echo f.WriteLine "$entries = Read-StructureFile -FilePath '!DT_FILE:\=/!' -Format '!DT_FMT!'"
echo f.WriteLine "$sep = [string]::new([char]0x2500, 45)"
echo f.WriteLine "Write-Host ''"
echo f.WriteLine "Write-Host $sep"
echo f.WriteLine "Write-Host ('  STRUCTURE ANALYSIS: !DT_FILE!')"
echo f.WriteLine "Write-Host ('  Format  : !DT_FMT!')"
echo f.WriteLine "Write-Host ('  Entries : ' + $entries.Count)"
echo f.WriteLine "Write-Host $sep"
echo f.WriteLine "Write-Host ''"
echo f.WriteLine "Write-Host '  [DIR] = has children    [---] = leaf entry'"
echo f.WriteLine "Write-Host ''"
echo f.WriteLine "$tree = Build-AnalysisTree -Entries $entries"
echo f.WriteLine "Print-AnalysisTree -Node $tree"
echo f.WriteLine "Write-Host ''"
echo f.WriteLine "Write-Host $sep"
echo f.WriteLine "$issues = 0"
echo f.WriteLine "for ($i = 0; $i -lt $entries.Count; $i++) {"
echo f.WriteLine "    $e = $entries[$i]"
echo f.WriteLine "    if ($i -lt $entries.Count - 1) {"
echo f.WriteLine "        $next = $entries[$i + 1]"
echo f.WriteLine "        if ($next.Depth -gt $e.Depth -and -not $e.Name.EndsWith('/')) {"
echo f.WriteLine "            Write-Host ('  [WARN] Has children but no trailing slash: ' + $e.Name)"
echo f.WriteLine "            $issues++"
echo f.WriteLine "        }"
echo f.WriteLine "    }"
echo f.WriteLine "}"
echo f.WriteLine "if ($issues -eq 0) { Write-Host '  [OK] No structural issues detected.' }"
echo f.WriteLine "Write-Host $sep"
echo f.Close
) > "%DET_VBS%"

cscript //nologo "%DET_VBS%"
if %errorlevel% neq 0 (
    echo [ERROR] Failed to generate analysis script.
    if exist "%DET_VBS%" del "%DET_VBS%"
    exit /b 2
)
if exist "%DET_VBS%" del "%DET_VBS%"

if not exist "%DET_PS1%" (
    echo [ERROR] Analysis script was not created.
    exit /b 2
)

powershell -ExecutionPolicy Bypass -File "%DET_PS1%"
set "DT_RESULT=%errorlevel%"
if exist "%DET_PS1%" del "%DET_PS1%"
exit /b %DT_RESULT%

:: ============================================================
:: INTERACTIVE MODE
:: ============================================================
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
if %errorlevel% equ 0 (
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
for /f "usebackq delims=" %%F in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    ". '%SHARED:\=/%'; Write-Output (Get-StructureFormat -FilePath '!_df_file:\=/!')"`) do set "_df_result=%%F"
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
