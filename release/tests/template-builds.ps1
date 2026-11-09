[CmdletBinding()]
param([string]$Binary = (Join-Path $PSScriptRoot '../target/debug/ptu.exe'))
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$binaryPath = (Resolve-Path -LiteralPath $Binary).Path
$scratchRoot = Join-Path $projectRoot ('target/template-check-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratchRoot -Force | Out-Null
$variables = @{
    CI='true'; WRANGLER_SEND_METRICS='false';
    WRANGLER_LOG_PATH=(Join-Path $scratchRoot 'wrangler.log');
    NPM_CONFIG_CACHE=(Join-Path $projectRoot 'target/npm-cache');
    NPM_CONFIG_USERCONFIG=(Join-Path $scratchRoot 'user.npmrc');
    NPM_CONFIG_GLOBALCONFIG=(Join-Path $scratchRoot 'global.npmrc');
    XDG_CONFIG_HOME=(Join-Path $scratchRoot 'config');
    XDG_CACHE_HOME=(Join-Path $scratchRoot 'cache')
}
[IO.File]::WriteAllText($variables.NPM_CONFIG_USERCONFIG, "registry=https://registry.npmjs.org/`n")
[IO.File]::WriteAllText($variables.NPM_CONFIG_GLOBALCONFIG, '')
$previous=@{}
try {
    foreach($key in $variables.Keys) { $previous[$key]=[Environment]::GetEnvironmentVariable($key,'Process'); [Environment]::SetEnvironmentVariable($key,$variables[$key],'Process') }
    foreach($name in 'react-vite','hono-worker','monorepo-pnpm') {
        & $binaryPath scaffold --ci --template $name --target $scratchRoot --project $name
        if($LASTEXITCODE -ne 0) { throw "Scaffold failed: $name" }
        Push-Location (Join-Path $scratchRoot $name)
        try {
            if($name -eq 'monorepo-pnpm') {
                $child=@{name='web-fixture';version='1.0.0';private=$true;scripts=@{build='node -e "process.exit(0)"';test='node -e "process.exit(0)"'}} | ConvertTo-Json -Depth 5
                [IO.File]::WriteAllText((Join-Path $PWD 'apps/web/package.json'),$child)
                & npx.cmd --yes pnpm@10 install --ignore-scripts
                if($LASTEXITCODE -ne 0) { throw 'pnpm workspace installation failed' }
                & npx.cmd --yes pnpm@10 run build
                if($LASTEXITCODE -ne 0) { throw 'pnpm recursive build failed' }
                & npx.cmd --yes pnpm@10 run test
                if($LASTEXITCODE -ne 0) { throw 'pnpm recursive test failed' }
            } else {
                & npm.cmd install --no-audit --no-fund --fetch-retries=1 --fetch-timeout=30000
                if($LASTEXITCODE -ne 0) { throw "Dependency installation failed: $name" }
                & npm.cmd run typecheck
                if($LASTEXITCODE -ne 0) { throw "Typecheck failed: $name" }
                & npm.cmd run build
                if($LASTEXITCODE -ne 0) { throw "Build failed: $name" }
            }
        } finally { Pop-Location }
        Write-Output "PASS: $name installs and builds"
    }
} finally {
    foreach($key in $previous.Keys) { [Environment]::SetEnvironmentVariable($key,$previous[$key],'Process') }
    Write-Output "Validation fixture retained: $scratchRoot"
}
