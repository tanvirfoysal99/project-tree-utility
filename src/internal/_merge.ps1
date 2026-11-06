function Get-ExplicitEntryContent {
    param($Entry)
    if($Entry.HasContent -or ($Entry.Content -and $Entry.Content.Trim())){return [pscustomobject]@{Specified=$true;Value=[string]$Entry.Content}}
    if($Entry.ContentDirective){
        if($Entry.ContentDirective.StartsWith('@content64:')){
            return [pscustomobject]@{Specified=$true;Value=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Entry.ContentDirective.Substring(11)))}
        }
        if($Entry.ContentDirective.StartsWith('@content:')){return [pscustomobject]@{Specified=$true;Value=$Entry.ContentDirective.Substring(9)}}
        throw 'Unsupported content directive.'
    }
    return [pscustomobject]@{Specified=$false;Value=''}
}

function ConvertTo-DashStructure {
    param([object[]]$Entries)
    foreach($entry in $Entries){
        $line=('-'*$entry.Depth)+' '+$entry.Name
        $content=Get-ExplicitEntryContent $entry
        if($content.Specified){$line+=' @content64:'+ [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($content.Value))}
        if($entry.Template){$line+=' @template:'+ $entry.Template}
        $line
    }
}

function Merge-StructureEntries {
    param([object[]]$EntriesA,[object[]]$EntriesB,[ValidateSet('union','a_over_b','b_over_a')][string]$Strategy)
    function Build-Nodes($Entries){
        $root=@{Name='';IsDir=$true;Entry=$null;Children=@{}}
        foreach($entry in $Entries){
            $parts=$entry.Path.Replace('/','\').Split('\');$parent=$root
            for($i=0;$i -lt $parts.Count;$i++){
                $key=$parts[$i]
                if(-not $parent.Children.ContainsKey($key)){$parent.Children[$key]=@{Name=$key;IsDir=$true;Entry=$null;Children=@{}}}
                $parent=$parent.Children[$key]
                if($i -eq $parts.Count-1){$parent.Name=$key;$parent.Entry=$entry;$parent.IsDir=[bool]$entry.IsDir}
            }
        }
        return $root
    }
    function Merge-Node($A,$B,[string]$Path){
        if(-not $A){return $B};if(-not $B){return $A}
        if($A.IsDir -ne $B.IsDir){
            if($Strategy -eq 'union'){throw ('File/directory conflict at '+$Path)}
            if($Strategy -eq 'b_over_a'){return $B};return $A
        }
        $preferred=if($Strategy -eq 'b_over_a'){$B}else{$A}
        $fallback=if($Strategy -eq 'b_over_a'){$A}else{$B}
        $pc=Get-ExplicitEntryContent $preferred.Entry;$fc=Get-ExplicitEntryContent $fallback.Entry
        $pt=[string]$preferred.Entry.Template;$ft=[string]$fallback.Entry.Template
        if($Strategy -eq 'union' -and (($pc.Specified -and $fc.Specified -and $pc.Value -cne $fc.Value) -or ($pt -and $ft -and $pt -ne $ft))){throw ('Content/template conflict at '+$Path)}
        $content=if($pc.Specified){$pc}else{$fc}
        $template=if($pt){$pt}else{$ft}
        $result=@{Name=$preferred.Name;IsDir=$preferred.IsDir;Children=@{};Entry=[pscustomobject]@{HasContent=$content.Specified;Content=$content.Value;Template=$template}}
        foreach($key in @(@($A.Children.Keys)+@($B.Children.Keys)|Sort-Object -Unique)){$result.Children[$key]=Merge-Node $A.Children[$key] $B.Children[$key] ($Path+'/'+$key)}
        return $result
    }
    function Flatten-Nodes($Node,[string]$Parent,[int]$Depth){
        foreach($child in @($Node.Children.Values|Sort-Object @{Expression={-not $_.IsDir}},Name)){
            $path=if($Parent){$Parent+'\'+$child.Name}else{$child.Name}
            $content=Get-ExplicitEntryContent $child.Entry
            [pscustomobject]@{Path=$path;Name=($child.Name+$(if($child.IsDir){'/'}else{''}));Depth=$Depth;IsDir=$child.IsDir;HasContent=$content.Specified;Content=$content.Value;Template=[string]$child.Entry.Template;ContentDirective=''}
            Flatten-Nodes $child $path ($Depth+1)
        }
    }
    $merged=Merge-Node (Build-Nodes $EntriesA) (Build-Nodes $EntriesB) ''
    return @(Flatten-Nodes $merged '' 1)
}
