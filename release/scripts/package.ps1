[CmdletBinding()]
param([ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version = '3.0.0')
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $project
try {
    $hostInfo = rustc -vV
    if ($LASTEXITCODE -ne 0 -or -not ($hostInfo -match '^host: x86_64-pc-windows-')) { throw 'This packaging script requires a native Windows x64 Rust toolchain.' }
    if ($env:CARGO_BUILD_TARGET -and $env:CARGO_BUILD_TARGET -notmatch '^x86_64-pc-windows-') { throw 'Use a native x64 target for this package.' }
    cargo build --release --locked
    if ($LASTEXITCODE -ne 0) { throw 'Release build failed.' }
    $destination = Join-Path $project 'dist'
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    $stage = Join-Path $destination "ptu-$Version-windows-x86_64"
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    Copy-Item -LiteralPath 'target/release/ptu.exe' -Destination $stage -Force
    Copy-Item -LiteralPath 'README.md','LICENSE.md','CHANGELOG.md','CONTRIBUTING.md','Cargo.toml','Cargo.lock','.gitignore' -Destination $stage -Force
    Copy-Item -LiteralPath 'docs','src','tests','scripts','examples','.github' -Destination $stage -Recurse -Force
    $archive = Join-Path $destination "ptu-$Version-windows-x86_64.zip"
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $archive -Force
    $hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText((Join-Path $destination 'SHA256SUMS'), "$hash  $([IO.Path]::GetFileName($archive))`n", [Text.UTF8Encoding]::new($false))
    Write-Output $archive
} finally { Pop-Location }
