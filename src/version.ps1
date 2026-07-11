param(
    [switch]$CheckUpdate,
    [switch]$Ci
)

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
    # GitLab returns releases newest-first; take the first one
    $releases = Invoke-RestMethod -Uri $RELEASES_URL `
        -Headers @{ 'User-Agent' = 'project-tree-utility' } `
        -TimeoutSec 8 `
        -ErrorAction Stop

    $latest = $releases[0].tag_name -replace '^v', ''
    $releaseUrl = "https://$GITLAB_HOST/$GITLAB_PROJECT/-/releases/$($releases[0].tag_name)"

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
    Write-Host '  [WARN] Could not reach GitLab. Check your connection.'
    Write-Host ''
    exit 2
}
