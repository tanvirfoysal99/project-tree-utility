param(
    [string]$StructureFile,
    [string]$Format,
    [ValidateSet('importable','md','txt','summary')][string]$OutputFormat = 'importable',
    [string]$OutputFile,
    [int]$SpaceUnit = 2,
    [switch]$FromEnvironment
)
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'internal/_shared.ps1')
    if ($FromEnvironment) {
        $StructureFile=$env:IMP_FILE; $Format=$env:IMP_FORMAT
        $OutputFormat=$env:OUT_TYPE; $OutputFile=$env:OUT_FILE; $SpaceUnit=[int]$env:SPACE_UNIT
    }
    if ($OutputFormat -notin @('importable','md','txt','summary')) { throw 'Invalid output format.' }
    if (-not (Confirm-StructureFormat $StructureFile $Format $SpaceUnit)) { throw 'Structure file failed validation.' }
    $entries = @(Read-StructureFile $StructureFile $Format $SpaceUnit)
    if (-not $entries.Count) { throw 'Structure contains no entries.' }
    $sb = New-Object Text.StringBuilder
    if ($OutputFormat -eq 'md') { [void]$sb.AppendLine('## Imported Structure'); [void]$sb.AppendLine('```text') }
    foreach ($entry in $entries) {
        if ($OutputFormat -eq 'importable') {
            foreach($line in @(ConvertTo-DashStructure @($entry))){[void]$sb.AppendLine($line)}
        } else { [void]$sb.AppendLine(('    ' * ($entry.Depth - 1)) + $entry.Name) }
    }
    if ($OutputFormat -eq 'md') { [void]$sb.AppendLine('```') }
    if ($OutputFormat -eq 'summary') { Write-Host $sb.ToString() }
    else {
        [IO.File]::WriteAllText($OutputFile,$sb.ToString(),(New-Object Text.UTF8Encoding($false)))
        Write-Host ('[OK] Saved: ' + $OutputFile)
    }
    exit 0
} catch { Write-Host ('[ERROR] Import failed: ' + $_.Exception.Message); exit 2 }
