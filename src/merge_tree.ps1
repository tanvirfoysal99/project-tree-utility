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
if (-not (Test-Path $shared)) {
    Write-Host '[ERROR] _shared.ps1 not found alongside merge_tree.ps1.'
    exit 2
}

. $shared

function Build-Tree {
    param($Entries)
    $root = @{
        Name     = '__ROOT__'
        Depth    = 0
        Children = [System.Collections.Generic.List[object]]::new()
    }
    $stack = [System.Collections.Generic.List[object]]::new()
    $stack.Add($root)

    foreach ($e in $Entries) {
        $node = @{
            Name     = $e.Name
            Depth    = $e.Depth
            Children = [System.Collections.Generic.List[object]]::new()
        }
        while ($stack.Count -gt 1 -and $stack[$stack.Count - 1].Depth -ge $e.Depth) {
            $stack.RemoveAt($stack.Count - 1)
        }
        $stack[$stack.Count - 1].Children.Add($node)
        $stack.Add($node)
    }

    return $root
}

function Merge-Trees {
    param($ANode, $BNode, [string]$MergeStrategy)

    $aByName = @{}
    foreach ($child in $ANode.Children) {
        $key = $child.Name.ToLower().TrimEnd('/')
        $aByName[$key] = $child
    }

    foreach ($bChild in $BNode.Children) {
        $key = $bChild.Name.ToLower().TrimEnd('/')
        if ($aByName.ContainsKey($key)) {
            if ($MergeStrategy -eq 'b_over_a') {
                $aByName[$key].Name = $bChild.Name
            }
            Merge-Trees -ANode $aByName[$key] -BNode $bChild -MergeStrategy $MergeStrategy
        } else {
            $ANode.Children.Add($bChild)
        }
    }
}

function Flatten-Tree {
    param($Node, [int]$Depth = 0)

    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($child in $Node.Children) {
        $result.Add(('-' * ($Depth + 1)) + ' ' + $child.Name)
        $sub = Flatten-Tree -Node $child -Depth ($Depth + 1)
        foreach ($line in $sub) {
            $result.Add($line)
        }
    }
    return $result
}

try {
    $entriesA = Read-StructureFile -FilePath $FileA -Format $FormatA -SpaceUnit $SpaceUnitA
    $entriesB = Read-StructureFile -FilePath $FileB -Format $FormatB -SpaceUnit $SpaceUnitB
    $treeA = Build-Tree -Entries $entriesA
    $treeB = Build-Tree -Entries $entriesB
    Merge-Trees -ANode $treeA -BNode $treeB -MergeStrategy $Strategy
    $flat = Flatten-Tree -Node $treeA

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
