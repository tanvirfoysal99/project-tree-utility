param(
    [Parameter(Mandatory = $true)][ValidateSet('store', 'clear')][string]$Action,
    [string]$Target = '',
    [string]$Username = 'oauth2',
    [string]$Secret = '',
    [switch]$Ci
)

$ErrorActionPreference = 'Stop'

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

function Get-TargetParts {
    param([Parameter(Mandatory = $true)][string]$Target)

    $clean = $Target.Trim()
    if ($clean.StartsWith('git:', [System.StringComparison]::OrdinalIgnoreCase)) {
        $clean = $clean.Substring(4)
    }

    try {
        $uri = [System.Uri]$clean
        return [pscustomobject]@{
            Protocol = if ($uri.Scheme) { $uri.Scheme } else { 'https' }
            Host     = $uri.Host
            Path     = $uri.AbsolutePath.Trim('/')
        }
    } catch {
        return [pscustomobject]@{
            Protocol = 'https'
            Host     = $clean
            Path     = ''
        }
    }
}

function Get-GcmCommand {
    $cmd = Get-Command 'git-credential-manager-core' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd }

    $cmd = Get-Command 'git-credential-manager' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd }

    return $null
}

function Invoke-GcmCredentialAction {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('store', 'erase')][string]$Action,
        [Parameter(Mandatory = $true)][string]$Target,
        [string]$Username = 'oauth2',
        [string]$Secret = ''
    )

    $cmd = Get-GcmCommand
    if (-not $cmd) { return $false }

    $parts = Get-TargetParts -Target $Target
    if (-not $parts.Host) { return $false }

    $payload = "protocol=$($parts.Protocol)`nhost=$($parts.Host)`n"
    if ($parts.Path) { $payload += "path=$($parts.Path)`n" }
    if ($Username) { $payload += "username=$Username`n" }
    if ($Secret) { $payload += "password=$Secret`n" }
    $payload += "`n"

    try {
        $null = $payload | & $cmd.Source $Action 2>$null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

if (-not $Target) {
    Write-Host '[ERROR] A credential target is required.'
    exit 2
}

switch ($Action) {
    'store' {
        if (-not $Secret) {
            if ($Ci) {
                Write-Host '[ERROR] CI mode requires the secret to be passed explicitly.'
                exit 1
            }
            $Secret = Read-Secret -Prompt 'Personal Access Token'
        }

        if (Invoke-GcmCredentialAction -Action store -Target $Target -Username $Username -Secret $Secret) {
            Write-Host ('[OK] Stored credential: ' + $Target)
            exit 0
        }

        $cmd = Get-Command cmdkey.exe -ErrorAction SilentlyContinue
        if (-not $cmd) {
            Write-Host '[ERROR] No credential helper found (git-credential-manager or cmdkey.exe).'
            exit 2
        }

        & $cmd.Source "/generic:$Target" "/user:$Username" "/pass:$Secret" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host '[ERROR] Credential store update failed.'
            exit $LASTEXITCODE
        }

        Write-Host ('[OK] Stored credential: ' + $Target)
        exit 0
    }

    'clear' {
        if (Invoke-GcmCredentialAction -Action erase -Target $Target) {
            Write-Host ('[OK] Removed credential: ' + $Target)
            exit 0
        }

        $cmd = Get-Command cmdkey.exe -ErrorAction SilentlyContinue
        if (-not $cmd) {
            Write-Host '[ERROR] No credential helper found (git-credential-manager or cmdkey.exe).'
            exit 2
        }

        & $cmd.Source "/delete:$Target" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host '[ERROR] Credential delete failed.'
            exit $LASTEXITCODE
        }

        Write-Host ('[OK] Removed credential: ' + $Target)
        exit 0
    }
}
