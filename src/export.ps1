param(
    [string]$ArgsFile = '',
    [string]$RootPath = '',
    [string]$OutputFile = '',
    [string]$OutputFormat = '',
    [int]$MaxDepth = 5,
    [ValidateSet('all', 'folders', 'files')][string]$ShowMode = 'all',
    [string]$ExcludeList = '',
    [string]$IgnoreFile = '',
    [string]$ExtraExclude = '',
    [switch]$Ci
)

# When called from export.bat, paths are passed via a temp file to avoid
# CMD quoting issues with spaces and special characters in directory names.
if ($ArgsFile -and (Test-Path -LiteralPath $ArgsFile)) {
    $lines = [System.IO.File]::ReadAllLines($ArgsFile)
    $RootPath     = if ($lines.Count -gt 0) { $lines[0].Trim() } else { '' }
    $OutputFile   = if ($lines.Count -gt 1) { $lines[1].Trim() } else { '' }
    $OutputFormat = if ($lines.Count -gt 2) { $lines[2].Trim() } else { 'md' }
    $mdRaw        = if ($lines.Count -gt 3) { $lines[3].Trim() } else { '5' }
    $MaxDepth     = if ($mdRaw -match '^\d+$') { [int]$mdRaw } else { 5 }
    $ShowMode     = if ($lines.Count -gt 4 -and $lines[4].Trim() -ne '') { $lines[4].Trim() } else { 'all' }
    $ExtraExclude = if ($lines.Count -gt 5) { $lines[5].Trim() } else { '' }
    $IgnoreFile   = if ($lines.Count -gt 6) { $lines[6].Trim() } else { '' }
}

if (-not $RootPath) {
    Write-Host '[ERROR] RootPath is required.'
    exit 2
}
if (-not $OutputFile) {
    Write-Host '[ERROR] OutputFile is required.'
    exit 2
}
if (-not $OutputFormat) { $OutputFormat = 'md' }
$validFormats = @('importable','md','txt','json','yaml')
if ($OutputFormat -notin $validFormats) {
    Write-Host "[ERROR] OutputFormat must be one of: $($validFormats -join ', ')"
    exit 2
}

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sharedPath = Join-Path $scriptRoot 'internal\_shared.ps1'
if (-not (Test-Path -LiteralPath $sharedPath)) {
    Write-Host '[ERROR] _shared.ps1 not found. Place it alongside export.ps1.'
    exit 2
}

. $sharedPath

function Get-ExcludedNames {
    param([string]$Value)
    if (-not $Value) { return @() }
    return @(
        $Value.Split(',') |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne '' }
    )
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$FullPath
    )

    $base = [System.IO.Path]::GetFullPath($BasePath).TrimEnd('\') + '\'
    $full = [System.IO.Path]::GetFullPath($FullPath)
    if ($full.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($base.Length).TrimStart('\')
    }
    return [System.IO.Path]::GetFileName($full)
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

function Get-TreeEntries {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string[]]$ExcludeFolders,
        [Parameter(Mandatory = $true)][int]$CurrentDepth,
        [Parameter(Mandatory = $true)][int]$MaxDepth
    )

    $items = [System.Collections.Generic.List[object]]::new()
    if ($MaxDepth -gt 0 -and $CurrentDepth -gt $MaxDepth) { return $items }

    $children = Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    foreach ($child in $children) {
        if (Test-ExcludedPath -FullPath $child.FullName -ExcludeFolders $ExcludeFolders) {
            continue
        }

        $rel = Get-RelativePath -BasePath $RootPath -FullPath $child.FullName
        $entry = [pscustomobject]@{
            Path  = $rel -replace '\\', '/'
            Type  = if ($child.PSIsContainer) { 'tree' } else { 'blob' }
            IsDir = [bool]$child.PSIsContainer
        }
        $items.Add($entry) | Out-Null

        if ($child.PSIsContainer) {
            $nested = Get-TreeEntries -Path $child.FullName -RootPath $RootPath -ExcludeFolders $ExcludeFolders -CurrentDepth ($CurrentDepth + 1) -MaxDepth $MaxDepth
            foreach ($n in $nested) { $items.Add($n) | Out-Null }
        }
    }

    return $items
}

function Build-TextTree {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Prefix = '',
        [Parameter(Mandatory = $true)][int]$CurrentDepth,
        [Parameter(Mandatory = $true)][int]$MaxDepth,
        [Parameter(Mandatory = $true)][string[]]$ExcludeFolders,
        [Parameter(Mandatory = $true)][string]$Format,
        [Parameter(Mandatory = $true)][string]$ShowMode,
        [Parameter(Mandatory = $true)][System.Text.StringBuilder]$Sb
    )

    if ($MaxDepth -gt 0 -and $CurrentDepth -gt $MaxDepth) { return }

    $items = Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    $filtered = foreach ($child in $items) {
        if (Test-ExcludedPath -FullPath $child.FullName -ExcludeFolders $ExcludeFolders) { continue }
        $child
    }

    $dirs = @($filtered | Where-Object { $_.PSIsContainer })
    $files = @($filtered | Where-Object { -not $_.PSIsContainer })
    $all = switch ($ShowMode) {
        'folders' { $dirs }
        'files'   { $files }
        default   { $dirs + $files }
    }

    for ($i = 0; $i -lt $all.Count; $i++) {
        $item = $all[$i]
        $isLast = ($i -eq $all.Count - 1)
        $slash = if ($item.PSIsContainer) { '/' } else { '' }
        $emoji = Get-Emoji -Item $item

        if ($Format -eq 'importable') {
            $dashes = '-' * $CurrentDepth
            [void]$Sb.AppendLine($dashes + ' ' + $item.Name + $slash)
        } else {
            $conn = if ($isLast) { [char]0x2514 + [char]0x2500 + [char]0x2500 + ' ' } else { [char]0x251C + [char]0x2500 + [char]0x2500 + ' ' }
            if ($Format -eq 'md') {
                [void]$Sb.AppendLine($Prefix + $conn + $emoji + ' ``' + $item.Name + $slash + '``')
            } else {
                [void]$Sb.AppendLine($Prefix + $conn + $emoji + ' ' + $item.Name + $slash)
            }
        }

        if ($item.PSIsContainer) {
            $newPrefix = if ($Format -eq 'importable') { '' } elseif ($isLast) { $Prefix + '    ' } else { $Prefix + ([char]0x2502 + '   ') }
            Build-TextTree -Path $item.FullName -Prefix $newPrefix -CurrentDepth ($CurrentDepth + 1) -MaxDepth $MaxDepth -ExcludeFolders $ExcludeFolders -Format $Format -ShowMode $ShowMode -Sb $Sb
        }
    }
}

$root = (Resolve-Path -LiteralPath $RootPath).Path
$rootName = Split-Path -Path $root -Leaf
$exclude = @()
$exclude += Get-ExcludedNames -Value $ExcludeList
$exclude += Get-ExcludedNames -Value $ExtraExclude
$configExcludes = Get-ExcludeList -RootPath $root -IgnoreFile $IgnoreFile -ExtraExclude ($exclude -join ',')

$sb = [System.Text.StringBuilder]::new()
$sep = [string]::new([char]0x2500, 45)
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

if ($OutputFormat -in @('json', 'yaml')) {
    $entries = Get-TreeEntries -Path $root -RootPath $root -ExcludeFolders $configExcludes -CurrentDepth 1 -MaxDepth $MaxDepth
    if ($OutputFormat -eq 'json') {
        $output = ConvertTo-TreeJson -Entries $entries -RootName $rootName -Depth 20
    } else {
        $output = ConvertTo-TreeYaml -Entries $entries -RootName $rootName
    }
} else {
    $sb.AppendLine($sep) | Out-Null
    $sb.AppendLine('  PROJECT SUMMARY') | Out-Null
    $sb.AppendLine('  Generated : ' + $timestamp) | Out-Null
    $sb.AppendLine('  Root      : ' + $rootName) | Out-Null
    $sb.AppendLine('  Format    : ' + $OutputFormat) | Out-Null
    $sb.AppendLine($sep) | Out-Null
    $sb.AppendLine('') | Out-Null

    if ($OutputFormat -eq 'md') {
        $sb.AppendLine('## ' + $rootName + '/') | Out-Null
        $sb.AppendLine('``````text') | Out-Null
    } elseif ($OutputFormat -eq 'importable') {
        $sb.AppendLine('- ' + $rootName + '/') | Out-Null
    } else {
        $sb.AppendLine($rootName + '/') | Out-Null
    }

    Build-TextTree -Path $root -Prefix '' -CurrentDepth 1 -MaxDepth $MaxDepth -ExcludeFolders $configExcludes -Format $OutputFormat -ShowMode $ShowMode -Sb $sb

    if ($OutputFormat -eq 'md') {
        $sb.AppendLine('``````') | Out-Null
    }

    $output = $sb.ToString()
}

$outputDir = Split-Path -Parent $OutputFile
if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}
[System.IO.File]::WriteAllText($OutputFile, $output, [System.Text.Encoding]::UTF8)

if (-not $Ci) {
    Write-Host ('[OK] Saved: ' + $OutputFile)
}

exit 0
