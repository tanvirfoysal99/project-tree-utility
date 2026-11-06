param(
    [string]$StructureFile = '',
    [string]$Format = 'dash',
    [string]$TargetBase = '',
    [string]$ProjectName = '',
    [ValidateSet('skip','overwrite','ask')][string]$OverwriteMode = 'skip',
    [switch]$DryRun,
    [int]$SpaceUnit = 2,
    [string]$TemplateName = '',
    [switch]$FromEnvironment,
    [switch]$Ci
)
$ErrorActionPreference = 'Stop'
$foldersCreated = 0; $filesCreated = 0; $skipped = 0
try {
    . (Join-Path $PSScriptRoot 'internal/_shared.ps1')
    if ($env:TREE_CI -match '^(?i:1|true|yes)$') { $Ci=$true }
    if ($FromEnvironment) {
        $StructureFile = $env:STRUC_FILE; $Format = $env:STRUC_FORMAT
        $TargetBase = $env:TARGET_BASE; $ProjectName = $env:PROJECT_NAME
        $OverwriteMode = $env:OVERWRITE_MODE; $DryRun = $env:DRY_RUN -eq '1'
        $SpaceUnit = [int]$env:SPACE_UNIT; $TemplateName = $env:TEMPLATE_NAME
    }
    if ($OverwriteMode -notin @('skip','overwrite','ask')) { throw 'Invalid overwrite mode.' }
    if ($Ci -and $OverwriteMode -eq 'ask') { throw 'CI mode cannot prompt for overwrites.' }
    $projectRoot = Resolve-SafeProjectRoot $TargetBase $ProjectName
    if ($Format -eq 'template') {
        if (-not (Get-TemplatePreset $TemplateName)) { throw ('Unknown template: ' + $TemplateName) }
    } elseif (-not (Confirm-StructureFormat $StructureFile $Format $SpaceUnit)) {
        throw 'Structure file failed format validation.'
    }
    $entries = @(Read-StructureFile $StructureFile $Format $SpaceUnit $TemplateName)
    if (-not $entries.Count) { throw 'Structure contains no entries.' }
    $plan = New-Object 'System.Collections.Generic.List[object]'
    $destinations = @{}
    foreach ($entry in $entries) {
        if (Test-DangerousName $entry.Path) { throw ('Unsafe entry: ' + $entry.Path) }
        $full = [IO.Path]::GetFullPath((Join-Path $projectRoot $entry.Path))
        if (-not (Test-SafePath $full $projectRoot)) { throw ('Unsafe destination: ' + $full) }
        if ($destinations.ContainsKey($full)) { throw ('Duplicate destination: ' + $full) }
        if (Test-Path -LiteralPath $full) {
            $existingDirectory = (Get-Item -LiteralPath $full -Force).PSIsContainer
            if ($existingDirectory -ne [bool]$entry.IsDir) { throw ('File/directory conflict: ' + $full) }
        }
        $content = if ($entry.IsDir) { '' } else { Get-StructureEntryContent $entry $ProjectName $TemplateName }
        $item = [pscustomobject]@{ Path=$full; IsDir=[bool]$entry.IsDir; Content=$content }
        $destinations[$full] = $item; $plan.Add($item)
    }
    foreach ($item in $plan) {
        $parent = Split-Path $item.Path -Parent
        while ($parent -and $parent -ne $projectRoot) {
            if (($destinations.ContainsKey($parent) -and -not $destinations[$parent].IsDir) -or
                ((Test-Path -LiteralPath $parent) -and -not (Test-Path -LiteralPath $parent -PathType Container))) {
                throw ('Parent is a file: ' + $parent)
            }
            $parent = Split-Path $parent -Parent
        }
    }
    $logPath = Join-Path $projectRoot '_creation_log.txt'
    if (-not (Test-SafePath $logPath $projectRoot) -or $destinations.ContainsKey($logPath)) { throw 'Unsafe or reserved creation log path.' }
    $log = New-Object 'System.Collections.Generic.List[string]'
    function Ensure-ScaffoldDirectory([string]$Path) {
        if ($Path -ne $projectRoot -and -not (Test-SafePath $Path $projectRoot)) { throw ('Unsafe directory: ' + $Path) }
        if ($Path -eq $projectRoot) { $null = Resolve-SafeProjectRoot $TargetBase $ProjectName }
        if (Test-Path -LiteralPath $Path) {
            if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw ('Directory expected: ' + $Path) }
            return
        }
        if ($Path -ne $projectRoot) { Ensure-ScaffoldDirectory (Split-Path $Path -Parent) }
        $null = [IO.Directory]::CreateDirectory($Path)
        $script:foldersCreated++
    }
    foreach ($item in $plan) {
        if ($item.IsDir) {
            if (Test-Path -LiteralPath $item.Path) { $skipped++; continue }
            if (-not $DryRun) { Ensure-ScaffoldDirectory $item.Path }
            Write-Host ('[DIR] ' + $item.Path); $log.Add('[DIR] ' + $item.Path)
        } else {
            if (Test-Path -LiteralPath $item.Path) {
                if ($OverwriteMode -eq 'skip' -or ($OverwriteMode -eq 'ask' -and (Read-Host ('Overwrite ' + $item.Path + '? (y/N)')) -notmatch '^(?i)y$')) {
                    $skipped++; continue
                }
            }
            if (-not $DryRun) {
                Ensure-ScaffoldDirectory (Split-Path $item.Path -Parent)
                if (-not (Test-SafePath $item.Path $projectRoot)) { throw ('Unsafe file: ' + $item.Path) }
                [IO.File]::WriteAllText($item.Path, $item.Content, (New-Object Text.UTF8Encoding($false)))
                $filesCreated++
            }
            Write-Host ('[FILE] ' + $item.Path); $log.Add('[FILE] ' + $item.Path)
        }
    }
    if (-not $DryRun) {
        Ensure-ScaffoldDirectory $projectRoot
        if (-not (Test-SafePath $logPath $projectRoot)) { throw 'Unsafe creation log path.' }
        [IO.File]::WriteAllLines($logPath, $log, (New-Object Text.UTF8Encoding($false)))
    }
    Write-Host ('[OK] Scaffold complete. Created folders: {0}; files: {1}; skipped: {2}.' -f $foldersCreated,$filesCreated,$skipped)
    if ($DryRun) { Write-Host '[DRY RUN] Nothing written to disk.' }
    exit 0
} catch {
    Write-Host ('[ERROR] Scaffold failed: ' + $_.Exception.Message)
    Write-Host ('[INFO] Partial result: created folders: {0}; files: {1}; skipped: {2}.' -f $foldersCreated,$filesCreated,$skipped)
    exit 2
}
