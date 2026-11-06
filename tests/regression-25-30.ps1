$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('ptu-final-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $scratch
$script:checks=0;$script:lastOutput=''
function Assert($Condition,[string]$Message){if(-not $Condition){throw ('FAIL: '+$Message+"`n"+$script:lastOutput)};$script:checks++;Write-Host ('PASS: '+$Message)}
function Reject([scriptblock]$Action,[string]$Message){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Assert $failed $Message}
function Write-Fixture([string]$Path,[string]$Text){[IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false)))}
function Run-Backend([string]$Name,[hashtable]$Parameters,[string]$Root=$repo){
    $arguments=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $Root ('src/'+$Name+'.ps1')))
    foreach($key in $Parameters.Keys){if($Parameters[$key] -is [bool]){if($Parameters[$key]){$arguments+='-'+$key}}else{$arguments+='-'+$key;$arguments+=[string]$Parameters[$key]}}
    $script:lastOutput=(& powershell.exe @arguments 2>&1|Out-String);return $LASTEXITCODE
}
try{
    . (Join-Path $repo 'src/internal/_shared.ps1')
    . (Join-Path $repo 'src/internal/_http.ps1')
    . (Join-Path $repo 'src/internal/_watch.ps1')
    foreach($file in Get-ChildItem (Join-Path $repo 'src') -Recurse -Filter *.ps1){$t=$null;$e=$null;$null=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$t,[ref]$e);Assert ($e.Count -eq 0) ('PowerShell 5.1 syntax: '+$file.Name)}
    foreach($file in Get-ChildItem (Join-Path $repo 'bin') -Filter *.bat){Assert (-not (Select-String -LiteralPath $file.FullName -Pattern '%TEMP%|_temp\.ps1|_temp\.vbs|cscript' -Quiet)) ('No temporary script/argument files: '+$file.Name)}
    $live=Join-Path $scratch 'live';$null=New-Item -ItemType Directory -Path (Join-Path $live 'src/deep'),(Join-Path $live 'empty')
    Write-Fixture (Join-Path $live 'root.txt') 'root';Write-Fixture (Join-Path $live 'src/deep/nested.txt') 'nested'
    Write-Fixture (Join-Path $live '.treeignore') "maxdepth: 1`nshowmode: folders"
    $output=Join-Path $scratch 'tree.txt'
    Assert ((Run-Backend export @{RootPath=$live;OutputFile=$output;OutputFormat='importable';Ci=$true}) -eq 0) 'Export reads configured depth/show mode when omitted'
    $read=@(Read-StructureFile $output dash)
    Assert ($read.Count -eq 2 -and @($read|Where-Object {-not $_.IsDir}).Count -eq 0) 'Configured folders-only and depth are applied'
    Assert ((Run-Backend export @{RootPath=$live;OutputFile=$output;OutputFormat='importable';ShowMode='files';MaxDepth=0;Ci=$true}) -eq 0) 'Explicit options override configured values including depth zero'
    $read=@(Read-StructureFile $output dash)
    Assert (@($read|Where-Object Path -eq 'src\deep\nested.txt').Count -eq 1 -and @($read|Where-Object IsDir).Count -eq 0) 'Files-only export traverses nested directories and preserves full paths'
    foreach($format in @('json','yaml')){
        $structured=Join-Path $scratch ('tree.'+$format)
        Assert ((Run-Backend export @{RootPath=$live;OutputFile=$structured;OutputFormat=$format;ShowMode='folders';MaxDepth=0;Ci=$true}) -eq 0) ($format+' honors folders-only mode')
        Assert (@(Read-StructureFile $structured $format|Where-Object {-not $_.IsDir}).Count -eq 0) ($format+' contains no file nodes in folders mode')
        Assert ((Run-Backend export @{RootPath=$live;OutputFile=$structured;OutputFormat=$format;ShowMode='files';MaxDepth=0;Ci=$true}) -eq 0) ($format+' honors files-only mode')
        $read=@(Read-StructureFile $structured $format)
        Assert (@($read|Where-Object {$_.Path.Replace('\','/') -eq 'live/src/deep/nested.txt'}).Count -eq 1 -and @($read|Where-Object {$_.Path -eq 'live\empty'}).Count -eq 0) ($format+' files mode retains necessary ancestors but omits empty folders')
    }
    $config=Get-TreeConfig $live
    Assert ((Resolve-TreeOptions $config @{MaxDepth=0}).MaxDepth -eq 0) 'Watch/export preserve explicit unlimited depth'
    $source=Join-Path $scratch 'source.txt';Write-Fixture $source '- root.txt'
    $oldPreload=$env:VERIFY_PRELOAD_FILE;$env:VERIFY_PRELOAD_FILE=$source
    try{Assert ((Run-Backend verify @{LivePath=$live;Format='dash';Ci=$true}) -in @(0,1)) 'Library preload reaches verification without requesting another structure file'}finally{$env:VERIFY_PRELOAD_FILE=$oldPreload}
    foreach($backend in @('export','git_tree')){Assert ((Run-Backend $backend @{ArgsFile=(Join-Path $scratch 'missing.args')}) -eq 2 -and $script:lastOutput -match '\[ERROR\]' -and $script:lastOutput -notmatch 'At .*\.ps1') ($backend+' catches argument-file setup failure')}
    Assert ((Run-Backend verify @{StructureFile=$source;LivePath=$live;Format='dash';SpaceUnit=0;Ci=$true}) -ne 0) 'Invalid numeric input returns nonzero'
    $locked=Join-Path $scratch 'locked.txt';Write-Fixture $locked 'preserve'
    $lock=[IO.File]::Open($locked,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try{Assert ((Run-Backend export @{RootPath=$live;OutputFile=$locked;OutputFormat='importable';Ci=$true}) -eq 2 -and $script:lastOutput -match '\[ERROR\]') 'Export catches output write errors'}finally{$lock.Dispose()}
    Assert ([IO.File]::ReadAllText($locked) -eq 'preserve') 'Failed output write preserves locked file'
    $colorScript=Join-Path $scratch 'color.ps1';Write-Fixture $colorScript (". '"+(Join-Path $repo 'src/internal/_shared.ps1').Replace("'","''")+"'; Write-Color 'plain message' Green")
    $text=(& powershell.exe -NoProfile -NonInteractive -File $colorScript|Out-String)
    Assert ($text.Trim() -eq 'plain message' -and $text.IndexOf([char]27) -lt 0) 'PowerShell 5.1 color output redirects as plain readable text'
    foreach($name in @('react-vite','hono-worker','monorepo-pnpm')){
        $preset=Get-TemplatePreset $name;$package=($preset.Entries|Where-Object Path -eq 'package.json').Content|ConvertFrom-Json
        Assert ($package.scripts.build -and $package.engines.node) ($name+' declares build scripts and runtime requirements')
        if($name -ne 'monorepo-pnpm'){Assert ($package.dependencies -and $package.devDependencies.typescript -and $package.scripts.typecheck) ($name+' declares required runtime and build dependencies')}
    }
    # Retry tests are local mocks, with sleeping replaced by a counter.
    & {
        $script:requests=0;$script:delays=@()
        function Start-Sleep {param($Milliseconds);$script:delays+= $Milliseconds}
        function Invoke-WebRequest {param($Uri,$Headers,[switch]$UseBasicParsing,$TimeoutSec,$MaximumRedirection,$ErrorAction);$script:requests++;if($script:requests -lt 3){throw (New-Object Net.WebException('fixture timeout',[Net.WebExceptionStatus]::Timeout))};Assert ($TimeoutSec -eq 15 -and $MaximumRedirection -eq 0) 'HTTP timeout and redirect bounds are applied';[pscustomobject]@{Content='{}'}}
        $response=Invoke-TreeHttpRequest 'https://fixture.invalid/api'
        Assert ($script:requests -eq 3 -and $script:delays.Count -eq 2) 'Transient failures retry within the configured budget'
    }
    & {
        $script:requests=0
        function Start-Sleep {}
        function Invoke-WebRequest {$script:requests++;throw (New-Object Net.WebException('fixture timeout',[Net.WebExceptionStatus]::Timeout))}
        Reject {Invoke-TreeHttpRequest 'https://fixture.invalid/api' -Retries 1} 'Exhausted retry budget returns an explicit error'
        Assert ($script:requests -eq 2) 'HTTP retries are bounded'
    }
    Add-Type 'public class PtuFixtureHttpException : System.Exception { public object Response { get; set; } }'
    & {
        $script:requests=0;$script:delay=-1
        function Start-Sleep {param($Milliseconds);$script:delay=$Milliseconds}
        function Invoke-WebRequest {
            $script:requests++
            if($script:requests -eq 1){$failure=New-Object PtuFixtureHttpException;$failure.Response=[pscustomobject]@{StatusCode=429;Headers=@{'Retry-After'='0'}};throw $failure}
            return [pscustomobject]@{Content='{}'}
        }
        $null=Invoke-TreeHttpRequest 'https://fixture.invalid/api'
        Assert ($script:requests -eq 2 -and $script:delay -eq 0) 'Rate-limit retry respects a bounded Retry-After value'
    }
    & {
        $script:requests=0
        function Invoke-WebRequest {$script:requests++;$failure=New-Object PtuFixtureHttpException;$failure.Response=[pscustomobject]@{StatusCode=401;Headers=@{}};throw $failure}
        Reject {Invoke-TreeHttpRequest 'https://fixture.invalid/api'} 'Authentication failures are reported without retrying'
        Assert ($script:requests -eq 1) 'Permanent HTTP failures are not retried'
    }
    Reject {Invoke-TreeHttpRequest 'http://fixture.invalid/api'} 'API client rejects insecure transport before network access'
    # Import remote functions via their ASTs, without running the remote command.
    $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'src/git_tree.ps1'),[ref]$t,[ref]$e)
    foreach($name in @('Get-GitHubTree','Get-GitLabTree','Write-Step','Write-Ok','Write-Warn')){$definition=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true);. ([scriptblock]::Create($definition.Extent.Text))}
    & {
        function Invoke-ApiRequest {param($Uri,$Pat,$PatHeader,$PatPrefix);$script:captured=$Uri;[pscustomobject]@{Content='{"tree":[{"path":"a.txt","type":"blob"}],"truncated":false}'}}
        $null=Get-GitHubTree owner repo 'feature/a&b' ''
        Assert ($script:captured -match 'feature%2Fa%26b\?recursive=1') 'GitHub branch is encoded as one URL component'
    }
    & {function Invoke-ApiRequest {[pscustomobject]@{Content='{"tree":[],"truncated":true}'}};Reject {Get-GitHubTree owner repo main ''} 'Truncated GitHub tree fails explicitly'}
    & {
        $script:pages=0
        function Invoke-ApiRequest {param($Uri,$Pat,$PatHeader,$PatPrefix);$script:pages++;$script:captured=$Uri;if($script:pages -eq 1){[pscustomobject]@{Content='[{"path":"one","type":"blob"}]';Headers=@{'X-Next-Page'='2'}}}else{[pscustomobject]@{Content='[]';Headers=@{}}}}
        $entries=@(Get-GitLabTree 'https://fixture.invalid' 'group%2Frepo' 'feature/a&b' '')
        Assert ($entries.Count -eq 1 -and $script:pages -eq 2 -and $script:captured -match 'ref=feature%2Fa%26b&') 'GitLab encodes branch values and accepts single-item/empty pages'
    }
    & {function Invoke-ApiRequest {[pscustomobject]@{Content='[]';Headers=@{'X-Next-Page'='1'}}};Reject {Get-GitLabTree 'https://fixture.invalid' repo main ''} 'GitLab repeated pagination fails instead of looping'}
    & {function Invoke-ApiRequest {[pscustomobject]@{Content='{}';Headers=@{}}};Reject {Get-GitLabTree 'https://fixture.invalid' repo main ''} 'Malformed GitLab response is rejected'}
    # Watcher lifecycle tests use real local filesystem events and injected errors.
    $watch=Join-Path $scratch 'watch';$null=New-Item -ItemType Directory -Path (Join-Path $watch 'ignored')
    $script:snapshots=0;$baseline=@(Get-EventSubscriber).Count
    $eventsScript=Join-Path $scratch 'events.ps1'
    Write-Fixture $eventsScript @'
param($Path)
Start-Sleep -Milliseconds 700
1..12|ForEach-Object {[IO.File]::WriteAllText((Join-Path $Path 'burst.txt'),[string]$_)}
Start-Sleep -Milliseconds 700
[IO.File]::WriteAllText((Join-Path $Path 'ignored/skip.txt'),'ignored')
'@
    $start=New-Object Diagnostics.ProcessStartInfo;$start.FileName='powershell.exe';$start.Arguments='-NoProfile -NonInteractive -File "'+$eventsScript+'" "'+$watch+'"';$start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $writer=[Diagnostics.Process]::Start($start)
    try{Invoke-TreeWatch $watch @() @('ignored') 0 -DurationSeconds 3 -OnSnapshot {$script:snapshots++}}finally{$writer.WaitForExit();$writer.Dispose()}
    Assert ($script:snapshots -ge 2 -and $script:snapshots -le 3) 'Watcher coalesces a burst and ignores excluded activity'
    Assert (@(Get-EventSubscriber).Count -eq $baseline) 'Watcher unregisters every subscription on completion'
    Assert (@(Get-Event|Where-Object SourceIdentifier -like 'TreeWatch.*').Count -eq 0) 'Watcher drains its own queued events'
    $script:snapshots=0
    Invoke-TreeWatch $watch @() @('ignored') 0 -DurationSeconds 1 -OnSnapshot {
        $script:snapshots++
        if($script:snapshots -eq 1){$subscriber=Get-EventSubscriber|Where-Object SourceIdentifier -like 'TreeWatch.*.Error'|Select-Object -First 1;$null=New-Event -SourceIdentifier $subscriber.SourceIdentifier}
    }
    Assert ($script:snapshots -ge 2) 'Watcher error schedules a recovery rescan'
    $script:snapshots=0
    Invoke-TreeWatch $watch @() @('ignored') 0 -DurationSeconds 1 -OnSnapshot {
        $script:snapshots++
        if($script:snapshots -eq 1){[IO.File]::WriteAllText((Join-Path $watch 'startup.txt'),'startup')}
    }
    Assert ($script:snapshots -ge 2) 'Changes during the initial snapshot are queued and reconciled'
    Reject {Invoke-TreeWatch (Join-Path $scratch 'does-not-exist') @() @() 0 -DurationSeconds 1} 'Watcher setup failure returns an error'
    Assert (@(Get-EventSubscriber).Count -eq $baseline) 'Watcher setup failure does not leak subscriptions'
    $argsObject=[pscustomobject]@{FullPath=(Join-Path $watch 'ignored/file.txt');OldFullPath=(Join-Path $watch 'visible.txt')}
    Assert (Test-TreeWatchEvent $argsObject $watch @('ignored') 0) 'Rename from an included path is detected even if destination is excluded'
    Write-Host ('All {0} checks passed on PowerShell {1}.' -f $script:checks,$PSVersionTable.PSVersion)
}finally{
    $resolved=[IO.Path]::GetFullPath($scratch);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if($resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -match '^ptu-final-[a-f0-9]{32}$'){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
