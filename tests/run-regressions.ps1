$ErrorActionPreference='Stop'
$suites = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.tests.ps1' | Sort-Object Name)
if (-not $suites.Count) { throw 'No regression test suites were found.' }
foreach($suite in $suites){
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $suite.FullName
    if($LASTEXITCODE -ne 0){throw ('Regression suite failed: '+$suite.Name)}
}
