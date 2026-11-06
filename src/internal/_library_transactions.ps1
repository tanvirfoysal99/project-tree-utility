function Write-AtomicLibraryFile {
    param([string]$Path,[string]$Text,[string]$Backup='')
    foreach($candidate in @($Path,$Backup) | Where-Object {$_}){
        if(-not (Test-SafePath $candidate $script:StoreDataDir)){throw 'Unsafe library persistence path.'}
    }
    $temporary=Join-Path $script:StoreDataDir ('.library-'+[guid]::NewGuid().ToString('N')+'.tmp')
    try {
        $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes($Text)
        $stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
        if([IO.File]::Exists($Path)){[IO.File]::Replace($temporary,$Path,$(if($Backup){$Backup}else{$null}),$true)}
        else{[IO.File]::Move($temporary,$Path)}
    }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}

function Get-LibraryJournalPath { return ($script:StoreJson+'.transaction') }

function Recover-LibraryChange {
    $journalPath=Get-LibraryJournalPath
    if(-not [IO.File]::Exists($journalPath)){return}
    if(-not (Test-SafePath $journalPath $script:StoreDataDir)){throw 'Unsafe library recovery journal.'}
    $journal=[IO.File]::ReadAllText($journalPath)|ConvertFrom-Json
    if($journal.Operation -notin @('add','rename','delete') -or -not $journal.Before -or -not $journal.After){throw 'Invalid recovery journal; preserved for manual recovery.'}
    $oldPath=if($journal.Old){Resolve-LibraryPath $journal.Old}else{''}
    $newPath=if($journal.New){Resolve-LibraryPath $journal.New}else{''}
    $current=if([IO.File]::Exists($script:StoreJson)){[IO.File]::ReadAllText($script:StoreJson)}else{''}
    if($current -ceq $journal.After){
        if($journal.Operation -eq 'delete' -and [IO.File]::Exists($newPath)){[IO.File]::Delete($newPath)}
    }else{
        # Roll back only states described by this journal. Ambiguous states are
        # retained for recovery instead of overwriting someone else's file.
        if($journal.Operation -eq 'add' -and [IO.File]::Exists($newPath)){
            if((Get-FileHash -LiteralPath $newPath -Algorithm SHA256).Hash -ne $journal.Hash){throw 'Uncommitted file changed; journal preserved for manual recovery.'}
            [IO.File]::Delete($newPath)
        }
        if($journal.Operation -in @('rename','delete') -and [IO.File]::Exists($newPath)){
            if([IO.File]::Exists($oldPath)){throw 'Both recovery paths exist; journal preserved for manual recovery.'}
            [IO.File]::Move($newPath,$oldPath)
        }
        if($current -cne $journal.Before){throw 'Library index differs from both journal revisions; manual recovery required.'}
    }
    [IO.File]::Delete($journalPath)
}

function Invoke-LibraryTransaction {
    param([scriptblock]$Action)
    if($script:LibraryLockDepth -gt 0){return (& $Action)}
    Ensure-StoreDirectory
    $lockPath=$script:StoreJson+'.lock'
    if(-not (Test-SafePath $lockPath $script:StoreDataDir)){throw 'Unsafe library lock path.'}
    $timer=[Diagnostics.Stopwatch]::StartNew();$lock=$null
    while(-not $lock){
        try{$lock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}
        catch [IO.IOException]{if($timer.ElapsedMilliseconds -ge 5000){throw 'Library is busy; timed out waiting for its lock.'};Start-Sleep -Milliseconds 50}
    }
    $script:LibraryLockDepth=1
    try{Recover-LibraryChange;return (& $Action)}finally{$script:LibraryLockDepth=0;$lock.Dispose()}
}

function Commit-LibraryChange {
    param($Index,[string]$Operation,[string]$Old,[string]$New,[scriptblock]$Change,[string]$Hash='')
    Confirm-LibraryIndex $Index
    $journalPath=Get-LibraryJournalPath
    $journal=[ordered]@{Operation=$Operation;Old=$Old;New=$New;Hash=$Hash;Before=[IO.File]::ReadAllText($script:StoreJson);After=($Index|ConvertTo-Json -Depth 10)}
    Write-AtomicLibraryFile $journalPath ($journal|ConvertTo-Json -Depth 12)
    try{
        & $Change
        Write-LibraryIndexCore $Index
        Recover-LibraryChange
    }catch{
        $failure=$_.Exception.Message
        try{Recover-LibraryChange}catch{throw ($failure+' Recovery pending: '+$_.Exception.Message)}
        throw $failure
    }
}

function Get-LibraryIndex { Invoke-LibraryTransaction { Read-LibraryIndexCore } }
function Save-LibraryIndex { param($Index);Invoke-LibraryTransaction { Write-LibraryIndexCore $Index } }
function Add-TreeEntry { param($SourceFile,$UserName,$Format,$Source);Invoke-LibraryTransaction { Add-TreeEntryCore $SourceFile $UserName $Format $Source } }
function Rename-TreeEntry { param($NameOrId,$NewName);Invoke-LibraryTransaction { Rename-TreeEntryCore $NameOrId $NewName } }
function Remove-TreeEntry { param($NameOrId);Invoke-LibraryTransaction { Remove-TreeEntryCore $NameOrId } }
function Register-OrphanFile { param($Orphan,$UserName);Invoke-LibraryTransaction { Register-OrphanFileCore $Orphan $UserName } }
function Clear-Library {
    Invoke-LibraryTransaction {
        $index=Get-LibraryIndex
        foreach($entry in @($index.trees)){Remove-TreeEntryCore $entry.id | Out-Null}
        foreach($orphan in @(Get-OrphanFiles)){
            $old='store_trees\'+[IO.Path]::GetFileName($orphan.FilePath)
            $stash='store_trees\.pending-'+[guid]::NewGuid().ToString('N')+'.txt'
            $oldPath=Resolve-LibraryPath $old;$newPath=Resolve-LibraryPath $stash
            Commit-LibraryChange (Get-LibraryIndex) 'delete' $old $stash { [IO.File]::Move($oldPath,$newPath) }
        }
    }
}
