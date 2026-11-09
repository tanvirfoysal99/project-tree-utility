[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Binary,
    [string]$Destination = (Join-Path $env:LOCALAPPDATA 'Programs\PTU'),
    [switch]$AddToPath
)
$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $Binary).Path
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw 'Binary must be a file.' }
$targetDirectory = [IO.Path]::GetFullPath($Destination)
New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
$target = Join-Path $targetDirectory 'ptu.exe'
if ($source -ne $target) { Copy-Item -LiteralPath $source -Destination $target -Force }
if ($AddToPath) {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($targetDirectory -notin @($userPath -split ';')) {
        $newPath = if ($userPath) { $userPath.TrimEnd(';') + ';' + $targetDirectory } else { $targetDirectory }
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    }
}
Write-Output "Installed $target"
if ($AddToPath) { Write-Output 'Open a new terminal to use the updated PATH.' }
