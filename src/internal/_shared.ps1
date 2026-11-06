# =============================================================
#  _shared.ps1
#  Shared Library - Project Tree Utility
#
#  Sourced by every subcommand. Never run directly.
#  Provides: format detection, parsing, emoji mapping,
#            path safety, file stubs, VBScript runner,
#            and output helpers.
#
#  Calling convention from .bat files:
#    powershell -ExecutionPolicy Bypass -Command
#      ". '$sharedPs1'; Invoke-SomeFunction -Param value"
# =============================================================

# ─────────────────────────────────────────────────────────────
# SECTION 1: Format Detection
# ─────────────────────────────────────────────────────────────

function Get-StructureFormat {
    param([string]$FilePath)
    $lines = @(Get-Content -LiteralPath $FilePath -Encoding UTF8 -ErrorAction Stop |
        Where-Object { $_.Trim() -and -not $_.TrimStart().StartsWith('#') })
    if (-not $lines.Count) { return 'empty' }
    $ext = [IO.Path]::GetExtension($FilePath).ToLowerInvariant()
    if ($ext -eq '.json') { return 'json' }
    if ($ext -in @('.yaml','.yml')) { return 'yaml' }
    $first = $lines[0].TrimStart()
    if ($first -match '^[\[{]') { return 'json' }
    if ($first -match '^(?:-\s+)?(?:name|path|type|children|entries)\s*:' -or $first -eq '-') { return 'yaml' }
    if (@($lines | Where-Object { $_ -match '[\u251c\u2514]' }).Count) { return 'treesym' }
    if (@($lines | Where-Object { $_ -match '^-+\s+\S' }).Count -eq $lines.Count) { return 'dash' }
    $tabs = @($lines | Where-Object { $_ -match '^\t+\S' }).Count
    $spaces = @($lines | Where-Object { $_ -match '^ +\S' }).Count
    if ($tabs -and $spaces) { return 'unknown' }
    if ($tabs) { return 'tab' }
    if ($spaces) { return 'space' }
    # A flat list is valid in both tab and space layouts: do not guess.
    return 'unknown'
}

function Confirm-StructureFormat {
    param([string]$FilePath, [string]$Format, [int]$SpaceUnit = 2)
    try { $null = Read-StructureFile $FilePath $Format $SpaceUnit; return $true }
    catch { return $false }
}
# ─────────────────────────────────────────────────────────────
# SECTION 2: Structure Parser
# ─────────────────────────────────────────────────────────────

function Parse-StructureLine {
    param(
        [string]$Line,
        [string]$Format,
        [int]$SpaceUnit  = 2,
        [bool]$IsFirst   = $false,
        [bool]$HasRoot   = $false
    )
    switch ($Format) {
        'dash' {
            if ($Line -match '^(-+)\s*(.+)$') {
                $decorated = Split-TreeNodeDecorators -Text $Matches[2].Trim()
                $name = $decorated.Path.Trim()
                $contentDirective = ''
                $contentDirective = $decorated.ContentDirective
                return @{ Depth = $Matches[1].Length; Name = $name; IsDir = $name.EndsWith('/'); Template = $decorated.Template; ContentDirective = $contentDirective }
            }
            return $null
        }
        'tab' {
            if ($Line -match '^(\t*)(.+)$') {
                $decorated = Split-TreeNodeDecorators -Text $Matches[2].Trim()
                $name = $decorated.Path.Trim()
                if (-not $name) { return $null }
                $contentDirective = ''
                $contentDirective = $decorated.ContentDirective
                return @{ Depth = $Matches[1].Length + 1; Name = $name; IsDir = $name.EndsWith('/'); Template = $decorated.Template; ContentDirective = $contentDirective }
            }
            return $null
        }
        'treesym' {
            $clean = $Line -replace [char]0x2502, ' '
            if ($clean -match '^(\s*)([\u251C\u2514][\u2500\-]*\s*)?(.*)$') {
                $indent       = $Matches[1].Length
                $hasConnector = ($null -ne $Matches[2] -and $Matches[2].Length -gt 0)
                $decorated    = Split-TreeNodeDecorators -Text $Matches[3].Trim()
                $name         = $decorated.Path.Trim()
                if (-not $name) { return $null }
                if ($IsFirst -and -not $hasConnector) { $depth = 1 }
                else { $depth = [math]::Floor($indent / 4) + $(if ($HasRoot) { 2 } else { 1 }) }
                $contentDirective = ''
                $contentDirective = $decorated.ContentDirective
                return @{ Depth = $depth; Name = $name; IsDir = $name.EndsWith('/'); Template = $decorated.Template; ContentDirective = $contentDirective }
            }
            return $null
        }
        'space' {
            if ($Line -match '^(\s*)(.+)$') {
                $decorated = Split-TreeNodeDecorators -Text $Matches[2].Trim()
                $name = $decorated.Path.Trim()
                if (-not $name) { return $null }
                if ($SpaceUnit -le 0) { $SpaceUnit = 2 }
                $depth = [math]::Floor($Matches[1].Length / $SpaceUnit) + 1
                $contentDirective = ''
                $contentDirective = $decorated.ContentDirective
                return @{ Depth = $depth; Name = $name; IsDir = $name.EndsWith('/'); Template = $decorated.Template; ContentDirective = $contentDirective }
            }
            return $null
        }
    }
    return $null
}

function Assert-StructureEntries {
    param([AllowEmptyCollection()][object[]]$Entries)
    if (-not $Entries.Count) { throw 'Structure contains no entries.' }
    $paths = @{}
    foreach ($entry in $Entries) {
        $location = if ($entry.Line) { 'line ' + $entry.Line } else { 'node ' + $entry.Path }
        if (Test-DangerousName $entry.Path) { throw ('Invalid path at ' + $location + ': ' + $entry.Path) }
        $path = $entry.Path.Replace('/','\').TrimEnd('\')
        if ($paths.ContainsKey($path)) { throw ('Duplicate path at ' + $location + ': ' + $path) }
        $entry.Path = $path
        $paths[$path] = $entry
    }
    foreach ($entry in $Entries) {
        $parent = [IO.Path]::GetDirectoryName($entry.Path)
        while ($parent) {
            if ($paths.ContainsKey($parent) -and -not $paths[$parent].IsDir) { throw ('File cannot be a parent: ' + $parent) }
            $parent = [IO.Path]::GetDirectoryName($parent)
        }
    }
}

function Read-StructureFile {
    param([string]$FilePath, [string]$Format, [int]$SpaceUnit = 2, [string]$TemplateName = '')
    if ($Format -notin @('template','json','yaml','dash','tab','space','treesym')) { throw ('Unknown structure format: ' + $Format) }
    if ($SpaceUnit -lt 1) { throw 'Spaces per indentation level must be positive.' }
    if ($Format -in @('template','json','yaml')) {
        $entries = @()
        switch ($Format) {
            template {
                $preset = Get-TemplatePreset $TemplateName
                if (-not $preset) { throw ('Unknown template: ' + $TemplateName) }
                $entries = @(ConvertFrom-TreeNode -Node $preset.Entries -Depth 1 -ParentPath '')
            }
            json { $entries = @(ConvertFrom-TreeJson $FilePath) }
            yaml { $entries = @(ConvertFrom-TreeYaml $FilePath) }
        }
        Assert-StructureEntries $entries
        return $entries
    }
    $lines = @(Get-Content -LiteralPath $FilePath -Encoding UTF8 -ErrorAction Stop)
    $entries = New-Object 'System.Collections.Generic.List[object]'
    $stack = @{}
    $hasRoot = $false
    for ($i=0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if (-not $line.Trim() -or $line.TrimStart().StartsWith('#')) { continue }
        $first = $entries.Count -eq 0
        $valid = switch ($Format) {
            dash { $line -match '^-+\s+\S' }
            tab { $line -match '^\t*[^\s].*' }
            space { $line -match '^( *)(\S.*)$' -and ($Matches[1].Length % $SpaceUnit -eq 0) }
            treesym {
                if ($first -and $line -notmatch '[\u251c\u2514]') { $hasRoot=$true; $true }
                else { $clean=$line.Replace([string][char]0x2502,' '); $clean -match '^( *)(?:[\u251c\u2514][\u2500-]{2,})\s+\S' -and ($Matches[1].Length % 4 -eq 0) }
            }
        }
        if (-not $valid) { throw ('Invalid ' + $Format + ' entry or indentation at line ' + ($i+1)) }
        $parsed = Parse-StructureLine $line $Format $SpaceUnit $first $hasRoot
        if (-not $parsed) { throw ('Unparseable entry at line ' + ($i+1)) }
        if ($parsed.Name.EndsWith('\')) { $parsed.IsDir=$true; $parsed.Name=$parsed.Name.TrimEnd('\')+'/' }
        # Check the untrimmed path too: parsing must not conceal invalid suffixes.
        $rawName = switch ($Format) {
            dash { $line -replace '^-+\s+','' }
            tab { $line.TrimStart([char]9) }
            space { $line.TrimStart(' ') }
            treesym { $line -replace '^[\s\u2502]*[\u251c\u2514]?[\u2500-]*\s*','' }
        }
        $rawName = ($rawName -split '\s+@(?:content|content64|template):',2)[0]
        if (Test-DangerousName $rawName.TrimEnd('/')) { throw ('Invalid name at line ' + ($i+1) + ': ' + $rawName) }
        foreach ($key in @($stack.Keys)) { if ($key -ge $parsed.Depth) { $stack.Remove($key) } }
        $parent = $null
        if ($parsed.Depth -gt 1) {
            if (-not $stack.ContainsKey($parsed.Depth-1)) { throw ('Missing parent or skipped depth at line ' + ($i+1)) }
            $parent=$stack[$parsed.Depth-1]
            if (-not $parent.IsDir) {
                if ($Format -eq 'treesym') { $parent.IsDir=$true; $parent.Name=$parent.Name.TrimEnd('/')+'/' }
                else { throw ('File cannot have children at line ' + ($i+1)) }
            }
        }
        if ($first -and $hasRoot) { $parsed.IsDir=$true; $parsed.Name=$parsed.Name.TrimEnd('/')+'/' }
        $parsed.Path = if ($parent) { Join-Path $parent.Path $parsed.Name.TrimEnd('/') } else { $parsed.Name.TrimEnd('/') }
        $parsed.Line=$i+1
        $entry=[pscustomobject]$parsed
        $stack[$parsed.Depth]=$entry
        $entries.Add($entry)
    }
    Assert-StructureEntries $entries.ToArray()
    return $entries.ToArray()
}
function Get-Emoji {
    param([System.IO.FileSystemInfo]$Item)
    if (-not $Item.PSIsContainer) {
        $ext = $Item.Extension.ToLower()
        $map = @{
            '.tsx'=0x269B; '.jsx'=0x269B;
            '.ts'=0x1F4DC; '.js'=0x1F4DC; '.mjs'=0x1F4DC; '.cjs'=0x1F4DC;
            '.css'=0x1F3A8; '.scss'=0x1F3A8; '.sass'=0x1F3A8; '.less'=0x1F3A8;
            '.html'=0x1F310; '.htm'=0x1F310; '.hbs'=0x1F310; '.ejs'=0x1F310;
            '.json'=0x1F4CB; '.jsonc'=0x1F4CB;
            '.yaml'=0x2699; '.yml'=0x2699; '.toml'=0x2699; '.ini'=0x2699; '.cfg'=0x2699;
            '.env'=0x1F512; '.lock'=0x1F512;
            '.md'=0x1F4D6; '.mdx'=0x1F4D6;
            '.txt'=0x1F4C4; '.log'=0x1F4C4; '.csv'=0x1F4C4;
            '.png'=0x1F5BC; '.jpg'=0x1F5BC; '.jpeg'=0x1F5BC; '.gif'=0x1F5BC; '.webp'=0x1F5BC;
            '.svg'=0x1F3F4; '.ico'=0x1F3F4;
            '.woff'=0x1F524; '.woff2'=0x1F524; '.ttf'=0x1F524; '.otf'=0x1F524;
            '.sh'=0x1F4BB; '.bat'=0x1F4BB; '.ps1'=0x1F4BB;
            '.py'=0x1F40D; '.rs'=0x1F980; '.go'=0x1F4A7;
            '.sql'=0x1F5C4; '.db'=0x1F5C4;
            '.pdf'=0x1F4D5; '.zip'=0x1F4E6; '.tar'=0x1F4E6; '.gz'=0x1F4E6;
            '.wasm'=0x1F9E9; '.prisma'=0x1F5C4;
            '.graphql'=0x1F517; '.gql'=0x1F517;
        }
        if ($map.ContainsKey($ext)) { return [char]::ConvertFromUtf32($map[$ext]) }
        return [char]::ConvertFromUtf32(0x1F4C4)
    }
    $n = $Item.Name.ToLower()
    $folderMap = @{
        'components'=0x269B; 'component'=0x269B; 'ui'=0x269B; 'elements'=0x269B;
        'pages'=0x1F4F1; 'page'=0x1F4F1; 'views'=0x1F4F1; 'view'=0x1F4F1; 'screens'=0x1F4F1;
        'layouts'=0x1F4D0; 'layout'=0x1F4D0; 'templates'=0x1F4D0;
        'assets'=0x1F4E6; 'static'=0x1F4E6; 'public'=0x1F4E6;
        'images'=0x1F5BC; 'img'=0x1F5BC; 'imgs'=0x1F5BC; 'photos'=0x1F5BC;
        'utils'=0x1F527; 'util'=0x1F527; 'helpers'=0x1F527; 'helper'=0x1F527; 'lib'=0x1F527;
        'services'=0x1F4E1; 'service'=0x1F4E1; 'api'=0x1F4E1; 'apis'=0x1F4E1;
        'context'=0x1F9E0; 'store'=0x1F9E0; 'state'=0x1F9E0; 'redux'=0x1F9E0;
        'config'=0x2699; 'settings'=0x2699; 'env'=0x2699;
        'tests'=0x1F9EA; 'test'=0x1F9EA; '__tests__'=0x1F9EA; 'spec'=0x1F9EA;
        'src'=0x1F4C2; 'source'=0x1F4C2; 'app'=0x1F4C2;
        'hooks'=0x1FA9D; 'hook'=0x1FA9D;
        'middleware'=0x1F6E1; 'middlewares'=0x1F6E1;
        'workers'=0x1F9F5; 'worker'=0x1F9F5;
        'routes'=0x1F9ED; 'route'=0x1F9ED; 'router'=0x1F9ED;
    }
    if ($folderMap.ContainsKey($n)) { return [char]::ConvertFromUtf32($folderMap[$n]) }
    return [char]::ConvertFromUtf32(0x1F4C1)
}

function Get-TreeEmoji {
    param(
        [string]$Name,
        [string]$Type
    )

    if ($Type -eq 'tree') {
        $n = $Name.ToLower()
        $folderMap = @{
            'components'=0x269B; 'component'=0x269B; 'ui'=0x269B; 'elements'=0x269B
            'pages'=0x1F4F1; 'page'=0x1F4F1; 'views'=0x1F4F1; 'view'=0x1F4F1; 'screens'=0x1F4F1
            'layouts'=0x1F4D0; 'layout'=0x1F4D0; 'templates'=0x1F4D0
            'assets'=0x1F4E6; 'static'=0x1F4E6; 'public'=0x1F4E6
            'images'=0x1F5BC; 'img'=0x1F5BC; 'imgs'=0x1F5BC; 'photos'=0x1F5BC
            'utils'=0x1F527; 'util'=0x1F527; 'helpers'=0x1F527; 'helper'=0x1F527; 'lib'=0x1F527
            'services'=0x1F4E1; 'service'=0x1F4E1; 'api'=0x1F4E1; 'apis'=0x1F4E1
            'context'=0x1F9E0; 'store'=0x1F9E0; 'state'=0x1F9E0; 'redux'=0x1F9E0
            'config'=0x2699; 'settings'=0x2699; 'env'=0x2699
            'tests'=0x1F9EA; 'test'=0x1F9EA; '__tests__'=0x1F9EA; 'spec'=0x1F9EA
            'src'=0x1F4C2; 'source'=0x1F4C2; 'app'=0x1F4C2
            'hooks'=0x1FA9D; 'hook'=0x1FA9D
            'middleware'=0x1F6E1; 'middlewares'=0x1F6E1
            'workers'=0x1F9F5; 'worker'=0x1F9F5
            'routes'=0x1F9ED; 'route'=0x1F9ED; 'router'=0x1F9ED
        }
        if ($folderMap.ContainsKey($n)) { return [char]::ConvertFromUtf32($folderMap[$n]) }
        return [char]::ConvertFromUtf32(0x1F4C1)
    }

    $ext = [System.IO.Path]::GetExtension($Name).ToLower()
    $fileMap = @{
        '.tsx'=0x269B; '.jsx'=0x269B
        '.ts'=0x1F4DC; '.js'=0x1F4DC; '.mjs'=0x1F4DC; '.cjs'=0x1F4DC
        '.css'=0x1F3A8; '.scss'=0x1F3A8; '.sass'=0x1F3A8; '.less'=0x1F3A8
        '.html'=0x1F310; '.htm'=0x1F310; '.hbs'=0x1F310; '.ejs'=0x1F310
        '.json'=0x1F4CB; '.jsonc'=0x1F4CB
        '.yaml'=0x2699; '.yml'=0x2699; '.toml'=0x2699; '.ini'=0x2699; '.cfg'=0x2699
        '.env'=0x1F512; '.lock'=0x1F512
        '.md'=0x1F4D6; '.mdx'=0x1F4D6
        '.txt'=0x1F4C4; '.log'=0x1F4C4; '.csv'=0x1F4C4
        '.png'=0x1F5BC; '.jpg'=0x1F5BC; '.jpeg'=0x1F5BC; '.gif'=0x1F5BC; '.webp'=0x1F5BC
        '.svg'=0x1F3F4; '.ico'=0x1F3F4
        '.woff'=0x1F524; '.woff2'=0x1F524; '.ttf'=0x1F524; '.otf'=0x1F524
        '.sh'=0x1F4BB; '.bat'=0x1F4BB; '.ps1'=0x1F4BB
        '.py'=0x1F40D; '.rs'=0x1F980; '.go'=0x1F4A7
        '.sql'=0x1F5C4; '.db'=0x1F5C4
        '.pdf'=0x1F4D5; '.zip'=0x1F4E6; '.tar'=0x1F4E6; '.gz'=0x1F4E6
        '.wasm'=0x1F9E9; '.prisma'=0x1F5C4
        '.graphql'=0x1F517; '.gql'=0x1F517
    }
    if ($fileMap.ContainsKey($ext)) { return [char]::ConvertFromUtf32($fileMap[$ext]) }
    return [char]::ConvertFromUtf32(0x1F4C4)
}

# ─────────────────────────────────────────────────────────────
# SECTION 4: Path Safety
# ─────────────────────────────────────────────────────────────

function Test-SafePath {
    param([string]$CandidatePath, [string]$AllowedBase)
    try {
        $resolved    = [System.IO.Path]::GetFullPath($CandidatePath)
        $baseResolved = [System.IO.Path]::GetFullPath($AllowedBase).TrimEnd('\') + '\'
        if (-not $resolved.StartsWith($baseResolved, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
        # Check the destination and all existing ancestors, including the base.
        # Lexical containment alone cannot prevent writes through junctions.
        $cursor = $resolved
        while ($cursor) {
            try {
                $attributes = [System.IO.File]::GetAttributes($cursor)
                if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
            } catch [System.IO.FileNotFoundException] {
                # A missing leaf is normal when validating a planned write.
            } catch [System.IO.DirectoryNotFoundException] {
            }
            $parent = [System.IO.Path]::GetDirectoryName($cursor.TrimEnd('\'))
            if (-not $parent -or $parent -eq $cursor) { break }
            $cursor = $parent
        }
        return $true
    } catch {
        return $false
    }
}

function Resolve-SafeProjectRoot {
    param([string]$TargetBase, [string]$ProjectName)
    if ((Test-DangerousName $ProjectName) -or [string]::IsNullOrWhiteSpace($ProjectName) -or
        $ProjectName -in @('.', '..') -or
        $ProjectName -match '[\\/:\x00-\x1F*?"<>|]' -or
        $ProjectName -match '[. ]$' -or
        $ProjectName -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$') {
        throw 'Project name must be a valid single Windows directory name.'
    }
    $basePath = [System.IO.Path]::GetFullPath($TargetBase)
    $projectRoot = Join-Path $basePath $ProjectName
    if (-not (Test-SafePath -CandidatePath $projectRoot -AllowedBase $basePath)) {
        throw 'Project root is outside the target directory or crosses a reparse point.'
    }
    return $projectRoot
}

function Test-DangerousName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -match '^[\\/]' -or $Name -match '[\\/]{2}' -or $Name -match '[:\x00-\x1F*?"<>|]') { return $true }
    $parts = $Name.Replace('/','\').TrimEnd('\').Split('\')
    foreach ($part in $parts) {
        if (-not $part -or $part.Length -gt 255 -or $part -in @('.','..') -or $part -match '[. ]$') { return $true }
        # Windows also reserves the superscript digits 1, 2 and 3 in device names.
        $deviceStem = ($part -split '\.',2)[0].TrimEnd(' ')
        if ($deviceStem -match '^(CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|COM[1-9\u00b9\u00b2\u00b3]|LPT[1-9\u00b9\u00b2\u00b3])$') { return $true }
    }
    return $false
}

# ─────────────────────────────────────────────────────────────
# SECTION 5: File Stubs
# ─────────────────────────────────────────────────────────────

function Get-FileStub {
    param([string]$FileName, [string]$ProjectName, [string]$TemplateName = '')
    $ext  = [System.IO.Path]::GetExtension($FileName).ToLower()
    $base = [System.IO.Path]::GetFileNameWithoutExtension($FileName).ToLower()
    $nl   = [Environment]::NewLine
    $q    = [char]34
    switch ($FileName.ToLower()) {
        'readme.md'     { return ('# ' + $ProjectName + $nl + $nl + 'Scaffolded by Project Tree Utility.' + $nl) }
        'package.json'  { return ('{' + $nl + '  ' + $q + 'name' + $q + ': ' + $q + $ProjectName + $q + ',' + $nl + '  ' + $q + 'version' + $q + ': ' + $q + '0.0.1' + $q + ',' + $nl + '  ' + $q + 'private' + $q + ': true' + $nl + '}' + $nl) }
        'wrangler.toml' { return ('name = ' + $q + $ProjectName + $q + $nl + 'compatibility_date = ' + $q + '2024-01-01' + $q + $nl + 'main = ' + $q + 'src/index.ts' + $q + $nl) }
        '.gitignore'    { return ('node_modules/' + $nl + 'dist/' + $nl + '.wrangler/' + $nl + '.env' + $nl + '.env.local' + $nl + 'out/' + $nl + 'build/' + $nl) }
        'tsconfig.json' { return ('{' + $nl + '  ' + $q + 'compilerOptions' + $q + ': {' + $nl + '    ' + $q + 'target' + $q + ': ' + $q + 'ES2020' + $q + ',' + $nl + '    ' + $q + 'strict' + $q + ': true' + $nl + '  }' + $nl + '}' + $nl) }
    }
    if ($ext -like '.env*') { return ('# Environment variables for ' + $ProjectName + $nl) }
    switch ($ext) {
        '.ts'  {
            if ($base -eq 'index') { return ('// ' + $ProjectName + ' - entry point' + $nl + 'export {}' + $nl) }
            return ('export {}' + $nl)
        }
        { $_ -in '.tsx','.jsx' } {
            $comp = (Get-Culture).TextInfo.ToTitleCase($base)
            $lt = [char]60; $gt = [char]62
            return ('export default function ' + $comp + '() {' + $nl + '  return ' + $lt + 'div' + $gt + $comp + $lt + '/div' + $gt + ';' + $nl + '}' + $nl)
        }
        { $_ -in '.js','.mjs','.cjs' }        { return ('// ' + $FileName + $nl) }
        { $_ -in '.css','.scss','.sass','.less' } { return ('/* ' + $FileName + ' styles */' + $nl) }
        '.json'                                { return ('{}' + $nl) }
        { $_ -in '.yaml','.yml' }              { return ('# ' + $FileName + $nl) }
        '.sql'                                 { return ('-- ' + $FileName + $nl) }
        { $_ -in '.md','.mdx' }                { return ('# ' + $base + $nl) }
        '.prisma'                              { return ('// Prisma schema for ' + $ProjectName + $nl) }
        { $_ -in '.graphql','.gql' }           { return ('# GraphQL schema' + $nl) }
    }
    return ''
}

# ─────────────────────────────────────────────────────────────
# SECTION 6: Output Helpers
# ─────────────────────────────────────────────────────────────

function Format-FileSize {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N2} KB' -f ($Bytes / 1KB)) }
    return "$Bytes Bytes"
}

function Write-Banner {
    param([string]$Title, [int]$Width = 44)
    $sep = [string]::new([char]0x2500, $Width)
    Write-Host $sep
    Write-Host "  $Title"
    Write-Host $sep
}

# ─────────────────────────────────────────────────────────────
# SECTION 7: Tree Config / Templates / Structure Helpers
# ─────────────────────────────────────────────────────────────

function Get-TreeConfig {
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [string]$IgnoreFile = '',
        [string]$ExtraExclude = ''
    )

    $config = [pscustomobject]@{
        RootPath       = $RootPath
        IgnoreFile     = ''
        ExcludeFolders = @('node_modules','dist','.git','.wrangler','.next','.turbo','out','build')
        MaxDepth       = $null
        ShowMode       = $null
        Template       = ''
    }

    $candidateFiles = New-Object System.Collections.Generic.List[string]
    if ($IgnoreFile -and $IgnoreFile.Trim()) {
        $explicit = $IgnoreFile.Trim()
        if (-not [System.IO.Path]::IsPathRooted($explicit)) {
            $explicit = Join-Path $RootPath $explicit
        }
        if(-not (Test-Path -LiteralPath $explicit -PathType Leaf -ErrorAction Stop)){throw ('Specified ignore file not found: '+$explicit)}
        $candidateFiles.Add($explicit) | Out-Null
    }
    foreach ($name in @('.treeignore', '.treerc')) {
        $candidateFiles.Add((Join-Path $RootPath $name)) | Out-Null
    }

    foreach ($configPath in $candidateFiles) {
        if (-not (Test-Path -LiteralPath $configPath)) { continue }
        $config.IgnoreFile = $configPath
        $lines = Get-Content -LiteralPath $configPath -Encoding UTF8 -ErrorAction Stop
        foreach ($raw in $lines) {
            $line = $raw.Trim()
            if (-not $line -or $line.StartsWith('#') -or $line.StartsWith(';')) { continue }

            if ($line -match '^(?:exclude|ignore|skip)\s*[:=]\s*(.+)$') {
                $values = $Matches[1] -split '[,;]'
                foreach ($value in $values) {
                    $clean = $value.Trim().TrimEnd('/').TrimStart('/')
                    if ($clean -and $config.ExcludeFolders -notcontains $clean) {
                        $config.ExcludeFolders += $clean
                    }
                }
                continue
            }

            if ($line -match '^(?:maxdepth|depth)\s*[:=]\s*(\d+)$') {
                $config.MaxDepth = [int]$Matches[1]
                continue
            }

            if ($line -match '^(?:showmode|show)\s*[:=]\s*(all|folders|files)$') {
                $config.ShowMode = $Matches[1].ToLowerInvariant()
                continue
            }

            if ($line -match '^template\s*[:=]\s*(.+)$') {
                $config.Template = $Matches[1].Trim()
                continue
            }

            $cleanLine = $line.TrimEnd('/').TrimStart('/')
            if ($cleanLine -and $config.ExcludeFolders -notcontains $cleanLine) {
                $config.ExcludeFolders += $cleanLine
            }
        }
        break
    }

    if ($ExtraExclude -and $ExtraExclude.Trim()) {
        foreach ($entry in $ExtraExclude.Split(',')) {
            $clean = $entry.Trim()
            if ($clean -and $config.ExcludeFolders -notcontains $clean) {
                $config.ExcludeFolders += $clean
            }
        }
    }

    return $config
}

function Get-TemplatePresetCore {
    param([string]$Name)

    $key = ([string]$Name).Trim().ToLowerInvariant()
    if (-not $key) { return $null }

    $nl = [Environment]::NewLine
    $q  = [char]34

    switch ($key) {
        'react-vite' {
            return [pscustomobject]@{
                Name = 'react-vite'
                Entries = @(
                    [pscustomobject]@{ Path = 'src'; IsDir = $true }
                    [pscustomobject]@{ Path = 'src/main.tsx'; IsDir = $false; Content = 'import React from ' + $q + 'react' + $q + ';' + $nl + 'import ReactDOM from ' + $q + 'react-dom/client' + $q + ';' + $nl + 'import App from ' + $q + './App' + $q + ';' + $nl + 'import ' + $q + './index.css' + $q + ';' + $nl + $nl + 'ReactDOM.createRoot(document.getElementById(' + $q + 'root' + $q + ') as HTMLElement).render(' + $nl + '  <React.StrictMode>' + $nl + '    <App />' + $nl + '  </React.StrictMode>' + $nl + ');' + $nl }
                    [pscustomobject]@{ Path = 'src/App.tsx'; IsDir = $false; Content = 'export default function App() {' + $nl + '  return <main>Hello from React Vite</main>;' + $nl + '}' + $nl }
                    [pscustomobject]@{ Path = 'src/index.css'; IsDir = $false; Content = 'html, body, #root {' + $nl + '  margin: 0;' + $nl + '  min-height: 100%;' + $nl + '}' + $nl + 'body {' + $nl + '  font-family: system-ui, sans-serif;' + $nl + '}' + $nl }
                    [pscustomobject]@{ Path = 'index.html'; IsDir = $false; Content = '<!doctype html>' + $nl + '<html lang=' + $q + 'en' + $q + '>' + $nl + '<head>' + $nl + '  <meta charset=' + $q + 'UTF-8' + $q + ' />' + $nl + '  <meta name=' + $q + 'viewport' + $q + ' content=' + $q + 'width=device-width, initial-scale=1.0' + $q + ' />' + $nl + '  <title>React Vite App</title>' + $nl + '</head>' + $nl + '<body>' + $nl + '  <div id=' + $q + 'root' + $q + '></div>' + $nl + '  <script type=' + $q + 'module' + $q + ' src=' + $q + '/src/main.tsx' + $q + '></script>' + $nl + '</body>' + $nl + '</html>' + $nl }
                    [pscustomobject]@{ Path = 'package.json'; IsDir = $false; Content = '{' + $nl + '  ' + $q + 'name' + $q + ': ' + $q + 'react-vite-app' + $q + ',' + $nl + '  ' + $q + 'private' + $q + ': true,' + $nl + '  ' + $q + 'scripts' + $q + ': {' + $nl + '    ' + $q + 'dev' + $q + ': ' + $q + 'vite' + $q + ',' + $nl + '    ' + $q + 'build' + $q + ': ' + $q + 'vite build' + $q + $nl + '  }' + $nl + '}' + $nl }
                    [pscustomobject]@{ Path = 'vite.config.ts'; IsDir = $false; Content = 'import { defineConfig } from ' + $q + 'vite' + $q + ';' + $nl + 'export default defineConfig({});' + $nl }
                    [pscustomobject]@{ Path = 'tsconfig.json'; IsDir = $false; Content = '{' + $nl + '  ' + $q + 'compilerOptions' + $q + ': {' + $nl + '    ' + $q + 'target' + $q + ': ' + $q + 'ES2020' + $q + ',' + $nl + '    ' + $q + 'jsx' + $q + ': ' + $q + 'react-jsx' + $q + $nl + '  }' + $nl + '}' + $nl }
                    [pscustomobject]@{ Path = '.gitignore'; IsDir = $false; Content = 'node_modules/' + $nl + 'dist/' + $nl + '.env' + $nl + 'build/' + $nl }
                )
            }
        }
        'hono-worker' {
            return [pscustomobject]@{
                Name = 'hono-worker'
                Entries = @(
                    [pscustomobject]@{ Path = 'src'; IsDir = $true }
                    [pscustomobject]@{ Path = 'src/index.ts'; IsDir = $false; Content = 'import { Hono } from ' + $q + 'hono' + $q + ';' + $nl + $nl + 'const app = new Hono();' + $nl + 'app.get(' + $q + '/' + $q + ', (c) => c.text(' + $q + 'Hello from Hono Worker' + $q + '));' + $nl + $nl + 'export default app;' + $nl }
                    [pscustomobject]@{ Path = 'package.json'; IsDir = $false; Content = '{' + $nl + '  ' + $q + 'name' + $q + ': ' + $q + 'hono-worker' + $q + ',' + $nl + '  ' + $q + 'private' + $q + ': true,' + $nl + '  ' + $q + 'scripts' + $q + ': {' + $nl + '    ' + $q + 'dev' + $q + ': ' + $q + 'wrangler dev' + $q + ',' + $nl + '    ' + $q + 'deploy' + $q + ': ' + $q + 'wrangler deploy' + $q + $nl + '  }' + $nl + '}' + $nl }
                    [pscustomobject]@{ Path = 'wrangler.toml'; IsDir = $false; Content = 'name = ' + $q + 'hono-worker' + $q + $nl + 'main = ' + $q + 'src/index.ts' + $q + $nl + 'compatibility_date = ' + $q + '2024-01-01' + $q + $nl }
                    [pscustomobject]@{ Path = 'tsconfig.json'; IsDir = $false; Content = '{' + $nl + '  ' + $q + 'compilerOptions' + $q + ': {' + $nl + '    ' + $q + 'target' + $q + ': ' + $q + 'ES2020' + $q + ',' + $nl + '    ' + $q + 'strict' + $q + ': true' + $nl + '  }' + $nl + '}' + $nl }
                    [pscustomobject]@{ Path = '.gitignore'; IsDir = $false; Content = 'node_modules/' + $nl + 'dist/' + $nl + '.wrangler/' + $nl + '.env' + $nl + '.env.local' + $nl }
                )
            }
        }
        'monorepo-pnpm' {
            return [pscustomobject]@{
                Name = 'monorepo-pnpm'
                Entries = @(
                    [pscustomobject]@{ Path = 'apps'; IsDir = $true }
                    [pscustomobject]@{ Path = 'packages'; IsDir = $true }
                    [pscustomobject]@{ Path = 'apps/web'; IsDir = $true }
                    [pscustomobject]@{ Path = 'packages/ui'; IsDir = $true }
                    [pscustomobject]@{ Path = 'package.json'; IsDir = $false; Content = '{' + $nl + '  ' + $q + 'name' + $q + ': ' + $q + 'monorepo-pnpm' + $q + ',' + $nl + '  ' + $q + 'private' + $q + ': true' + $nl + '}' + $nl }
                    [pscustomobject]@{ Path = 'pnpm-workspace.yaml'; IsDir = $false; Content = 'packages:' + $nl + '  - apps/*' + $nl + '  - packages/*' + $nl }
                    [pscustomobject]@{ Path = '.gitignore'; IsDir = $false; Content = 'node_modules/' + $nl + 'dist/' + $nl + 'build/' + $nl }
                )
            }
        }
        default { return $null }
    }
}

function Split-TreeNodeDecorators {
    param([string]$Text)

    $result = [pscustomobject]@{
        Path = $Text.Trim()
        Template = ''
        Content = ''
        ContentDirective = ''
    }

    $base = $result.Path
    $directiveText = ''
    if ($base -match '^(.*?)(?:\s+(@.+))$') {
        $base = $Matches[1].Trim()
        $directiveText = $Matches[2].Trim()
    }

    if ($directiveText) {
        foreach ($token in ($directiveText -split '\s+(?=@)')) {
            $clean = $token.Trim()
            if (-not $clean) { continue }
            if ($clean -match '^@template:(.+)$') {
                $result.Template = $Matches[1].Trim()
            } elseif ($clean -match '^@content:(.*)$') {
                $result.Content = $Matches[1]
                $result.ContentDirective = $clean
            } elseif ($clean -match '^@content64:(.*)$') {
                $result.Content = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Matches[1]))
                $result.ContentDirective = $clean
            }
        }
    }

    $result.Path = $base
    return $result
}

function ConvertFrom-TreeNode {
    param(
        [Parameter(Mandatory = $true)]$Node,
        [int]$Depth = 1,
        [string]$ParentPath = ''
    )

    $entries = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Node) { throw ('Null tree node under ' + $ParentPath) }
    if ($Node -is [System.Collections.IDictionary]) { $Node = [pscustomobject]$Node }

    if (($Node -is [System.Array]) -or ($Node -is [System.Collections.IList]) -or ($Node -is [System.Collections.ICollection] -and -not ($Node -is [pscustomobject]))) {
        foreach ($child in $Node) {
            $nested = ConvertFrom-TreeNode -Node $child -Depth $Depth -ParentPath $ParentPath
            foreach ($entry in $nested) { $entries.Add($entry) | Out-Null }
        }
        return $entries
    }

    if ($Node -isnot [pscustomobject] -and $Node -isnot [string]) { throw ('Tree node must be an object or path string under ' + $ParentPath) }
    if ($Node -is [pscustomobject]) {
        foreach ($property in $Node.PSObject.Properties) {
            if ($property.Name -notin @('Name','Path','Type','IsDir','Children','Entries','Template','Content','ContentDirective')) { throw ('Unknown tree property: ' + $property.Name) }
            if ($property.Name -in @('Name','Path','Type','Template','Content','ContentDirective') -and $property.Value -isnot [string]) { throw ('Tree property must be a string: ' + $property.Name) }
            if ($property.Name -in @('Children','Entries') -and $null -ne $property.Value -and $property.Value -isnot [System.Array]) { throw ('Tree children must be an array under ' + $ParentPath) }
        }
        if ($Node.PSObject.Properties.Name -contains 'Children' -and $Node.PSObject.Properties.Name -contains 'Entries') { throw 'Use children or entries, not both.' }
        if ($Node.PSObject.Properties.Name -contains 'Name' -and $Node.PSObject.Properties.Name -contains 'Path') { throw 'Use name or path, not both.' }
    }
    $rawPath = ''
    foreach ($propName in @('Path','path','Name','name')) {
        if ($Node.PSObject.Properties.Name -contains $propName) {
            $rawPath = [string]$Node.$propName
            break
        }
    }
    if (-not $rawPath -and ($Node -is [string])) {
        $rawPath = [string]$Node
    }
    if (-not $rawPath) {
        $children = $null
        foreach ($propName in @('Children','children','Entries','entries')) {
            if ($Node.PSObject.Properties.Name -contains $propName) {
                $children = $Node.$propName
                break
            }
        }
        if ($children) {
            foreach ($child in $children) {
                $nested = ConvertFrom-TreeNode -Node $child -Depth $Depth -ParentPath $ParentPath
                foreach ($entry in $nested) { $entries.Add($entry) | Out-Null }
            }
        }
        if (-not $children) { throw ('Tree node requires a name, path, or nonempty children array under ' + $ParentPath) }
        return $entries
    }

    $rawName = ($rawPath -split '\s+@(?:content|content64|template):',2)[0]
    if (Test-DangerousName $rawName) { throw ('Invalid tree node path: ' + $rawName) }
    $decorated = Split-TreeNodeDecorators -Text $rawPath
    $hadTrailingSlash = $decorated.Path.Trim().EndsWith('/') -or $decorated.Path.Trim().EndsWith('\')
    $cleanPath = $decorated.Path.Trim().TrimEnd('/','\')
    if (-not $cleanPath) { return $entries }

    $typeHint = ''
    foreach ($propName in @('Type','type')) {
        if ($Node.PSObject.Properties.Name -contains $propName) {
            $typeHint = [string]$Node.$propName
            break
        }
    }
    if ($typeHint -and $typeHint -notmatch '^(file|blob|dir|directory|folder|tree)$') { throw ('Unknown tree node type: ' + $typeHint) }

    $hasChildren = $false
    foreach ($propName in @('Children','children','Entries','entries')) {
        if ($Node.PSObject.Properties.Name -contains $propName) {
            $hasChildren = $true
            break
        }
    }

    $explicitIsDir = $false
    if ($Node.PSObject.Properties.Name -contains 'IsDir') {
        if ($Node.IsDir -isnot [bool]) { throw 'IsDir must be a boolean.' }
        $explicitIsDir = $Node.IsDir
    }
    $isDir = $hasChildren -or $hadTrailingSlash -or $explicitIsDir -or ($typeHint -match '^(dir|directory|folder|tree)$')
    if (($typeHint -match '^(file|blob)$' -and $isDir) -or
        ($Node.PSObject.Properties.Name -contains 'IsDir' -and -not $Node.IsDir -and $isDir)) { throw ('Conflicting file/directory indicators: ' + $rawPath) }
    $fullPath = if ($ParentPath) { Join-Path $ParentPath $cleanPath } else { $cleanPath }
    $entry = [pscustomobject]@{
        Depth            = $Depth
        Name             = if ($isDir -and -not $cleanPath.EndsWith('/')) { $cleanPath + '/' } else { $cleanPath }
        Path             = $fullPath
        IsDir            = $isDir
        Template         = ''
        ContentDirective = ''
        Content          = ''
        HasContent       = $false
    }

    foreach ($propName in @('Template','template')) {
        if ($Node.PSObject.Properties.Name -contains $propName) {
            $entry.Template = [string]$Node.$propName
            break
        }
    }
    if (-not $entry.Template) { $entry.Template = $decorated.Template }

    foreach ($propName in @('ContentDirective','contentDirective')) {
        if ($Node.PSObject.Properties.Name -contains $propName) {
            $entry.ContentDirective = [string]$Node.$propName
            break
        }
    }
    if (-not $entry.ContentDirective -and $decorated.ContentDirective) {
        $entry.ContentDirective = $decorated.ContentDirective
    }

    foreach ($propName in @('Content','content')) {
        if ($Node.PSObject.Properties.Name -contains $propName) {
            $entry.Content = [string]$Node.$propName
            $entry.HasContent = $true
            break
        }
    }

    $entries.Add($entry) | Out-Null

    $children = $null
    foreach ($propName in @('Children','children','Entries','entries')) {
        if ($Node.PSObject.Properties.Name -contains $propName) {
            $children = $Node.$propName
            break
        }
    }
    if ($children) {
        foreach ($child in $children) {
            $nested = ConvertFrom-TreeNode -Node $child -Depth ($Depth + 1) -ParentPath $fullPath
            foreach ($entry2 in $nested) { $entries.Add($entry2) | Out-Null }
        }
    }

    return $entries
}

function ConvertFrom-TreeJson {
    param([Parameter(Mandatory = $true)][string]$FilePath)
    $raw = Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8 -ErrorAction Stop
    $data = $raw | ConvertFrom-Json
    return @(ConvertFrom-TreeNode -Node $data -Depth 1 -ParentPath '')
}

function ConvertFrom-TreeYaml {
    param([Parameter(Mandatory = $true)][string]$FilePath)
    . (Join-Path $PSScriptRoot '_yaml.ps1')
    $document = Read-TreeYamlDocument -FilePath $FilePath
    return @(ConvertFrom-TreeNode -Node $document -Depth 1 -ParentPath '')
}
function Get-StructureEntryContent {
    param(
        [Parameter(Mandatory = $true)][object]$Entry,
        [Parameter(Mandatory = $true)][string]$ProjectName,
        [string]$TemplateName = ''
    )

    if ($Entry.HasContent -or ($Entry.Content -and $Entry.Content.Trim())) { return $Entry.Content }
    if ($Entry.ContentDirective -and $Entry.ContentDirective.StartsWith('@content64:')) {
        return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Entry.ContentDirective.Substring(11)))
    }
    if ($Entry.ContentDirective -and $Entry.ContentDirective -match '^@content:(.*)$') {
        return $Matches[1]
    }

    $activeTemplate = $TemplateName
    if (-not $activeTemplate -and $Entry.Template) { $activeTemplate = $Entry.Template }
    if ($activeTemplate) {
        $preset = Get-TemplatePreset -Name $activeTemplate
        if ($preset -and $preset.Entries) {
            foreach ($candidate in $preset.Entries) {
                if ($candidate.Path.TrimEnd('/').ToLowerInvariant() -eq $Entry.Path.TrimEnd('/').ToLowerInvariant()) {
                    if ($candidate.Content) { return $candidate.Content }
                }
            }
        }
    }

    return (Get-FileStub -FileName ([System.IO.Path]::GetFileName($Entry.Path)) -ProjectName $ProjectName -TemplateName $activeTemplate)
}

# ─────────────────────────────────────────────────────────────
# SECTION 7: Exclude List Builder
# ─────────────────────────────────────────────────────────────

function ConvertTo-TreeNodeObject {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Entries,
        [Parameter(Mandatory = $true)][string]$RootName
    )

    $normalized=New-Object 'System.Collections.Generic.List[object]'
    $known=@{}
    foreach($entry in $Entries){$known[$entry.Path.Replace('\','/').Trim('/') ]=$true;$normalized.Add($entry)}
    foreach($entry in $Entries){
        $parent=[IO.Path]::GetDirectoryName($entry.Path.Replace('/','\'))
        while($parent){$key=$parent.Replace('\','/');if(-not $known.ContainsKey($key)){$known[$key]=$true;$normalized.Add([pscustomobject]@{Path=$key;IsDir=$true;Type='tree'})};$parent=[IO.Path]::GetDirectoryName($parent)}
    }
    $Entries=$normalized.ToArray()
    $groups = @{}
    foreach ($entry in $Entries) {
        $path = [string]$entry.Path
        if (-not $path) { continue }
        $cleanPath = $path.Replace('\','/').TrimEnd('/').TrimStart('/')
        if (-not $cleanPath) { continue }

        $parentPath = if ($cleanPath.Contains('/')) { $cleanPath.Substring(0, $cleanPath.LastIndexOf('/')) } else { '' }
        if (-not $groups.ContainsKey($parentPath)) {
            $groups[$parentPath] = [System.Collections.Generic.List[object]]::new()
        }
        $groups[$parentPath].Add($entry) | Out-Null
    }

    function Build-Node {
        param(
            [Parameter(Mandatory = $true)][string]$Name,
            [string]$Path = '',
            [Parameter(Mandatory = $true)][bool]$IsDir
        )

        $node = [ordered]@{
            name = $Name
            type = if ($IsDir) { 'dir' } else { 'file' }
        }

        if ($IsDir) {
            $node.children = @()
            if ($groups.ContainsKey($Path)) {
                foreach ($child in @($groups[$Path])) {
                    $childPath = ([string]$child.Path).Replace('\','/').TrimEnd('/').TrimStart('/')
                    $childName = [System.IO.Path]::GetFileName($childPath)
                    $childIsDir = ($child.Type -eq 'tree' -or $child.IsDir)
                    $childNode = Build-Node -Name $childName -Path $childPath -IsDir $childIsDir
                    foreach ($field in @('Content','ContentDirective','Template')) {
                        if ($child.PSObject.Properties.Name -contains $field -and ($child.$field -or ($field -eq 'Content' -and $child.HasContent))) {
                            $childNode | Add-Member -NotePropertyName $field -NotePropertyValue $child.$field
                        }
                    }
                    $node.children += $childNode
                }
            }
        }

        return [pscustomobject]$node
    }

    return (Build-Node -Name $RootName -Path '' -IsDir $true)
}

function ConvertTo-TreeJson {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Entries,
        [Parameter(Mandatory = $true)][string]$RootName,
        [int]$Depth = 10
    )

    $tree = ConvertTo-TreeNodeObject -Entries $Entries -RootName $RootName
    return ($tree | ConvertTo-Json -Depth $Depth -WarningAction Stop)
}

function ConvertTo-TreeYamlScalar {
    param([object]$Value)

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
        return [string]$Value
    }

    $text = [string]$Value
    # JSON strings are valid YAML double-quoted scalars and preserve all escapes.
    return (ConvertTo-Json -InputObject $text -Compress)
}

function ConvertTo-TreeYaml {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Entries,
        [Parameter(Mandatory = $true)][string]$RootName
    )

    $tree = ConvertTo-TreeNodeObject -Entries $Entries -RootName $RootName
    $sb = [System.Text.StringBuilder]::new()

    function Write-YamlNode {
        param(
            [Parameter(Mandatory = $true)]$Node,
            [Parameter(Mandatory = $true)][int]$Indent
        )

        $pad = [string]::new(' ', $Indent)
        [void]$sb.AppendLine($pad + 'name: ' + (ConvertTo-TreeYamlScalar $Node.name))
        [void]$sb.AppendLine($pad + 'type: ' + (ConvertTo-TreeYamlScalar $Node.type))
        foreach ($field in @('Content','ContentDirective','Template')) {
            if ($Node.PSObject.Properties.Name -contains $field) {
                [void]$sb.AppendLine($pad + $field + ': ' + (ConvertTo-TreeYamlScalar $Node.$field))
            }
        }
        if ($Node.type -eq 'dir') {
            [void]$sb.AppendLine($pad + 'children:')
            foreach ($child in @($Node.children)) {
                [void]$sb.AppendLine($pad + '  -')
                Write-YamlNode -Node $child -Indent ($Indent + 4)
            }
        }
    }

    Write-YamlNode -Node $tree -Indent 0
    return $sb.ToString().TrimEnd()
}

function Get-ExcludeList {
    param([string]$RootPath, [string]$ExtraExclude = '', [string]$IgnoreFile = '')
    $config = Get-TreeConfig -RootPath $RootPath -IgnoreFile $IgnoreFile -ExtraExclude $ExtraExclude
    $excludeFolders = @($config.ExcludeFolders)
    $gitIgnorePath = Join-Path $RootPath '.gitignore'
    if (Test-Path -LiteralPath $gitIgnorePath) {
        $ignoreLines = Get-Content -LiteralPath $gitIgnorePath | Where-Object { $_ -and -not $_.StartsWith('#') }
        foreach ($line in $ignoreLines) {
            $clean = $line.Trim().TrimEnd('/').TrimStart('/')
            if ($clean -and $clean -notmatch '[*!]' -and $clean -notmatch '/' -and $clean -notin $excludeFolders) {
                $excludeFolders += $clean
            }
        }
    }
    return $excludeFolders
}

. (Join-Path $PSScriptRoot '_scan.ps1')
function Get-LimitedItems {
    param([string]$Path,[int]$CurrentDepth,[int]$MaxDepth,[AllowEmptyCollection()][string[]]$ExcludeFolders)
    if($MaxDepth -gt 0 -and $CurrentDepth -ge $MaxDepth){return @()}
    $remaining=if($MaxDepth -eq 0){0}else{[Math]::Max(0,$MaxDepth-$CurrentDepth)}
    $scan=Get-TreeScan $Path $remaining $ExcludeFolders
    Assert-CompleteScan $scan
    return $scan.Items
}
function Write-Color {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Color = 'White',
        [switch]$NoNewline
    )
    # Write-Host colors work in Windows PowerShell 5.1 and do not emit raw ANSI
    # sequences to redirected output or terminals without VT support.
    $arguments=@{Object=$Message;NoNewline=$NoNewline}
    if($Color -in [Enum]::GetNames([ConsoleColor])){$arguments.ForegroundColor=$Color}
    Write-Host @arguments
}
#endregion

. (Join-Path $PSScriptRoot '_merge.ps1')

. (Join-Path $PSScriptRoot '_templates.ps1')
