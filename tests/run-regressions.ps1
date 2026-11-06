$ErrorActionPreference='Stop'
foreach($suite in Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'regression-*.ps1' | Sort-Object Name){
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $suite.FullName
    if($LASTEXITCODE -ne 0){throw ('Regression suite failed: '+$suite.Name)}
}
