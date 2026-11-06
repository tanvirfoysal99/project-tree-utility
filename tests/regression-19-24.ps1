$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('ptu-reliability-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $scratch
$script:checks=0;$script:lastOutput='';$links=New-Object 'System.Collections.Generic.List[string]'
$vaultTarget='git:https://ptu-fixture-'+[guid]::NewGuid().ToString('N')+'.invalid'
$vaultCreated=$false
function Assert($Condition,[string]$Message){if(-not $Condition){throw ('FAIL: '+$Message+"`n"+$script:lastOutput)};$script:checks++;Write-Host ('PASS: '+$Message)}
function Reject([scriptblock]$Action,[string]$Message){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Assert $failed $Message}
function Write-Fixture([string]$Path,[string]$Text){[IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))}
function Run-Backend([string]$Name,[hashtable]$Parameters,[string]$Root=$repo){
    $arguments=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $Root ('src/'+$Name+'.ps1')))
    foreach($key in $Parameters.Keys){if($Parameters[$key] -is [bool]){if($Parameters[$key]){$arguments+='-'+$key}}else{$arguments+='-'+$key;$arguments+=[string]$Parameters[$key]}}
    $script:lastOutput=(& powershell.exe @arguments 2>&1|Out-String);return $LASTEXITCODE
}
function Snapshot-Signature($Snapshot){return (@($Snapshot.MissingFiles)+@($Snapshot.MissingFolders)+@($Snapshot.ExtraFiles)+@($Snapshot.ExtraFolders)|Sort-Object)-join "`n"}
try{
    . (Join-Path $repo 'src/internal/_shared.ps1')
    $live=Join-Path $scratch 'live';$null=New-Item -ItemType Directory -Path (Join-Path $live 'deep/inner'),(Join-Path $live 'excluded')
    Write-Fixture (Join-Path $live 'top.txt') 'top';Write-Fixture (Join-Path $live '.hidden') 'hidden'
    [IO.File]::SetAttributes((Join-Path $live '.hidden'),[IO.FileAttributes]::Hidden)
    Write-Fixture (Join-Path $live 'deep/inner/actual.txt') 'deep';Write-Fixture (Join-Path $live 'excluded/actual.txt') 'excluded'
    $source=Join-Path $scratch 'source.txt'
    Write-Fixture $source "- top.txt`n- .hidden`n- deep/`n-- inner/`n--- missing.txt`n- excluded/`n-- absent.txt"
    $entries=@(Read-StructureFile $source dash)
    $scan=Get-TreeScan $live 1 @('excluded')
    Assert ($scan.Complete -and @($scan.Items|Where-Object Name -eq '.hidden').Count -eq 1) 'Scan includes hidden entries and records completion'
    $comparison=Get-TreeComparison $live $entries @('excluded') 1
    Assert (-not (Snapshot-Signature $comparison)) 'Expected and actual entries use the same depth and exclusion scope'
    Assert ($comparison.OutOfScope.Count -eq 4) 'Excluded and depth-limited expected entries are reported out of scope'
    $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'src/watch.ps1'),[ref]$t,[ref]$e)
    $definition=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-StructureSnapshot'},$true)
    . ([scriptblock]::Create($definition.Extent.Text))
    Assert ((Snapshot-Signature (Get-StructureSnapshot $live $entries @('excluded') 1)) -eq (Snapshot-Signature $comparison)) 'Watch and verify use identical comparison scope'
    $denied=Join-Path $live 'deep'
    & {
        function Get-ChildItem {param($LiteralPath,[switch]$Force,$ErrorAction);if($LiteralPath -eq $denied){throw [UnauthorizedAccessException]'fixture access denied'};Microsoft.PowerShell.Management\Get-ChildItem -LiteralPath $LiteralPath -Force -ErrorAction Stop}
        $failedScan=Get-TreeScan $live 0 @('excluded')
        Assert (-not $failedScan.Complete -and $failedScan.Errors.Count -eq 1) 'Enumeration failure produces an incomplete scan with path context'
        Reject {Assert-CompleteScan $failedScan} 'Incomplete scan cannot be treated as successful'
        Reject {Get-TreeComparison $live $entries @('excluded') 0} 'Comparison refuses incomplete enumeration'
    }
    $rootNamedBuild=Join-Path $scratch 'build';$null=New-Item -ItemType Directory -Path $rootNamedBuild;Write-Fixture (Join-Path $rootNamedBuild 'keep.txt') 'keep'
    Assert ((Get-TreeScan $rootNamedBuild 0 @('build')).Items.Count -eq 1) 'Exclusions apply to relative entries rather than root path segments'
    Reject {Get-TreeConfig -RootPath $live -IgnoreFile 'missing-ignore.txt'} 'Missing explicit scan policy fails instead of silently changing scope'
    $policy=Join-Path $scratch 'policy.txt';Write-Fixture $policy 'exclude: top.txt'
    & {
        function Get-Content {param($LiteralPath,$Encoding,$ErrorAction);throw [UnauthorizedAccessException]'fixture policy denied'}
        Reject {Get-TreeConfig -RootPath $live -IgnoreFile $policy} 'Unreadable scan policy fails closed'
    }
    $outside=Join-Path $scratch 'outside';$null=New-Item -ItemType Directory -Path $outside
    $link=Join-Path $live 'link';$null=New-Item -ItemType Junction -Path $link -Target $outside;$links.Add($link)
    $output=Join-Path $scratch 'export.txt';Write-Fixture $output 'preserve output'
    $code=Run-Backend export @{RootPath=$live;OutputFile=$output;OutputFormat='importable';MaxDepth=0;Ci=$true}
    Assert ($code -ne 0 -and [IO.File]::ReadAllText($output) -eq 'preserve output') 'Incomplete export does not overwrite an existing output file'
    Write-Fixture $source '- must-not-be-created.txt'
    $code=Run-Backend verify @{StructureFile=$source;LivePath=$live;Format='dash';Sync=$true;DeleteExtras=$true;Ci=$true}
    Assert ($code -eq 2 -and -not (Test-Path -LiteralPath (Join-Path $live 'must-not-be-created.txt'))) 'Sync performs no mutations after an incomplete scan'
    [IO.Directory]::Delete($link,$false);$links.Remove($link)|Out-Null
    $clean=Join-Path $scratch 'clean';$null=New-Item -ItemType Directory -Path $clean
    Write-Fixture $source '- expected.txt @content:created'
    $code=Run-Backend verify @{StructureFile=$source;LivePath=$clean;Format='dash';Sync=$true;Ci=$true}
    Assert ($code -eq 0 -and $script:lastOutput -match 'AFTER SYNC \(fresh scan\)') 'Successful sync rescans and returns the final clean status'
    Assert ([IO.File]::ReadAllText((Join-Path $clean 'expected.txt')) -eq 'created') 'Sync creates missing destination content'
    $moves=Join-Path $scratch 'moves';$null=New-Item -ItemType Directory -Path $moves
    $old=Join-Path $moves 'very-long-component-name-two.ts';Write-Fixture $old 'precious existing content'
    Write-Fixture $source '- very-long-component-name-one.ts @content:new destination'
    $code=Run-Backend verify @{StructureFile=$source;LivePath=$moves;Format='dash';Sync=$true;DeleteExtras=$true;Ci=$true}
    Assert ($code -eq 1 -and $script:lastOutput -match 'Possible move source preserved') 'Heuristic move source is preserved and remaining drift is reported'
    Assert ([IO.File]::ReadAllText($old) -eq 'precious existing content') 'Move suggestion does not destroy existing content'
    Assert ([IO.File]::ReadAllText((Join-Path $moves 'very-long-component-name-one.ts')) -eq 'new destination') 'Move suggestion does not suppress creation of the expected destination'

    $a=Join-Path $scratch 'a.json';$b=Join-Path $scratch 'b.json';$merged=Join-Path $scratch 'merged.txt'
    Write-Fixture $a '[{"path":"src/item.txt","type":"file","content":"first\n  indented\n\nlast","template":"react-vite"}]'
    Write-Fixture $b '[{"name":"src","type":"directory","children":[{"name":"other.txt","type":"file","content":"other"}]}]'
    $code=Run-Backend merge_tree @{FileA=$a;FormatA='json';FileB=$b;FormatB='json';Strategy='union';OutputFile=$merged}
    Assert ($code -eq 0) 'Merge accepts path-style and hierarchical entries together'
    $read=@(Read-StructureFile $merged dash);$item=$read|Where-Object Path -eq 'src\item.txt'
    Assert ((Get-StructureEntryContent $item 'project') -ceq "first`n  indented`n`nlast") 'Merged dash round trip preserves multiline content'
    Assert ($item.Template -eq 'react-vite') 'Merge preserves template metadata'
    Assert (@($read|Where-Object Path -eq 'src\other.txt').Count -eq 1) 'Union keeps unique entries from both inputs'
    Write-Fixture $b '[{"path":"src/item.txt","type":"file","content":"second","template":"hono-worker"}]'
    foreach($strategy in @('a_over_b','b_over_a')){
        $code=Run-Backend merge_tree @{FileA=$a;FormatA='json';FileB=$b;FormatB='json';Strategy=$strategy;OutputFile=$merged}
        $item=@(Read-StructureFile $merged dash)|Where-Object Path -eq 'src\item.txt'
        $wanted=if($strategy -eq 'a_over_b'){"first`n  indented`n`nlast"}else{'second'}
        Assert ($code -eq 0 -and (Get-StructureEntryContent $item 'p') -ceq $wanted) ($strategy+' applies content precedence')
    }
    Write-Fixture $merged 'unchanged'
    $code=Run-Backend merge_tree @{FileA=$a;FormatA='json';FileB=$b;FormatB='json';Strategy='union';OutputFile=$merged}
    Assert ($code -eq 1 -and [IO.File]::ReadAllText($merged) -eq 'unchanged') 'Union metadata conflicts fail without replacing output'
    Write-Fixture $a '{"name":"x","type":"file","content":"file wins"}'
    Write-Fixture $b '{"name":"x","type":"directory","children":[{"name":"child.txt","type":"file"}]}'
    foreach($strategy in @('a_over_b','b_over_a')){
        $code=Run-Backend merge_tree @{FileA=$a;FormatA='json';FileB=$b;FormatB='json';Strategy=$strategy;OutputFile=$merged}
        $read=@(Read-StructureFile $merged dash)
        Assert ($code -eq 0 -and $read.Count -eq $(if($strategy -eq 'a_over_b'){1}else{2})) ($strategy+' resolves file/directory conflicts without invalid children')
    }
    $code=Run-Backend merge_tree @{FileA=$a;FormatA='json';FileB=$b;FormatB='json';Strategy='union';OutputFile=$merged}
    Assert ($code -eq 1) 'Union rejects incompatible file/directory nodes'

    . (Join-Path $repo 'src/store.ps1')
    $script:StoreRoot=$scratch;$script:StoreDataDir=Join-Path $scratch 'data';$script:StoreTreeDir=Join-Path $script:StoreDataDir 'store_trees';$script:StoreJson=Join-Path $script:StoreDataDir 'store_data.json'
    Write-Fixture $source '- saved.txt'
    $entry=Add-TreeEntry $source 'original' dash manual
    Assert (Test-Path -LiteralPath ($script:StoreJson+'.bak')) 'Index replacement creates a previous-version backup'
    $before=[IO.File]::ReadAllText($script:StoreJson)
    $script:originalWriter=(Get-Command Write-LibraryIndexCore).ScriptBlock
    function Write-LibraryIndexCore {param($Index);if($script:failWrite){throw 'fixture index write failure'};& $script:originalWriter $Index}
    $script:failWrite=$true
    Reject {Add-TreeEntry $source 'failed-add' dash manual} 'Failed index commit rolls back an added file'
    Assert (-not (Test-Path -LiteralPath (Join-Path $script:StoreTreeDir 'failed-add.txt'))) 'Failed add leaves no unindexed file'
    Reject {Rename-TreeEntry 'original' 'failed-rename'} 'Failed index commit rolls back a rename'
    Assert (Test-Path -LiteralPath (Join-Path $script:StoreTreeDir 'original.txt')) 'Rename rollback restores original file'
    Reject {Remove-TreeEntry 'original'} 'Failed index commit restores a deleted file'
    Assert ([IO.File]::ReadAllText($script:StoreJson) -ceq $before) 'Failed mutations leave index bytes unchanged'
    Assert (-not (Test-Path -LiteralPath (Get-LibraryJournalPath))) 'Completed rollback removes recovery journal'
    $script:failWrite=$false
    $oldPath=Join-Path $script:StoreTreeDir 'original.txt';$newPath=Join-Path $script:StoreTreeDir 'interrupted.txt'
    $index=Get-LibraryIndex;$index.trees[0].file='store_trees\interrupted.txt';$index.trees[0].id='interrupted';$index.trees[0].name='interrupted'
    $journal=[ordered]@{Operation='rename';Old='store_trees\original.txt';New='store_trees\interrupted.txt';Before=$before;After=($index|ConvertTo-Json -Depth 10)}
    Write-AtomicLibraryFile (Get-LibraryJournalPath) ($journal|ConvertTo-Json -Depth 12)
    [IO.File]::Move($oldPath,$newPath)
    $recovered=Get-LibraryIndex
    Assert ($recovered.trees[0].id -eq 'original' -and [IO.File]::Exists($oldPath) -and -not [IO.File]::Exists($newPath)) 'Next access recovers a process interruption before index commit'
    $indexLock=[IO.File]::Open($script:StoreJson,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{
        Reject {Add-TreeEntry $source 'locked-index-add' dash manual} 'Actual index replacement failure rolls back its staged file'
        Assert (-not [IO.File]::Exists((Join-Path $script:StoreTreeDir 'locked-index-add.txt'))) 'Atomic replacement failure leaves no extra tree'
        Assert ([IO.File]::ReadAllText($script:StoreJson) -ceq $before) 'Atomic replacement failure preserves previous index bytes'
    }finally{$indexLock.Dispose()}
    $emptyIndex=[pscustomobject]@{version=1;trees=@()}
    $stashRelative='store_trees\.pending-fixture.txt';$stash=Resolve-LibraryPath $stashRelative
    $journal=[ordered]@{Operation='delete';Old='store_trees\original.txt';New=$stashRelative;Before=$before;After=($emptyIndex|ConvertTo-Json -Depth 10)}
    Write-AtomicLibraryFile (Get-LibraryJournalPath) ($journal|ConvertTo-Json -Depth 12)
    [IO.File]::Move($oldPath,$stash);Write-LibraryIndexCore $emptyIndex
    $recovered=Get-LibraryIndex
    Assert ($recovered.trees.Count -eq 0 -and -not [IO.File]::Exists($stash)) 'Recovery finishes cleanup after an already committed delete'
    Write-Fixture $script:StoreJson '{broken'
    Reject {Get-LibraryIndex} 'Malformed index is preserved instead of being reset'
    Assert ([IO.File]::ReadAllText($script:StoreJson) -ceq '{broken') 'Corruption recovery does not overwrite the malformed file'

    # Actual vault API exercise uses a unique fake host and dummy token only.
    . (Join-Path $repo 'src/internal/_credentials.ps1')
    $dummy='dummy-fixture-'+[guid]::NewGuid().ToString('N')
    $vaultCreated=$true;Invoke-CredentialVault write $vaultTarget 'fixture-user' $dummy
    $record=Invoke-CredentialVault read $vaultTarget
    Assert ($record.Username -eq 'fixture-user' -and $record.Secret -ceq $dummy) 'Windows vault write/read round trip preserves dummy credential'
    Assert ((Get-TreeStoredCredential $vaultTarget) -ceq $dummy) 'Remote credential retrieval reads the same vault target'
    Invoke-CredentialVault delete $vaultTarget;$vaultCreated=$false
    Assert ($null -eq (Invoke-CredentialVault read $vaultTarget)) 'Windows vault clear removes the dummy credential'
    Assert ((ConvertTo-CredentialTarget 'https://EXAMPLE.invalid:8443/group/repo/') -ceq 'git:https://example.invalid:8443/group/repo') 'Credential keys preserve repository paths and ports consistently'
    & {function Invoke-CredentialVault {param($Action,$Target);return $null};function Get-Command {return $null};Assert ((Get-TreeStoredCredential 'https://public.invalid/repo') -eq '') 'Missing credentials permit anonymous requests without prompting'}
    $helper=Join-Path $scratch 'credential-helper.exe'
    Add-Type -OutputAssembly $helper -OutputType ConsoleApplication -TypeDefinition @'
using System;
using System.IO;
public static class PtuFixtureCredentialHelper {
    public static void Main(string[] args) {
        string payload=Console.In.ReadToEnd();
        File.WriteAllText(Environment.GetEnvironmentVariable("PTU_HELPER_ARGS"),Environment.CommandLine);
        File.WriteAllText(Environment.GetEnvironmentVariable("PTU_HELPER_INPUT"),payload);
        Console.WriteLine("password="+Environment.GetEnvironmentVariable("PTU_EXPECTED_SECRET"));
    }
}
'@ | Out-Null
    $env:PTU_EXPECTED_SECRET=$dummy;$env:PTU_HELPER_ARGS=Join-Path $scratch 'helper-args.txt';$env:PTU_HELPER_INPUT=Join-Path $scratch 'helper-input.txt'
    & {
        function Invoke-CredentialVault {param($Action,$Target);return $null}
        function Get-Command {param($Name,$CommandType,$ErrorAction);if($Name -eq 'git-credential-manager'){return [pscustomobject]@{Source=$helper}}}
        Assert ((Get-TreeStoredCredential 'https://fixture.invalid:8443/group/repo') -ceq $dummy) 'Existing credential helpers remain readable through captured standard output'
    }
    Assert ([IO.File]::ReadAllText($env:PTU_HELPER_ARGS).IndexOf($dummy) -lt 0) 'Credential helper process arguments contain no token'
    Assert ([IO.File]::ReadAllText($env:PTU_HELPER_INPUT) -match 'host=fixture.invalid:8443' -and [IO.File]::ReadAllText($env:PTU_HELPER_INPUT) -match 'path=group/repo') 'Credential helper receives consistent host/path data through standard input'
    $copy=Join-Path $scratch 'toolkit';$null=New-Item -ItemType Directory -Path $copy
    Copy-Item -LiteralPath (Join-Path $repo 'src'),(Join-Path $repo 'bin') -Destination $copy -Recurse
    # The fixture overrides vault IO only, leaving real auth channel parsing intact.
    $mockCredentials=@'
function ConvertTo-CredentialTarget {param($Target);return $Target}
function Invoke-CredentialVault {param($Action,$Target,$Username,$Secret);if($Action -eq 'write' -and $Secret -cne $env:PTU_EXPECTED_SECRET){throw 'Wrong secret channel'};if($Action -eq 'write'){[IO.File]::WriteAllText($env:PTU_AUTH_ARGS,([Environment]::CommandLine))}}
function Get-TreeStoredCredential {param($Target);return ''}
'@
    Write-Fixture (Join-Path $copy 'src/internal/_credentials.ps1') $mockCredentials
    $env:PTU_EXPECTED_SECRET=$dummy;$env:PTU_AUTH_ARGS=Join-Path $scratch 'auth-command-line.txt'
    $code=Run-Backend auth @{Action='store';Target='https://fixture.invalid';SecretEnv='PTU_EXPECTED_SECRET';Ci=$true} $copy
    Assert ($code -eq 0 -and [IO.File]::ReadAllText($env:PTU_AUTH_ARGS).IndexOf($dummy) -lt 0 -and $script:lastOutput.IndexOf($dummy) -lt 0) 'Environment secret is absent from process arguments and output'
    $script:lastOutput=($dummy | & powershell.exe -NoProfile -NonInteractive -File (Join-Path $copy 'src/auth.ps1') -Action store -Target 'https://fixture.invalid' -SecretStdin -Ci 2>&1|Out-String)
    Assert ($LASTEXITCODE -eq 0 -and [IO.File]::ReadAllText($env:PTU_AUTH_ARGS).IndexOf($dummy) -lt 0) 'Standard-input secret is absent from process arguments'
    $script:lastOutput=(& powershell.exe -NoProfile -NonInteractive -File (Join-Path $copy 'src/cli.ps1') auth store https://fixture.invalid oauth2 dummy-literal --ci 2>&1|Out-String)
    Assert ($LASTEXITCODE -eq 2 -and $script:lastOutput -notmatch 'dummy-literal') 'CLI rejects literal secret arguments without echoing them'
    $harness=Join-Path $scratch 'public.ps1'
    Write-Fixture $harness @'
function Invoke-WebRequest { [pscustomobject]@{Content='{"tree":[{"path":"public.txt","type":"blob"}],"truncated":false}';Headers=@{}} }
& (Join-Path $env:PTU_COPY 'src/git_tree.ps1') -Provider github -RepoUrl 'https://github.com/fixture/public' -Branch main -OutputFile $env:PTU_PUBLIC_OUTPUT -OutputFormat importable -Ci
exit $LASTEXITCODE
'@
    $env:PTU_COPY=$copy;$env:PTU_PUBLIC_OUTPUT=Join-Path $scratch 'public.txt'
    $script:lastOutput=(& powershell.exe -NoProfile -NonInteractive -File $harness 2>&1|Out-String)
    Assert ($LASTEXITCODE -eq 0 -and (Confirm-StructureFormat $env:PTU_PUBLIC_OUTPUT dash)) 'CI public-repository export succeeds anonymously with a mocked API'
    # Concurrent writers use a separate copied library and the actual file lock.
    $worker=Join-Path $scratch 'worker.ps1'
    Write-Fixture $worker @'
param($Root,$Source,$Name)
$ErrorActionPreference='Stop'
. (Join-Path $Root 'src/store.ps1')
Add-TreeEntry $Source $Name dash manual | Out-Null
'@
    $workers=@()
    for($i=0;$i -lt 4;$i++){
        $start=New-Object Diagnostics.ProcessStartInfo;$start.FileName='powershell.exe';$start.Arguments='-NoProfile -NonInteractive -File "'+$worker+'" "'+$copy+'" "'+$source+'" same-name';$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
        $p=New-Object Diagnostics.Process;$p.StartInfo=$start;$null=$p.Start();$workers+=@{Process=$p;Out=$p.StandardOutput.ReadToEndAsync();Error=$p.StandardError.ReadToEndAsync()}
    }
    foreach($workerProcess in $workers){$p=$workerProcess.Process;try{if(-not $p.WaitForExit(15000)){$p.Kill();throw 'Concurrent library worker timed out.'};$script:lastOutput=$workerProcess.Out.Result+$workerProcess.Error.Result;Assert ($p.ExitCode -eq 0) 'Concurrent library writer completed'}finally{$p.Dispose()}}
    $parallelIndex=[IO.File]::ReadAllText((Join-Path $copy 'data/store_data.json'))|ConvertFrom-Json
    Assert ($parallelIndex.trees.Count -eq 4 -and @($parallelIndex.trees.id|Sort-Object -Unique).Count -eq 4) 'Concurrent updates preserve every entry with unique filenames'
    Write-Host ('All {0} checks passed on PowerShell {1}.' -f $script:checks,$PSVersionTable.PSVersion)
}finally{
    if($vaultCreated){Invoke-CredentialVault delete $vaultTarget}
    foreach($link in $links){if(Test-Path -LiteralPath $link){[IO.Directory]::Delete($link,$false)}}
    foreach($name in @('PTU_EXPECTED_SECRET','PTU_AUTH_ARGS','PTU_COPY','PTU_PUBLIC_OUTPUT','PTU_HELPER_ARGS','PTU_HELPER_INPUT')){[Environment]::SetEnvironmentVariable($name,$null,'Process')}
    $resolved=[IO.Path]::GetFullPath($scratch);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if($resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -match '^ptu-reliability-[a-f0-9]{32}$'){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
