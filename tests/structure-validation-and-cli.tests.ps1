$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('ptu-cli-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $scratch
$script:checks=0
$script:lastOutput=''
function Assert($Condition,[string]$Message) {
    if(-not $Condition){throw ('FAIL: '+$Message+"`n"+$script:lastOutput)}
    $script:checks++;Write-Host ('PASS: '+$Message)
}
function Write-Fixture([string]$Path,[string]$Text){[IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))}
function Reject([scriptblock]$Action,[string]$Message){$failed=$false;try{& $Action | Out-Null}catch{$failed=$true};Assert $failed $Message}
function Run-CLI([string[]]$Arguments,[string]$Wrapper='tree.bat',[hashtable]$Environment=@{}){
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=$env:ComSpec
    $quoted=@($Arguments | ForEach-Object { '"'+$_+'"' }) -join ' '
    $start.Arguments='/d /c ""'+(Join-Path $copy $Wrapper)+'" '+$quoted+'"'
    $start.WorkingDirectory=$scratch
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $start.RedirectStandardInput=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $start.EnvironmentVariables.Remove('TREE_CI');$start.EnvironmentVariables.Remove('PTU_LEGACY')
    foreach($key in $Environment.Keys){$start.EnvironmentVariables[$key]=[string]$Environment[$key]}
    $process=New-Object Diagnostics.Process;$process.StartInfo=$start
    try{
        $null=$process.Start();$process.StandardInput.Close()
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit(15000)){& taskkill.exe /PID $process.Id /T /F | Out-Null;throw ('CLI prompted or timed out: '+($Arguments -join ' '))}
        $script:lastOutput=$stdout.Result+$stderr.Result
        return $process.ExitCode
    }finally{$process.Dispose()}
}
try{
    . (Join-Path $repo 'src/internal/_shared.ps1')
    $file=Join-Path $scratch 'structure[1].txt'
    $samples=@{
        dash="- src/`n-- index.ts";tab="src/`n`tindex.ts";space="src/`n  index.ts"
        treesym=([string][char]0x251c+[char]0x2500+[char]0x2500+' src/'+"`n"+[char]0x2502+'   '+[char]0x2514+[char]0x2500+[char]0x2500+' index.ts')
        yaml="- name: src`n  type: directory";json='{"name":"src","type":"directory"}'
    }
    foreach($format in $samples.Keys){
        Write-Fixture $file $samples[$format]
        Assert ((Get-StructureFormat $file) -eq $format) ('Detect '+$format+' using a literal bracketed filename')
        Assert (Confirm-StructureFormat $file $format) ('Validate '+$format+' canonical structure')
    }
    Write-Fixture $file "root/`nfile.txt"
    Assert ((Get-StructureFormat $file) -eq 'unknown') 'Flat indentation layout remains explicitly ambiguous'
    Write-Fixture $file "root/`n`tfirst.txt`n  second.txt"
    Assert ((Get-StructureFormat $file) -eq 'unknown') 'Mixed indentation is not guessed'
    Write-Fixture $file '# comment'
    Assert ((Get-StructureFormat $file) -eq 'empty') 'Comment-only input is empty'
    Reject {Get-StructureFormat (Join-Path $scratch 'missing.txt')} 'Unreadable input is an error, not empty success'
    foreach($bad in @("-- orphan.txt","- a/`n--- jump.txt","- file.txt`n-- child.txt","- a/`n-- old/`n- b/`n--- stale.txt","- Same.txt`n- same.txt","- a.txt`n- a.txt/","- a.txt`n- a.txt/child.txt","- ok/`nbad")){
        Write-Fixture $file $bad
        Reject {Read-StructureFile $file dash} ('Reject invalid dash hierarchy: '+($bad -replace "`n",' | '))
        Assert (-not (Confirm-StructureFormat $file dash)) 'Validator and reader agree on invalid hierarchy'
    }
    Write-Fixture $file "root/`n   wrong.txt"
    Reject {Read-StructureFile $file space 2} 'Reject partial space indentation units'
    $json=Join-Path $scratch 'nodes.json'
    foreach($bad in @('{}','123','null','[]','{"name":12}','{"name":"a","type":"weird"}','{"name":"a","children":{}}','{"name":"a","type":"file","children":[]}','[{"name":"a"},{"name":"a"}]','{"name":"a","unused":true}')){
        Write-Fixture $json $bad
        Reject {Read-StructureFile $json json} ('Reject invalid node schema: '+$bad)
    }
    foreach($name in @('../file','a/../b','a/./b','a/CON.txt','a/NUL .txt','a/LPT1',('a/COM'+[char]0x00b9+'.txt'),'C:relative','a:stream','a./b','a /b','a/b.','a/b ','/root','\\server\share','a//b',('a/'+('x'*256)))){
        Assert (Test-DangerousName $name) ('Reject invalid Windows component: '+$name)
    }
    foreach($name in @('file..txt','a..b/okay.txt','CONNECTION.txt','src/[literal].txt',"O'Brien/file.txt")){
        Assert (-not (Test-DangerousName $name)) ('Allow valid Windows path: '+$name)
    }
    Write-Fixture $file "- src/`n-- file..txt"
    Assert (@(Read-StructureFile $file dash).Count -eq 2) 'Harmless double dots survive parsing'

    $copy=Join-Path $scratch "toolkit O'Brien [tools]"
    $null=New-Item -ItemType Directory -Path $copy
    Copy-Item -LiteralPath (Join-Path $repo 'src'),(Join-Path $repo 'bin'),(Join-Path $repo 'tree.bat') -Destination $copy -Recurse
    $live=Join-Path $scratch 'live';$null=New-Item -ItemType Directory -Path $live
    Write-Fixture (Join-Path $live 'keep.txt') 'keep'
    Write-Fixture $file '- keep.txt'
    foreach($command in @('import','export','scaffold','merge','verify','watch','security','gittree','auth','library','detection')){
        Assert ((Run-CLI @($command,'--ci')) -eq 2) ($command+' CI rejects missing arguments without prompting')
    }
    Assert ((Run-CLI @('--ci')) -eq 2) 'Root CI requires a subcommand'
    Assert ((Run-CLI @('version','--ci')) -eq 0) 'Version CI exits without prompts or a network check'
    Assert ((Run-CLI @('version') 'bin/version.bat' @{TREE_CI='1'}) -eq 2) 'Unknown version positional argument returns usage error'
    Assert ((Run-CLI @() 'bin/version.bat' @{TREE_CI='1'}) -eq 0) 'Direct version wrapper respects TREE_CI'
    Assert ((Run-CLI @() 'bin/import.bat' @{TREE_CI='1'}) -eq 2) 'Direct import wrapper respects TREE_CI'
    Assert ((Run-CLI @('verify','--ci',$live,$file,'dash')) -eq 0) 'Documented verify positional order works'
    Assert ((Run-CLI @('--ci','verify','--structure',$file,'--live',$live,'--format','dash')) -eq 0) 'Leading CI and named verify options work'
    Assert ((Run-CLI @('--live',$live,'--structure',$file,'--format','dash','--ci') 'bin/verify.bat') -eq 0) 'Direct verify wrapper normalizes public flags'
    Assert ((Run-CLI @('watch','--ci','--path',$file)) -eq 2) 'CI watch rejects a file as its directory'
    Assert ((Run-CLI @('verify','--structure',$file,'--live',$live,'--format','dash') 'tree.bat' @{TREE_CI='1'}) -eq 0) 'Environment CI matches flag CI'
    Write-Fixture $file '- missing.txt'
    Assert ((Run-CLI @('verify','--ci',$live,$file,'dash')) -eq 1) 'Verify drift status survives the router'
    Write-Fixture $file "-- invalid.txt"
    Assert ((Run-CLI @('verify','--ci',$live,$file,'dash')) -eq 2) 'Invalid verification input returns error status'
    Write-Fixture $file '- keep.txt'
    Assert ((Run-CLI @('import','--ci','--structure',$file,'--format','dash','--output','converted.txt')) -eq 0) 'CI import accepts named options'
    Assert (Test-Path -LiteralPath (Join-Path $scratch 'converted.txt')) 'Relative output resolves against caller directory'
    Assert ((Run-CLI @('export',$live,'importable','exported.txt','--ci')) -eq 0) 'Trailing CI and positional export work'
    Assert (Confirm-StructureFormat (Join-Path $scratch 'exported.txt') dash) 'CLI export produces a valid structure'
    Assert ((Run-CLI @('scaffold','--ci','--structure',$file,'--format','dash','--target',$scratch,'--project','cli-project')) -eq 0) 'CI scaffold runs without menu input'
    Assert (Test-Path -LiteralPath (Join-Path $scratch 'cli-project/keep.txt')) 'CI scaffold writes expected file'
    Assert ((Run-CLI @('scaffold','--ci','--template','monorepo-pnpm','--target',$scratch,'--project','template-project','--dry-run')) -eq 0) 'CI template dry run completes'
    Assert (-not (Test-Path -LiteralPath (Join-Path $scratch 'template-project'))) 'CLI dry run does not write'
    Assert ((Run-CLI @('scaffold','--ci','--structure',$file,'--target',$scratch,'--project','x','--overwrite','ask')) -eq 2) 'CI rejects interactive overwrite mode'
    Assert ((Run-CLI @('merge','--ci','--file-a',$file,'--format-a','dash','--file-b',$file,'--format-b','dash','--output','merged.txt')) -eq 0) 'CI merge executes with explicit inputs'
    Assert ((Run-CLI @('detection','--ci','ANALYSE',$file,'dash')) -eq 0) 'CI analysis never enters the interactive detector'
    Assert ((Run-CLI @('security','--ci','VALIDATE_ALL',$file,'dash',$live)) -eq 0) 'CI security validates all entries'
    Assert ((Run-CLI @('security','--ci','--action','VALIDATE_PATH','--candidate',$file,'--base',$live)) -eq 1) 'Security rejection status survives named action routing'
    Assert ((Run-CLI @('library','--ci','save',$file,'dash','manual','first')) -eq 0) 'CI library save accepts an explicit name'
    Assert ((Run-CLI @('library','--ci','list')) -eq 0) 'CI library list does not run interactive cleanup'
    Assert ((Run-CLI @('library','--ci','rename','first','renamed')) -eq 0) 'CI library rename completes'
    Assert ((Run-CLI @('library','--ci','open','renamed')) -eq 0 -and $script:lastOutput -match 'store_trees') 'CI library open resolves a saved path'
    Assert ((Run-CLI @('library','--ci','delete','missing')) -eq 1) 'Library failure is not reported as success'
    Assert ((Run-CLI @('library','--ci','delete','renamed')) -eq 0) 'CI library delete completes'
    Assert ((Run-CLI @('library','--ci','purge')) -eq 2) 'CI purge requires explicit confirmation flag'
    Assert ((Run-CLI @('library','--ci','purge','--yes')) -eq 0) 'CI purge with explicit flag completes on fixtures'
    Assert ((Run-CLI @('export','--ci','--root',$live,'--format','importable','--output','bang!file.txt')) -eq 0) 'Delayed expansion does not corrupt exclamation marks'
    Assert (Test-Path -LiteralPath (Join-Path $scratch 'bang!file.txt')) 'Exclamation filename is preserved'
    foreach($arguments in @(@('version','--ci','--bogus'),@('version','--ci','--check','--check'),@('export','--ci','--root'),@('verify','--ci',$live,$file,'dash','extra'))){
        Assert ((Run-CLI $arguments) -eq 2) ('Invalid CLI arguments fail: '+($arguments -join ' '))
    }
    # Replace external-service backends only in the disposable copy. Verify option
    # forwarding and status propagation without contacting APIs or credentials.
    $versionPath=Join-Path $copy 'src/version.ps1'
    Write-Fixture $versionPath 'param([switch]$CheckUpdate,[switch]$Ci); if (-not $CheckUpdate -or -not $Ci) { exit 9 }; exit ([int]$env:FIXTURE_EXIT)'
    foreach($code in @(0,1,2)){
        Assert ((Run-CLI @('version','--check','--ci') 'tree.bat' @{FIXTURE_EXIT=$code}) -eq $code) ('Version status '+$code+' survives the router')
        Assert ((Run-CLI @('--ci','--check') 'bin/version.bat' @{FIXTURE_EXIT=$code}) -eq $code) ('Version flag order and direct wrapper preserve status '+$code)
    }
    Assert ((Run-CLI @() 'bin/version.bat') -eq 9) 'Legacy version wrapper preserves backend status across pause'
    Write-Fixture (Join-Path $copy 'src/git_tree.ps1') 'param($Provider,$RepoUrl,$Branch,$OutputFile,$OutputFormat,$SubFolder,[int]$MaxDepth,$ExcludeList,$GitLabBaseUrl,[switch]$Ci); if ($GitLabBaseUrl -ne "https://fixture.invalid" -or $SubFolder -ne "src" -or $MaxDepth -ne 3 -or -not $Ci) { exit 9 }; exit 0'
    Assert ((Run-CLI @('gittree','--ci','gitlab','https://fixture.invalid/group/repo','feature/branch','remote.txt','yaml','src','3','ignore','https://fixture.invalid')) -eq 0) 'Router forwards all nine remote arguments beyond the old limit'
    Write-Fixture (Join-Path $copy 'src/auth.ps1') 'param($Action,$Target,$Username,$Secret,[switch]$Ci); if ($Action -ne "clear" -or -not $Ci) { exit 9 }; exit 1'
    Assert ((Run-CLI @('auth','clear','git:https://fixture.invalid','--ci')) -eq 1) 'Auth backend failure survives routing without credential access'
    Write-Host ('All {0} checks passed on PowerShell {1}.' -f $script:checks,$PSVersionTable.PSVersion)
}finally{
    $resolved=[IO.Path]::GetFullPath($scratch);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if($resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -match '^ptu-cli-[a-f0-9]{32}$'){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
