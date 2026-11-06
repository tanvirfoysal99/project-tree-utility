param(
    [Parameter(Mandatory = $true)][ValidateSet('store', 'clear')][string]$Action,
    [string]$Target = '',
    [string]$Username = 'oauth2',
    [string]$SecretEnv = '',
    [switch]$SecretStdin,
    [switch]$Ci
)

$ErrorActionPreference = 'Stop'
if ($env:TREE_CI -match '^(?i:1|true|yes)$') { $Ci=$true }
if ($Ci) { $env:GCM_INTERACTIVE='Never'; $env:GIT_TERMINAL_PROMPT='0' }

function Read-Secret {
    param([string]$Prompt)
    $secure = Read-Host $Prompt -AsSecureString
    try {
        $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($secure)
        try {
            return [System.Runtime.InteropServices.Marshal]::PtrToStringUni($ptr)
        } finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($ptr)
        }
    } finally {
        $secure.Dispose()
    }
}

try {
    . (Join-Path $PSScriptRoot 'internal/_credentials.ps1')
    if($args.Count){throw 'Literal secret arguments are unsupported; use -SecretEnv or -SecretStdin.'}
    $Target=ConvertTo-CredentialTarget $Target
    if($Action -eq 'clear'){
        Invoke-CredentialVault delete $Target
        Write-Host '[OK] Removed credential from Windows vault.'
        exit 0
    }
    if($SecretEnv -and $SecretStdin){throw 'Choose one secret input channel.'}
    $secret=if($SecretEnv){[Environment]::GetEnvironmentVariable($SecretEnv)}elseif($SecretStdin){[Console]::In.ReadLine()}elseif(-not $Ci){Read-Secret 'Personal Access Token'}else{throw 'CI storage requires -SecretEnv or -SecretStdin.'}
    if([string]::IsNullOrEmpty($secret) -or $secret -match '[\r\n]'){throw 'A nonempty single-line secret is required.'}
    Invoke-CredentialVault write $Target $Username $secret
    Write-Host '[OK] Stored credential in Windows vault.'
    exit 0
}catch{Write-Host ('[ERROR] Credential operation failed: '+$_.Exception.Message);exit 2}
finally{$secret=$null}