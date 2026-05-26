#Requires -Version 7.0
$ErrorActionPreference = 'Stop'

if (-not (Test-Path messy.py)) {
    Write-Host 'verify FAIL: messy.py not produced'
    exit 1
}
if (-not (Test-Path test_messy.py)) {
    Write-Host 'verify FAIL: test_messy.py missing (validator should have copied it from input/)'
    exit 1
}

$out = & python -m pytest test_messy.py -q 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host 'verify FAIL: pytest failed'
    Write-Host $out
    exit 1
}

Write-Host 'verify OK'
exit 0
