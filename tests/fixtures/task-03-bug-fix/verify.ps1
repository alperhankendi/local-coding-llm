#Requires -Version 7.0
$ErrorActionPreference = 'Stop'

if (-not (Test-Path calculator.py)) {
    Write-Host 'verify FAIL: calculator.py not produced'
    exit 1
}
if (-not (Test-Path test_calculator.py)) {
    Write-Host 'verify FAIL: test_calculator.py missing (validator should have copied it from input/)'
    exit 1
}

$out = & python -m pytest test_calculator.py -q 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host 'verify FAIL: pytest failed'
    Write-Host $out
    exit 1
}

Write-Host 'verify OK'
exit 0
