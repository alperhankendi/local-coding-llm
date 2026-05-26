#Requires -Version 7.0
# Iterate over tests/fixtures/*. For each fixture:
#   1. Copy any input/ files into a per-task working dir.
#   2. Send the prompt to Ollama (OpenAI-compatible chat completions).
#   3. Parse fenced code blocks with a filename header line, write each to a file.
#   4. Run the fixture's verify.ps1 in that working dir.
#   5. Aggregate PASS/FAIL.
#
# Acceptance: at least $MinPass fixtures must pass (default 3 of 4).
#
# Usage:
#   .\validate-coding-tasks.ps1                              # default qwen3-coder:30b, MinPass=3
#   .\validate-coding-tasks.ps1 -Model qwen2.5-coder:1.5b    # small model
#   .\validate-coding-tasks.ps1 -Model qwen2.5-coder:1.5b -MinPass 1   # lenient for small models

param(
    [string]$Model   = 'qwen3-coder:30b',
    [int]   $MinPass = 3
)

$ErrorActionPreference = 'Stop'
$model  = $Model
$apiUrl = 'http://localhost:11434/v1/chat/completions'

$fixturesRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\tests\fixtures')).Path
$runRoot      = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path `
                ("benchmark-results\validation-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

$systemPrompt = @'
You are a precise coding agent. When asked to produce files:
- Output one fenced code block per file, no prose around it.
- The first line inside each block must be a comment containing ONLY the exact filename, for example:
    # fizzbuzz.py
    // app.js
- Do not nest code blocks. Do not split a single file across multiple blocks.
- Do not include any text outside of code blocks.
'@

$fixtures = Get-ChildItem -Directory $fixturesRoot | Sort-Object Name
if ($fixtures.Count -eq 0) {
    Write-Host "RESULT: FAIL no fixtures found at $fixturesRoot"
    exit 1
}

$results = @()
foreach ($fix in $fixtures) {
    $name = $fix.Name
    Write-Host ""
    Write-Host "===== $name ====="

    $promptPath = Join-Path $fix.FullName 'prompt.txt'
    $verifyPath = Join-Path $fix.FullName 'verify.ps1'
    if (-not (Test-Path $promptPath)) { Write-Host "  skip: no prompt.txt"; continue }
    if (-not (Test-Path $verifyPath)) { Write-Host "  skip: no verify.ps1"; continue }

    $prompt = Get-Content -Raw $promptPath
    $outDir = Join-Path $runRoot $name
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null

    # Copy any input/ files into the working dir
    $inputDir = Join-Path $fix.FullName 'input'
    if (Test-Path $inputDir) {
        Copy-Item -Path (Join-Path $inputDir '*') -Destination $outDir -Recurse -Force
    }

    # Call the model
    $body = @{
        model       = $model
        messages    = @(
            @{ role = 'system'; content = $systemPrompt }
            @{ role = 'user';   content = $prompt }
        )
        temperature = 0
    } | ConvertTo-Json -Depth 10

    $sw = [Diagnostics.Stopwatch]::StartNew()
    Write-Host '  generating...'
    try {
        $resp = Invoke-RestMethod -Uri $apiUrl -Method Post -Body $body `
            -ContentType 'application/json' -TimeoutSec 600
    } catch {
        Write-Host "  ERROR: $($_.Exception.Message)"
        $results += [pscustomobject]@{
            name = $name; pass = $false; reason = 'request failed'; elapsed_s = $null
        }
        continue
    }
    $sw.Stop()

    $content = $resp.choices[0].message.content
    Set-Content -Path (Join-Path $outDir '_raw_output.md') -Value $content -Encoding UTF8

    # Parse fenced code blocks and materialize files by a filename header.
    # Filename can appear either:
    #   (a) as the FIRST line INSIDE the code block (preferred per system prompt), or
    #   (b) as the last non-empty line BEFORE the code block (common model fallback)
    # Header pattern: a comment with just a path-like filename, e.g. `# foo.py`, `// app.js`
    $filenameRegex = '^[#/]+\s*([\w\.\-_/]+\.[\w]+)\s*$'

    $blockMatches = [regex]::Matches($content, '```[\w-]*\r?\n([\s\S]*?)```')
    $wroteAny = $false
    foreach ($b in $blockMatches) {
        $code = $b.Groups[1].Value
        $lines = $code -split "`r?`n", 2
        $first = $lines[0].Trim()
        $rest  = if ($lines.Count -gt 1) { $lines[1] } else { '' }

        $fname = $null
        $bodyToWrite = $code

        # (a) inside-block header
        if ($first -match $filenameRegex) {
            $fname = $Matches[1]
            $bodyToWrite = $rest
        } else {
            # (b) look at the last non-empty line before this block
            $before = $content.Substring(0, $b.Index)
            $beforeLines = @(($before -split "`r?`n") | Where-Object { $_.Trim() -ne '' })
            if ($beforeLines.Count -gt 0) {
                $lastBefore = [string]$beforeLines[$beforeLines.Count - 1]
                $lastBefore = $lastBefore.Trim()
                if ($lastBefore -match $filenameRegex) {
                    $fname = $Matches[1]
                    $bodyToWrite = $code
                }
            }
        }

        if (-not $fname) { continue }

        $dest    = Join-Path $outDir $fname
        $destDir = Split-Path $dest -Parent
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        Set-Content -Path $dest -Value $bodyToWrite -Encoding UTF8 -NoNewline
        Write-Host "  wrote $fname ($($bodyToWrite.Length) chars)"
        $wroteAny = $true
    }

    if (-not $wroteAny) {
        Write-Host '  FAIL: no fileable code blocks produced'
        $results += [pscustomobject]@{
            name = $name; pass = $false; reason = 'no files produced'; elapsed_s = [math]::Round($sw.Elapsed.TotalSeconds, 1)
        }
        continue
    }

    Write-Host '  verifying...'
    Push-Location $outDir
    try {
        & $verifyPath
        $pass = ($LASTEXITCODE -eq 0)
    } finally {
        Pop-Location
    }
    $reason = if ($pass) { 'ok' } else { 'verify failed' }
    Write-Host ("  result: {0} (model gen {1:N1} s)" -f $(if ($pass) { 'PASS' } else { 'FAIL' }), $sw.Elapsed.TotalSeconds)
    $results += [pscustomobject]@{
        name      = $name
        pass      = $pass
        reason    = $reason
        elapsed_s = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    }
}

$passCount = ($results | Where-Object pass).Count
$total     = $results.Count

Write-Host ''
Write-Host '===== Summary ====='
foreach ($r in $results) {
    $tag = if ($r.pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("  {0}  {1,-20} {2,5} s   ({3})" -f $tag, $r.name, $r.elapsed_s, $r.reason)
}
Write-Host ("  {0} of {1} passed (threshold {2})" -f $passCount, $total, $MinPass)
Write-Host "  Run artifacts: $runRoot"

if ($passCount -ge $MinPass) {
    Write-Host 'RESULT: OK'
} else {
    Write-Host "RESULT: FAIL only $passCount of $total passed (need at least $MinPass)"
    exit 1
}
