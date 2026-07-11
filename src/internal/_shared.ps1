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
    $ext = [System.IO.Path]::GetExtension($FilePath).ToLowerInvariant()
    if ($ext -eq '.json') { return 'json' }
    if ($ext -in @('.yaml', '.yml')) { return 'yaml' }

    $lines = @(
        Get-Content -Path $FilePath -ErrorAction SilentlyContinue |
        Where-Object { $_.Trim() -ne '' -and -not $_.TrimStart().StartsWith('#') }
    )
    if (-not $lines) { return 'empty' }
    $first = $lines[0].Trim()
    if ($first -match '^[\{\[]')                       { return 'json' }
    if ($first -match '^[A-Za-z_][\w-]*\s*:\s*$' -or $first -match '^-+\s*[\w-]+\s*:\s*') { return 'yaml' }
    if ($first -match '^-+\s+\S')                     { return 'dash'    }
    if ($first -match '\t')                            { return 'tab'     }
    if ($first -match '[\u251C\u2514\u2502]')         { return 'treesym' }
    if ($first -match '^\s+\S')                       { return 'space'   }
    return 'unknown'
}

function Confirm-StructureFormat {
    param([string]$FilePath, [string]$Format, [int]$SpaceUnit = 2)
    try {
        switch ($Format) {
            'json' {
                $null = (Get-Content -LiteralPath $FilePath -Raw -ErrorAction Stop) | ConvertFrom-Json
                return $true
            }
            'yaml' {
                $null = ConvertFrom-TreeYaml -FilePath $FilePath
                return $true
            }
            default {
                $lines = @(
                    Get-Content -Path $FilePath -ErrorAction SilentlyContinue |
                    Where-Object { $_.Trim() -ne '' -and -not $_.TrimStart().StartsWith('#') }
                )
                if (-not $lines) { return $false }
                switch ($Format) {
                    'dash'    { foreach ($l in $lines) { if ($l -notmatch '^-+\s+\S') { return $false } } }
                    'tab'     { foreach ($l in $lines) { if ($l -notmatch '^\t*\S')   { return $false } } }
                    'treesym' { foreach ($l in $lines) { if ($l -notmatch '^[\s\u2502]*[\u251C\u2514\-|]*\s*\S') { return $false } } }
                    'space'   { foreach ($l in $lines) { if ($l -notmatch '^\s*\S')   { return $false } } }
                    default   { return $false }
                }
                return $true
            }
        }
    } catch {
        return $false
    }
}

# ─────────────────────────────────────────────────────────────
# SECTION 2: Structure Parser
# ─────────────────────────────────────────────────────────────

function Parse-StructureLine {
    param(
        [string]$Line,
        [string]$Format,
        [int]$SpaceUnit  = 2,
        [bool]$IsFirst   = $false
    )
    switch ($Format) {
        'dash' {
            if ($Line -match '^(-+)\s*(.+)$') {
                $decorated = Split-TreeNodeDecorators -Text $Matches[2].Trim()
                $name = $decorated.Path.Trim()
                $contentDirective = ''
                if ($decorated.Content) { $contentDirective = '@content:' + $decorated.Content }
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
                if ($decorated.Content) { $contentDirective = '@content:' + $decorated.Content }
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
                else { $depth = [math]::Floor($indent / 4) + 2 }
                $contentDirective = ''
                if ($decorated.Content) { $contentDirective = '@content:' + $decorated.Content }
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
                if ($decorated.Content) { $contentDirective = '@content:' + $decorated.Content }
                return @{ Depth = $depth; Name = $name; IsDir = $name.EndsWith('/'); Template = $decorated.Template; ContentDirective = $contentDirective }
            }
            return $null
        }
    }
    return $null
}

function Read-StructureFile {
    param([string]$FilePath, [string]$Format, [int]$SpaceUnit = 2, [string]$TemplateName = '')

    if ($Format -eq 'template') {
        $preset = Get-TemplatePreset -Name $TemplateName
        if (-not $preset) { return @() }
        return @(ConvertFrom-TreeNode -Node $preset.Entries -Depth 1 -ParentPath '')
    }
    if ($Format -eq 'json') { return @(ConvertFrom-TreeJson -FilePath $FilePath) }
    if ($Format -eq 'yaml') {
        return @(ConvertFrom-TreeYaml -FilePath $FilePath)
    }

    $rawLines = @(
        Get-Content -Path $FilePath |
        Where-Object { $_.Trim() -ne '' -and -not $_.TrimStart().StartsWith('#') }
    )
    $entries = [System.Collections.Generic.List[object]]::new()
    $pathStack = @{}
    for ($i = 0; $i -lt $rawLines.Count; $i++) {
            $p = Parse-StructureLine -Line $rawLines[$i] -Format $Format -SpaceUnit $SpaceUnit -IsFirst ($i -eq 0)
        if ($p) {
            $parent = if ($p.Depth -eq 1) { '' } else { $pathStack[$p.Depth - 1] }
            $cleanName = $p.Name.TrimEnd('/')
            $p.Path = if ($parent) { Join-Path $parent $cleanName } else { $cleanName }
            $pathStack[$p.Depth] = $p.Path
            $null = $entries.Add([pscustomobject]$p)
        }
    }
    return $entries
}

# ─────────────────────────────────────────────────────────────
# SECTION 3: Emoji Mapping
# ─────────────────────────────────────────────────────────────

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
        return $resolved.StartsWith($baseResolved, [System.StringComparison]::OrdinalIgnoreCase)
    } catch {
        return $false
    }
}

function Test-DangerousName {
    param([string]$Name)
    if ($Name -match '\.\.')                                          { return $true }
    if ($Name -match '^[A-Za-z]:\\' -or $Name -match '^\\\\')        { return $true }
    if ($Name -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$') { return $true }
    if ($Name -match '[\x00-\x1F]')                                   { return $true }
    if ($Name -match '[*?"<>|]')                                      { return $true }
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
        $candidateFiles.Add($explicit) | Out-Null
    }
    foreach ($name in @('.treeignore', '.treerc')) {
        $candidateFiles.Add((Join-Path $RootPath $name)) | Out-Null
    }

    foreach ($configPath in $candidateFiles) {
        if (-not (Test-Path -LiteralPath $configPath)) { continue }
        $config.IgnoreFile = $configPath
        $lines = Get-Content -LiteralPath $configPath -ErrorAction SilentlyContinue
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

function Get-TemplatePreset {
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
            } elseif ($clean -match '^@content:(.+)$') {
                $result.Content = $Matches[1]
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
    if ($null -eq $Node) { return $entries }

    if (($Node -is [System.Array]) -or ($Node -is [System.Collections.IList]) -or ($Node -is [System.Collections.ICollection] -and -not ($Node -is [pscustomobject]))) {
        foreach ($child in $Node) {
            $nested = ConvertFrom-TreeNode -Node $child -Depth $Depth -ParentPath $ParentPath
            foreach ($entry in $nested) { $entries.Add($entry) | Out-Null }
        }
        return $entries
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
        return $entries
    }

    $decorated = Split-TreeNodeDecorators -Text $rawPath
    $cleanPath = $decorated.Path.Trim().TrimEnd('/')
    if (-not $cleanPath) { return $entries }

    $typeHint = ''
    foreach ($propName in @('Type','type')) {
        if ($Node.PSObject.Properties.Name -contains $propName) {
            $typeHint = [string]$Node.$propName
            break
        }
    }

    $hasChildren = $false
    foreach ($propName in @('Children','children','Entries','entries')) {
        if ($Node.PSObject.Properties.Name -contains $propName) {
            $hasChildren = $true
            break
        }
    }

    $isDir = $hasChildren -or $cleanPath.EndsWith('/') -or ($typeHint -match '^(dir|folder|tree)$')
    $fullPath = if ($ParentPath) { Join-Path $ParentPath $cleanPath } else { $cleanPath }
    $entry = [pscustomobject]@{
        Depth            = $Depth
        Name             = if ($isDir -and -not $cleanPath.EndsWith('/')) { $cleanPath + '/' } else { $cleanPath }
        Path             = $fullPath
        IsDir            = $isDir
        Template         = ''
        ContentDirective = ''
        Content          = ''
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
    if (-not $entry.ContentDirective -and $decorated.Content) {
        $entry.ContentDirective = '@content:' + $decorated.Content
    }

    foreach ($propName in @('Content','content')) {
        if ($Node.PSObject.Properties.Name -contains $propName) {
            $entry.Content = [string]$Node.$propName
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
    $raw = Get-Content -LiteralPath $FilePath -Raw -ErrorAction Stop
    $data = $raw | ConvertFrom-Json
    return @(ConvertFrom-TreeNode -Node $data -Depth 1 -ParentPath '')
}

function ConvertFrom-TreeYaml {
    param([Parameter(Mandatory = $true)][string]$FilePath)

    function ConvertFrom-YamlScalar {
        param([string]$Value)
        $v = $Value.Trim()
        if ($v -eq 'null' -or $v -eq '~') { return $null }
        if ($v -eq 'true') { return $true }
        if ($v -eq 'false') { return $false }
        if ($v -match '^-?\d+$') { return [int64]$v }
        if ($v -match '^-?\d+\.\d+$') { return [double]$v }
        if (($v.StartsWith('"') -and $v.EndsWith('"')) -or ($v.StartsWith("'") -and $v.EndsWith("'"))) {
            return $v.Substring(1, $v.Length - 2)
        }
        return $v
    }

    $rawLines = Get-Content -LiteralPath $FilePath -ErrorAction Stop
    $tokens = New-Object System.Collections.Generic.List[object]
    foreach ($raw in $rawLines) {
        $line = $raw -replace '\s+$', ''
        if (-not $line.Trim() -or $line.TrimStart().StartsWith('#')) { continue }
        $indent = $line.Length - $line.TrimStart().Length
        $tokens.Add([pscustomobject]@{ Indent = $indent; Text = $line.TrimStart() }) | Out-Null
    }

    function Parse-YamlBlock {
        param(
            [Parameter(Mandatory = $true)][System.Collections.Generic.List[object]]$Tokens,
            [Parameter(Mandatory = $true)][ref]$Index,
            [int]$BaseIndent = 0
        )

        $resultList = New-Object System.Collections.Generic.List[object]
        $resultMap = [ordered]@{}
        $mode = ''

        while ($Index.Value -lt $Tokens.Count) {
            $token = $Tokens[$Index.Value]
            if ($token.Indent -lt $BaseIndent) { break }
            if ($mode -eq '') {
                $mode = if ($token.Text.StartsWith('- ')) { 'list' } else { 'map' }
            }

            if ($mode -eq 'list') {
                if ($token.Indent -ne $BaseIndent -or -not $token.Text.StartsWith('- ')) { break }
                $itemText = $token.Text.Substring(2).Trim()
                $item = [ordered]@{}

                if ($itemText) {
                    if ($itemText -match '^([^:]+):\s*(.*)$') {
                        $item[$Matches[1].Trim()] = ConvertFrom-YamlScalar $Matches[2]
                    } else {
                        $item['path'] = ConvertFrom-YamlScalar $itemText
                    }
                }

                $Index.Value++
                if ($Index.Value -lt $Tokens.Count -and $Tokens[$Index.Value].Indent -gt $token.Indent) {
                    $nestedIndex = $Index.Value
                    $nested = Parse-YamlBlock -Tokens $Tokens -Index ([ref]$nestedIndex) -BaseIndent $Tokens[$Index.Value].Indent
                    $Index.Value = $nestedIndex
                    if ($nested -is [System.Collections.IEnumerable] -and -not ($nested -is [string])) {
                        $item['children'] = @($nested)
                    } elseif ($nested) {
                        foreach ($key in $nested.PSObject.Properties.Name) { $item[$key] = $nested.$key }
                    }
                }
                $resultList.Add([pscustomobject]$item) | Out-Null
                continue
            }

            if ($token.Indent -ne $BaseIndent -or $token.Text.StartsWith('- ')) { break }
            if ($token.Text -match '^([^:]+):\s*(.*)$') {
                $key = $Matches[1].Trim()
                $value = $Matches[2]
                $Index.Value++

                if ($value -eq '') {
                    if ($Index.Value -lt $Tokens.Count -and $Tokens[$Index.Value].Indent -gt $token.Indent) {
                        $nestedIndex = $Index.Value
                        $nested = Parse-YamlBlock -Tokens $Tokens -Index ([ref]$nestedIndex) -BaseIndent $Tokens[$Index.Value].Indent
                        $Index.Value = $nestedIndex
                        $resultMap[$key] = $nested
                    } else {
                        $resultMap[$key] = $null
                    }
                } elseif ($value -eq '|') {
                    $block = New-Object System.Collections.Generic.List[string]
                    while ($Index.Value -lt $Tokens.Count -and $Tokens[$Index.Value].Indent -gt $token.Indent) {
                        $block.Add($Tokens[$Index.Value].Text) | Out-Null
                        $Index.Value++
                    }
                    $resultMap[$key] = ($block -join [Environment]::NewLine)
                } else {
                    $resultMap[$key] = ConvertFrom-YamlScalar $value
                }
            } else {
                $Index.Value++
            }
        }

        if ($mode -eq 'list') { return $resultList }
        return [pscustomobject]$resultMap
    }

    $index = 0
    $parsed = Parse-YamlBlock -Tokens $tokens -Index ([ref]$index) -BaseIndent 0
    return @(ConvertFrom-TreeNode -Node $parsed -Depth 1 -ParentPath '')
}

function Get-StructureEntryContent {
    param(
        [Parameter(Mandatory = $true)][object]$Entry,
        [Parameter(Mandatory = $true)][string]$ProjectName,
        [string]$TemplateName = ''
    )

    if ($Entry.Content -and $Entry.Content.Trim()) { return $Entry.Content }
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
        [Parameter(Mandatory = $true)][object[]]$Entries,
        [Parameter(Mandatory = $true)][string]$RootName
    )

    $groups = @{}
    foreach ($entry in $Entries) {
        $path = [string]$entry.Path
        if (-not $path) { continue }
        $cleanPath = $path.TrimEnd('/').TrimStart('/')
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
                    $childPath = [string]$child.Path.TrimEnd('/').TrimStart('/')
                    $childName = [System.IO.Path]::GetFileName($childPath)
                    $childIsDir = ($child.Type -eq 'tree' -or $child.IsDir)
                    $node.children += (Build-Node -Name $childName -Path $childPath -IsDir $childIsDir)
                }
            }
        }

        return [pscustomobject]$node
    }

    return (Build-Node -Name $RootName -Path '' -IsDir $true)
}

function ConvertTo-TreeJson {
    param(
        [Parameter(Mandatory = $true)][object[]]$Entries,
        [Parameter(Mandatory = $true)][string]$RootName,
        [int]$Depth = 10
    )

    $tree = ConvertTo-TreeNodeObject -Entries $Entries -RootName $RootName
    return ($tree | ConvertTo-Json -Depth $Depth)
}

function ConvertTo-TreeYamlScalar {
    param([object]$Value)

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
        return [string]$Value
    }

    $text = [string]$Value
    if ($text -eq '') { return "''" }
    if ($text -match '^[A-Za-z0-9_\-\.\/]+$') { return $text }
    return ('"' + ($text -replace '"', '\"') + '"')
}

function ConvertTo-TreeYaml {
    param(
        [Parameter(Mandatory = $true)][object[]]$Entries,
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
    if (Test-Path $gitIgnorePath) {
        $ignoreLines = Get-Content $gitIgnorePath | Where-Object { $_ -and -not $_.StartsWith('#') }
        foreach ($line in $ignoreLines) {
            $clean = $line.Trim().TrimEnd('/').TrimStart('/')
            if ($clean -and $clean -notmatch '[*!]' -and $clean -notmatch '/' -and $clean -notin $excludeFolders) {
                $excludeFolders += $clean
            }
        }
    }
    return $excludeFolders
}

function Get-LimitedItems {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][int]$CurrentDepth,
        [Parameter(Mandatory = $true)][int]$MaxDepth,
        [Parameter(Mandatory = $true)][string[]]$ExcludeFolders
    )

    $items = Get-ChildItem -LiteralPath $Path -ErrorAction SilentlyContinue
    $result = [System.Collections.Generic.List[object]]::new()

    foreach ($item in $items) {
        $skip = $false
        foreach ($ex in $ExcludeFolders) {
            if ($item.Name -eq $ex) { $skip = $true; break }
        }
        if ($skip) { continue }

        [void]$result.Add($item)

        if ($item.PSIsContainer) {
            if ($MaxDepth -eq 0 -or $CurrentDepth + 1 -lt $MaxDepth) {
                $nested = Get-LimitedItems -Path $item.FullName `
                    -CurrentDepth ($CurrentDepth + 1) `
                    -MaxDepth $MaxDepth `
                    -ExcludeFolders $ExcludeFolders
                foreach ($n in $nested) { [void]$result.Add($n) }
            }
        }
    }

    return $result
}

function Write-Color {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Color = 'White',
        [switch]$NoNewline
    )
    $ansiMap = @{
        'Red'     = "`e[31m"
        'Green'   = "`e[32m"
        'Yellow'  = "`e[33m"
        'Blue'    = "`e[34m"
        'Magenta' = "`e[35m"
        'Cyan'    = "`e[36m"
        'White'   = "`e[37m"
        'Gray'    = "`e[90m"
        'Bold'    = "`e[1m"
        'Reset'   = "`e[0m"
    }
    $ansi  = if ($ansiMap.ContainsKey($Color)) { $ansiMap[$Color] } else { '' }
    $reset = $ansiMap['Reset']
    $line  = $ansi + $Message + $reset
    if ($NoNewline) { Write-Host $line -NoNewline } else { Write-Host $line }
}
#endregion
