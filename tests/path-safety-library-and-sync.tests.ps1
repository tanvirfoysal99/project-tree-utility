# Run with Windows PowerShell 5.1: powershell.exe -NoProfile -File tests/path-safety-library-and-sync.tests.ps1
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('ptu-regression-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $scratch
$script:checks = 0
$junctions = New-Object 'System.Collections.Generic.List[string]'
function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
    $script:checks++
    Write-Host ('PASS: ' + $Message)
}
function Assert-Throws([scriptblock]$Action, [string]$Message) {
    $threw = $false
    try { & $Action | Out-Null } catch { $threw = $true }
    Assert $threw $Message
}
function Write-Fixture([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}
function Invoke-Verify([string]$Structure, [string]$Live, [string]$Ignore = '') {
    & powershell.exe -NoProfile -NonInteractive -File (Join-Path $repo 'src/verify.ps1') -StructureFile $Structure -LivePath $Live -IgnoreFile $Ignore -Sync -DeleteExtras -Ci | Out-Host
    return $LASTEXITCODE
}
function Invoke-ScaffoldWrapper([string]$Wrapper, [string]$Structure, [string]$Name, [string]$Target, [switch]$Template) {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $env:ComSpec
    $arguments = if ($Template) { '--template monorepo-pnpm' } else { '"' + $Structure + '" dash' }
    # SET /P can discard buffered lines from a pipe; redirect a fixture file.
    $inputFile = Join-Path (Split-Path $Wrapper -Parent) 'test-input.txt'
    Write-Fixture $inputFile (($Name, '2', $Target, 'n', '1', '' -join "`r`n") + "`r`n")
    $start.Arguments = '/d /c ""' + $Wrapper + '" ' + $arguments + ' < "' + $inputFile + '""'
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(20000)) { $process.Kill(); throw 'Scaffold wrapper timed out.' }
        $script:wrapperCode = $process.ExitCode
        return ($stdout.Result + $stderr.Result)
    } finally { $process.Dispose() }
}
try {
    foreach ($file in Get-ChildItem $repo -Recurse -File | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' -and $_.Extension -in @('.ps1','.bat','.md') }) {
        Assert (-not (Select-String -LiteralPath $file.FullName -Pattern '^(<<<<<<< |=======\s*$|>>>>>>> )' -Quiet)) ('No conflict markers: ' + $file.Name)
        if ($file.Extension -eq '.ps1') {
            $tokens = $null; $errors = $null
            $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            Assert ($errors.Count -eq 0) ('PowerShell syntax: ' + $file.Name)
        }
    }
    . (Join-Path $repo 'src/internal/_shared.ps1')
    $base = Join-Path $scratch 'base'
    $outside = Join-Path $scratch 'outside'
    $null = New-Item -ItemType Directory -Path $base,$outside
    Assert (Test-SafePath (Join-Path $base 'new/deep/file.txt') $base) 'Missing descendants inside base are allowed'
    Assert (-not (Test-SafePath $base $base)) 'Base itself is not an entry destination'
    Assert (-not (Test-SafePath (Join-Path $base '../outside/file.txt') $base)) 'Traversal outside base is rejected'
    Assert (-not (Test-SafePath ($base + '-sibling/file.txt') $base)) 'Sibling prefix is rejected'
    Assert ((Resolve-SafeProjectRoot $base 'valid-project') -eq (Join-Path $base 'valid-project')) 'Valid project name resolves inside base'
    foreach ($name in @('../outside','..','.', 'nested/project','nested\project','C:\outside','CON','NUL.txt','bad:name','trailing.','trailing ')) {
        Assert-Throws { Resolve-SafeProjectRoot $base $name } ('Reject project name: ' + $name)
    }
    $link = Join-Path $base 'link'
    $null = New-Item -ItemType Junction -Path $link -Target $outside
    $junctions.Add($link)
    Assert (-not (Test-SafePath (Join-Path $link 'new.txt') $base)) 'Junction ancestor is rejected'
    Assert (-not (Test-SafePath $link $base)) 'Junction destination is rejected'
    Assert-Throws { Resolve-SafeProjectRoot $base 'link' } 'Existing project junction is rejected'
    Assert (-not (Test-SafePath (Join-Path $link 'new.txt') $link)) 'Junction base is rejected'

    # Redirect library state to scratch; never read or modify the user library.
    . (Join-Path $repo 'src/store.ps1')
    $script:StoreRoot = $scratch
    $script:StoreDataDir = Join-Path $scratch 'data'
    $script:StoreTreeDir = Join-Path $script:StoreDataDir 'store_trees'
    $script:StoreJson = Join-Path $script:StoreDataDir 'store_data.json'
    $source = Join-Path $scratch 'source.txt'
    Write-Fixture $source '- hello.txt'
    $entry = Add-TreeEntry $source 'First tree' 'dash' 'manual'
    $stored = Get-TreePath $entry.id
    Assert ($stored -eq (Join-Path $script:StoreTreeDir 'first-tree.txt')) 'Saved tree resolves under data/store_trees'
    Assert (Test-Path -LiteralPath $stored) 'Saved tree exists'
    Assert ((Resolve-TreeSelection 1).FilePath -eq $stored) 'Picker uses canonical resolver'
    Assert (@(Get-OrphanFiles).Count -eq 0) 'Saved tree is not treated as orphan'
    Assert (Rename-TreeEntry $entry.id 'Renamed tree') 'Library rename succeeds'
    Assert (Test-Path -LiteralPath (Get-TreePath 'Renamed tree')) 'Renamed tree resolves'
    $index = Get-LibraryIndex
    $index.trees[0].file = 'data/store_trees/renamed-tree.txt'
    Save-LibraryIndex $index
    $index = Get-LibraryIndex
    Assert ($index.trees[0].file -ceq 'store_trees\renamed-tree.txt') 'Repo-relative legacy path migrates to data-relative form'
    Assert (Remove-TreeEntry 'Renamed tree') 'Library deletion succeeds'
    Assert (-not (Test-Path -LiteralPath (Join-Path $script:StoreTreeDir 'renamed-tree.txt'))) 'Library deletion removes correct file'
    foreach ($path in @('../outside/victim.txt','store_trees/../../victim.txt','C:\victim.txt','store_trees/sub/victim.txt','store_trees/CON.txt','store_trees/victim:stream.txt')) {
        Assert-Throws { Resolve-LibraryPath $path } ('Reject library path: ' + $path)
    }
    $victim = Join-Path $outside 'victim.txt'
    Write-Fixture $victim 'preserve me'
    Write-Fixture $script:StoreJson '{"version":1,"trees":[{"id":"evil","name":"evil","file":"../outside/victim.txt"}]}'
    Assert-Throws { Remove-TreeEntry 'evil' } 'Tampered index cannot delete outside library'
    Assert (([IO.File]::ReadAllText($victim)) -eq 'preserve me') 'Outside sentinel is unchanged'
    Write-Fixture $script:StoreJson '{"version":1,"trees":[{}]}'
    Assert-Throws { Get-LibraryIndex } 'Invalid entry schema is rejected'
    Write-Fixture $script:StoreJson '{broken'
    Assert-Throws { Get-LibraryIndex } 'Malformed index is rejected without replacing it'
    Assert (([IO.File]::ReadAllText($script:StoreJson)) -eq '{broken') 'Malformed index remains untouched'
    $libraryLink = Join-Path $script:StoreTreeDir 'linked.txt'
    # A directory junction with a .txt name exercises the same reparse check as file symlinks.
    $null = New-Item -ItemType Junction -Path $libraryLink -Target $outside
    $junctions.Add($libraryLink)
    Assert-Throws { Resolve-LibraryPath 'store_trees/linked.txt' } 'Library reparse destination is rejected'
    Assert-Throws { Get-OrphanFiles } 'Orphan discovery rejects reparse entries'
    Assert-Throws { Register-OrphanFile ([pscustomobject]@{ FilePath = $victim; Format = 'dash' }) 'external' } 'Orphan registration rejects external source'

    $live = Join-Path $scratch 'live'
    $null = New-Item -ItemType Directory -Path $live
    Write-Fixture (Join-Path $live 'keep.txt') 'keep'
    $null = New-Item -ItemType Directory -Path (Join-Path $live 'extra/node_modules'),(Join-Path $live 'extra/deep'),(Join-Path $live 'empty')
    Write-Fixture (Join-Path $live 'extra/node_modules/secret.txt') 'excluded'
    Write-Fixture (Join-Path $live 'extra/deep/secret.txt') 'depth limited'
    Write-Fixture (Join-Path $live 'extra/hidden.txt') 'hidden'
    [IO.File]::SetAttributes((Join-Path $live 'extra/hidden.txt'), [IO.FileAttributes]::Hidden)
    Write-Fixture (Join-Path $live 'extra/delete.txt') 'delete'
    $structure = Join-Path $scratch 'structure.txt'
    Write-Fixture $structure "- keep.txt`r`n- created/`r`n-- new.txt"
    $ignore = Join-Path $scratch 'ignore.txt'
    Write-Fixture $ignore "maxdepth: 2`nexclude: hidden.txt"
    $code = Invoke-Verify $structure $live $ignore
    Assert ($code -eq 1) 'Sync returns existing drift status after successful reconciliation'
    Assert (Test-Path -LiteralPath (Join-Path $live 'created/new.txt')) 'Sync creates safe missing entries'
    foreach ($relative in @('keep.txt','extra/node_modules/secret.txt','extra/deep/secret.txt','extra/hidden.txt')) {
        Assert (Test-Path -LiteralPath (Join-Path $live $relative)) ('Preserve protected descendant: ' + $relative)
    }
    Assert (-not (Test-Path -LiteralPath (Join-Path $live 'extra/delete.txt'))) 'Delete explicitly scanned extra file'
    Assert (-not (Test-Path -LiteralPath (Join-Path $live 'empty'))) 'Delete empty extra directory'
    Assert (Test-Path -LiteralPath (Join-Path $live 'extra')) 'Preserve extra directory containing protected children'
    $liveLink = Join-Path $live 'escape'
    $null = New-Item -ItemType Junction -Path $liveLink -Target $outside
    $junctions.Add($liveLink)
    Write-Fixture $structure "- should-not-be-created.txt`r`n- escape/new.txt"
    $code = Invoke-Verify $structure $live $ignore
    Assert ($code -eq 2) 'Sync rejects plan containing a junction'
    Assert (-not (Test-Path -LiteralPath (Join-Path $outside 'new.txt'))) 'No writes through junction'
    Assert (-not (Test-Path -LiteralPath (Join-Path $live 'should-not-be-created.txt'))) 'Entire sync plan is rejected before any mutation'

    foreach ($format in @('dash','template')) {
        foreach ($name in @('../outside','valid-project')) {
            & powershell.exe -NoProfile -NonInteractive -File (Join-Path $repo 'src/scaffold_validate.ps1') -StructureFile $source -Format $format -TargetBase $base -ProjectName $name | Out-Host
            if ($name -eq 'valid-project') { Assert ($LASTEXITCODE -eq 0) ('Scaffold validates safe root in ' + $format + ' mode') }
            else { Assert ($LASTEXITCODE -ne 0) ('Scaffold rejects escaping root in ' + $format + ' mode') }
        }
    }
    $copy = Join-Path $scratch 'toolkit'
    $null = New-Item -ItemType Directory -Path $copy
    Copy-Item -LiteralPath (Join-Path $repo 'bin'),(Join-Path $repo 'src') -Destination $copy -Recurse
    $wrapper = Join-Path $copy 'bin/scaffold.bat'
    $target = Join-Path $scratch 'scaffold-target'
    $null = New-Item -ItemType Directory -Path $target
    $output = Invoke-ScaffoldWrapper $wrapper $source '../escape-project' $target
    Assert ($output -match 'Security checks failed') 'Scaffold wrapper stops on invalid root'
    Assert ($script:wrapperCode -ne 0) 'Scaffold wrapper preserves validation failure exit code'
    Assert (-not (Test-Path -LiteralPath (Join-Path $scratch 'escape-project'))) 'Scaffold wrapper does not create escaped project'
    $output = Invoke-ScaffoldWrapper $wrapper $source '../escape-template' $target -Template
    Assert ($script:wrapperCode -ne 0) 'Template wrapper preserves validation failure exit code'
    Assert (-not (Test-Path -LiteralPath (Join-Path $scratch 'escape-template'))) 'Template wrapper does not create escaped project'
    $output = Invoke-ScaffoldWrapper $wrapper $source 'safe-project' $target
    if (-not (Test-Path -LiteralPath (Join-Path $target 'safe-project/hello.txt'))) { Write-Host $output }
    Assert (Test-Path -LiteralPath (Join-Path $target 'safe-project/hello.txt')) 'Scaffold creates valid project'
    Assert ($script:wrapperCode -eq 0) 'Scaffold wrapper preserves success exit code'
    # Wrapper/backend interface smoke test, including a trailing directory slash.
    $export = Join-Path $scratch 'export.txt'
    & (Join-Path $repo 'bin/export.bat') --ci ($base + '\') importable $export 1 all link | Out-Host
    Assert ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $export)) 'Export wrapper and resolved backend agree on ArgsFile interface'
    & powershell.exe -NoProfile -NonInteractive -File (Join-Path $repo 'src/version.ps1') -Ci | Out-Host
    Assert ($LASTEXITCODE -eq 0) 'Version command runs without network in CI mode'
    Write-Host ('All {0} checks passed on PowerShell {1}.' -f $script:checks,$PSVersionTable.PSVersion)
} finally {
    # Remove only fixture junctions, without traversing their targets.
    foreach ($junction in $junctions) {
        if (Test-Path -LiteralPath $junction) { [IO.Directory]::Delete($junction, $false) }
    }
    $resolvedScratch = [IO.Path]::GetFullPath($scratch)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolvedScratch.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolvedScratch -Leaf) -match '^ptu-regression-[a-f0-9]{32}$') {
        Remove-Item -LiteralPath $resolvedScratch -Recurse -Force
    }
}
