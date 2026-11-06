param(
    [Parameter(Mandatory = $true)][string]$StructureFile,
    [Parameter(Mandatory = $true)][ValidateSet('dash', 'tab', 'treesym', 'space', 'json', 'yaml', 'template')][string]$Format,
    [Parameter(Mandatory = $true)][string]$TargetBase,
    [Parameter(Mandatory = $true)][string]$ProjectName,
    [int]$SpaceUnit = 2
)

$ErrorActionPreference = 'Stop'

$shared = Join-Path $PSScriptRoot 'internal\_shared.ps1'
if (-not (Test-Path -LiteralPath $shared)) {
    Write-Host '[ERROR] _shared.ps1 not found alongside scaffold_validate.ps1.'
    exit 2
}

. $shared

try {
    $projectRoot = Resolve-SafeProjectRoot -TargetBase $TargetBase -ProjectName $ProjectName
    if ($Format -eq 'template') {
        Write-Color '[SECURITY] Template preset selected; built-in definitions will be used.' Gray
        exit 0
    }

    if (-not (Test-Path -LiteralPath $StructureFile)) {
        Write-Color ('[SECURITY] File not found: ' + $StructureFile) Red
        exit 1
    }

    if (-not (Confirm-StructureFormat -FilePath $StructureFile -Format $Format -SpaceUnit $SpaceUnit)) {
        Write-Color ('[SECURITY] Structure file failed format validation (' + $Format + ').') Red
        exit 1
    }

    $entries = Read-StructureFile -FilePath $StructureFile -Format $Format -SpaceUnit $SpaceUnit
    $badNames = $entries | Where-Object { Test-DangerousName -Name $_.Name.TrimEnd('/') }
    if ($badNames) {
        foreach ($entry in $badNames) {
            Write-Color ('[SECURITY] Dangerous name: ' + $entry.Name) Red
        }
        Write-Color '[SECURITY] Structure file contains dangerous entry names. Aborting.' Red
        exit 1
    }

    $stack = @{}
    $failed = $false
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $e = $entries[$i]
        $parent = if ($e.Depth -eq 1) { $projectRoot } else { $stack[$e.Depth - 1] }
        if (-not $parent) { $parent = $projectRoot }
        try {
            $full = Join-Path $parent $e.Name.TrimEnd('/')
        } catch {
            Write-Color ('[SECURITY] Invalid path component: ' + $e.Name) Red
            $failed = $true
            continue
        }
        # Always update stack: any entry can be a parent regardless of trailing slash
        $stack[$e.Depth] = $full
        if (-not (Test-SafePath -CandidatePath $full -AllowedBase $projectRoot)) {
            Write-Color ('[SECURITY] Unsafe path: ' + $full) Red
            $failed = $true
        }
    }

    if ($failed) {
        Write-Color '[SECURITY] One or more paths would write outside the target base. Aborting.' Red
        exit 1
    }

    Write-Color '[SECURITY] All checks passed.' Green
    exit 0
} catch {
    Write-Color ('[ERROR] Security validation failed: ' + $_.Exception.Message) Red
    exit 2
}
