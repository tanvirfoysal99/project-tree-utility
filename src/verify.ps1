param(
    [string]$StructureFile = '',
    [string]$LivePath = '',
    [string]$IgnoreFile = '',
    [switch]$Sync,
    [switch]$DeleteExtras,
    [switch]$Ci
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptRoot

$sharedPath = Join-Path $scriptRoot 'internal\_shared.ps1'
if (-not (Test-Path -LiteralPath $sharedPath)) {
    Write-Host '[ERROR] _shared.ps1 not found. Place it alongside verify.ps1.'
    exit 2
}

. $sharedPath

function Prompt-Default {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)][string]$DefaultValue,
        [switch]$CiMode
    )

    if ($CiMode) { return $DefaultValue }
    $value = Read-Host $Message
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $DefaultValue
    }
    return $value.Trim()
}

function Resolve-ReportPath {
    param([Parameter(Mandatory = $true)][string]$InputValue)

    $path = $InputValue.Trim()
    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = 'verify_report.txt'
    }

    if ([string]::IsNullOrWhiteSpace([System.IO.Path]::GetExtension($path))) {
        $path += '.txt'
    }

    if ([System.IO.Path]::IsPathRooted($path)) {
        return $path
    }

    return (Join-Path $scriptRoot $path)
}

function Format-FileSize {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:F1} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:F1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:F1} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

function Resolve-EntryPath {
    param(
        [Parameter(Mandatory = $true)][object]$Entry,
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][hashtable]$PathStack
    )

    if ($Entry.PSObject.Properties.Name -contains 'Path' -and $Entry.Path) {
        return (Join-Path -Path $BasePath -ChildPath $Entry.Path.TrimStart('\', '/'))
    }

    $parent = if ($Entry.Depth -eq 1) { $BasePath } else { $PathStack[$Entry.Depth - 1] }
    if (-not $parent) { $parent = $BasePath }
    return (Join-Path -Path $parent -ChildPath $Entry.Name.TrimEnd('/'))
}

function Test-ExcludedPath {
    param(
        [Parameter(Mandatory = $true)][string]$FullPath,
        [Parameter(Mandatory = $true)][string[]]$ExcludeFolders
    )

    $normalized = $FullPath -replace '/', '\'
    foreach ($ex in $ExcludeFolders) {
        $pattern = '(^|\\)' + [regex]::Escape($ex) + '(\\|$)'
        if ($normalized -match $pattern) {
            return $true
        }
    }

    return $false
}

function Get-LevenshteinDistance {
    param([string]$Left, [string]$Right)

    $a = if ($null -eq $Left) { '' } else { $Left.ToLowerInvariant() }
    $b = if ($null -eq $Right) { '' } else { $Right.ToLowerInvariant() }
    if ($a -eq $b) { return 0 }
    if ($a.Length -eq 0) { return $b.Length }
    if ($b.Length -eq 0) { return $a.Length }

    $matrix = New-Object 'object[]' ($a.Length + 1)
    for ($i = 0; $i -le $a.Length; $i++) {
        $row = New-Object 'int[]' ($b.Length + 1)
        $row[0] = $i
        $matrix[$i] = $row
    }
    for ($j = 0; $j -le $b.Length; $j++) {
        $matrix[0][$j] = $j
    }

    for ($i = 1; $i -le $a.Length; $i++) {
        for ($j = 1; $j -le $b.Length; $j++) {
            $cost = if ($a[$i - 1] -eq $b[$j - 1]) { 0 } else { 1 }
            $deletion = $matrix[$i - 1][$j] + 1
            $insertion = $matrix[$i][$j - 1] + 1
            $substitution = $matrix[$i - 1][$j - 1] + $cost
            $matrix[$i][$j] = [Math]::Min([Math]::Min($deletion, $insertion), $substitution)
        }
    }

    return $matrix[$a.Length][$b.Length]
}

function Get-PathSimilarity {
    param([string]$ExpectedPath, [string]$ActualPath)

    $expectedNorm = ($ExpectedPath -replace '/', '\').Trim('\')
    $actualNorm = ($ActualPath -replace '/', '\').Trim('\')
    if (-not $expectedNorm -or -not $actualNorm) { return 0.0 }

    $expectedLeaf = [System.IO.Path]::GetFileName($expectedNorm).ToLowerInvariant()
    $actualLeaf = [System.IO.Path]::GetFileName($actualNorm).ToLowerInvariant()
    $expectedStem = [System.IO.Path]::GetFileNameWithoutExtension($expectedLeaf)
    $actualStem = [System.IO.Path]::GetFileNameWithoutExtension($actualLeaf)
    $expectedExt = [System.IO.Path]::GetExtension($expectedLeaf)
    $actualExt = [System.IO.Path]::GetExtension($actualLeaf)
    if (-not $expectedLeaf -or -not $actualLeaf) { return 0.0 }

    $expectedParent = [System.IO.Path]::GetDirectoryName($expectedNorm)
    $actualParent = [System.IO.Path]::GetDirectoryName($actualNorm)
    $expectedParent = if ($expectedParent) { $expectedParent.ToLowerInvariant() } else { '' }
    $actualParent = if ($actualParent) { $actualParent.ToLowerInvariant() } else { '' }

    $leafDistance = Get-LevenshteinDistance -Left $expectedLeaf -Right $actualLeaf
    $leafMax = [Math]::Max($expectedLeaf.Length, $actualLeaf.Length)
    $leafScore = if ($leafMax -eq 0) { 1.0 } else { 1.0 - ($leafDistance / $leafMax) }

    $stemDistance = Get-LevenshteinDistance -Left $expectedStem -Right $actualStem
    $stemMax = [Math]::Max($expectedStem.Length, $actualStem.Length)
    $stemScore = if ($stemMax -eq 0) { 1.0 } else { 1.0 - ($stemDistance / $stemMax) }

    $parentDistance = Get-LevenshteinDistance -Left $expectedParent -Right $actualParent
    $parentMax = [Math]::Max($expectedParent.Length, $actualParent.Length)
    $parentScore = if ($parentMax -eq 0) { 1.0 } else { 1.0 - ($parentDistance / $parentMax) }

    $expectedSegments = @($expectedParent -split '\\' | Where-Object { $_ })
    $actualSegments = @($actualParent -split '\\' | Where-Object { $_ })
    $segmentScore = 0.0
    if ($expectedSegments.Count -gt 0 -and $actualSegments.Count -gt 0) {
        $overlap = @($expectedSegments | Where-Object { $_ -in $actualSegments }).Count
        $segmentScore = $overlap / [Math]::Max($expectedSegments.Count, $actualSegments.Count)
    }

    $extScore = if ($expectedExt -and $actualExt -and ($expectedExt -eq $actualExt)) { 1.0 } else { 0.0 }

    $score = (
        ($leafScore * 0.45) +
        ($stemScore * 0.20) +
        ($parentScore * 0.15) +
        ($segmentScore * 0.15) +
        ($extScore * 0.05)
    )

    return [Math]::Max(0.0, [Math]::Min(1.0, $score))
}

function Get-NormalizedFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return ([System.IO.Path]::GetFullPath($Path) -replace '/', '\').TrimEnd('\')
}

function Get-SubtreeSignature {
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][object[]]$Items,
        [string]$BasePath = ''
    )

    $root = Get-NormalizedFullPath -Path $RootPath
    $prefix = $root + '\'
    $parts = New-Object System.Collections.Generic.List[string]

    foreach ($item in $Items) {
        $candidate = $null
        if ($item.PSObject.Properties.Name -contains 'FullName' -and $item.FullName) {
            $candidate = $item.FullName
        } elseif ($item.PSObject.Properties.Name -contains 'Path' -and $item.Path) {
            $candidate = $item.Path
        }

        if (-not $candidate) { continue }
        if (-not [System.IO.Path]::IsPathRooted($candidate) -and $BasePath) {
            $candidate = Join-Path -Path $BasePath -ChildPath $candidate
        }
        $full = Get-NormalizedFullPath -Path $candidate
        if ($full -eq $root) { continue }
        if (-not $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { continue }

        $relative = $full.Substring($prefix.Length)
        $isDir = $false
        if ($item.PSObject.Properties.Name -contains 'PSIsContainer') {
            $isDir = [bool]$item.PSIsContainer
        } elseif ($item.PSObject.Properties.Name -contains 'IsDir') {
            $isDir = [bool]$item.IsDir
        }
        $kind = if ($isDir) { 'd' } else { 'f' }
        $parts.Add(($relative -replace '/', '\') + '|' + $kind) | Out-Null
    }

    return (@($parts | Sort-Object) -join "`n")
}

function Find-MovedFolders {
    param(
        [string[]]$MissingPaths,
        [string[]]$ExtraPaths,
        [object[]]$ExpectedEntries,
        [object[]]$LiveItems,
        [string]$BasePath
    )

    $matches = [System.Collections.Generic.List[object]]::new()
    $usedExtras = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $expectedSignatures = @{}
    foreach ($missing in $MissingPaths) {
        $expectedSignatures[$missing] = Get-SubtreeSignature -RootPath $missing -Items $ExpectedEntries -BasePath $BasePath
    }

    $actualSignatures = @{}
    foreach ($extra in $ExtraPaths) {
        $actualSignatures[$extra] = Get-SubtreeSignature -RootPath $extra -Items $LiveItems
    }

    foreach ($missing in ($MissingPaths | Sort-Object Length -Descending)) {
        $bestPath = $null
        $bestScore = 0.0

        foreach ($extra in $ExtraPaths) {
            if ($usedExtras.Contains($extra)) { continue }

            $expectedSig = $expectedSignatures[$missing]
            $actualSig = $actualSignatures[$extra]
            if ($expectedSig -and $actualSig -and $expectedSig -eq $actualSig) {
                $bestPath = $extra
                $bestScore = 1.0
                break
            }

            $score = Get-PathSimilarity -ExpectedPath $missing -ActualPath $extra
            if ($score -gt $bestScore) {
                $bestScore = $score
                $bestPath = $extra
            }
        }

        if ($bestPath -and $bestScore -ge 0.86) {
            $null = $usedExtras.Add($bestPath)
            $matches.Add([pscustomobject]@{
                FromPath = $missing
                ToPath   = $bestPath
                Score    = $bestScore
            }) | Out-Null
        }
    }

    return $matches
}

function Find-MovedEntries {
    param(
        [string[]]$MissingPaths,
        [string[]]$ExtraPaths
    )

    $matches = [System.Collections.Generic.List[object]]::new()
    $usedExtras = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($missing in ($MissingPaths | Sort-Object Length -Descending)) {
        $bestPath = $null
        $bestScore = 0.0
        foreach ($extra in $ExtraPaths) {
            if ($usedExtras.Contains($extra)) { continue }
            $score = Get-PathSimilarity -ExpectedPath $missing -ActualPath $extra
            if ($score -gt $bestScore) {
                $bestScore = $score
                $bestPath = $extra
            }
        }

        if ($bestPath -and $bestScore -ge 0.88) {
            $null = $usedExtras.Add($bestPath)
            $matches.Add([pscustomobject]@{
                FromPath = $missing
                ToPath   = $bestPath
                Score    = $bestScore
            }) | Out-Null
        }
    }

    return $matches
}

Write-Host ''
Write-Color '============================================' Gray
Write-Color '  verify.bat  |  Structure Drift Detector' Gray
Write-Color '============================================' Gray

Write-Host ''
$structureInput = if ($StructureFile -and $StructureFile.Trim()) {
    $StructureFile.Trim()
} else {
    Prompt-Default "Structure file path (press Enter for '_struc_file.txt')" '_struc_file.txt' -CiMode:$Ci
}
if ([System.IO.Path]::IsPathRooted($structureInput)) {
    $structureFile = $structureInput
} else {
    $structureFile = Join-Path $scriptRoot $structureInput
}

if (-not (Test-Path -LiteralPath $structureFile)) {
    Write-Color "[ERROR] File not found: $structureFile" Red
    exit 2
}

$format = Get-StructureFormat -FilePath $structureFile
if ($format -eq 'empty') {
    Write-Color '[ERROR] Structure file is empty or contains only comments.' Red
    exit 2
}

if ($format -eq 'unknown') {
    if ($Ci) {
        Write-Color '[ERROR] Structure file format could not be auto-detected in CI mode.' Red
        exit 2
    }
    Write-Color '[INFO] Format not auto-detected.' White
    Write-Color '[1] Dash    [2] Tab    [3] Tree symbols    [4] Fixed spaces' White
    $choice = (Read-Host 'Enter choice (1-4)').Trim()
    switch ($choice) {
        '1' { $format = 'dash' }
        '2' { $format = 'tab' }
        '3' { $format = 'treesym' }
        '4' {
            $format = 'space'
            $spaceInput = Read-Host 'Spaces per depth level (default 2)'
            if ([string]::IsNullOrWhiteSpace($spaceInput)) {
                $spaceUnit = 2
            } else {
                [int]$spaceUnit = $spaceInput
            }
        }
        default {
            Write-Color '[ERROR] No format selected.' Red
            exit 2
        }
    }
}

if (-not $spaceUnit) {
    $spaceUnit = 2
}

Write-Color "[OK] Format: $format" Green

if (-not (Confirm-StructureFormat -FilePath $structureFile -Format $format -SpaceUnit $spaceUnit)) {
    Write-Color '[ERROR] Structure file failed validation.' Red
    exit 2
}

$entries = Read-StructureFile -FilePath $structureFile -Format $format -SpaceUnit $spaceUnit
if (-not $entries -or @($entries).Count -eq 0) {
    Write-Color '[ERROR] Structure file has no parseable entries.' Red
    exit 2
}

$badNames = $entries | Where-Object { Test-DangerousName -Name $_.Name.TrimEnd('/') }
if ($badNames) {
    Write-Color '[ERROR] Structure file contains dangerous entry names.' Red
    $badNames | ForEach-Object { Write-Color ('  - ' + $_.Name) White }
    exit 2
}

Write-Host ''
Write-Color 'Which live directory to compare against?' White
Write-Color '[1] This directory  (where verify.bat lives)' White
Write-Color '[2] Enter a custom path' White
if ($LivePath -and $LivePath.Trim()) {
    $base = $LivePath.Trim()
} else {
    if ($Ci) {
        $base = (Resolve-Path -LiteralPath $scriptRoot).Path
    } else {
    $dirChoice = (Read-Host 'Enter choice (1-2, default 1)').Trim()
    if ([string]::IsNullOrWhiteSpace($dirChoice)) {
        $dirChoice = '1'
    }

    if ($dirChoice -eq '1') {
        $base = (Resolve-Path -LiteralPath $scriptRoot).Path
    } elseif ($dirChoice -eq '2') {
        $liveInput = Read-Host 'Enter full directory path'
        if ([string]::IsNullOrWhiteSpace($liveInput)) {
            Write-Color '[ERROR] No path entered.' Red
            exit 2
        }
        $base = $liveInput.Trim()
    } else {
        Write-Color '[ERROR] Invalid directory choice.' Red
        exit 2
    }
    }
}

if (-not (Test-Path -LiteralPath $base)) {
    Write-Color "[ERROR] Directory not found: $base" Red
    exit 2
}

Write-Host ''
$extraExclude = if ($Ci) { '' } else { Read-Host 'Extra folders to exclude (comma-separated, or Enter to skip)' }
$treeConfig = Get-TreeConfig -RootPath $base -IgnoreFile $IgnoreFile -ExtraExclude $extraExclude
$defaultMaxDepth = if ($treeConfig.MaxDepth) { [string]$treeConfig.MaxDepth } else { '5' }
$maxDepthInput = Prompt-Default 'Max depth to scan (default 5)' $defaultMaxDepth -CiMode:$Ci
[int]$maxDepth = $maxDepthInput

Write-Host ''
$saveReport = if ($Ci) { '' } else { (Read-Host 'Save verification report to file? (y/N)').Trim() }
$reportFile = ''
if ($saveReport -match '^(?i)y$') {
    $reportName = Prompt-Default "Report file name (press Enter for 'verify_report.txt')" 'verify_report.txt' -CiMode:$Ci
    $reportFile = Resolve-ReportPath $reportName
}

try {
    $expectedFiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $expectedFolders = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $actualFiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $actualFolders = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $pathStack = @{}
    $expectedEntryMap = @{}
    foreach ($entry in $entries) {
        $fullPath = Resolve-EntryPath -Entry $entry -BasePath $base -PathStack $pathStack
        # Always update pathStack: any entry can be a parent regardless of trailing slash
        $pathStack[$entry.Depth] = $fullPath
        $expectedEntryMap[$fullPath] = $entry
        if ($entry.IsDir) {
            [void]$expectedFolders.Add($fullPath)
        } else {
            [void]$expectedFiles.Add($fullPath)
        }
    }

    $excludeFolders = Get-ExcludeList -RootPath $base -ExtraExclude $extraExclude -IgnoreFile $IgnoreFile
    $liveItems = Get-LimitedItems -Path $base -CurrentDepth 0 -MaxDepth $maxDepth -ExcludeFolders $excludeFolders

    foreach ($item in $liveItems) {
        if ($item.PSIsContainer) {
            [void]$actualFolders.Add($item.FullName)
        } else {
            [void]$actualFiles.Add($item.FullName)
        }
    }

    $missingFiles = @($expectedFiles | Where-Object { -not $actualFiles.Contains($_) })
    $missingFolders = @($expectedFolders | Where-Object { -not $actualFolders.Contains($_) })
    $extraFiles = @($actualFiles | Where-Object { -not $expectedFiles.Contains($_) })
    $extraFolders = @($actualFolders | Where-Object { -not $expectedFolders.Contains($_) })
    $matchedFiles = @($expectedFiles | Where-Object { $actualFiles.Contains($_) })
    $matchedFolders = @($expectedFolders | Where-Object { $actualFolders.Contains($_) })

    $movedFiles = Find-MovedEntries -MissingPaths $missingFiles -ExtraPaths $extraFiles
    $movedFolders = Find-MovedFolders -MissingPaths $missingFolders -ExtraPaths $extraFolders -ExpectedEntries $entries -LiveItems $liveItems -BasePath $base

    $missingFiles = @($missingFiles | Where-Object { $movedFiles.FromPath -notcontains $_ })
    $extraFiles = @($extraFiles | Where-Object { $movedFiles.ToPath -notcontains $_ })
    $missingFolders = @($missingFolders | Where-Object { $movedFolders.FromPath -notcontains $_ })
    $extraFolders = @($extraFolders | Where-Object { $movedFolders.ToPath -notcontains $_ })

    $sep = [string]::new([char]0x2500, 45)
    $sb = [System.Text.StringBuilder]::new()
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    [void]$sb.AppendLine($sep)
    [void]$sb.AppendLine('  VERIFICATION REPORT')
    [void]$sb.AppendLine('  Generated : ' + $timestamp)
    [void]$sb.AppendLine('  Structure : ' + $structureFile)
    [void]$sb.AppendLine('  Live Dir  : ' + $base)
    [void]$sb.AppendLine($sep)
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('  [MATCHED]  Folders : ' + $matchedFolders.Count)
    [void]$sb.AppendLine('  [MATCHED]  Files   : ' + $matchedFiles.Count)
    [void]$sb.AppendLine('  [MOVED]    Folders : ' + $movedFolders.Count)
    [void]$sb.AppendLine('  [MOVED]    Files   : ' + $movedFiles.Count)
    [void]$sb.AppendLine('  [MISSING]  Folders : ' + $missingFolders.Count)
    [void]$sb.AppendLine('  [MISSING]  Files   : ' + $missingFiles.Count)
    [void]$sb.AppendLine('  [EXTRA]    Folders : ' + $extraFolders.Count)
    [void]$sb.AppendLine('  [EXTRA]    Files   : ' + $extraFiles.Count)
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine($sep)

    if ($missingFolders.Count -gt 0) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('  MISSING FOLDERS:')
        foreach ($path in $missingFolders) {
            [void]$sb.AppendLine('    - ' + $path)
        }
    }

    if ($missingFiles.Count -gt 0) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('  MISSING FILES:')
        foreach ($path in $missingFiles) {
            [void]$sb.AppendLine('    - ' + $path)
        }
    }

    if ($movedFolders.Count -gt 0) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('  MOVED FOLDERS:')
        foreach ($move in $movedFolders) {
            [void]$sb.AppendLine('    ~ ' + $move.FromPath + ' -> ' + $move.ToPath)
        }
    }

    if ($movedFiles.Count -gt 0) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('  MOVED FILES:')
        foreach ($move in $movedFiles) {
            [void]$sb.AppendLine('    ~ ' + $move.FromPath + ' -> ' + $move.ToPath)
        }
    }

    if ($extraFolders.Count -gt 0) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('  EXTRA FOLDERS (not in structure):')
        foreach ($path in $extraFolders) {
            [void]$sb.AppendLine('    + ' + $path)
        }
    }

    if ($extraFiles.Count -gt 0) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('  EXTRA FILES (not in structure):')
        foreach ($path in $extraFiles) {
            [void]$sb.AppendLine('    + ' + $path)
        }
    }

    if ($matchedFiles.Count -gt 0) {
        $baseRoot = (Get-NormalizedFullPath -Path $base).TrimEnd('\')
        $matchedFileInfos = foreach ($path in ($matchedFiles | Sort-Object)) {
            $item = Get-Item -LiteralPath $path
            $relativePath = $path
            $basePrefix = $baseRoot + '\'
            if ($path.StartsWith($basePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $relativePath = $path.Substring($basePrefix.Length)
            }

            [pscustomobject]@{
                RelativePath  = $relativePath
                SizeBytes     = [long]$item.Length
                SizeText      = Format-FileSize -Bytes ([long]$item.Length)
                LastWriteTime = [datetime]$item.LastWriteTime
            }
        }

        $pathWidth = 24
        $sizeWidth = 8
        $totalBytes = [long]0
        $newestWrite = [datetime]::MinValue

        foreach ($info in $matchedFileInfos) {
            if ($info.RelativePath.Length -gt $pathWidth) {
                $pathWidth = $info.RelativePath.Length
            }
            if ($info.SizeText.Length -gt $sizeWidth) {
                $sizeWidth = $info.SizeText.Length
            }
            $totalBytes += $info.SizeBytes
            if ($info.LastWriteTime -gt $newestWrite) {
                $newestWrite = $info.LastWriteTime
            }
        }

        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('  FILE METADATA:')
        foreach ($info in $matchedFileInfos) {
            [void]$sb.AppendLine(('    [OK]  {0,-' + $pathWidth + '}  {1,' + $sizeWidth + '}  {2}') -f $info.RelativePath, $info.SizeText, $info.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
        }
        [void]$sb.AppendLine(('  Matched files: {0}  |  Total size: {1}  |  Newest: {2}') -f $matchedFileInfos.Count, ('{0:F1} MB' -f ($totalBytes / 1MB)), $newestWrite.ToString('yyyy-MM-dd HH:mm:ss'))
    }

    $driftCount = $missingFolders.Count + $missingFiles.Count + $extraFolders.Count + $extraFiles.Count + $movedFolders.Count + $movedFiles.Count
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine($sep)
    if ($driftCount -eq 0) {
        [void]$sb.AppendLine('  RESULT: NO DRIFT - live directory matches structure file exactly.')
    } else {
        [void]$sb.AppendLine('  RESULT: DRIFT DETECTED - ' + $driftCount + ' discrepancies found.')
    }
    [void]$sb.AppendLine($sep)

    $reportText = $sb.ToString()
    Write-Host $reportText

    if ($Sync) {
        $projectName = Split-Path -Path $base -Leaf
        $created = 0
        $deleted = 0

        foreach ($path in $missingFolders) {
            if (-not (Test-Path -LiteralPath $path)) {
                New-Item -ItemType Directory -Path $path -Force | Out-Null
                $created++
                Write-Color ('[SYNC] Created folder: ' + $path) Cyan
            }
        }

        foreach ($path in $missingFiles) {
            if (-not (Test-Path -LiteralPath $path)) {
                $entry = $expectedEntryMap[$path]
                $parentDir = Split-Path -Path $path -Parent
                if ($parentDir -and -not (Test-Path -LiteralPath $parentDir)) {
                    New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
                }
                $content = Get-StructureEntryContent -Entry $entry -ProjectName $projectName
                [System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))
                $created++
                Write-Color ('[SYNC] Created file: ' + $path) Cyan
            }
        }

        if ($DeleteExtras) {
            foreach ($path in ($extraFiles | Sort-Object -Descending)) {
                if ((Test-Path -LiteralPath $path) -and (Test-SafePath -CandidatePath $path -AllowedBase $base)) {
                    Remove-Item -LiteralPath $path -Force
                    $deleted++
                    Write-Color ('[SYNC] Deleted file: ' + $path) Cyan
                }
            }
            foreach ($path in ($extraFolders | Sort-Object { $_.Length } -Descending)) {
                if ((Test-Path -LiteralPath $path) -and (Test-SafePath -CandidatePath $path -AllowedBase $base)) {
                    Remove-Item -LiteralPath $path -Recurse -Force
                    $deleted++
                    Write-Color ('[SYNC] Deleted folder: ' + $path) Cyan
                }
            }
        }

        Write-Color ('[SYNC] Created: ' + $created + '  Deleted: ' + $deleted) Cyan
    }

    if ($reportFile) {
        $reportDir = Split-Path -Parent $reportFile
        if ($reportDir -and -not (Test-Path -LiteralPath $reportDir)) {
            New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
        }
        [System.IO.File]::WriteAllText($reportFile, $reportText, [System.Text.UTF8Encoding]::new($false))
        Write-Color "[OK] Report saved: $reportFile" Green
    }

    if ($driftCount -gt 0) {
        exit 1
    }

    exit 0
} catch {
    Write-Color '[ERROR] Verification could not complete.' Red
    Write-Color $_.Exception.Message Red
    exit 2
}
