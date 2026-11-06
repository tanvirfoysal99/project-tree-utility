function Test-TreeWatchEvent {
    param($EventArgs,[string]$BasePath,[string[]]$ExcludeFolders,[int]$MaxDepth)
    $prefix=[IO.Path]::GetFullPath($BasePath).TrimEnd('\')+'\'
    foreach($property in @('FullPath','OldFullPath')){
        $value=[string]$EventArgs.$property
        if($value -and $value.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -and (Test-TreeScope $value.Substring($prefix.Length) $ExcludeFolders $MaxDepth)){return $true}
    }
    return $false
}

function Invoke-TreeWatch {
    param([string]$BasePath,[AllowEmptyCollection()][object[]]$Entries=@(),[string[]]$ExcludeFolders=@(),[int]$MaxDepth=5,[ValidateRange(50,5000)][int]$DebounceMs=250,[ValidateRange(0,2147483647)][int]$DurationSeconds=0,[scriptblock]$OnSnapshot)
    $watcher=$null;$subscriptions=New-Object 'System.Collections.Generic.List[object]'
    $prefix='TreeWatch.'+[guid]::NewGuid().ToString('N')+'.'
    $clock=[Diagnostics.Stopwatch]::StartNew();$lastScan=0L;$lastChange=0L;$dirty=$false
    function Publish-Snapshot {
        try{
            if($Entries.Count){$snapshot=Get-TreeComparison $BasePath $Entries $ExcludeFolders $MaxDepth}
            else{$scan=Get-TreeScan $BasePath $MaxDepth $ExcludeFolders;Assert-CompleteScan $scan;$snapshot=[pscustomobject]@{Scan=$scan}}
            if($OnSnapshot){& $OnSnapshot $snapshot}
        }catch{Write-Host ('[WATCH WARN] Snapshot incomplete; retrying: '+$_.Exception.Message)}
    }
    try{
        $watcher=New-Object IO.FileSystemWatcher
        $watcher.Path=$BasePath;$watcher.IncludeSubdirectories=$true;$watcher.Filter='*'
        $watcher.NotifyFilter=[IO.NotifyFilters]'FileName,DirectoryName,LastWrite,Size,CreationTime'
        foreach($name in @('Created','Changed','Deleted','Renamed','Error')){
            $identifier=$prefix+$name
            Register-ObjectEvent -InputObject $watcher -EventName $name -SourceIdentifier $identifier | Out-Null
            $subscriptions.Add($identifier)
        }
        # Subscribe and enable before the first snapshot so startup changes queue.
        $watcher.EnableRaisingEvents=$true
        Publish-Snapshot
        Write-Host '[WATCH] Ready. Press Ctrl+C to stop.'
        while($DurationSeconds -eq 0 -or $clock.Elapsed.TotalSeconds -lt $DurationSeconds){
            foreach($event in @(Get-Event | Where-Object {$_.SourceIdentifier.StartsWith($prefix)})){
                try{
                    if($event.SourceIdentifier -eq $prefix+'Error'){
                        Write-Host '[WATCH WARN] Watcher error or buffer overflow; scheduling a full rescan.'
                        $dirty=$true;$lastChange=$clock.ElapsedMilliseconds-$DebounceMs
                    }elseif(Test-TreeWatchEvent $event.SourceEventArgs $BasePath $ExcludeFolders $MaxDepth){
                        $dirty=$true;$lastChange=$clock.ElapsedMilliseconds
                    }
                }finally{Remove-Event -EventIdentifier $event.EventIdentifier -ErrorAction SilentlyContinue}
            }
            if(($dirty -and $clock.ElapsedMilliseconds-$lastChange -ge $DebounceMs) -or $clock.ElapsedMilliseconds-$lastScan -ge 5000){
                Publish-Snapshot;$lastScan=$clock.ElapsedMilliseconds;$dirty=$false
            }
            Start-Sleep -Milliseconds 50
        }
    }finally{
        if($watcher){$watcher.EnableRaisingEvents=$false}
        foreach($identifier in $subscriptions){Unregister-Event -SourceIdentifier $identifier -ErrorAction SilentlyContinue}
        foreach($event in @(Get-Event | Where-Object {$_.SourceIdentifier.StartsWith($prefix)})){Remove-Event -EventIdentifier $event.EventIdentifier -ErrorAction SilentlyContinue}
        if($watcher){$watcher.Dispose()}
    }
}
