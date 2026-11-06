param([ValidateSet('Analyse','Merge')][string]$Action)
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'internal/_shared.ps1')
    if ($Action -eq 'Merge') {
        & (Join-Path $PSScriptRoot 'merge_tree.ps1') -FileA $env:DT_FILE_A -FormatA $env:DT_FMT_A -FileB $env:DT_FILE_B -FormatB $env:DT_FMT_B -Strategy $env:DT_STRATEGY -OutputFile $env:DT_OUT
        exit $LASTEXITCODE
    }
    $entries = @(Read-StructureFile -FilePath $env:DT_FILE -Format $env:DT_FMT)
    if (-not $entries.Count) { throw 'Structure contains no entries.' }
    foreach ($entry in $entries) {
        $tag = if ($entry.IsDir) { '[DIR]' } else { '[FILE]' }
        Write-Host (('-' * $entry.Depth) + ' ' + $tag + ' ' + $entry.Name)
        Write-Host ('    path: ' + $entry.Path)
    }
    exit 0
} catch { Write-Host ('[ERROR] Analysis failed: ' + $_.Exception.Message); exit 2 }
