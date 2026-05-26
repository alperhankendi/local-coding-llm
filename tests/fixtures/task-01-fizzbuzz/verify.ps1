#Requires -Version 7.0
# Runs in the per-task working directory after the model's output is materialized there.
$ErrorActionPreference = 'Stop'

if (-not (Test-Path fizzbuzz.py)) {
    Write-Host 'verify FAIL: fizzbuzz.py not produced'
    exit 1
}

$out = & python fizzbuzz.py 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "verify FAIL: python exited with $LASTEXITCODE"
    Write-Host $out
    exit 1
}

$lines = ($out -split "`r?`n") | Where-Object { $_ -ne '' }
if ($lines.Count -ne 100) {
    Write-Host "verify FAIL: expected 100 lines, got $($lines.Count)"
    exit 1
}

$checks = @(
    @{Index=0;  Expected='1'}
    @{Index=1;  Expected='2'}
    @{Index=2;  Expected='Fizz'}
    @{Index=4;  Expected='Buzz'}
    @{Index=14; Expected='FizzBuzz'}
    @{Index=99; Expected='Buzz'}
)
foreach ($c in $checks) {
    if ($lines[$c.Index] -ne $c.Expected) {
        Write-Host "verify FAIL: line $($c.Index) expected '$($c.Expected)' got '$($lines[$c.Index])'"
        exit 1
    }
}

Write-Host 'verify OK'
exit 0
