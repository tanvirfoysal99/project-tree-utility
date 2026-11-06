function Invoke-TreeHttpRequest {
    param([string]$Uri,[hashtable]$Headers=@{},[ValidateRange(1,120)][int]$TimeoutSec=15,[ValidateRange(0,5)][int]$Retries=2)
    $parsed=[Uri]$Uri
    if($parsed.Scheme -ne 'https' -or $parsed.UserInfo){throw 'API requests require HTTPS without embedded credentials.'}
    for($attempt=0;$attempt -le $Retries;$attempt++){
        try{return (Invoke-WebRequest -Uri $Uri -Headers $Headers -UseBasicParsing -TimeoutSec $TimeoutSec -MaximumRedirection 0 -ErrorAction Stop)}
        catch{
            $response=$_.Exception.Response;$status=0
            if($response){$status=[int]$response.StatusCode}
            $transient=$status -in @(408,429,500,502,503,504) -or ($_.Exception -is [Net.WebException] -and -not $response)
            if($transient -and $attempt -lt $Retries){
                $delay=[Math]::Min(8,[Math]::Pow(2,$attempt))
                $retryAfter=0
                if($response -and [int]::TryParse([string]$response.Headers['Retry-After'],[ref]$retryAfter)){$delay=[Math]::Min(8,[Math]::Max(0,$retryAfter))}
                Start-Sleep -Milliseconds ([int]($delay*1000));continue
            }
            $detail=switch($status){401{'Unauthorized; check stored credentials.'};403{'Forbidden; check API permissions or rate limits.'};404{'Repository or branch not found.'};0{'Connection failed or timed out.'};default{'API request failed.'}}
            throw ('HTTP '+$status+': '+$detail+' Attempts: '+($attempt+1))
        }
    }
}

function Assert-RemoteTreeEntries {
    param([AllowEmptyCollection()][object[]]$Entries)
    $seen=@{}
    foreach($entry in $Entries){
        if(-not $entry.path -or $entry.type -notin @('tree','blob','commit') -or (Test-DangerousName $entry.path)){throw 'API returned an invalid tree entry.'}
        if($seen.ContainsKey([string]$entry.path)){throw 'API returned duplicate tree paths.'};$seen[[string]$entry.path]=$true
    }
}
