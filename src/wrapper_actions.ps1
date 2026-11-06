param([Parameter(Mandatory=$true)][string]$Action)
# Fixed menu operations. Environment values remain data, never source code.
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'internal/_shared.ps1')
    if ($Action -like 'Store*') { . (Join-Path $PSScriptRoot 'store.ps1') }
    $detectVariables = @{
        DetectImport='IMP_FILE'; DetectScaffold='STRUC_FILE'; DetectMergeA='FILE_A'
        DetectMergeB='FILE_B'; DetectLibraryMerge='OM_FILE_B'; DetectAnalysis='_df_file'
    }
    if ($detectVariables.ContainsKey($Action)) {
        Write-Output (Get-StructureFormat ([Environment]::GetEnvironmentVariable($detectVariables[$Action])))
        exit 0
    }
    switch ($Action) {
        'ConvertImport' { & (Join-Path $PSScriptRoot 'import.ps1') -FromEnvironment; exit $LASTEXITCODE }
        'ValidateScaffold' {
            $source = if ($env:STRUC_FORMAT -eq 'template') { 'template' } else { $env:STRUC_FILE }
            & (Join-Path $PSScriptRoot 'scaffold_validate.ps1') -StructureFile $source -Format $env:STRUC_FORMAT -TargetBase $env:TARGET_BASE -ProjectName $env:PROJECT_NAME -SpaceUnit ([int]$env:SPACE_UNIT)
            exit $LASTEXITCODE
        }
        'ValidateFile' {
            if (-not (Confirm-StructureFormat $env:SEC_FILE $env:SEC_FMT)) { throw 'Structure file failed format validation.' }
        }
        'ValidatePath' {
            if (-not (Test-SafePath $env:SEC_CAND $env:SEC_BASE)) { throw 'Unsafe destination path.' }
        }
        'ValidateNames' {
            $entries = @(Read-StructureFile $env:SEC_FILE $env:SEC_FMT)
            if (-not $entries.Count) { throw 'No parseable entries.' }
            foreach ($entry in $entries) {
                if (Test-DangerousName $entry.Name.TrimEnd('/')) { throw ('Unsafe name: ' + $entry.Name) }
            }
        }
        'ValidateEntries' {
            foreach ($entry in @(Read-StructureFile $env:SEC_FILE $env:SEC_FMT)) {
                $full = Join-Path $env:SEC_BASE $entry.Path
                if (-not (Test-SafePath $full $env:SEC_BASE)) { throw ('Unsafe path: ' + $full) }
            }
        }
        'StoreSave' {
            if (-not (Add-TreeEntry $env:SV_FILE $env:SV_NAME $env:SV_FMT $env:SV_SRC)) { throw 'Library save failed.' }
        }
        'StoreList' { Remove-MissingEntries; Show-LibraryTable | Out-Null }
        'StoreShow' { Show-LibraryTable | Out-Null }
        'StoreSelect' {
            $selection = Resolve-TreeSelection ([int]$env:OPEN_NUM)
            if (-not $selection) { Write-Output 'NOTFOUND' }
            else {
                Write-Output ('NAME=' + $selection.Name); Write-Output ('FILE=' + $selection.FilePath)
                Write-Output ('FMT=' + $selection.Format); Write-Output ('ORPHAN=' + $selection.IsOrphan)
            }
        }
        'StoreSelectMerge' {
            $selection = Resolve-TreeSelection ([int]$env:OM_NUM)
            if (-not $selection) { Write-Output 'NOTFOUND' }
            else { Write-Output ('FILE=' + $selection.FilePath); Write-Output ('FMT=' + $selection.Format) }
        }
        'StoreSelectRename' {
            $selection = Resolve-TreeSelection ([int]$env:RN_NUM)
            if (-not $selection) { Write-Output 'NOTFOUND' } else { Write-Output ('NAME=' + $selection.Name) }
        }
        'StoreSelectDelete' {
            $selection = Resolve-TreeSelection ([int]$env:DL_NUM)
            if (-not $selection) { Write-Output 'NOTFOUND' } else { Write-Output ('NAME=' + $selection.Name) }
        }
        'StoreRegister' {
            $orphan = [pscustomobject]@{ Name=$env:OPEN_NAME; FilePath=$env:OPEN_FILE; Format=$env:OPEN_FMT }
            Register-OrphanFile $orphan $env:REG_NAME | Out-Null
        }
        'StoreRename' {
            if (-not (Rename-TreeEntry $env:RN_OLD $env:RN_NEW)) { throw 'Library rename failed.' }
        }
        'StoreDelete' {
            if (-not (Remove-TreeEntry $env:DL_NAME)) { throw 'Library deletion failed.' }
        }
        'StorePurge' {
            Clear-Library
            Write-Host '[OK] Library purged.'
        }
        default { throw ('Unknown wrapper action: ' + $Action) }
    }
    exit 0
} catch { Write-Host ('[ERROR] ' + $_.Exception.Message); exit 2 }
