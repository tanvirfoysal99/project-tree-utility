[CmdletBinding()]
param([string]$Binary = (Join-Path $PSScriptRoot '../target/debug/ptu.exe'))
$ErrorActionPreference='Stop'
$binaryPath=(Resolve-Path -LiteralPath $Binary).Path
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$scratch=Join-Path $projectRoot ('target/live-check-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
Push-Location $scratch
try {
    foreach($provider in 'github','gitlab') {
        $repo=if($provider -eq 'github'){'https://github.com/octocat/Hello-World'}else{'https://gitlab.com/gitlab-examples/nodejs'}
        & $binaryPath gittree --ci --anonymous --provider $provider --repo $repo --branch master --format json --output "$provider.json"
        if($LASTEXITCODE -ne 0){throw "Public $provider tree export failed"}
        $entries=Get-Content -LiteralPath "$provider.json" -Raw | ConvertFrom-Json
        if(@($entries).Count -eq 0){throw "Public $provider tree was unexpectedly empty"}
        Write-Output "PASS: public $provider layout, $(@($entries).Count) entries"
    }
    & $binaryPath version --check
    if($LASTEXITCODE -ne 0){throw 'Upstream version check failed'}
} finally { Pop-Location; Write-Output "Live-check fixture retained: $scratch" }
