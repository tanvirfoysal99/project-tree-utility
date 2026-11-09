[CmdletBinding()]
param([string]$Binary, [switch]$CheckHelp, [switch]$CheckExamples)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$cliSource=[IO.File]::ReadAllText((Join-Path $projectRoot 'src/cli.rs'))
$reference=[IO.File]::ReadAllText((Join-Path $projectRoot 'docs/CLI.md'))
$specStart=$cliSource.IndexOf('fn specification(')
$specEnd=$cliSource.IndexOf('fn alias(')
if($specStart -lt 0 -or $specEnd -le $specStart){throw 'Cannot locate CLI specification'}
$specification=$cliSource.Substring($specStart,$specEnd-$specStart)
$commands=[regex]::Matches($specification,'"(?<command>[a-z]+)"\s*=>\s*\(\s*"(?<allowed>[^"]*)"\s*,\s*"(?<positional>[^"]*)"\s*,?\s*\)')
if($commands.Count -ne 12){throw 'Command inventory changed; update the complete reference and checker count'}
$bindings=0
foreach($command in $commands){
    $name=$command.Groups['command'].Value
    $start='<!-- command:'+$name+' -->'
    $end='<!-- /command:'+$name+' -->'
    $first=$reference.IndexOf($start)
    $last=$reference.IndexOf($end)
    if($first -lt 0 -or $last -le $first){throw "Missing complete command section: $name"}
    $section=$reference.Substring($first,$last-$first)
    foreach($option in ($command.Groups['allowed'].Value -split '\s+' | Where-Object { $_ })){
        $literal='`--'+$option+'`'
        if(-not $section.Contains($literal)){throw "Undocumented $name option: --$option"}
        $bindings++
    }
    foreach($term in '**Exit:**','Positional'){
        if($section.IndexOf($term,[StringComparison]::OrdinalIgnoreCase) -lt 0){throw "Missing $name $term reference"}
    }
}
$formatsSource=[IO.File]::ReadAllText((Join-Path $projectRoot 'src/formats.rs'))
$renderStart=$formatsSource.IndexOf('pub fn render(')
$renderEnd=$formatsSource.IndexOf('fn render_tree(')
$render=$formatsSource.Substring($renderStart,$renderEnd-$renderStart)
$outputNames=@()
foreach($arm in [regex]::Matches($render,'(?m)^\s*(?<keys>"[a-z]+"(?:\s*\|\s*"[a-z]+")*)\s*=>')){
    foreach($value in [regex]::Matches($arm.Groups['keys'].Value,'"([a-z]+)"')){$outputNames += $value.Groups[1].Value}
}
$outputNames=@($outputNames | Sort-Object -Unique)
if($outputNames.Count -ne 8){throw 'Output format inventory changed; update the complete format table'}
foreach($value in $outputNames){if(-not $reference.Contains(('`'+$value+'`'))){throw "Undocumented output value: $value"}}
$parseStart=$formatsSource.IndexOf('pub fn parse(')
$parseEnd=$formatsSource.IndexOf('fn yaml_value(')
$parseSource=$formatsSource.Substring($parseStart,$parseEnd-$parseStart)
$inputNames=@()
foreach($arm in [regex]::Matches($parseSource,'(?m)^\s*(?<keys>"[a-z]+"(?:\s*\|\s*"[a-z]+")*)\s*=>')){
    foreach($value in [regex]::Matches($arm.Groups['keys'].Value,'"([a-z]+)"')){$inputNames += $value.Groups[1].Value}
}
$inputNames=@($inputNames | Sort-Object -Unique)
if($inputNames.Count -ne 7){throw 'Input format inventory changed; update the full input-format table'}
foreach($value in $inputNames){if(-not $reference.Contains(('`'+$value+'`'))){throw "Undocumented input value: $value"}}
$aliasSource=$cliSource.Substring($specEnd,$cliSource.IndexOf('impl Options')-$specEnd)
$aliasCount=0
foreach($arm in [regex]::Matches($aliasSource,'(?m)^\s*(?<keys>"[a-z-]+"(?:\s*\|\s*"[a-z-]+")*)\s*=>\s*"(?<canonical>[a-z-]+)"')){
    foreach($value in [regex]::Matches($arm.Groups['keys'].Value,'"([a-z-]+)"')){
        $alias=$value.Groups[1].Value
        if($alias -ne $arm.Groups['canonical'].Value){
            if($reference.IndexOf($alias,[StringComparison]::OrdinalIgnoreCase) -lt 0){throw "Undocumented compatibility alias: $alias"}
            $aliasCount++
        }
    }
}

function Get-HeadingIds([string]$Content){
    $seen=@{}; $ids=@(); $fenceCharacter=$null; $fenceLength=0
    foreach($line in ($Content -split '\r?\n')){
        $fence=[regex]::Match($line,'^\s{0,3}(`{3,}|~{3,})')
        if($fence.Success){
            $mark=$fence.Groups[1].Value
            if($null -eq $fenceCharacter){$fenceCharacter=$mark.Substring(0,1);$fenceLength=$mark.Length}
            elseif($mark.StartsWith($fenceCharacter) -and $mark.Length -ge $fenceLength){$fenceCharacter=$null}
            continue
        }
        if($null -ne $fenceCharacter){continue}
        $heading=[regex]::Match($line,'^#{1,6}\s+(.+?)\s*#*\s*$')
        if($heading.Success){
            $slug=$heading.Groups[1].Value.ToLowerInvariant().Replace('`','')
            $slug=[regex]::Replace($slug,'[^\p{L}\p{N}_ -]','').Replace(' ','-')
            if($seen.ContainsKey($slug)){$seen[$slug]++;$ids+=($slug+'-'+$seen[$slug])}else{$seen[$slug]=0;$ids+=$slug}
        }
    }
    return $ids
}

$documents=@(Get-ChildItem -LiteralPath $projectRoot -File -Filter '*.md')+@(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'docs'),(Join-Path $projectRoot 'tests') -File -Filter '*.md')
$linkCount=0
foreach($document in $documents){
    $body=[IO.File]::ReadAllText($document.FullName)
    foreach($link in [regex]::Matches($body,'\]\(([^)]+)\)')){
        $target=$link.Groups[1].Value
        if($target -match '^[a-z][a-z0-9+.-]*://'){continue}
        $parts=$target -split '#',2
        $file=if($parts[0]){[IO.Path]::GetFullPath((Join-Path $document.DirectoryName $parts[0]))}else{$document.FullName}
        if(-not(Test-Path -LiteralPath $file -PathType Leaf)){throw "Broken link in $($document.Name): $target"}
        if($parts.Count -eq 2 -and $parts[1] -and [IO.Path]::GetExtension($file) -eq '.md'){
            $fragment=[Uri]::UnescapeDataString($parts[1])
            if($fragment -notin @(Get-HeadingIds ([IO.File]::ReadAllText($file)))){throw "Broken heading link in $($document.Name): $target"}
        }
        $linkCount++
    }
}

if($CheckHelp -or $CheckExamples){
    if(-not $Binary){$name=if([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT){'ptu.exe'}else{'ptu'};$Binary=Join-Path $projectRoot ('target/release/'+$name)}
    $Binary=(Resolve-Path -LiteralPath $Binary).Path
}
if($CheckHelp){
    foreach($command in $commands){
        $name=$command.Groups['command'].Value
        $output=@(& $Binary $name --help)
        if($LASTEXITCODE -ne 0){throw "Documented command has failing help: $name"}
        $helpText=$output -join "`n"
        foreach($option in ($command.Groups['allowed'].Value -split '\s+' | Where-Object { $_ })){
            if(-not $helpText.Contains('--'+$option)){throw "Help omits $name option: --$option"}
        }
    }
}
if($CheckExamples){
    $fixture=Join-Path $projectRoot ('target/docs-examples-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $fixture | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'examples') -Destination $fixture -Recurse
    Push-Location $fixture
    try {
        & $Binary scaffold --structure ./examples/layout.txt --format dash --target ./demo-work --project demo --dry-run
        if($LASTEXITCODE -ne 0 -or (Test-Path ./demo-work)){throw 'Documented dry-run example failed or wrote the project'}
        & $Binary scaffold --structure ./examples/layout.txt --format dash --target ./demo-work --project demo
        if($LASTEXITCODE -ne 0){throw 'Documented scaffold example failed'}
        & $Binary verify --live ./demo-work/demo --structure ./examples/layout.txt --format dash --ignore-file ./examples/verify.treeignore
        if($LASTEXITCODE -ne 0){throw 'Documented verification example failed'}
        & $Binary export --root ./demo-work/demo --format treesym --output ./demo-tree.txt --max-depth 0 --exclude _creation_log.txt
        if($LASTEXITCODE -ne 0){throw 'Documented tree export failed'}
        & $Binary import --structure ./demo-tree.txt --format treesym --output ./converted.json --output-format json
        if($LASTEXITCODE -ne 0){throw 'Documented tree conversion failed'}
    } finally { Pop-Location }
    Write-Output "Documentation example fixture: $fixture"
}
Write-Output "PASS: $($commands.Count) commands, $bindings option bindings, $($inputNames.Count) input names, $($outputNames.Count) output names, $aliasCount renamed aliases, $linkCount local links/anchors"
