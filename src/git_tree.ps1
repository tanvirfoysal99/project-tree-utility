<#
.SYNOPSIS
    git_tree.ps1
    Remote Repository Tree Exporter
    Part of the Project Tree Utility toolkit

.DESCRIPTION
    Fetches the file/folder tree of a public or private GitHub or GitLab
    repository over HTTPS and exports it in the chosen output format.

    Supported providers:
      - GitHub (github.com)
      - GitLab (gitlab.com + self-hosted instances)

    Credentials are looked up in Windows Credential Manager and available Git
    credential helpers. Interactive use can prompt for a PAT when needed;
    CI permits anonymous requests and never prompts. Tokens are not written
    to project files, echoed, or accepted as literal command arguments.

.PARAMETER Provider
    'github' or 'gitlab'

.PARAMETER RepoUrl
    Full HTTPS URL to the repository.
    e.g. https://github.com/owner/repo
         https://gitlab.com/group/repo
         https://git.company.com/group/repo

.PARAMETER Branch
    Branch name to fetch. Required, no default.

.PARAMETER OutputFile
    Full path to the output file.

.PARAMETER OutputFormat
    'importable' | 'md' | 'txt' | 'json' | 'yaml'

.PARAMETER SubFolder
    Optional subfolder path to filter to. e.g. 'src' or 'packages/core'

.PARAMETER MaxDepth
    0 = unlimited. Otherwise cap at this many levels.

.PARAMETER ExcludeList
    Comma-separated folder/file names to omit from output.

.PARAMETER GitLabBaseUrl
    Base URL for GitLab. Defaults to https://gitlab.com
    Set to self-hosted base e.g. https://git.company.com
#>

param(
    [string]$ArgsFile      = '',
    [string]$Provider      = '',
    [string]$RepoUrl       = '',
    [string]$Branch        = '',
    [string]$OutputFile    = '',
    [string]$OutputFormat  = '',
    [string]$SubFolder     = '',
    [int]$MaxDepth         = 0,
    [string]$ExcludeList   = 'node_modules,.git,dist,build,.next,.wrangler',
    [string]$GitLabBaseUrl = 'https://gitlab.com',
    [switch]$Ci,
    [switch]$FromEnvironment
)
$ErrorActionPreference='Stop'
try {
if($FromEnvironment){
    $Provider=$env:PROVIDER;$RepoUrl=$env:REPO_URL;$Branch=$env:BRANCH;$OutputFile=$env:OUT_FILE;$OutputFormat=$env:FORMAT_TYPE
    $SubFolder=$env:SUBFOLDER;if($env:MAX_DEPTH){$MaxDepth=[int]$env:MAX_DEPTH};$ExcludeList=$env:EXCLUDE_LIST;$GitLabBaseUrl=$env:GITLAB_BASE
}
if ($env:TREE_CI -match '^(?i:1|true|yes)$') { $Ci=$true }
if ($Ci) { $env:GCM_INTERACTIVE='Never'; $env:GIT_TERMINAL_PROMPT='0' }

# Legacy ArgsFile input remains supported; wrappers now use environment data.
if ($ArgsFile) {
    if(-not (Test-Path -LiteralPath $ArgsFile -PathType Leaf)){throw 'Argument file not found.'}
    $lines         = [System.IO.File]::ReadAllLines($ArgsFile)
    $Provider      = if ($lines.Count -gt 0) { $lines[0].Trim() } else { '' }
    $RepoUrl       = if ($lines.Count -gt 1) { $lines[1].Trim() } else { '' }
    $Branch        = if ($lines.Count -gt 2) { $lines[2].Trim() } else { '' }
    $OutputFile    = if ($lines.Count -gt 3) { $lines[3].Trim() } else { '' }
    $OutputFormat  = if ($lines.Count -gt 4) { $lines[4].Trim() } else { 'txt' }
    $SubFolder     = if ($lines.Count -gt 5) { $lines[5].Trim() } else { '' }
    $mdRaw         = if ($lines.Count -gt 6) { $lines[6].Trim() } else { '0' }
    $MaxDepth      = if ($mdRaw -match '^\d+$') { [int]$mdRaw } else { 0 }
    $ExcludeList   = if ($lines.Count -gt 7 -and $lines[7].Trim() -ne '') { $lines[7].Trim() } else { 'node_modules,.git,dist,build,.next,.wrangler' }
    $GitLabBaseUrl = if ($lines.Count -gt 8 -and $lines[8].Trim() -ne '') { $lines[8].Trim() } else { 'https://gitlab.com' }
}

# Validate required fields
$validProviders = @('github','gitlab')
$validFormats   = @('importable','md','txt','json','yaml')
if ($Provider -notin $validProviders) { Write-Host "[ERROR] Provider must be 'github' or 'gitlab'."; exit 2 }
if (-not $RepoUrl)     { Write-Host '[ERROR] RepoUrl is required.';    exit 2 }
if (-not $Branch)      { Write-Host '[ERROR] Branch is required.';     exit 2 }
if (-not $OutputFile)  { Write-Host '[ERROR] OutputFile is required.'; exit 2 }
if ($OutputFormat -notin $validFormats) { Write-Host '[ERROR] Unsupported output format.'; exit 2 }

$ErrorActionPreference = 'Stop'

# ─────────────────────────────────────────────────────────────
# SECTION 1: Helpers
# ─────────────────────────────────────────────────────────────

function Write-Step {
    param([string]$Msg)
    Write-Host ("[INFO] " + $Msg)
}

function Write-Ok {
    param([string]$Msg)
    Write-Host ("[OK]   " + $Msg)
}

function Write-Warn {
    param([string]$Msg)
    Write-Host ("[WARN] " + $Msg)
}

function Write-Fail {
    param([string]$Msg)
    Write-Host ("[ERROR] " + $Msg)
}

function ConvertTo-PlainText {
    param([System.Security.SecureString]$Secure)
    if (-not $Secure -or $Secure.Length -eq 0) { return '' }
    $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($Secure)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringUni($ptr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($ptr)
    }
}

function Get-RepoHost {
    param([Parameter(Mandatory = $true)][string]$Url)
    try {
        return ([System.Uri]$Url).Authority.ToLowerInvariant()
    } catch {
        return ''
    }
}

function Get-RepoPath {
    param([Parameter(Mandatory = $true)][string]$Url)
    try {
        return ([System.Uri]$Url).AbsolutePath.Trim('/').Trim()
    } catch {
        return ''
    }
}

function Get-StoredPat {
    param([string]$RepoHost,[string]$Path='')
    return (Get-TreeStoredCredential ('git:https://'+$RepoHost+'/'+$Path))
}
. (Join-Path $PSScriptRoot 'internal/_credentials.ps1')
$sharedPath = Join-Path $PSScriptRoot 'internal\_shared.ps1'
if (-not (Test-Path -LiteralPath $sharedPath)) {
    Write-Fail "_shared.ps1 not found alongside git_tree.ps1."
    exit 1
}
. $sharedPath

. (Join-Path $PSScriptRoot 'internal/_http.ps1')
function Invoke-ApiRequest {
    param([string]$Uri,[string]$Pat='',[string]$PatHeader='Authorization',[string]$PatPrefix='token')
    $headers=@{'User-Agent'='ProjectTreeUtility/2.2'}
    if($Pat){$headers[$PatHeader]=if($PatPrefix){$PatPrefix+' '+$Pat}else{$Pat}}
    return (Invoke-TreeHttpRequest $Uri $headers)
}
function Get-RemoteTreeNode {
    param(
        [Parameter(Mandatory = $true)][object[]]$Entries,
        [Parameter(Mandatory = $true)][string]$RootName
    )

    $treeEntries = @($Entries | ForEach-Object {
        [pscustomobject]@{
            Path  = $_.Path
            Type  = $_.Type
            IsDir = ($_.Type -eq 'tree')
        }
    })
    return (ConvertTo-TreeNodeObject -Entries $treeEntries -RootName $RootName)
}

# ─────────────────────────────────────────────────────────────
# SECTION 2: URL Parser
# ─────────────────────────────────────────────────────────────

function Parse-GitHubUrl {
    param([string]$Url)
    # Accepts: https://github.com/owner/repo
    #          https://github.com/owner/repo/tree/branch
    #          https://github.com/owner/repo/tree/branch/sub/folder
    if ($Url -match '^https://github\.com/([^/]+)/([^/]+?)(?:\.git)?(?:/tree/[^/]+(?:/(.+))?)?$') {
        return @{
            Owner  = $Matches[1]
            Repo   = $Matches[2].TrimEnd('/')
        }
    }
    throw "Could not parse GitHub URL. Expected: https://github.com/owner/repo"
}

function Parse-GitLabUrl {
    param([string]$Url, [string]$BaseUrl)

    $base = $BaseUrl.TrimEnd('/')
    $escapedBase = [regex]::Escape($base)

    # Accepts: {base}/namespace/repo
    #          {base}/group/subgroup/repo  (nested groups)
    if ($Url -match "^$escapedBase/(.+?)(?:\.git)?(?:/-/tree/[^/]+(?:/(.+))?)?$") {
        $namespacePath = $Matches[1].TrimEnd('/')
        return @{
            NamespacePath = $namespacePath
            EncodedPath   = [Uri]::EscapeDataString($namespacePath)
        }
    }
    throw "Could not parse GitLab URL. Expected: $base/namespace/repo"
}

# ─────────────────────────────────────────────────────────────
# SECTION 3: GitHub Tree Fetcher
# ─────────────────────────────────────────────────────────────

function Get-GitHubTree {
    param([string]$Owner, [string]$Repo, [string]$Branch, [string]$Pat)

    $uri = "https://api.github.com/repos/$([Uri]::EscapeDataString($Owner))/$([Uri]::EscapeDataString($Repo))/git/trees/$([Uri]::EscapeDataString($Branch))?recursive=1"
    Write-Step "Calling GitHub API..."
    Write-Step "  $uri"

    $response = Invoke-ApiRequest -Uri $uri -Pat $Pat `
                                  -PatHeader 'Authorization' -PatPrefix 'token'
    $data = $response.Content | ConvertFrom-Json

    if($data.PSObject.Properties.Name -notcontains 'tree' -or $data.tree -isnot [Array]){throw 'GitHub returned an invalid tree response.'}
    if($data.truncated -eq $true){throw 'GitHub returned an incomplete (truncated) tree; output was not written.'}
    Assert-RemoteTreeEntries @($data.tree)
    # Normalise to @{ Path; Type }  -  type: 'blob'=file, 'tree'=folder
    $entries = @($data.tree | ForEach-Object {
        @{ Path = $_.path; Type = $_.type }
    })

    Write-Ok ("GitHub API returned " + $entries.Count + " entries.")
    return $entries
}

# ─────────────────────────────────────────────────────────────
# SECTION 4: GitLab Tree Fetcher (with pagination)
# ─────────────────────────────────────────────────────────────

function Get-GitLabTree {
    param([string]$BaseUrl, [string]$EncodedPath, [string]$Branch, [string]$Pat)

    $base    = $BaseUrl.TrimEnd('/')
    $allItems = [System.Collections.Generic.List[object]]::new()
    $page    = 1
    $perPage = 100

    Write-Step "Calling GitLab API (paginated)..."

    $visited=@{}
    do {
        if($visited.ContainsKey($page) -or $page -gt 10000){throw 'Invalid or excessive GitLab pagination.'};$visited[$page]=$true
        $uri = "$base/api/v4/projects/$EncodedPath/repository/tree" +
               "?recursive=true&ref=$([Uri]::EscapeDataString($Branch))&per_page=$perPage&page=$page"
        Write-Step "  Page $page  -  $uri"

        $response = Invoke-ApiRequest -Uri $uri -Pat $Pat `
                                      -PatHeader 'PRIVATE-TOKEN' -PatPrefix ''

        if(-not ([string]$response.Content).TrimStart().StartsWith('[')){throw 'GitLab returned an invalid tree page.'}
        $parsedItems = $response.Content | ConvertFrom-Json
        $items = @($parsedItems)
        Assert-RemoteTreeEntries @($items)
        foreach ($item in $items) {
            $allItems.Add(@{
                Path = $item.path
                Type = if ($item.type -eq 'tree') { 'tree' } else { 'blob' }
            }) | Out-Null
        }

        # Check if more pages exist
        $nextPage = $response.Headers['X-Next-Page']
        if ($nextPage -and $nextPage -ne '') {
            $next=0;if(-not [int]::TryParse([string]$nextPage,[ref]$next) -or $next -le $page){throw 'Invalid GitLab next-page header.'};$page=$next
        } else {
            $page = 0
        }

    } while ($page -gt 0)

    Assert-RemoteTreeEntries $allItems.ToArray()
    Write-Ok ("GitLab API returned " + $allItems.Count + " entries (all pages).")
    return $allItems
}

# ─────────────────────────────────────────────────────────────
# SECTION 5: Filter + Sort entries
# ─────────────────────────────────────────────────────────────

function Filter-Entries {
    param(
        $Entries,
        [string]$SubFolder,
        [int]$MaxDepth,
        [string[]]$ExcludeParts
    )

    $prefix = ''
    if ($SubFolder -ne '') {
        $prefix = $SubFolder.Trim('/') + '/'
    }

    $filtered = [System.Collections.Generic.List[object]]::new()

    foreach ($e in $Entries) {
        $path = $e.Path

        # Subfolder filter
        if ($prefix -ne '') {
            if (-not $path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            $path = $path.Substring($prefix.Length)
            if ($path -eq '') { continue }
        }

        # Exclude list  -  check every path segment
        $parts = $path.Split('/')
        $skip  = $false
        foreach ($part in $parts) {
            if ($part -in $ExcludeParts) { $skip = $true; break }
        }
        if ($skip) { continue }

        # Max depth filter (depth = number of segments)
        $depth = $parts.Count
        if ($MaxDepth -gt 0 -and $depth -gt $MaxDepth) { continue }

        $filtered.Add(@{ Path = $path; Type = $e.Type; Depth = $depth; Parts = $parts }) | Out-Null
    }

    # Sort: folders before files at each level, then alphabetical
    $sorted = $filtered | Sort-Object {
        $e = $_
        # Build sort key: for each path, prepend folder-first marker per segment
        $e.Parts -join '/'
    }

    return $sorted
}

# ─────────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────
# SECTION 6: Output Renderer
# ─────────────────────────────────────────────────────────────

function Build-PrefixTable {
    <#
    .SYNOPSIS
        Pre-computes the prefix string (pipe chars + spacing) and isLast flag
        for every entry, matching exactly how export.bat's Show-Tree does it.
        Returns a hashtable keyed by entry index.
    #>
    param($Entries)

    $table = @{}
    $count = $Entries.Count

    for ($i = 0; $i -lt $count; $i++) {
        $e     = $Entries[$i]
        $depth = $e.Parts.Count

        # Find siblings at the same depth with the same parent path
        $parentPath = if ($depth -gt 1) { $e.Parts[0..($depth - 2)] -join '/' } else { '' }
        $siblings   = @($Entries | Where-Object {
            $_.Parts.Count -eq $depth -and
            ($(if ($_.Parts.Count -gt 1) { $_.Parts[0..($_.Parts.Count-2)] -join '/' } else { '' })) -eq $parentPath
        })
        $isLast = ($siblings[$siblings.Count - 1].Path -eq $e.Path)

        # Build prefix by walking up the ancestor chain
        # For each ancestor level, check if THAT ancestor was also the last sibling
        # to decide whether to emit pipe or spaces
        $prefix = ''
        for ($d = 1; $d -lt $depth; $d++) {
            # Get the ancestor at this depth
            $ancestorParts      = $e.Parts[0..($d - 1)]
            $ancestorPath       = $ancestorParts -join '/'
            $ancestorParentPath = if ($d -gt 1) { $ancestorParts[0..($d - 2)] -join '/' } else { '' }

            # Find that ancestor's siblings
            $ancestorSiblings = @($Entries | Where-Object {
                $_.Parts.Count -eq $d -and
                ($(if ($_.Parts.Count -gt 1) { $_.Parts[0..($_.Parts.Count-2)] -join '/' } else { '' })) -eq $ancestorParentPath
            })
            $ancestorIsLast = ($ancestorSiblings[$ancestorSiblings.Count - 1].Path.StartsWith($ancestorPath))

            if ($ancestorIsLast) {
                $prefix += '    '
            } else {
                $prefix += ([char]0x2502 + '   ')
            }
        }

        $table[$i] = @{ Prefix = $prefix; IsLast = $isLast }
    }

    return $table
}

function Render-Output {
    param($Entries, [string]$Format, [string]$RepoName, [string]$Branch)

    $sb  = [System.Text.StringBuilder]::new()
    $sep = [string]::new([char]0x2500, 45)

    if ($Format -eq 'json' -or $Format -eq 'yaml') {
        $tree = Get-RemoteTreeNode -Entries $Entries -RootName $RepoName
        if ($Format -eq 'json') {
            return ($tree | ConvertTo-Json -Depth 100 -WarningAction Stop)
        }
        return (ConvertTo-TreeYaml -Entries $Entries -RootName $RepoName)
    }

    # Summary header  -  matches export.bat PROJECT SUMMARY style
    if ($Format -ne 'importable') {
        $totalFolders = @($Entries | Where-Object { $_.Type -eq 'tree' }).Count
        $totalFiles   = @($Entries | Where-Object { $_.Type -ne 'tree' }).Count

        $sb.AppendLine($sep) | Out-Null
        $sb.AppendLine(' ' + [char]::ConvertFromUtf32(0x1F4CA) + '  PROJECT SUMMARY (Git Tree)') | Out-Null
        $sb.AppendLine($sep) | Out-Null
        $sb.AppendLine(' ' + [char]::ConvertFromUtf32(0x1F4C1) + '  Total Folders : ' + $totalFolders) | Out-Null
        $sb.AppendLine(' ' + [char]::ConvertFromUtf32(0x1F4C4) + '  Total Files   : ' + $totalFiles) | Out-Null
        $sb.AppendLine(' ' + [char]::ConvertFromUtf32(0x1F517) + '  Repository    : ' + $RepoName) | Out-Null
        $sb.AppendLine(' ' + [char]::ConvertFromUtf32(0x1F33F) + '  Branch        : ' + $Branch) | Out-Null
        $sb.AppendLine(' ' + [char]::ConvertFromUtf32(0x1F4C5) + '  Generated     : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) | Out-Null
        $sb.AppendLine($sep) | Out-Null
        $sb.AppendLine('') | Out-Null
    }

    # Root folder line  -  matches export.bat exactly
    if ($Format -eq 'md') {
        $sb.AppendLine('## ' + $RepoName + '/') | Out-Null
        $sb.AppendLine('``````text') | Out-Null
    } elseif ($Format -ne 'importable') {
        $sb.AppendLine($RepoName + '/') | Out-Null
    }

    # Pre-compute prefix table for txt/md (not needed for importable)
    if ($Format -ne 'importable') {
        $prefixTable = Build-PrefixTable -Entries $Entries
    }

    for ($i = 0; $i -lt $Entries.Count; $i++) {
        $e     = $Entries[$i]
        $name  = $e.Parts[$e.Parts.Count - 1]
        $slash = if ($e.Type -eq 'tree') { '/' } else { '' }

        if ($Format -eq 'importable') {
            $dashes = '-' * $e.Parts.Count
            $sb.AppendLine($dashes + ' ' + $name + $slash) | Out-Null
            continue
        }

        # Build emoji via Get-Emoji from _shared.ps1
        $mockItem = if ($e.Type -eq 'tree') {
            New-Object System.IO.DirectoryInfo((Join-Path $env:TEMP $name))
        } else {
            New-Object System.IO.FileInfo((Join-Path $env:TEMP $name))
        }
        $emoji = Get-Emoji -Item $mockItem

        $pt     = $prefixTable[$i]
        $prefix = $pt.Prefix
        $conn   = if ($pt.IsLast) {
            [char]0x2514 + [char]0x2500 + [char]0x2500 + ' '
        } else {
            [char]0x251C + [char]0x2500 + [char]0x2500 + ' '
        }

        if ($Format -eq 'md') {
            $sb.AppendLine($prefix + $conn + $emoji + ' ``' + $name + $slash + '``') | Out-Null
        } else {
            $sb.AppendLine($prefix + $conn + $emoji + ' ' + $name + $slash) | Out-Null
        }
    }

    if ($Format -eq 'md') {
        $sb.AppendLine('``````') | Out-Null
    }

    # File type breakdown for txt/md  -  matches export.bat FILE TYPE BREAKDOWN
    if ($Format -ne 'importable') {
        $fileEntries = @($Entries | Where-Object { $_.Type -ne 'tree' })
        if ($fileEntries.Count -gt 0) {
            $extGroups = $fileEntries | Group-Object {
                $ext = [System.IO.Path]::GetExtension($_.Parts[$_.Parts.Count - 1]).ToLower()
                if ($ext -eq '') { '(none)' } else { $ext }
            } | Sort-Object Count -Descending

            $sb.AppendLine('') | Out-Null
            $sb.AppendLine($sep) | Out-Null
            $sb.AppendLine(' ' + [char]::ConvertFromUtf32(0x1F4C8) + '  FILE TYPE BREAKDOWN') | Out-Null
            $sb.AppendLine($sep) | Out-Null

            foreach ($grp in $extGroups) {
                $pct    = [math]::Round(($grp.Count / $fileEntries.Count) * 100, 2)
                $bar    = [math]::Round($pct / 5)
                $filled = [string]::new([char]0x2588, $bar)
                $empty  = [string]::new([char]0x2591, 20 - $bar)
                # Mock a FileInfo for emoji
                $mockFile = New-Object System.IO.FileInfo((Join-Path $env:TEMP ('x' + $grp.Name)))
                $grpEmoji = Get-Emoji -Item $mockFile
                $sb.AppendLine(' ' + $grpEmoji + ' ' + $grp.Name.PadRight(12) + $pct.ToString('F2').PadLeft(6) + '%%  ' + $filled + $empty + $grp.Count.ToString().PadLeft(4) + ' files') | Out-Null
            }

            $sb.AppendLine($sep) | Out-Null
        }
    }

    return $sb.ToString()
}

# SECTION 7: Main execution
# ─────────────────────────────────────────────────────────────

Write-Host ''
Write-Host '============================================'
Write-Host '  git_tree.ps1  |  Remote Tree Exporter'
Write-Host '============================================'
Write-Host ''

# Validate URL scheme
if (-not $RepoUrl.StartsWith('https://')) {
    Write-Fail "URL must start with https://  -  HTTP is not accepted."
    exit 1
}
if($MaxDepth -lt 0){throw 'Maximum depth cannot be negative.'}
if($Provider -eq 'gitlab'){
    $repoUri=[Uri]$RepoUrl;$baseUri=[Uri]$GitLabBaseUrl
    if($baseUri.Scheme -ne 'https' -or $baseUri.UserInfo -or $baseUri.Authority -ne $repoUri.Authority){throw 'GitLab base URL must use HTTPS and match the repository host and port.'}
}

Write-Host ''

# Parse URL and fetch tree
try {
    $repoHost = Get-RepoHost -Url $RepoUrl
    $repoPath = Get-RepoPath -Url $RepoUrl
    $pat = Get-StoredPat -RepoHost $repoHost -Path $repoPath

    if (-not $pat -and -not $Ci) {


        Write-Host "Personal Access Token (optional)."
        Write-Host "  GitHub: token with 'repo' or 'read:repo' scope."
        Write-Host "  GitLab: token with 'read_repository' scope."
        Write-Host "  Press Enter to skip (public repos only)."
        $securePat = Read-Host "PAT" -AsSecureString
        $pat = ConvertTo-PlainText -Secure $securePat
        $securePat.Dispose()
        Write-Host ''
    } elseif ($pat) {
        Write-Step "Using stored credential for host: $repoHost"
    }

    if ($Provider -eq 'github') {

        $parsed  = Parse-GitHubUrl -Url $RepoUrl
        $owner   = $parsed.Owner
        $repo    = $parsed.Repo
        $repoName = $repo

        Write-Step "Provider : GitHub"
        Write-Step "Owner    : $owner"
        Write-Step "Repo     : $repo"
        Write-Step "Branch   : $Branch"
        if ($SubFolder -ne '') { Write-Step "Subfolder: $SubFolder" }
        Write-Host ''

        $rawEntries = Get-GitHubTree -Owner $owner -Repo $repo -Branch $Branch -Pat $pat

    } elseif ($Provider -eq 'gitlab') {

        $parsed      = Parse-GitLabUrl -Url $RepoUrl -BaseUrl $GitLabBaseUrl
        $nsPath      = $parsed.NamespacePath
        $encodedPath = $parsed.EncodedPath
        $repoName    = $nsPath.Split('/')[-1]

        Write-Step "Provider  : GitLab ($GitLabBaseUrl)"
        Write-Step "Namespace : $nsPath"
        Write-Step "Branch    : $Branch"
        if ($SubFolder -ne '') { Write-Step "Subfolder : $SubFolder" }
        Write-Host ''

        $rawEntries = Get-GitLabTree -BaseUrl $GitLabBaseUrl `
                                     -EncodedPath $encodedPath `
                                     -Branch $Branch -Pat $pat
    }

} catch {
    $pat = ''
    Write-Fail $_.Exception.Message
    exit 2
}

# Clear PAT from memory  -  all API calls are complete
$pat = ''
$securePat = $null

# Parse exclude list
$excludeParts = @()
if ($ExcludeList -ne '') {
    $excludeParts = $ExcludeList.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
}

# Filter and sort
Write-Host ''
Write-Step "Filtering and sorting entries..."
$filtered = @(Filter-Entries -Entries $rawEntries `
                           -SubFolder $SubFolder `
                           -MaxDepth $MaxDepth `
                           -ExcludeParts $excludeParts)

Write-Ok ("$($filtered.Count) entries after filtering.")

if ($filtered.Count -eq 0) {
    Write-Warn "No entries remain after filtering. Check subfolder path, excludes, and max depth."
    exit 1
}

# Render output
Write-Step "Rendering output (format: $OutputFormat)..."
$output = Render-Output -Entries $filtered -Format $OutputFormat `
                        -RepoName $repoName -Branch $Branch

# Write file
$outputDir = Split-Path -Parent $OutputFile
if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}
[System.IO.File]::WriteAllText($OutputFile, $output, [System.Text.Encoding]::UTF8)

$sep = [string]::new([char]0x2500, 45)
Write-Host ''
Write-Host $sep
Write-Host '  GIT TREE EXPORT COMPLETE'
Write-Host $sep
Write-Host ('  Provider  : ' + $Provider)
Write-Host ('  Repo      : ' + $repoName)
Write-Host ('  Branch    : ' + $Branch)
Write-Host ('  Entries   : ' + $filtered.Count)
Write-Host ('  Format    : ' + $OutputFormat)
Write-Host ('  Saved to  : ' + $OutputFile)
Write-Host $sep

exit 0

} catch { Write-Host ('[ERROR] Remote export failed: '+$_.Exception.Message); exit 2 }
