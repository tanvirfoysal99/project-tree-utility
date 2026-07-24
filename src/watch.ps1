param(
    [string]$WatchPath = '',
    [string]$StructureFile = '',
    [string]$IgnoreFile = '',
    [int]$MaxDepth = 0
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptRoot

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

    $expectedFiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $expectedFolders = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $actualFiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $actualFolders = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($entry in $Entries) {
        $rel = ''
        if ($entry.PSObject.Properties.Name -contains 'Path' -and $entry.Path) {
            $rel = $entry.Path.TrimStart('\', '/')
        } else {
            $rel = $entry.Name.TrimEnd('/')
        }
        $full = Join-Path $BasePath $rel
        if ($entry.IsDir) { [void]$expectedFolders.Add($full) } else { [void]$expectedFiles.Add($full) }
    }

    $liveItems = Get-LimitedItems -Path $BasePath -CurrentDepth 0 -MaxDepth $ScanDepth -ExcludeFolders $ExcludeFolders
    foreach ($item in $liveItems) {
        if ($item.PSIsContainer) { [void]$actualFolders.Add($item.FullName) } else { [void]$actualFiles.Add($item.FullName) }
    }

    return [pscustomobject]@{
        ExpectedFiles   = $expectedFiles
        ExpectedFolders = $expectedFolders
        ActualFiles     = $actualFiles
        ActualFolders   = $actualFolders
        MissingFiles    = @($expectedFiles | Where-Object { -not $actualFiles.Contains($_) })
        MissingFolders  = @($expectedFolders | Where-Object { -not $actualFolders.Contains($_) })
        ExtraFiles      = @($actualFiles | Where-Object { -not $expectedFiles.Contains($_) })
        ExtraFolders    = @($actualFolders | Where-Object { -not $expectedFolders.Contains($_) })
    }
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
if (-not (Test-Path -LiteralPath $base)) {
    Write-Color "[ERROR] Directory not found: $base" Red
    exit 2
}

$treeConfig = Get-TreeConfig -RootPath $base -IgnoreFile $IgnoreFile
$scanDepth = if ($MaxDepth -gt 0) { $MaxDepth } elseif ($treeConfig.MaxDepth) { [int]$treeConfig.MaxDepth } else { 5 }
$excludeFolders = Get-ExcludeList -RootPath $base -IgnoreFile $IgnoreFile

$structurePath = ''
$entries = @()
if ($StructureFile -and $StructureFile.Trim()) {
    $structurePath = Resolve-FullPath $StructureFile
    if (-not (Test-Path -LiteralPath $structurePath)) {
        Write-Color "[ERROR] Structure file not found: $structurePath" Red
        exit 2
    }
    $format = Get-StructureFormat -FilePath $structurePath
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

if ($entries.Count -gt 0) {
    $snapshot = Get-StructureSnapshot -BasePath $base -Entries $entries -ExcludeFolders $excludeFolders -ScanDepth $scanDepth
    Write-DriftSnapshot -Snapshot $snapshot
}

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $base
$watcher.IncludeSubdirectories = $true
$watcher.Filter = '*'
$watcher.NotifyFilter = [System.IO.NotifyFilters]'FileName, DirectoryName, LastWrite, Size, CreationTime'
$watcher.EnableRaisingEvents = $true

$subs = @(
    Register-ObjectEvent -InputObject $watcher -EventName Created -SourceIdentifier 'TreeWatch.Created'
    Register-ObjectEvent -InputObject $watcher -EventName Changed -SourceIdentifier 'TreeWatch.Changed'
    Register-ObjectEvent -InputObject $watcher -EventName Deleted -SourceIdentifier 'TreeWatch.Deleted'
    Register-ObjectEvent -InputObject $watcher -EventName Renamed -SourceIdentifier 'TreeWatch.Renamed'
)

Write-Color '[WATCH] Press Ctrl+C to stop.' Gray

try {
    while ($true) {
        $event = Wait-Event -Timeout 1
        if (-not $event) { continue }

        switch ($event.SourceIdentifier) {
            'TreeWatch.Created' { Write-Color ('[CREATE] ' + $event.SourceEventArgs.FullPath) Green }
            'TreeWatch.Changed' { Write-Color ('[CHANGE] ' + $event.SourceEventArgs.FullPath) Yellow }
            'TreeWatch.Deleted' { Write-Color ('[DELETE] ' + $event.SourceEventArgs.FullPath) Red }
            'TreeWatch.Renamed' {
                Write-Color ('[RENAME] ' + $event.SourceEventArgs.OldFullPath + ' -> ' + $event.SourceEventArgs.FullPath) Cyan
            }
        }

        Remove-Event -EventIdentifier $event.EventIdentifier

        if ($entries.Count -gt 0) {
            $snapshot = Get-StructureSnapshot -BasePath $base -Entries $entries -ExcludeFolders $excludeFolders -ScanDepth $scanDepth
            Write-DriftSnapshot -Snapshot $snapshot
        }
    }
} finally {
    foreach ($sub in $subs) {
        Unregister-Event -SubscriptionId $sub.Id -ErrorAction SilentlyContinue
        Remove-Job -Id $sub.Id -Force -ErrorAction SilentlyContinue
    }
    $watcher.Dispose()
}
