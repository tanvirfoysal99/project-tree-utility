[CmdletBinding()]
param([switch]$IncludeNativeAuth)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$archive=Join-Path $projectRoot 'dist/ptu-3.0.0-windows-x86_64.zip'
$manifest=Join-Path $projectRoot 'dist/SHA256SUMS'
$expected=([IO.File]::ReadAllText($manifest).Trim() -split '\s+')[0]
$actual=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
if($actual -ne $expected){throw 'Portable ZIP checksum mismatch'}
$extracted=Join-Path $projectRoot ('target/package-check-'+[guid]::NewGuid().ToString('N'))
Expand-Archive -LiteralPath $archive -DestinationPath $extracted
foreach($file in 'ptu.exe','Cargo.toml','Cargo.lock','CONTRIBUTING.md','docs/QA_REPORT.md','src/main.rs','tests/commands.rs','scripts/install.ps1','examples/layout.yaml','.github/workflows/ci.yml') {
    if(-not(Test-Path -LiteralPath (Join-Path $extracted $file) -PathType Leaf)){throw "Package omits $file"}
}
$binary=Join-Path $extracted 'ptu.exe'
if((Get-FileHash -LiteralPath $binary).Hash -ne (Get-FileHash -LiteralPath (Join-Path $projectRoot 'target/release/ptu.exe')).Hash){throw 'Packaged executable differs from release build'}
foreach($doc in Get-ChildItem -LiteralPath $extracted -Recurse -File -Filter '*.md') {
    foreach($match in [regex]::Matches([IO.File]::ReadAllText($doc.FullName),'\]\(([^)]+)\)')) {
        $target=$match.Groups[1].Value.Split('#')[0]
        if($target -and $target -notmatch '^[a-z]+://' -and -not(Test-Path -LiteralPath (Join-Path $doc.DirectoryName $target))){throw "Broken packaged link in $($doc.Name): $target"}
    }
}
$originalBinary=[Environment]::GetEnvironmentVariable('PTU_TEST_BINARY','Process')
$originalPath=$env:PATH
Push-Location $projectRoot
try {
    $env:PATH="$env:SystemRoot\System32;$env:SystemRoot"
    & $binary --version
    if($LASTEXITCODE -ne 0){throw 'Packaged executable requires an unavailable runtime'}
    $env:PATH=$originalPath
    $env:PTU_TEST_BINARY=$binary
    & cargo test --locked --test cli --test commands --test watch
    if($LASTEXITCODE -ne 0){throw 'Packaged CLI command matrix failed'}
    if($IncludeNativeAuth) {
        & cargo test --locked --test native_auth -- --ignored
        if($LASTEXITCODE -ne 0){throw 'Packaged native credential integration failed'}
    }
    Write-Output 'PASS: packaged executable, checksum, required files, documentation links, and command matrix'
} finally {
    $env:PATH=$originalPath
    [Environment]::SetEnvironmentVariable('PTU_TEST_BINARY',$originalBinary,'Process')
    Pop-Location
    Write-Output "Package-check fixture retained: $extracted"
}
