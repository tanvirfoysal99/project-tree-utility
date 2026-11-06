# No param block: preserve every public CLI token, including unknown flags, as data.
$ErrorActionPreference = 'Stop'
$invocationDirectory = (Get-Location).Path
$tokens = @($args)
$ci = $env:TREE_CI -match '^(?i:1|true|yes)$'
$original = @()
try {
    $remaining = New-Object 'System.Collections.Generic.List[string]'
    foreach ($token in $tokens) {
        if ($token -in @('--ci','-Ci')) { $ci=$true } else { $remaining.Add([string]$token) }
    }
    if (-not $remaining.Count) { throw 'A subcommand is required.' }
    $command = $remaining[0].ToLowerInvariant()
    $original = @($remaining | Select-Object -Skip 1)
    $wrappers = @{import='import';export='export';scaffold='scaffold';merge='merge';verify='verify';security='security';gittree='git_tree';library='store';auth='auth';watch='watch';version='version';detection='detection'}
    if (-not $wrappers.ContainsKey($command)) { throw ('Unknown subcommand: ' + $command) }
    $switches = @('sync','delete-extras','dry-run','check','yes','secret-stdin')
    $aliases = @{'check-update'='check';checkupdate='check';structurefile='structure';livepath='live';rootpath='root';outputfile='output';outputformat='output-format';targetbase='target';projectname='project';templatename='template';overwritemode='overwrite';dryrun='dry-run';ignorefile='ignore-file';maxdepth='max-depth';showmode='show-mode';extraexclude='exclude';excludelist='exclude';spaceunit='space-unit';deleteextras='delete-extras';filea='file-a';fileb='file-b';formata='format-a';formatb='format-b';spaceunita='space-unit-a';spaceunitb='space-unit-b';repourl='repo';gitlabbaseurl='gitlab-base';subfolder='subfolder'}
    $options=@{}; $positionals=New-Object 'System.Collections.Generic.List[string]'
    for ($i=0;$i -lt $original.Count;$i++) {
        $token=[string]$original[$i]
        if ($token.StartsWith('-')) {
            $key=$token.TrimStart('-').ToLowerInvariant()
            if ($aliases.ContainsKey($key)) { $key=$aliases[$key] }
            if ($options.ContainsKey($key)) { throw ('Duplicate option: ' + $token) }
            if ($key -in $switches) { $options[$key]=$true }
            else {
                if ($i+1 -ge $original.Count -or $original[$i+1].StartsWith('--')) { throw ('Missing value for ' + $token) }
                $i++; $options[$key]=[string]$original[$i]
            }
        } else { $positionals.Add($token) }
    }
    function Check-Options([string[]]$Allowed) {
        foreach ($key in $options.Keys) { if ($key -notin $Allowed) { throw ('Unknown option for ' + $command + ': --' + $key) } }
    }
    function Map-Positionals([string[]]$Names) {
        if ($positionals.Count -gt $Names.Count) { throw ('Too many positional arguments for ' + $command) }
        for($j=0;$j -lt $positionals.Count;$j++) {
            if ($options.ContainsKey($Names[$j])) { throw ('Specify ' + $Names[$j] + ' once, by position or name.') }
            $options[$Names[$j]]=$positionals[$j]
        }
    }
    function Required([string]$Name) {
        if (-not $options.ContainsKey($Name) -or [string]::IsNullOrWhiteSpace([string]$options[$Name])) { throw ('Required option: --' + $Name) }
        return $options[$Name]
    }
    function Value([string]$Name,$Default) { if ($options.ContainsKey($Name)) { return $options[$Name] }; return $Default }
    function Full-Path([string]$Path) {
        if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
        return [IO.Path]::GetFullPath((Join-Path $invocationDirectory $Path))
    }
    function Input-Format([string]$Path,[string]$Name='format') {
        $format=Value $Name ''
        if (-not $format) { $format=Get-StructureFormat $Path }
        if ($format -notin @('dash','tab','space','treesym','json','yaml')) { throw 'Ambiguous or unsupported format; supply --format explicitly.' }
        return $format
    }
    . (Join-Path $PSScriptRoot 'internal/_shared.ps1')
    $allowedOptions = @{
        import=@('structure','format','output','output-format','space-unit')
        export=@('root','format','output-format','output','max-depth','show-mode','exclude','ignore-file')
        verify=@('live','structure','format','space-unit','ignore-file','sync','delete-extras')
        scaffold=@('structure','format','target','project','template','overwrite','dry-run','space-unit')
        merge=@('file-a','format-a','file-b','format-b','strategy','output','space-unit-a','space-unit-b')
        security=@('action','file','format','base','candidate')
        library=@('action','file','format','source','name','new-name','yes')
        auth=@('action','target','username','secret-env','secret-stdin')
        gittree=@('provider','repo','branch','output','format','subfolder','max-depth','exclude','gitlab-base')
        watch=@('path','structure','format','max-depth','ignore-file');version=@('check');detection=@()
    }
    Check-Options $allowedOptions[$command]
    # Keep existing menus when no CI request or complete noninteractive operation
    # was supplied. A recursion guard lets wrappers call their original menu body.
    if (-not $ci -and (
        ($original.Count -eq 0 -and $command -ne 'version') -or
        ($command -eq 'scaffold' -and -not $options.ContainsKey('project') -and $positionals.Count -lt 4) -or
        ($command -eq 'library' -and ($original.Count -eq 0 -or $positionals[0] -in @('LIST','OPEN','RENAME','DELETE','PURGE') -and $positionals.Count -eq 1 -or $positionals[0] -eq 'SAVE' -and $positionals.Count -lt 5 -and -not $options.ContainsKey('name'))))) {
        $oldGuard=$env:PTU_LEGACY
        try {
            $env:PTU_LEGACY='1'
            & (Join-Path $PSScriptRoot ('../bin/'+$wrappers[$command]+'.bat')) @original
            $legacyCode=$LASTEXITCODE
        } finally { $env:PTU_LEGACY=$oldGuard }
        exit $legacyCode
    }
    $parameters=@{}; $backend=''
    switch ($command) {
        import {
            Check-Options @('structure','format','output','output-format','space-unit')
            Map-Positionals @('structure','format','output','output-format')
            $source=Full-Path (Required 'structure')
            $parameters=@{StructureFile=$source;Format=(Input-Format $source);OutputFile=(Full-Path (Required 'output'));OutputFormat=(Value 'output-format' 'importable');SpaceUnit=[int](Value 'space-unit' 2)}
            $backend='import'
        }
        export {
            Check-Options @('root','format','output-format','output','max-depth','show-mode','exclude','ignore-file')
            Map-Positionals @('root','format','output','max-depth','show-mode','exclude','ignore-file')
            if ($options.ContainsKey('output-format')) { if ($options.ContainsKey('format')) { throw 'Specify one output format.' }; $options.format=$options['output-format'] }
            $parameters=@{RootPath=(Full-Path (Required 'root'));OutputFile=(Full-Path (Required 'output'));OutputFormat=(Required 'format');ExtraExclude=(Value 'exclude' '');Ci=$ci}
            if($options.ContainsKey('max-depth')){$parameters.MaxDepth=[int]$options['max-depth']}
            if($options.ContainsKey('show-mode')){$parameters.ShowMode=$options['show-mode']}
            if ($options.ContainsKey('ignore-file')) { $parameters.IgnoreFile=Full-Path $options['ignore-file'] }
            $backend='export'
        }
        verify {
            Check-Options @('live','structure','format','space-unit','ignore-file','sync','delete-extras')
            Map-Positionals @('live','structure','format')
            if ($options.ContainsKey('delete-extras') -and -not $options.ContainsKey('sync')) { throw '--delete-extras requires --sync.' }
            if (-not $ci -and -not $options.ContainsKey('structure') -and -not $options.ContainsKey('live')) {
                $parameters=@{Sync=[bool]$options.sync;DeleteExtras=[bool]$options['delete-extras']};$backend='verify';break
            }
            $source=Full-Path (Required 'structure')
            $parameters=@{StructureFile=$source;LivePath=(Full-Path (Required 'live'));Format=(Input-Format $source);SpaceUnit=[int](Value 'space-unit' 2);Sync=[bool]$options.sync;DeleteExtras=[bool]$options['delete-extras'];Ci=$ci}
            if ($options.ContainsKey('ignore-file')) { $parameters.IgnoreFile=Full-Path $options['ignore-file'] }
            $backend='verify'
        }
        scaffold {
            Check-Options @('structure','format','target','project','template','overwrite','dry-run','space-unit')
            Map-Positionals @('structure','format','target','project')
            $parameters=@{TargetBase=(Full-Path (Required 'target'));ProjectName=(Required 'project');OverwriteMode=(Value 'overwrite' 'skip');DryRun=[bool]$options['dry-run'];SpaceUnit=[int](Value 'space-unit' 2);Ci=$ci}
            if ($ci -and $parameters.OverwriteMode -eq 'ask') { throw 'CI mode cannot use overwrite=ask.' }
            if ($options.ContainsKey('template')) {
                if ($options.ContainsKey('structure')) { throw 'Choose --template or --structure.' }
                $parameters.Format='template';$parameters.TemplateName=Required 'template'
            } else { $parameters.StructureFile=Full-Path (Required 'structure');$parameters.Format=Input-Format $parameters.StructureFile }
            $backend='scaffold'
        }
        merge {
            Check-Options @('file-a','format-a','file-b','format-b','strategy','output','space-unit-a','space-unit-b')
            Map-Positionals @('file-a','format-a','file-b','format-b','strategy','output')
            $a=Full-Path (Required 'file-a');$b=Full-Path (Required 'file-b')
            $parameters=@{FileA=$a;FileB=$b;FormatA=(Input-Format $a 'format-a');FormatB=(Input-Format $b 'format-b');Strategy=(Value 'strategy' 'union');OutputFile=(Full-Path (Required 'output'));SpaceUnitA=[int](Value 'space-unit-a' 2);SpaceUnitB=[int](Value 'space-unit-b' 2)}
            $backend='merge_tree'
        }
        security {
            Check-Options @('action','file','format','base','candidate')
            if ($positionals.Count -and $options.ContainsKey('action')) { throw 'Specify the security action once.' }
            if ($positionals.Count) { $action=$positionals[0].ToUpperInvariant();$positionals.RemoveAt(0) } else { $action=([string](Required 'action')).ToUpperInvariant() }
            if ($action -eq 'VALIDATE_PATH') { Map-Positionals @('candidate','base');if (-not (Test-SafePath (Full-Path (Required 'candidate')) (Full-Path (Required 'base')))) { exit 1 } }
            elseif ($action -in @('VALIDATE_FILE','VALIDATE_NAMES','VALIDATE_ALL')) {
                Map-Positionals @('file','format','base');$source=Full-Path (Required 'file');$format=Input-Format $source
                $entries=@(Read-StructureFile $source $format)
                if ($action -eq 'VALIDATE_ALL') { $base=Full-Path (Required 'base');foreach($entry in $entries){if(-not (Test-SafePath (Join-Path $base $entry.Path) $base)){exit 1}} }
            } else { throw 'Unknown security action.' }
            Write-Host '[OK] Security validation passed.';exit 0
        }
        library {
            Check-Options @('action','file','format','source','name','new-name','yes')
            if ($positionals.Count -and $options.ContainsKey('action')) { throw 'Specify the library action once.' }
            if ($positionals.Count) { $action=$positionals[0].ToLowerInvariant();$positionals.RemoveAt(0) } else { $action=([string](Required 'action')).ToLowerInvariant() }
            . (Join-Path $PSScriptRoot 'store.ps1')
            switch ($action) {
                list { Map-Positionals @();Show-LibraryTable | Out-Null }
                save { Map-Positionals @('file','format','source','name');$source=Full-Path (Required 'file');if(-not (Add-TreeEntry $source (Required 'name') (Input-Format $source) (Value 'source' 'manual'))){exit 1} }
                open { Map-Positionals @('name');$path=Get-TreePath (Required 'name');if(-not $path){exit 1};Write-Output $path }
                rename { Map-Positionals @('name','new-name');if(-not (Rename-TreeEntry (Required 'name') (Required 'new-name'))){exit 1} }
                delete { Map-Positionals @('name');if(-not (Remove-TreeEntry (Required 'name'))){exit 1} }
                purge { Map-Positionals @();if(-not $options.yes){throw 'Library purge requires --yes.'};& (Join-Path $PSScriptRoot 'wrapper_actions.ps1') -Action StorePurge;exit $LASTEXITCODE }
                default { throw 'Unknown library action.' }
            }
            exit 0
        }
        auth {
            Check-Options @('action','target','username','secret-env','secret-stdin');Map-Positionals @('action','target','username')
            $parameters=@{Action=(Required 'action');Target=(Required 'target');Username=(Value 'username' 'oauth2');Ci=$ci}
            if ($options.ContainsKey('secret-env')) { $parameters.SecretEnv=$options['secret-env'] }
            if ($options.ContainsKey('secret-stdin')) { $parameters.SecretStdin=$true }
            if ($ci -and $parameters.Action -eq 'store' -and -not $parameters.SecretEnv -and -not $parameters.SecretStdin) { throw 'CI credential storage requires --secret-env NAME or --secret-stdin.' }
            $backend='auth'
        }
        gittree {
            Check-Options @('provider','repo','branch','output','format','subfolder','max-depth','exclude','gitlab-base');Map-Positionals @('provider','repo','branch','output','format','subfolder','max-depth','exclude','gitlab-base')
            $parameters=@{Provider=(Required 'provider');RepoUrl=(Required 'repo');Branch=(Required 'branch');OutputFile=(Full-Path (Required 'output'));OutputFormat=(Required 'format');SubFolder=(Value 'subfolder' '');MaxDepth=[int](Value 'max-depth' 0);ExcludeList=(Value 'exclude' 'node_modules,.git,dist,build,.next,.wrangler');GitLabBaseUrl=(Value 'gitlab-base' 'https://gitlab.com');Ci=$ci}
            $backend='git_tree'
        }
        version { Check-Options @('check');Map-Positionals @();$parameters=@{CheckUpdate=[bool]$options.check;Ci=$ci};$backend='version' }
        watch {
            Check-Options @('path','structure','format','max-depth','ignore-file');Map-Positionals @('path','structure','ignore-file','max-depth')
            $parameters=@{WatchPath=(Full-Path (Required 'path'));Ci=$ci}
            if($options.ContainsKey('max-depth')){$parameters.MaxDepth=[int]$options['max-depth']}
            if ($options.ContainsKey('structure')) { $parameters.StructureFile=Full-Path $options.structure;$parameters.Format=Input-Format $parameters.StructureFile }
            if ($options.ContainsKey('ignore-file')) { $parameters.IgnoreFile=Full-Path $options['ignore-file'] };$backend='watch'
        }
        detection {
            Check-Options @()
            if ($positionals.Count -eq 3 -and $positionals[0] -eq 'ANALYSE') {
                $env:DT_FILE=Full-Path $positionals[1];$env:DT_FMT=$positionals[2]
                $parameters=@{Action='Analyse'}
            } elseif ($positionals.Count -eq 7 -and $positionals[0] -eq 'BUILD_TREE') {
                $env:DT_FILE_A=Full-Path $positionals[1];$env:DT_FMT_A=$positionals[2]
                $env:DT_FILE_B=Full-Path $positionals[3];$env:DT_FMT_B=$positionals[4]
                $env:DT_STRATEGY=$positionals[5];$env:DT_OUT=Full-Path $positionals[6]
                $parameters=@{Action='Merge'}
            } else { throw 'Detection requires ANALYSE file format or BUILD_TREE fileA formatA fileB formatB strategy output.' }
            $backend='detection'
        }
    }
    if ($parameters.ContainsKey('MaxDepth') -and $parameters.MaxDepth -lt 0) { throw 'Maximum depth cannot be negative.' }
    $global:LASTEXITCODE=0
    & (Join-Path $PSScriptRoot ($backend+'.ps1')) @parameters
    exit $LASTEXITCODE
} catch { Write-Host ('[ERROR] ' + $_.Exception.Message); exit 2 }
