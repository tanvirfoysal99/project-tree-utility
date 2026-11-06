param(
    [string]$WatchPath = '',
    [string]$StructureFile = '',
    [string]$IgnoreFile = '',
    [int]$MaxDepth = 0,
    [string]$Format = '',
    [switch]$Ci,
    [ValidateRange(0,2147483647)][int]$DurationSeconds=0
)

$ErrorActionPreference = 'Stop'
try {
if ($env:TREE_CI -match '^(?i:1|true|yes)$') { $Ci=$true }
if ($Ci -and -not $WatchPath) { Write-Host '[ERROR] CI watch requires a directory path.'; exit 2 }

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $scriptRoot

$sharedPath = Join-Path $scriptRoot 'internal\_shared.ps1'
if (-not (Test-Path -LiteralPath $sharedPath)) {
    Write-Host '[ERROR] _shared.ps1 not found. Place it alongside watch.ps1.'
    exit 2
}

. $sharedPath

function Resolve-PathOrPrompt {
    param([string]$InputPath, [string]$Prompt, [string]$DefaultValue)
    if ($InputPath -and $InputPath.Trim()) { return $InputPath.Trim() }
    $value = Read-Host $Prompt
    if ([string]::IsNullOrWhiteSpace($value)) { return $DefaultValue }
    return $value.Trim()
}

function Resolve-FullPath {
    param([string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $scriptRoot $PathValue)
}

function Get-StructureSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][object[]]$Entries,
        [Parameter(Mandatory = $true)][string[]]$ExcludeFolders,
        [Parameter(Mandatory = $true)][int]$ScanDepth
    )

    return (Get-TreeComparison $BasePath $Entries $ExcludeFolders $ScanDepth)
}
function Write-DriftSnapshot {
    param([Parameter(Mandatory = $true)]$Snapshot)

    $driftCount = $Snapshot.MissingFolders.Count + $Snapshot.MissingFiles.Count + $Snapshot.ExtraFolders.Count + $Snapshot.ExtraFiles.Count
    $stamp = Get-Date -Format 'HH:mm:ss'
    if ($driftCount -eq 0) {
        Write-Color ("[{0}] clean - live directory matches structure" -f $stamp) Green
    } else {
        Write-Color ("[{0}] drift={1} missingF={2} missingFi={3} extraF={4} extraFi={5}" -f $stamp, $driftCount, $Snapshot.MissingFolders.Count, $Snapshot.MissingFiles.Count, $Snapshot.ExtraFolders.Count, $Snapshot.ExtraFiles.Count) Red
    }
}

Write-Host ''
Write-Color '============================================' Gray
Write-Color '  tree watch  |  Live Drift Monitor' Gray
Write-Color '============================================' Gray

$watchInput = Resolve-PathOrPrompt -InputPath $WatchPath -Prompt 'Directory to watch (press Enter for current folder)' -DefaultValue '.'
$base = Resolve-FullPath $watchInput
if (-not (Test-Path -LiteralPath $base -PathType Container)) {
    Write-Color "[ERROR] Directory not found: $base" Red
    exit 2
}

$treeConfig = Get-TreeConfig -RootPath $base -IgnoreFile $IgnoreFile
$explicit=@{}
if($PSBoundParameters.ContainsKey('MaxDepth')){$explicit.MaxDepth=$MaxDepth}
$scanDepth=(Resolve-TreeOptions $treeConfig $explicit).MaxDepth
$excludeFolders = Get-ExcludeList -RootPath $base -IgnoreFile $IgnoreFile

$structurePath = ''
$entries = @()
if ($StructureFile -and $StructureFile.Trim()) {
    $structurePath = Resolve-FullPath $StructureFile
    if (-not (Test-Path -LiteralPath $structurePath)) {
        Write-Color "[ERROR] Structure file not found: $structurePath" Red
        exit 2
    }
    if (-not $Format) { $Format = Get-StructureFormat -FilePath $structurePath }
    if ($format -eq 'empty' -or $format -eq 'unknown') {
        Write-Color '[ERROR] Structure file format could not be detected.' Red
        exit 2
    }
    $entries = @(Read-StructureFile -FilePath $structurePath -Format $format)
}

Write-Color ('[WATCH] Root    : ' + $base) Gray
Write-Color ('[WATCH] Depth   : ' + $scanDepth) Gray
Write-Color ('[WATCH] Excludes: ' + ($excludeFolders -join ', ')) Gray
if ($structurePath) {
    Write-Color ('[WATCH] Structure: ' + $structurePath) Gray
}

. (Join-Path $PSScriptRoot 'internal/_watch.ps1')
Invoke-TreeWatch -BasePath $base -Entries $entries -ExcludeFolders $excludeFolders -MaxDepth $scanDepth -DurationSeconds $DurationSeconds -OnSnapshot {
    param($snapshot)
    if($snapshot.PSObject.Properties.Name -contains 'MissingFiles'){Write-DriftSnapshot $snapshot}
    else{Write-Host ('[WATCH] Snapshot entries: '+$snapshot.Scan.Items.Count)}
}
exit 0
} catch { Write-Host ('[ERROR] Watch failed: ' + $_.Exception.Message); exit 2 }