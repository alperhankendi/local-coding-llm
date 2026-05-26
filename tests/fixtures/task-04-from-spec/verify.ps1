#Requires -Version 7.0
$ErrorActionPreference = 'Stop'

if (-not (Test-Path csv_group.py)) {
    Write-Host 'verify FAIL: csv_group.py not produced'
    exit 1
}

$csv = @"
name,team
alice,red
bob,blue
carol,red
dave,green
eve,red
"@

$out = $csv | & python csv_group.py --by team 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "verify FAIL: cli exited with $LASTEXITCODE"
    Write-Host $out
    exit 1
}

$lines = ($out -split "`r?`n") | Where-Object { $_ -ne '' }
$expected = @('blue: 1', 'green: 1', 'red: 3')

if ($lines.Count -ne $expected.Count) {
    Write-Host "verify FAIL: expected $($expected.Count) lines, got $($lines.Count)"
    Write-Host "got: $($lines -join ' | ')"
    exit 1
}

for ($i = 0; $i -lt $expected.Count; $i++) {
    if ($lines[$i].Trim() -ne $expected[$i]) {
        Write-Host "verify FAIL: line $i expected '$($expected[$i])' got '$($lines[$i])'"
        exit 1
    }
}

# Negative path: missing column should exit non-zero
$null = $csv | & python csv_group.py --by nope 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host 'verify FAIL: cli should exit non-zero on missing column'
    exit 1
}

Write-Host 'verify OK'
exit 0
