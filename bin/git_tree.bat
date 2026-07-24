@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "GT_PS1=%~dp0..\src\git_tree.ps1"
set "CI_MODE=0"
set "GITLAB_BASE=https://gitlab.com"
set "EXCLUDE_LIST=node_modules,.git,dist,build,.next,.wrangler"

if /i "%~1"=="--ci" (
    set "CI_MODE=1"
    shift
)
if defined TREE_CI set "CI_MODE=1"

if not exist "%GT_PS1%" (
    echo [ERROR] git_tree.ps1 not found. Place it alongside git_tree.bat.
    exit /b 2
)

if "%CI_MODE%"=="1" goto ci_mode

echo.
echo ============================================
echo   git_tree.bat  ^|  Remote Tree Exporter
echo ============================================
echo.
echo Which provider?
echo [1] GitHub   ^(github.com^)
echo [2] GitLab   ^(gitlab.com or self-hosted^)
set /p prov_choice="Enter choice (1-2): "
if "!prov_choice!"=="2" (
    set "PROVIDER=gitlab"
    echo.
    set /p GITLAB_BASE="GitLab base URL (press Enter for https://gitlab.com): "
    if "!GITLAB_BASE!"=="" set "GITLAB_BASE=https://gitlab.com"
) else (
    set "PROVIDER=github"
)

echo.
if "!PROVIDER!"=="github" (
    echo Enter the repository HTTPS URL.
    echo Example: https://github.com/owner/repo
) else (
    echo Enter the repository HTTPS URL.
    echo Example: !GITLAB_BASE!/namespace/repo
)
set /p REPO_URL="URL: "

echo.
echo Enter the branch name to export.
set /p BRANCH="Branch: "

echo.
set /p SUBFOLDER="Export only a subfolder? (e.g. src/components - or press Enter for full repo): "

echo.
set /p MAX_DEPTH="Max depth to export? (press Enter for unlimited): "
if "!MAX_DEPTH!"=="" set "MAX_DEPTH=0"

echo.
set /p custom_exclude="Add extra folders to exclude? (comma-separated, or press Enter to skip): "
if not "!custom_exclude!"=="" set "EXCLUDE_LIST=!EXCLUDE_LIST!,!custom_exclude!"

echo.
echo Choose output format:
echo [1] Importable dash layout  ^(.txt^)
echo [2] Markdown                ^(.md^)
echo [3] Plain text tree         ^(.txt^)
echo [4] JSON tree               ^(.json^)
echo [5] YAML tree               ^(.yaml^)
set /p fmt_choice="Enter choice (1-5): "
set "FORMAT_TYPE=importable"
set "FMT_EXT=.txt"
if "!fmt_choice!"=="2" ( set "FORMAT_TYPE=md" & set "FMT_EXT=.md" )
if "!fmt_choice!"=="3" ( set "FORMAT_TYPE=txt" & set "FMT_EXT=.txt" )
if "!fmt_choice!"=="4" ( set "FORMAT_TYPE=json" & set "FMT_EXT=.json" )
if "!fmt_choice!"=="5" ( set "FORMAT_TYPE=yaml" & set "FMT_EXT=.yaml" )

echo.
set /p OUT_NAME="Output file name (without extension, or press Enter for 'git_tree_export'): "
if "!OUT_NAME!"=="" set "OUT_NAME=git_tree_export"
set "OUT_FILE=%~dp0!OUT_NAME!!FMT_EXT!"

echo.
echo ============================================
echo   EXPORT SUMMARY - please confirm
echo ============================================
echo   Provider  : !PROVIDER!
if "!PROVIDER!"=="gitlab" echo   Base URL  : !GITLAB_BASE!
echo   Repo URL  : !REPO_URL!
echo   Branch    : !BRANCH!
if not "!SUBFOLDER!"=="" echo   Subfolder : !SUBFOLDER!
echo   Max Depth : !MAX_DEPTH! (0 = unlimited)
echo   Excludes  : !EXCLUDE_LIST!
echo   Format    : !FORMAT_TYPE!
echo   Output    : !OUT_NAME!!FMT_EXT!
echo ============================================
echo.
set /p confirm="Proceed? (y/N): "
if /i not "!confirm!"=="y" (
    echo Cancelled.
    goto gt_exit
)

call :run_git_tree
if errorlevel 1 goto gt_exit

if "%CI_MODE%"=="1" goto gt_exit

echo.
set /p do_clip="Copy output to clipboard? (y/N): "
if /i "!do_clip!"=="y" (
    type "!OUT_FILE!" | clip
    echo [OK] Copied to clipboard.
)

if exist "%~dp0store.bat" (
    echo.
    set /p do_store="Save this result to the project tree library? (y/N): "
    if /i "!do_store!"=="y" (
        call "%~dp0store.bat" SAVE "!OUT_FILE!" "!FORMAT_TYPE!" "git_tree"
    )
)

if /i "!FORMAT_TYPE!"=="importable" (
    echo.
    echo ============================================
    echo   Scaffold this repository structure?
    echo ============================================
    echo   [1] Yes - launch scaffold.bat now
    echo   [2] No  - I am done
    set /p hoff="Enter choice (1-2): "
    if "!hoff!"=="1" (
        if exist "%~dp0scaffold.bat" (
            call "%~dp0scaffold.bat" "!OUT_FILE!" "dash"
        ) else (
            echo [ERROR] scaffold.bat not found in this directory.
        )
    )
)

echo.
echo ============================================
echo   git_tree.bat done.
echo ============================================
goto gt_exit

:ci_mode
set "PROVIDER=%~1"
set "REPO_URL=%~2"
set "BRANCH=%~3"
set "OUT_FILE=%~4"
set "FORMAT_TYPE=%~5"
set "SUBFOLDER=%~6"
set "MAX_DEPTH=%~7"
set "EXCLUDE_LIST=%~8"
set "GITLAB_BASE=%~9"

if "%PROVIDER%"=="" exit /b 2
if "%REPO_URL%"=="" exit /b 2
if "%BRANCH%"=="" exit /b 2
if "%OUT_FILE%"=="" exit /b 2
if "%FORMAT_TYPE%"=="" exit /b 2
if "%MAX_DEPTH%"=="" set "MAX_DEPTH=0"
if "%EXCLUDE_LIST%"=="" set "EXCLUDE_LIST=node_modules,.git,dist,build,.next,.wrangler"
if "%GITLAB_BASE%"=="" set "GITLAB_BASE=https://gitlab.com"

if not "%OUT_FILE:~1,1%"==":" if not "%OUT_FILE:~0,2%"=="\\" set "OUT_FILE=%~dp0..\%OUT_FILE%"

call :run_git_tree
exit /b %errorlevel%

:run_git_tree
set "GTU_ARGS=%TEMP%\ptu_gittree_args_%RANDOM%.txt"
(
    echo !PROVIDER!
    echo !REPO_URL!
    echo !BRANCH!
    echo !OUT_FILE!
    echo !FORMAT_TYPE!
    echo !SUBFOLDER!
    echo !MAX_DEPTH!
    echo !EXCLUDE_LIST!
    echo !GITLAB_BASE!
) > "!GTU_ARGS!"
powershell -NoProfile -ExecutionPolicy Bypass -File "%GT_PS1%" -ArgsFile "!GTU_ARGS!"
set "_ec=%errorlevel%"
del /f /q "!GTU_ARGS!" 2>nul
exit /b %_ec%

:gt_exit
if "%CI_MODE%"=="0" pause
endlocal
