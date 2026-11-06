function Test-TreeScope {
    param([string]$RelativePath,[AllowEmptyCollection()][string[]]$ExcludeFolders=@(),[int]$MaxDepth=0)
    $path=$RelativePath.Replace('\','/').Trim('/')
    if (-not $path) { return $false }
    $parts=$path.Split('/')
    if ($MaxDepth -gt 0 -and $parts.Count -gt $MaxDepth) { return $false }
    foreach ($exclude in $ExcludeFolders) {
        $rule=$exclude.Replace('\','/').Trim('/')
        if (-not $rule) { continue }
        if ($rule.Contains('/')) {
            if ($path -eq $rule -or $path.StartsWith($rule+'/',[StringComparison]::OrdinalIgnoreCase)) { return $false }
        } elseif ($parts -contains $rule) { return $false }
    }
    return $true
}

function Get-TreeScan {
    param([string]$Path,[ValidateRange(0,2147483647)][int]$MaxDepth=0,[AllowEmptyCollection()][string[]]$ExcludeFolders=@())
    $root=[IO.Path]::GetFullPath($Path).TrimEnd('\')
    if($root -eq [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path)).TrimEnd('\')){$root=[IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path))}
    $items=New-Object 'System.Collections.Generic.List[object]'
    $errors=New-Object 'System.Collections.Generic.List[object]'
    function Scan-Directory([string]$Directory,[string]$Relative) {
        try { $children=@(Get-ChildItem -LiteralPath $Directory -Force -ErrorAction Stop) }
        catch { $errors.Add([pscustomobject]@{Path=$Directory;Message=$_.Exception.Message});return }
        foreach ($child in $children) {
            $rel=if($Relative){$Relative+'/'+$child.Name}else{$child.Name}
            if (-not (Test-TreeScope $rel $ExcludeFolders $MaxDepth)) { continue }
            $items.Add($child)
            if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                $errors.Add([pscustomobject]@{Path=$child.FullName;Message='Reparse points are not followed; scan is incomplete.'})
                continue
            }
            if ($child.PSIsContainer -and ($MaxDepth -eq 0 -or $rel.Split('/').Count -lt $MaxDepth)) { Scan-Directory $child.FullName $rel }
        }
    }
    try {
        $rootItem=Get-Item -LiteralPath $root -Force -ErrorAction Stop
        if (-not $rootItem.PSIsContainer) { throw 'Scan root must be a directory.' }
        if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Scan root cannot be a reparse point.' }
        Scan-Directory $root ''
    } catch { $errors.Add([pscustomobject]@{Path=$root;Message=$_.Exception.Message}) }
    return [pscustomobject]@{Root=$root;Items=$items.ToArray();Errors=$errors.ToArray();Complete=($errors.Count -eq 0);MaxDepth=$MaxDepth;ExcludeFolders=$ExcludeFolders}
}

function Assert-CompleteScan {
    param($Scan)
    if (-not $Scan.Complete) {
        foreach ($errorItem in $Scan.Errors) { Write-Host ('[SCAN ERROR] '+$errorItem.Path+': '+$errorItem.Message) }
        throw 'Directory scan is incomplete; export/comparison/sync refused.'
    }
}

function Get-TreeComparison {
    param([string]$BasePath,[object[]]$Entries,[AllowEmptyCollection()][string[]]$ExcludeFolders=@(),[int]$MaxDepth=0)
    $root=[IO.Path]::GetFullPath($BasePath).TrimEnd('\')
    if($root -eq [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($BasePath)).TrimEnd('\')){$root=[IO.Path]::GetPathRoot([IO.Path]::GetFullPath($BasePath))}
    $expectedFiles=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $expectedFolders=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $actualFiles=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $actualFolders=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $outOfScope=New-Object 'System.Collections.Generic.List[object]'
    foreach ($entry in $Entries) {
        if (-not (Test-TreeScope $entry.Path $ExcludeFolders $MaxDepth)) { $outOfScope.Add($entry);continue }
        $full=[IO.Path]::GetFullPath((Join-Path $root $entry.Path))
        if ($entry.IsDir) { $null=$expectedFolders.Add($full) } else { $null=$expectedFiles.Add($full) }
        # Path-style entries imply directory parents even when not listed explicitly.
        $parent=Split-Path $full -Parent
        while ($parent -and $parent -ne $root) { $null=$expectedFolders.Add($parent);$parent=Split-Path $parent -Parent }
    }
    $scan=Get-TreeScan $root $MaxDepth $ExcludeFolders
    Assert-CompleteScan $scan
    foreach ($item in $scan.Items) { if ($item.PSIsContainer){$null=$actualFolders.Add($item.FullName)}else{$null=$actualFiles.Add($item.FullName)} }
    return [pscustomobject]@{
        Scan=$scan;LiveItems=$scan.Items;OutOfScope=$outOfScope.ToArray()
        ExpectedFiles=$expectedFiles;ExpectedFolders=$expectedFolders;ActualFiles=$actualFiles;ActualFolders=$actualFolders
        MissingFiles=@($expectedFiles | Where-Object {-not $actualFiles.Contains($_)})
        MissingFolders=@($expectedFolders | Where-Object {-not $actualFolders.Contains($_)})
        ExtraFiles=@($actualFiles | Where-Object {-not $expectedFiles.Contains($_)})
        ExtraFolders=@($actualFolders | Where-Object {-not $expectedFolders.Contains($_)})
        MatchedFiles=@($expectedFiles | Where-Object {$actualFiles.Contains($_)})
        MatchedFolders=@($expectedFolders | Where-Object {$actualFolders.Contains($_)})
    }
}

function Resolve-TreeOptions {
    param($Config,[hashtable]$Explicit,[int]$DefaultDepth=5,[string]$DefaultShowMode='all')
    $depth=if($Explicit.ContainsKey('MaxDepth')){[int]$Explicit.MaxDepth}elseif($null -ne $Config.MaxDepth){[int]$Config.MaxDepth}else{$DefaultDepth}
    $show=if($Explicit.ContainsKey('ShowMode')){[string]$Explicit.ShowMode}elseif($Config.ShowMode){[string]$Config.ShowMode}else{$DefaultShowMode}
    if($depth -lt 0 -or $show -notin @('all','folders','files')){throw 'Invalid tree depth or show mode.'}
    return [pscustomobject]@{MaxDepth=$depth;ShowMode=$show}
}
