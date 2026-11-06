param(
    [Parameter(Mandatory = $true)][string]$FileA,
    [Parameter(Mandatory = $true)][string]$FormatA,
    [Parameter(Mandatory = $true)][string]$FileB,
    [Parameter(Mandatory = $true)][string]$FormatB,
    [Parameter(Mandatory = $true)][ValidateSet('union', 'a_over_b', 'b_over_a')][string]$Strategy,
    [Parameter(Mandatory = $true)][string]$OutputFile,
    [int]$SpaceUnitA = 2,
    [int]$SpaceUnitB = 2
)

$ErrorActionPreference = 'Stop'

$shared = Join-Path $PSScriptRoot 'internal\_shared.ps1'
if (-not (Test-Path -LiteralPath $shared)) {
    Write-Host '[ERROR] _shared.ps1 not found alongside merge_tree.ps1.'
    exit 2
}

. $shared

try {
    $entriesA = Read-StructureFile -FilePath $FileA -Format $FormatA -SpaceUnit $SpaceUnitA
    $entriesB = Read-StructureFile -FilePath $FileB -Format $FormatB -SpaceUnit $SpaceUnitB
    $merged=@(Merge-StructureEntries @($entriesA) @($entriesB) $Strategy)
    $flat=@(ConvertTo-DashStructure $merged)
    $sep = [string]::new([char]0x2500, 45)
    Write-Host $sep
    Write-Host '  TREE-AWARE MERGE SUMMARY'
    Write-Host $sep
    Write-Host ('  File A entries : ' + $entriesA.Count)
    Write-Host ('  File B entries : ' + $entriesB.Count)
    Write-Host ('  Merged total   : ' + $flat.Count)
    Write-Host ('  Strategy       : ' + $Strategy)
    Write-Host $sep

    [System.IO.File]::WriteAllLines($OutputFile, $flat, [System.Text.Encoding]::UTF8)
    Write-Host ('[OK] Saved: ' + $OutputFile)
    exit 0
} catch {
    Write-Host ('[ERROR] Merge failed: ' + $_.Exception.Message)
    exit 1
}
