# Optional integration check: downloads dependencies into a disposable directory.
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('ptu-template-build-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $scratch
$oldMetrics=$env:WRANGLER_SEND_METRICS;$oldCi=$env:CI
try{
    $env:WRANGLER_SEND_METRICS='false';$env:CI='true'
    foreach($name in @('react-vite','hono-worker')){
        & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $repo 'src/scaffold.ps1') -Format template -TemplateName $name -ProjectName $name -TargetBase $scratch -Ci
        if($LASTEXITCODE -ne 0){throw ('Scaffold failed: '+$name)}
        $project=Join-Path $scratch $name
        Push-Location -LiteralPath $project
        try {
            & npm.cmd install --no-audit --no-fund
            if($LASTEXITCODE -ne 0){throw ('Dependency installation failed: '+$name)}
            & npm.cmd run typecheck
            if($LASTEXITCODE -ne 0){throw ('Typecheck failed: '+$name)}
            & npm.cmd run build
            if($LASTEXITCODE -ne 0){throw ('Build failed: '+$name)}
        } finally { Pop-Location }
        Write-Host ('PASS: '+$name+' installs, typechecks, and builds.')
    }
}finally{
    $env:WRANGLER_SEND_METRICS=$oldMetrics;$env:CI=$oldCi
    $resolved=[IO.Path]::GetFullPath($scratch);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if($resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -match '^ptu-template-build-[a-f0-9]{32}$'){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
