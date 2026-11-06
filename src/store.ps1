<#
.SYNOPSIS
    store.ps1
    Project Tree Library - Core Logic
    Part of the Project Tree Utility toolkit

.DESCRIPTION
    Manages store_data.json and the store_trees\ directory.
    All JSON read/write, file copy, rename, delete, slug generation,
    orphan detection, and console table rendering live here.

    Dot-sourced by the CLI and action adapters; use tree.bat library publicly.
    Mutations use the transaction helpers for locking, atomic index replacement,
    rollback, and interrupted-operation recovery.

.NOTES
    Functions exported:
        Get-LibraryIndex       Read (or create) store_data.json
        Save-LibraryIndex      Write store_data.json
        Ensure-StoreDirectory  Create store_trees\ if missing
        Get-SafeSlug           User name -> collision-safe filename slug
        Get-EntryCount         Count non-blank non-comment lines in a .txt
        Add-TreeEntry          Copy file + write JSON entry
        Remove-TreeEntry       Delete file + remove JSON entry
        Rename-TreeEntry       Rename file + update JSON entry
        Get-TreePath           Name or id -> physical file path
        Get-OrphanFiles        .txt files in store_trees\ with no JSON entry
        Show-LibraryTable      Print formatted console table
        Resolve-TreeSelection  Interactive numbered picker -> returns entry
#>

$ErrorActionPreference = 'Stop'

# Paths (resolved relative to project root)
$script:StoreRoot    = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$script:StoreJson    = Join-Path $script:StoreRoot 'data\store_data.json'
$script:StoreTreeDir = Join-Path $script:StoreRoot 'data\store_trees'
$script:StoreDataDir = Join-Path $script:StoreRoot 'data'

# Shared library (for format detection + entry counting)
$sharedPath = Join-Path $PSScriptRoot 'internal\_shared.ps1'
if (Test-Path -LiteralPath $sharedPath) { . $sharedPath }

function Resolve-LibraryPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    # Accept the original data-relative form and migrate repo-relative paths.
    $normalized = $RelativePath.Replace('/', '\')
    if ($normalized.StartsWith('data\', [StringComparison]::OrdinalIgnoreCase)) {
        $normalized = $normalized.Substring(5)
    }
    if ($normalized -notmatch '^store_trees\\[^\\]+\.txt$') {
        throw ('Invalid library file path: ' + $RelativePath)
    }
    $leaf = $normalized.Substring(12)
    if (Test-DangerousName -Name $leaf) { throw ('Unsafe library filename: ' + $RelativePath) }
    if ($leaf -match ':' -or $leaf -match '[. ]$') { throw ('Invalid library filename: ' + $RelativePath) }
    $fullPath = [IO.Path]::GetFullPath((Join-Path $script:StoreDataDir $normalized))
    if (-not (Test-SafePath -CandidatePath $fullPath -AllowedBase $script:StoreTreeDir)) {
        throw ('Library file path is outside the library or crosses a reparse point: ' + $RelativePath)
    }
    return $fullPath
}

function Confirm-LibraryIndex {
    param([object]$Index)
    if ($null -eq $Index -or $Index.version -ne 1 -or $null -eq $Index.trees -or
        $Index.trees -is [string] -or $Index.trees -isnot [System.Collections.IEnumerable]) {
        throw 'Invalid library index schema (expected version 1 and a trees array).'
    }
    $ids = @{}
    foreach ($entry in $Index.trees) {
        if (-not $entry.id -or -not $entry.name -or -not $entry.file -or $ids.ContainsKey([string]$entry.id)) {
            throw 'Invalid library entry: id, name and file are required; ids must be unique.'
        }
        $ids[[string]$entry.id] = $true
        $null = Resolve-LibraryPath -RelativePath ([string]$entry.file)
    }
}

# ─────────────────────────────────────────────────────────────
# Ensure-StoreDirectory
# Creates store_trees\ if it does not exist.
# ─────────────────────────────────────────────────────────────
function Ensure-StoreDirectory {
    if (-not (Test-SafePath -CandidatePath $script:StoreJson -AllowedBase $script:StoreDataDir)) {
        throw 'Library index crosses a reparse point.'
    }
    if (-not (Test-SafePath -CandidatePath $script:StoreTreeDir -AllowedBase $script:StoreDataDir)) {
        throw 'Library directory crosses a reparse point.'
    }
    if (-not (Test-Path -LiteralPath $script:StoreTreeDir)) {
        New-Item -ItemType Directory -Path $script:StoreTreeDir -Force | Out-Null
        Write-Host '[INFO] Created store_trees\ directory.'
    }
}

# ─────────────────────────────────────────────────────────────
# Get-LibraryIndex
# Returns parsed index object. Creates empty skeleton if missing.
# ─────────────────────────────────────────────────────────────
function Read-LibraryIndexCore {
    Ensure-StoreDirectory

    if (-not (Test-Path -LiteralPath $script:StoreJson)) {
        $skeleton = [ordered]@{
            version = 1
            trees   = @()
        }
        $json = $skeleton | ConvertTo-Json -Depth 10
        Write-AtomicLibraryFile $script:StoreJson $json ($script:StoreJson+'.bak')
        return $skeleton
    }

    $raw = [System.IO.File]::ReadAllText($script:StoreJson, [System.Text.Encoding]::UTF8)
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw 'Library index is empty; preserve it for recovery rather than replacing it.'
    }

    try {
        $parsed = $raw | ConvertFrom-Json
    } catch {
        throw ('Cannot read library index: ' + $_.Exception.Message)
    }
    Confirm-LibraryIndex -Index $parsed
    $migrated = $false
    foreach ($entry in $parsed.trees) {
        $canonical = 'store_trees\' + [IO.Path]::GetFileName((Resolve-LibraryPath -RelativePath $entry.file))
        if ($entry.file -cne $canonical) { $entry.file = $canonical; $migrated = $true }
    }
    if ($migrated) { Save-LibraryIndex -Index $parsed }
    return $parsed
}

# ─────────────────────────────────────────────────────────────
# Save-LibraryIndex
# Writes the index object back to store_data.json cleanly.
# ─────────────────────────────────────────────────────────────
function Write-LibraryIndexCore {
    param([object]$Index)
    Ensure-StoreDirectory
    Confirm-LibraryIndex -Index $Index
    $json = $Index | ConvertTo-Json -Depth 10
    Write-AtomicLibraryFile $script:StoreJson $json ($script:StoreJson+'.bak')
}

# ─────────────────────────────────────────────────────────────
# Get-SafeSlug
# Converts a user-visible name to a safe filename slug.
# Spaces -> hyphens, strips specials, truncates at 60, appends
# -2/-3 etc. if the slug already exists in store_trees\.
# ─────────────────────────────────────────────────────────────
function Get-SafeSlug {
    param([string]$Name)

    # Lowercase, replace spaces with hyphens
    $slug = $Name.ToLower().Trim()
    $slug = $slug -replace '\s+', '-'
    # Keep only alphanumeric, hyphens, underscores, dots
    $slug = $slug -replace '[^a-z0-9\-_\.]', ''
    # Collapse multiple hyphens
    $slug = $slug -replace '-{2,}', '-'
    $slug = $slug.Trim('-')
    # Truncate
    if ($slug.Length -gt 60) { $slug = $slug.Substring(0, 60).TrimEnd('-') }
    if ($slug -eq '') { $slug = 'tree' }
    if (Test-DangerousName ($slug + '.txt')) { $slug = 'tree-' + $slug }

    # Collision check
    $base    = $slug
    $counter = 2
    while (Test-Path -LiteralPath (Join-Path $script:StoreTreeDir ($slug + '.txt'))) {
        $slug = $base + '-' + $counter
        $counter++
    }

    return $slug
}

# ─────────────────────────────────────────────────────────────
# Get-EntryCount
# Counts non-blank, non-comment lines in a structure .txt file.
# ─────────────────────────────────────────────────────────────
function Get-EntryCount {
    param([string]$FilePath)
    if (-not (Test-Path -LiteralPath $FilePath)) { return 0 }
    $count = 0
    foreach ($line in [System.IO.File]::ReadAllLines($FilePath, [System.Text.Encoding]::UTF8)) {
        $t = $line.Trim()
        if ($t -ne '' -and -not $t.StartsWith('#')) { $count++ }
    }
    return $count
}

# ─────────────────────────────────────────────────────────────
# Add-TreeEntry
# Copies source file into store_trees\, adds entry to JSON.
# Returns the new entry object, or $null on failure.
# ─────────────────────────────────────────────────────────────
function Add-TreeEntryCore {
    param(
        [string]$SourceFile,
        [string]$UserName,
        [string]$Format,
        [string]$Source   # import | export | git_tree | merge | manual
    )

    if ($Format -eq 'importable') { $Format='dash' }
    $null = Read-StructureFile -FilePath $SourceFile -Format $Format
    Ensure-StoreDirectory

    $index = Get-LibraryIndex

    # Check for duplicate name
    $existingNames = @($index.trees | ForEach-Object { $_.name })
    $finalName = $UserName
    if ($existingNames -contains $UserName) {
        # Find a free suffix
        $counter = 2
        while ($existingNames -contains ($UserName + ' (' + $counter + ')')) { $counter++ }
        $finalName = $UserName + ' (' + $counter + ')'
        Write-Host ("[INFO] Name already exists. Saving as: $finalName")
    }

    $slug    = Get-SafeSlug -Name $finalName
    $destFile = Resolve-LibraryPath -RelativePath ('store_trees\' + $slug + '.txt')

    $count = Get-EntryCount -FilePath $SourceFile
    $now   = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')

    $entry = [ordered]@{
        id       = $slug
        name     = $finalName
        created  = $now
        modified = $now
        format   = $Format
        source   = $Source
        entry_count = $count
        file     = ('store_trees\' + $slug + '.txt')
    }

    # Rebuild trees array (PowerShell JSON arrays need explicit handling)
    $trees = [System.Collections.Generic.List[object]]::new()
    foreach ($t in $index.trees) { $trees.Add($t) }
    $trees.Add($entry)

    $index.trees = $trees.ToArray()
    $relative='store_trees\'+$slug+'.txt'
    $hash=(Get-FileHash -LiteralPath $SourceFile -Algorithm SHA256).Hash
    Commit-LibraryChange $index 'add' '' $relative { [IO.File]::Copy($SourceFile,$destFile,$false) } $hash

    Write-Host ('[OK] Saved to library: ' + $finalName)
    return $entry
}

# ─────────────────────────────────────────────────────────────
# Remove-TreeEntry
# Deletes .txt from store_trees\ and removes JSON entry.
# Accepts name or id.
# ─────────────────────────────────────────────────────────────
function Remove-TreeEntryCore {
    param([string]$NameOrId)

    $index = Get-LibraryIndex
    $target = $index.trees | Where-Object { $_.name -eq $NameOrId -or $_.id -eq $NameOrId } | Select-Object -First 1

    if (-not $target) {
        Write-Host ('[ERROR] No library entry found: ' + $NameOrId)
        return $false
    }

    $filePath=Resolve-LibraryPath $target.file
    $stash='store_trees\.pending-'+[guid]::NewGuid().ToString('N')+'.txt'
    $stashPath=Resolve-LibraryPath $stash
    # Remove from index
    $trees = [System.Collections.Generic.List[object]]::new()
    foreach ($t in $index.trees) {
        if ($t.id -ne $target.id) { $trees.Add($t) }
    }
    $index.trees = $trees.ToArray()
    Commit-LibraryChange $index 'delete' $target.file $stash { if([IO.File]::Exists($filePath)){[IO.File]::Move($filePath,$stashPath)} }

    Write-Host ('[OK] Removed from library: ' + $target.name)
    return $true
}

# ─────────────────────────────────────────────────────────────
# Rename-TreeEntry
# Renames .txt on disk and updates name + id in JSON.
# ─────────────────────────────────────────────────────────────
function Rename-TreeEntryCore {
    param([string]$NameOrId, [string]$NewName)

    $index = Get-LibraryIndex
    $target = $index.trees | Where-Object { $_.name -eq $NameOrId -or $_.id -eq $NameOrId } | Select-Object -First 1

    if (-not $target) {
        Write-Host ('[ERROR] No library entry found: ' + $NameOrId)
        return $false
    }

    # Check new name not already taken
    $existingNames = @($index.trees | ForEach-Object { $_.name })
    if ($existingNames -contains $NewName) {
        Write-Host ('[ERROR] A library entry already exists with that name: ' + $NewName)
        return $false
    }

    $oldFile = Resolve-LibraryPath -RelativePath $target.file
    $newSlug = Get-SafeSlug -Name $NewName
    $newFile = Resolve-LibraryPath -RelativePath ('store_trees\' + $newSlug + '.txt')

    $oldRelative=$target.file
    # Update entry in index
    $trees = [System.Collections.Generic.List[object]]::new()
    foreach ($t in $index.trees) {
        if ($t.id -eq $target.id) {
            $t.name     = $NewName
            $t.id       = $newSlug
            $t.file     = 'store_trees\' + $newSlug + '.txt'
            $t.modified = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
        }
        $trees.Add($t)
    }
    $index.trees = $trees.ToArray()
    Commit-LibraryChange $index 'rename' $oldRelative ('store_trees\'+$newSlug+'.txt') { if([IO.File]::Exists($oldFile)){[IO.File]::Move($oldFile,$newFile)}else{throw 'Cannot rename a missing tree file.'} }

    Write-Host ('[OK] Renamed to: ' + $NewName)
    return $true
}

# ─────────────────────────────────────────────────────────────
# Get-TreePath
# Resolves a name or id to the physical file path.
# Returns empty string if not found.
# ─────────────────────────────────────────────────────────────
function Get-TreePath {
    param([string]$NameOrId)

    $index = Get-LibraryIndex
    $target = $index.trees | Where-Object { $_.name -eq $NameOrId -or $_.id -eq $NameOrId } | Select-Object -First 1
    if (-not $target) { return '' }

    $filePath = Resolve-LibraryPath -RelativePath $target.file
    if (Test-Path -LiteralPath $filePath) { return $filePath }
    return ''
}

# ─────────────────────────────────────────────────────────────
# Get-OrphanFiles
# Returns .txt files in store_trees\ that have no JSON entry.
# Each result: @{ Name; FilePath; Format; EntryCount }
# ─────────────────────────────────────────────────────────────
function Get-OrphanFiles {
    Ensure-StoreDirectory
    $index = Get-LibraryIndex

    $registeredFiles = @($index.trees | ForEach-Object {
        [System.IO.Path]::GetFileName($_.file).ToLower()
    })

    $orphans = [System.Collections.Generic.List[object]]::new()

    Get-ChildItem -LiteralPath $script:StoreTreeDir -Filter '*.txt' -ErrorAction Stop | ForEach-Object {
        if($_.Name.StartsWith('.pending-')){return}
        $safePath = Resolve-LibraryPath -RelativePath ('store_trees\' + $_.Name)
        if ($registeredFiles -notcontains $_.Name.ToLower()) {
            $fmt = 'unknown'
            # Try format detection if _shared.ps1 was loaded
            if (Get-Command 'Get-StructureFormat' -ErrorAction SilentlyContinue) {
                try { $fmt = Get-StructureFormat -FilePath $safePath } catch {}
            }
            $orphans.Add([ordered]@{
                Name       = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
                FilePath   = $safePath
                Format     = $fmt
                EntryCount = '?'
            }) | Out-Null
        }
    }

    return $orphans
}

# ─────────────────────────────────────────────────────────────
# Show-LibraryTable
# Prints the full library list to console.
# Returns total item count (registered + orphans) for picker use.
# ─────────────────────────────────────────────────────────────
function Show-LibraryTable {
    $index   = Get-LibraryIndex
    $orphans = Get-OrphanFiles
    $sep     = [string]::new([char]0x2500, 64)

    $registeredCount = @($index.trees).Count
    $orphanCount     = @($orphans).Count
    $total           = $registeredCount + $orphanCount

    if ($total -eq 0) {
        Write-Host ''
        Write-Host '  Library is empty. Import, export, or merge a tree to get started.'
        Write-Host ''
        return 0
    }

    Write-Host ''
    Write-Host $sep
    Write-Host ('  {0,-4} {1,-30} {2,8}   {3,-12} {4}' -f '#', 'Name', 'Entries', 'Date', 'Source')
    Write-Host $sep

    $num = 1

    # Registered entries
    foreach ($t in $index.trees) {
        $filePath = Resolve-LibraryPath -RelativePath $t.file
        $missing  = -not (Test-Path -LiteralPath $filePath)
        $nameDisp = if ($missing) { $t.name + ' [MISSING]' } else { $t.name }
        $dateDisp = if ($t.created) { $t.created.Substring(0, 10) } else { '?' }
        $cntDisp  = if ($missing)   { '?' } else { $t.entry_count.ToString() }

        Write-Host ('  [{0,-2}] {1,-30} {2,8}   {3,-12} ({4})' -f `
            $num, $nameDisp, $cntDisp, $dateDisp, $t.source)
        $num++
    }

    # Orphan separator + entries
    if ($orphanCount -gt 0) {
        Write-Host ''
        Write-Host ('  ' + [string]::new([char]0x2500, 3) + ' Unregistered files (manual) ' + [string]::new([char]0x2500, 30))

        foreach ($o in $orphans) {
            Write-Host ('  [{0,-2}] {1,-30} {2,8}   {3,-12} [manual]  format: {4}' -f `
                $num, $o.Name, $o.EntryCount, '', $o.Format)
            $num++
        }
    }

    Write-Host $sep
    Write-Host ''
    return $total
}

# ─────────────────────────────────────────────────────────────
# Resolve-TreeSelection
# Given a 1-based number from the user, returns a unified object:
#   @{ Name; FilePath; Format; IsOrphan; IsRegistered; Entry }
# Entry is the JSON object for registered trees, $null for orphans.
# ─────────────────────────────────────────────────────────────
function Resolve-TreeSelection {
    param([int]$Number)

    $index   = Get-LibraryIndex
    $orphans = Get-OrphanFiles

    $regList = @($index.trees)
    $regCount = $regList.Count

    if ($Number -lt 1) { return $null }

    if ($Number -le $regCount) {
        $entry    = $regList[$Number - 1]
        $filePath = Resolve-LibraryPath -RelativePath $entry.file
        return [ordered]@{
            Name         = $entry.name
            FilePath     = $filePath
            Format       = $entry.format
            IsOrphan     = $false
            IsRegistered = $true
            Entry        = $entry
        }
    }

    $orphanIdx = $Number - $regCount - 1
    $orphList  = @($orphans)
    if ($orphanIdx -ge 0 -and $orphanIdx -lt $orphList.Count) {
        $o = $orphList[$orphanIdx]
        return [ordered]@{
            Name         = $o.Name
            FilePath     = $o.FilePath
            Format       = $o.Format
            IsOrphan     = $true
            IsRegistered = $false
            Entry        = $null
        }
    }

    return $null
}

# ─────────────────────────────────────────────────────────────
# Remove-MissingEntries  (interactive helper used by LIST action)
# Prompts user to clean up any entries whose files are gone.
# ─────────────────────────────────────────────────────────────
function Remove-MissingEntries {
    $index = Get-LibraryIndex
    $missing = @($index.trees | Where-Object {
        -not (Test-Path -LiteralPath (Resolve-LibraryPath -RelativePath $_.file))
    })

    if ($missing.Count -eq 0) { return }

    Write-Host ''
    Write-Host ('  [WARN] ' + $missing.Count + ' entries point to missing files:')
    foreach ($m in $missing) {
        Write-Host ('    - ' + $m.name + '  (' + $m.file + ')')
    }
    Write-Host ''
    $ans = Read-Host '  Remove these orphan JSON entries? (y/N)'
    if ($ans.ToLower() -eq 'y') {
        foreach ($m in $missing) {
            Remove-TreeEntry -NameOrId $m.id | Out-Null
        }
        Write-Host '  [OK] Orphan entries removed.'
    }
}

# ─────────────────────────────────────────────────────────────
# Register-OrphanFile
# Promotes a manually-dropped file into a proper JSON entry.
# ─────────────────────────────────────────────────────────────
function Register-OrphanFileCore {
    param([object]$Orphan, [string]$UserName)

    $safePath = Resolve-LibraryPath -RelativePath ('store_trees\' + [IO.Path]::GetFileName($Orphan.FilePath))
    if ([IO.Path]::GetFullPath($Orphan.FilePath) -ne $safePath) {
        throw 'Orphan file must be inside the library directory.'
    }

    $index = Get-LibraryIndex

    $existingNames = @($index.trees | ForEach-Object { $_.name })
    $finalName = $UserName
    if ($existingNames -contains $UserName) {
        $counter = 2
        while ($existingNames -contains ($UserName + ' (' + $counter + ')')) { $counter++ }
        $finalName = $UserName + ' (' + $counter + ')'
        Write-Host ("[INFO] Name taken. Saving as: $finalName")
    }

    $fmt = $Orphan.Format
    if ($fmt -eq 'unknown' -or $fmt -eq '') { $fmt = 'dash' }
    $null=Read-StructureFile $safePath $fmt

    $count = Get-EntryCount -FilePath $safePath
    $now   = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    $slug  = [System.IO.Path]::GetFileNameWithoutExtension($Orphan.FilePath)

    $entry = [ordered]@{
        id          = $slug
        name        = $finalName
        created     = $now
        modified    = $now
        format      = $fmt
        source      = 'manual'
        entry_count = $count
        file        = 'store_trees\' + $slug + '.txt'
    }

    $trees = [System.Collections.Generic.List[object]]::new()
    foreach ($t in $index.trees) { $trees.Add($t) }
    $trees.Add($entry)
    $index.trees = $trees.ToArray()
    Save-LibraryIndex -Index $index

    Write-Host ('[OK] Registered: ' + $finalName)
    return $entry
}

. (Join-Path $PSScriptRoot 'internal/_library_transactions.ps1')
