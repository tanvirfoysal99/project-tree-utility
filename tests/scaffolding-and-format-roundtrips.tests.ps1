$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('ptu-formats-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $scratch
$script:checks = 0
function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw ('FAIL: ' + $Message + "`n" + $script:lastOutput) }
    $script:checks++; Write-Host ('PASS: ' + $Message)
}
function Write-Fixture([string]$Path,[string]$Text) { [IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($false))) }
function Run-Backend([string]$Name,[hashtable]$Parameters,[string]$Root=$repo) {
    $arguments = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $Root ('src/' + $Name + '.ps1')))
    foreach ($key in $Parameters.Keys) {
        if ($Parameters[$key] -is [bool]) { if ($Parameters[$key]) { $arguments += '-'+$key } }
        else { $arguments += '-'+$key; $arguments += [string]$Parameters[$key] }
    }
    $script:lastOutput = (& powershell.exe @arguments 2>&1 | Out-String)
    return $LASTEXITCODE
}
function Signature($Entries) { return (@($Entries | ForEach-Object { $_.Path.Replace('\','/') + '|' + $_.IsDir } | Sort-Object) -join "`n") }
function Assert-RejectedYaml([string]$Text,[string]$Message) {
    $file = Join-Path $scratch 'invalid.yaml'; Write-Fixture $file $Text
    $failed = $false
    try { Read-StructureFile $file yaml | Out-Null } catch { $failed = $true }
    Assert $failed $Message
}
try {
    . (Join-Path $repo 'src/internal/_shared.ps1')
    foreach ($file in Get-ChildItem (Join-Path $repo 'bin') -Filter *.bat) {
        Assert (-not (Select-String -LiteralPath $file.FullName -Pattern '\-Command\b|f\.WriteLine|cscript\b' -Quiet)) ('No source interpolation or generated scripts: ' + $file.Name)
    }
    foreach ($file in Get-ChildItem (Join-Path $repo 'src') -Recurse -Filter *.ps1) {
        $tokens=$null; $errors=$null
        $null=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
        Assert ($errors.Count -eq 0) ('PowerShell 5.1 syntax: ' + $file.Name)
    }
    foreach ($preset in @('react-vite','hono-worker','monorepo-pnpm')) {
        $entries = @(Read-StructureFile '' template 2 $preset)
        $definition = Get-TemplatePreset $preset
        foreach ($directory in @($definition.Entries | Where-Object IsDir)) {
            Assert (@($entries | Where-Object { $_.Path.Replace('\','/') -eq $directory.Path -and $_.IsDir }).Count -eq 1) ($preset + ' preserves directory ' + $directory.Path)
        }
        $code=Run-Backend scaffold @{Format='template';TemplateName=$preset;ProjectName=$preset;TargetBase=$scratch}
        Assert ($code -eq 0) ('Scaffold preset: ' + $preset)
        foreach ($directory in @($definition.Entries | Where-Object IsDir)) {
            Assert (Test-Path -LiteralPath (Join-Path (Join-Path $scratch $preset) $directory.Path) -PathType Container) ($preset + ' creates directory ' + $directory.Path)
        }
    }
    $nodes = @(
        [pscustomobject]@{name='empty';type='directory'},
        [pscustomobject]@{name='slash/'},
        [pscustomobject]@{Path='explicit';IsDir=$true},
        [pscustomobject]@{name='children';children=@()},
        [pscustomobject]@{name='file.txt';type='file'}
    )
    $entries = @(ConvertFrom-TreeNode $nodes)
    Assert (@($entries | Where-Object IsDir).Count -eq 4) 'All four supported directory indicators work'
    Assert (-not $entries[-1].IsDir) 'Explicit file stays a file'
    $structure = Join-Path $scratch "O'Brien structure.txt"
    Write-Fixture $structure "- nested/deep/main.txt @content:hello`n- empty/"
    $code=Run-Backend scaffold @{StructureFile=$structure;Format='dash';TargetBase=$scratch;ProjectName="O'Brien project"}
    Assert ($code -eq 0) 'Scaffold accepts apostrophes and creates implicit parents'
    Assert (([IO.File]::ReadAllText((Join-Path $scratch "O'Brien project/nested/deep/main.txt"))) -eq 'hello') 'Scaffold writes literal content'
    Assert ($script:lastOutput -match 'Created folders: 4; files: 1') 'Counters count successful directory and file creation'
    $code=Run-Backend scaffold @{StructureFile=$structure;Format='dash';TargetBase=$scratch;ProjectName='dry';DryRun=$true}
    Assert ($code -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $scratch 'dry'))) 'Dry run creates no directory or log'
    Write-Fixture $structure "- first.txt`n- parent`n-- child.txt"
    $code=Run-Backend scaffold @{StructureFile=$structure;Format='dash';TargetBase=$scratch;ProjectName='bad-parent'}
    Assert ($code -eq 2 -and -not (Test-Path -LiteralPath (Join-Path $scratch 'bad-parent'))) 'File parent conflict fails before writes'
    Write-Fixture $structure '- nested.txt'
    $code=Run-Backend scaffold @{StructureFile=$structure;Format='dash';TargetBase=$scratch;ProjectName='collision'}
    Assert ($code -eq 0) 'Prepare collision fixture'
    Write-Fixture $structure '- nested.txt/'
    $code=Run-Backend scaffold @{StructureFile=$structure;Format='dash';TargetBase=$scratch;ProjectName='collision'}
    Assert ($code -eq 2 -and $script:lastOutput -notmatch '\[OK\]') 'Write conflict returns failure without a success summary'
    $code=Run-Backend scaffold @{Format='template';TemplateName='missing';TargetBase=$scratch;ProjectName='unknown'}
    Assert ($code -eq 2) 'Unknown preset returns failure'
    $lockedRoot=Join-Path $scratch 'locked-project'; $null=New-Item -ItemType Directory -Path $lockedRoot
    $lockedPath=Join-Path $lockedRoot 'locked.txt'; Write-Fixture $lockedPath 'unchanged'
    Write-Fixture $structure "- made.txt @content:created`n- locked.txt @content:changed"
    $lock=[IO.File]::Open($lockedPath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        $code=Run-Backend scaffold @{StructureFile=$structure;Format='dash';TargetBase=$scratch;ProjectName='locked-project';OverwriteMode='overwrite'}
        Assert ($code -eq 2 -and $script:lastOutput -notmatch '\[OK\]') 'Actual write failure returns nonzero without a success summary'
        Assert ($script:lastOutput -match 'Partial result: created folders: 0; files: 1') 'Partial failure reports only successful writes'
        Assert (-not (Test-Path -LiteralPath (Join-Path $lockedRoot '_creation_log.txt'))) 'Failed scaffold does not write a success log'
    } finally { $lock.Dispose() }
    Assert (([IO.File]::ReadAllText($lockedPath)) -eq 'unchanged') 'Failed write preserves locked file'

    # Real disk -> dash -> import -> scaffold; paths are relative to the chosen root.
    $live = Join-Path $scratch 'live'; $null=New-Item -ItemType Directory -Path (Join-Path $live 'src/components'),(Join-Path $live 'empty')
    Write-Fixture (Join-Path $live 'src/components/Button.tsx') ''
    Write-Fixture (Join-Path $live 'package.json') '{}'
    $dash=Join-Path $scratch 'export.txt'; $converted=Join-Path $scratch 'converted.txt'
    $code=Run-Backend export @{RootPath=$live;OutputFile=$dash;OutputFormat='importable';MaxDepth=0;Ci=$true}
    Assert ($code -eq 0 -and (Confirm-StructureFormat $dash dash)) 'Local dash export passes importer validation'
    $before=@(Read-StructureFile $dash dash)
    Assert (@($before | Where-Object { $_.Path -eq 'src\components\Button.tsx' }).Count -eq 1) 'Export preserves nested hierarchy without an extra root'
    $code=Run-Backend import @{StructureFile=$dash;Format='dash';OutputFile=$converted;OutputFormat='importable'}
    Assert ($code -eq 0 -and (Confirm-StructureFormat $converted dash)) 'Import dash conversion has no presentation header'
    Assert ((Signature $before) -eq (Signature @(Read-StructureFile $converted dash))) 'Import conversion preserves every path and type'
    $code=Run-Backend scaffold @{StructureFile=$converted;Format='dash';TargetBase=$scratch;ProjectName='roundtrip'}
    Assert ($code -eq 0 -and (Test-Path -LiteralPath (Join-Path $scratch 'roundtrip/src/components/Button.tsx'))) 'Export/import output scaffolds correct hierarchy'

    # Test the remote renderer without a network request or credential lookup.
    $t=$null;$e=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'src/git_tree.ps1'),[ref]$t,[ref]$e)
    $render=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Render-Output'},$true)
    . ([scriptblock]::Create($render.Extent.Text))
    $remote=@(@{Path='src';Type='tree';Parts=@('src')},@{Path='src/main.ts';Type='blob';Parts=@('src','main.ts')})
    $remoteDash=Render-Output $remote importable 'repo' 'main'
    Write-Fixture $converted $remoteDash
    Assert ((Signature @(Read-StructureFile $converted dash)) -eq "src/main.ts|False`nsrc|True") 'Remote dash renderer preserves root-relative hierarchy'

    foreach ($format in @('json','yaml')) {
        $output=Join-Path $scratch ('tree.'+$format)
        $code=Run-Backend export @{RootPath=$live;OutputFile=$output;OutputFormat=$format;MaxDepth=0;Ci=$true}
        Assert ($code -eq 0 -and (Confirm-StructureFormat $output $format)) ($format + ' export validates')
        $tree=@(Read-StructureFile $output $format)
        Assert (@($tree | Where-Object { $_.Path.Replace('\','/') -eq 'live/src/components/Button.tsx' }).Count -eq 1) ($format + ' round trip preserves descendants')
        Assert (@($tree | Where-Object { $_.Path.Replace('\','/') -eq 'live/empty' -and $_.IsDir }).Count -eq 1) ($format + ' preserves empty directories')
    }
    $yaml=Join-Path $scratch 'scalar.yaml'
    $content="first`n  indented`n# literal comment`n`nlast`n"
    $contentEntries=@([pscustomobject]@{Path='text.txt';IsDir=$false;Content=$content;HasContent=$true})
    Write-Fixture $yaml (ConvertTo-TreeYaml $contentEntries "O'Brien root")
    $read=@(Read-StructureFile $yaml yaml)
    Assert ($read[1].Content -ceq $content) 'YAML writer/reader preserves multiline content and indentation'
    foreach ($value in @('true','null','123','back\slash','double"quote',"O'Brien",'',"snowman $([char]0x2603)")) {
        Write-Fixture $yaml ('name: ' + (ConvertTo-TreeYamlScalar 'text.txt') + "`ntype: file`ncontent: " + (ConvertTo-TreeYamlScalar $value))
        $read=@(Read-StructureFile $yaml yaml)
        Assert ($read[0].Content -ceq $value) ('YAML preserves quoted scalar: ' + $value)
    }
    Write-Fixture $yaml "- name: text.txt`n  type: file`n  content: |-`n    first`n      indented`n    # literal`n`n    last"
    $read=@(Read-StructureFile $yaml yaml)
    Assert ($read[0].Content -ceq "first`n  indented`n# literal`n`nlast") 'YAML literal block preserves blank lines, comments, and relative indentation'
    Assert-RejectedYaml "name: a`nname: b" 'YAML duplicate keys fail explicitly'
    Assert-RejectedYaml "name: a`nunknown: x" 'Unsupported YAML keys fail explicitly'
    Assert-RejectedYaml "name: &anchor value" 'Unsupported YAML anchors fail explicitly'
    Assert-RejectedYaml "name: a`ncontent: >`n  folded" 'Unsupported YAML folded blocks fail explicitly'
    Assert-RejectedYaml "name: a`n children: []`n   broken" 'Invalid YAML indentation is rejected'
    $emptyRoot=Join-Path $scratch 'empty-root'; $null=New-Item -ItemType Directory -Path $emptyRoot
    foreach ($format in @('json','yaml')) {
        $output=Join-Path $scratch ('empty.'+$format)
        $code=Run-Backend export @{RootPath=$emptyRoot;OutputFile=$output;OutputFormat=$format;Ci=$true}
        Assert ($code -eq 0) ($format + ' supports empty root exports')
        $read=@(Read-StructureFile $output $format)
        Assert ($read.Count -eq 1 -and $read[0].IsDir) ($format + ' preserves an empty root directory')
    }

    # Exercise the permanent action adapter in a disposable toolkit copy.
    $copy=Join-Path $scratch "toolkit O'Brien"
    $null=New-Item -ItemType Directory -Path $copy
    Copy-Item -LiteralPath (Join-Path $repo 'src'),(Join-Path $repo 'bin') -Destination $copy -Recurse
    Write-Fixture $structure '- hello.txt'
    $sentinel=Join-Path $scratch 'injected.txt'
    $env:SV_FILE=$structure; $env:SV_FMT='dash'; $env:SV_SRC='manual'
    $env:SV_NAME="x'; Set-Content -LiteralPath '$sentinel' -Value injected; #"
    $code=Run-Backend wrapper_actions @{Action='StoreSave'} $copy
    Assert ($code -eq 0 -and -not (Test-Path -LiteralPath $sentinel)) 'Library display name is stored as data and cannot execute PowerShell'
    $env:RN_NUM="1; Set-Content -LiteralPath '$sentinel' -Value injected"
    $code=Run-Backend wrapper_actions @{Action='StoreSelectRename'} $copy
    Assert ($code -eq 2 -and -not (Test-Path -LiteralPath $sentinel)) 'Picker input cannot execute PowerShell'
    $env:IMP_FILE=$structure; $env:IMP_FORMAT='dash'; $env:OUT_TYPE='importable'; $env:SPACE_UNIT='2'; $env:OUT_FILE=Join-Path $scratch "O'Brien converted.txt"
    $code=Run-Backend wrapper_actions @{Action='ConvertImport'} $copy
    Assert ($code -eq 0 -and (Confirm-StructureFormat $env:OUT_FILE dash)) 'Import adapter safely accepts apostrophes in input and output paths'
    & (Join-Path $copy 'bin/security.bat') VALIDATE_FILE $structure dash | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'Security wrapper supports a toolkit and structure path containing apostrophes'
    & (Join-Path $copy 'bin/detection.bat') ANALYSE $structure dash | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'Analysis wrapper invokes permanent backend with apostrophe paths'
    $merged=Join-Path $scratch "O'Brien merged.txt"
    & (Join-Path $copy 'bin/detection.bat') BUILD_TREE $structure dash $structure dash union $merged | Out-Null
    Assert ($LASTEXITCODE -eq 0 -and (Confirm-StructureFormat $merged dash)) 'Detection merge wrapper invokes permanent backend safely'
    Write-Host ('All {0} checks passed on PowerShell {1}.' -f $script:checks,$PSVersionTable.PSVersion)
} finally {
    foreach ($name in @('SV_FILE','SV_FMT','SV_SRC','SV_NAME','RN_NUM','IMP_FILE','IMP_FORMAT','OUT_TYPE','SPACE_UNIT','OUT_FILE')) { [Environment]::SetEnvironmentVariable($name,$null,'Process') }
    $resolved=[IO.Path]::GetFullPath($scratch)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if ($resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -match '^ptu-formats-[a-f0-9]{32}$') { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
