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
    [switch]$Ci,
    [switch]$FromEnvironment
)

$ErrorActionPreference = 'Stop'
try {
if ($FromEnvironment) {
    $RootPath=$env:SCAN_DIR; $OutputFile=$env:OUT_FILE; $OutputFormat=$env:FORMAT_TYPE
    if ($env:MAX_DEPTH) { $MaxDepth=[int]$env:MAX_DEPTH }
    if ($env:SHOW_MODE) { $ShowMode=$env:SHOW_MODE }
    $ExtraExclude=$env:extra_exclude; $IgnoreFile=$env:IGNORE_FILE
}
# Legacy ArgsFile input remains supported; wrappers now use environment data.
if ($ArgsFile) {
    if(-not (Test-Path -LiteralPath $ArgsFile -PathType Leaf)){throw 'Argument file not found.'}
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
    param([string]$Path,[string]$RootPath,[AllowEmptyCollection()][string[]]$ExcludeFolders,[int]$CurrentDepth,[int]$MaxDepth)
    $scan=Get-TreeScan $RootPath $MaxDepth $ExcludeFolders
    Assert-CompleteScan $scan
    foreach($item in $scan.Items){
        [pscustomobject]@{Path=(Get-RelativePath $RootPath $item.FullName).Replace('\','/');Type=$(if($item.PSIsContainer){'tree'}else{'blob'});IsDir=[bool]$item.PSIsContainer}
    }
}
function Build-TextTree {
    param([string]$Path,[string]$Prefix='',[int]$CurrentDepth,[int]$MaxDepth,[AllowEmptyCollection()][string[]]$ExcludeFolders,[string]$Format,[string]$ShowMode,[Text.StringBuilder]$Sb)
    # Render the already-completed scan; do not race a second recursive scan.
    $groups=@{}
    foreach($item in $script:ExportScan.Items){
        $parent=if($item.PSIsContainer){$item.Parent.FullName}else{$item.DirectoryName}
        if(-not $groups.ContainsKey($parent)){$groups[$parent]=New-Object 'System.Collections.Generic.List[object]'}
        $groups[$parent].Add($item)
    }
    function Render-Children([string]$Parent,[string]$Pad,[int]$Depth) {
        $children=@($groups[$Parent] | Sort-Object @{Expression={-not $_.PSIsContainer}},Name)
        foreach($item in $children){
            $visible=$ShowMode -eq 'all' -or ($ShowMode -eq 'folders' -and $item.PSIsContainer) -or ($ShowMode -eq 'files' -and -not $item.PSIsContainer)
            $slash=if($item.PSIsContainer){'/'}else{''}
            if($visible){
                if($Format -eq 'importable'){
                    # Files-only output uses complete relative paths so omitted directory
                    # lines cannot change the hierarchy on re-import.
                    if($ShowMode -eq 'files'){[void]$Sb.AppendLine('- '+(Get-RelativePath $script:ExportScan.Root $item.FullName).Replace('\','/'))}
                    else{[void]$Sb.AppendLine(('-'*$Depth)+' '+$item.Name+$slash)}
                }else{
                    $connector=[string]$(if($item.FullName -eq $children[-1].FullName){[char]0x2514}else{[char]0x251c})+[char]0x2500+[char]0x2500+' '
                    [void]$Sb.AppendLine($Pad+$connector+(Get-Emoji $item)+' '+$item.Name+$slash)
                }
            }
            if($item.PSIsContainer){Render-Children $item.FullName ($Pad+'    ') ($Depth+1)}
        }
    }
    Render-Children $script:ExportScan.Root $Prefix $CurrentDepth
}
if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) { Write-Host '[ERROR] RootPath must be a directory.'; exit 2 }
$root = (Resolve-Path -LiteralPath $RootPath).Path
$rootName = Split-Path -Path $root -Leaf
$exclude = @()
$exclude += Get-ExcludedNames -Value $ExcludeList
$exclude += Get-ExcludedNames -Value $ExtraExclude
$configExcludes = Get-ExcludeList -RootPath $root -IgnoreFile $IgnoreFile -ExtraExclude ($exclude -join ',')
$config=Get-TreeConfig -RootPath $root -IgnoreFile $IgnoreFile -ExtraExclude ($exclude -join ',')
$explicit=@{}
if($PSBoundParameters.ContainsKey('MaxDepth') -or ($FromEnvironment -and $env:MAX_DEPTH)){$explicit.MaxDepth=$MaxDepth}
if($PSBoundParameters.ContainsKey('ShowMode') -or ($FromEnvironment -and $env:SHOW_MODE)){$explicit.ShowMode=$ShowMode}
$resolvedOptions=Resolve-TreeOptions $config $explicit
$MaxDepth=$resolvedOptions.MaxDepth;$ShowMode=$resolvedOptions.ShowMode
$script:ExportScan=Get-TreeScan $root $MaxDepth $configExcludes
Assert-CompleteScan $script:ExportScan

$sb = [System.Text.StringBuilder]::new()
$sep = [string]::new([char]0x2500, 45)
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

if ($OutputFormat -in @('json', 'yaml')) {
    $entries=@($script:ExportScan.Items | ForEach-Object { [pscustomobject]@{Path=(Get-RelativePath $root $_.FullName).Replace('\','/');Type=$(if($_.PSIsContainer){'tree'}else{'blob'});IsDir=[bool]$_.PSIsContainer} })
    if($ShowMode -eq 'folders'){$entries=@($entries|Where-Object IsDir)}
    if($ShowMode -eq 'files'){$entries=@($entries|Where-Object {-not $_.IsDir});$entries=@($entries|ForEach-Object {$_|Add-Member -NotePropertyName Type -NotePropertyValue 'blob' -Force -PassThru})}
    if ($OutputFormat -eq 'json') {
        $output = ConvertTo-TreeJson -Entries $entries -RootName $rootName -Depth 100
    } else {
        $output = ConvertTo-TreeYaml -Entries $entries -RootName $rootName
    }
} else {
    if ($OutputFormat -ne 'importable') {
        $sb.AppendLine($sep) | Out-Null
        $sb.AppendLine('  PROJECT SUMMARY') | Out-Null
        $sb.AppendLine('  Generated : ' + $timestamp) | Out-Null
        $sb.AppendLine('  Root      : ' + $rootName) | Out-Null
        $sb.AppendLine('  Format    : ' + $OutputFormat) | Out-Null
        $sb.AppendLine($sep) | Out-Null
        $sb.AppendLine('') | Out-Null
    }

    if ($OutputFormat -eq 'md') {
        $sb.AppendLine('## ' + $rootName + '/') | Out-Null
        $sb.AppendLine('``````text') | Out-Null
    } elseif ($OutputFormat -ne 'importable') {
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

} catch { Write-Host ('[ERROR] Export failed: '+$_.Exception.Message); exit 2 }
