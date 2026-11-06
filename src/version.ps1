param(
    [switch]$CheckUpdate,
    [switch]$Ci
)
$ErrorActionPreference='Stop'
try {
if ($env:TREE_CI -match '^(?i:1|true|yes)$') { $Ci=$true }

$CURRENT_VERSION = '2.2.0'
$GITLAB_HOST     = 'gitlab.com'
$GITLAB_PROJECT  = 'tanvirfoysaltoshin/project-tree-utility'
$RELEASES_URL    = "https://$GITLAB_HOST/api/v4/projects/$([uri]::EscapeDataString($GITLAB_PROJECT))/releases"
$REPO_URL        = "https://$GITLAB_HOST/$GITLAB_PROJECT"

Write-Host ''
Write-Host '  Project Tree Utility'
Write-Host "  Version : $CURRENT_VERSION"
Write-Host "  Repo    : $REPO_URL"
Write-Host ''

if (-not $CheckUpdate) {
    if (-not $Ci) {
        $ans = Read-Host '  Check for updates? (y/N)'
        if ($ans.Trim().ToLower() -ne 'y') { exit 0 }
    } else {
        exit 0
    }
}

Write-Host '  [INFO] Checking for updates ...'
try {
    # Use tags API — works on any public repo, no formal release required
    $TAGS_URL = "https://$GITLAB_HOST/api/v4/projects/$([uri]::EscapeDataString($GITLAB_PROJECT))/repository/tags?order_by=version&sort=desc&per_page=1"

    $tags = Invoke-RestMethod -Uri $TAGS_URL `
        -Headers @{ 'User-Agent' = 'project-tree-utility' } `
        -TimeoutSec 8 `
        -ErrorAction Stop

    if (-not $tags -or $tags.Count -eq 0) {
        Write-Host '  [INFO] No version tags found in the repository.'
        Write-Host ''
        exit 0
    }

    $latest     = $tags[0].name -replace '^v', ''
    $releaseUrl = "https://$GITLAB_HOST/$GITLAB_PROJECT/-/tags/$($tags[0].name)"

    if ([version]$latest -gt [version]$CURRENT_VERSION) {
        Write-Host ''
        Write-Host "  [UPDATE] New version available: v$latest"
        Write-Host "  Download: $releaseUrl"
        Write-Host ''
        exit 1
    } else {
        Write-Host "  [OK] You are on the latest version (v$CURRENT_VERSION)."
        Write-Host ''
        exit 0
    }
} catch {
    Write-Host "  [WARN] Update check failed: $($_.Exception.Message)"
    Write-Host ''
    exit 2
}

} catch { Write-Host ('[ERROR] Version failed: '+$_.Exception.Message); exit 2 }
