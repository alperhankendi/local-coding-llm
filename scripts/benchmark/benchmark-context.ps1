#Requires -Version 7.0
# Measure model behavior at different context window sizes.
# For each size: unload, send a prompt that fills ~80% of context, measure TTFT and VRAM.
# Writes timestamped JSON to benchmark-results\context-<ts>.json.
#
# Usage:
#   .\benchmark-context.ps1                                       # default 30b, 8K/32K/64K
#   .\benchmark-context.ps1 -Model qwen2.5-coder:1.5b             # small model
#   .\benchmark-context.ps1 -Sizes 4096,16384                     # custom sizes
#   .\benchmark-context.ps1 -RequiredSize 32768                   # must-pass size

param(
    [string]$Model        = 'qwen3-coder:30b',
    [int[]] $Sizes        = @(8192, 32768, 65536),
    [int]   $RequiredSize = 32768
)

$ErrorActionPreference = 'Stop'
$model  = $Model
$apiUrl = 'http://localhost:11434'

$resultsDir = Join-Path $PSScriptRoot '..\..\benchmark-results'
New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
$outFile = Join-Path $resultsDir ("context-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')

function Get-VramMb {
    $smi = & nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>$null
    if ($LASTEXITCODE -eq 0 -and $smi) {
        $first = ($smi.Trim() -split "`n")[0].Trim()
        return [int]$first
    }
    return $null
}

# Roughly 11 tokens per repetition (8 words + separators).
# Pre-build a large padding buffer (~600K chars) and slice from it per size.
$paddingUnit = 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. '
$paddingBig  = $paddingUnit * 12000

$results = @()
foreach ($ctx in $Sizes) {
    Write-Host ""
    Write-Host "===== num_ctx = $ctx ====="

    # Unload to force reload with new num_ctx
    try {
        Invoke-RestMethod -Uri "$apiUrl/api/generate" -Method Post -Body (@{
            model = $model; prompt = ''; keep_alive = 0
        } | ConvertTo-Json) -ContentType 'application/json' -TimeoutSec 30 | Out-Null
    } catch {
        Write-Host "  warn: could not unload between sizes: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds 3

    # Build a prompt that fills ~80% of the requested context.
    # Rough approximation: 4 chars per token.
    $targetTokens = [int]($ctx * 0.8)
    $targetChars  = $targetTokens * 4
    $sliceLen     = [math]::Min($paddingBig.Length, $targetChars)
    $prompt       = $paddingBig.Substring(0, $sliceLen) + "`n`nReply with the single word: ok"

    $body = @{
        model   = $model
        prompt  = $prompt
        stream  = $false
        options = @{ num_ctx = $ctx; num_predict = 5 }
    } | ConvertTo-Json -Depth 5

    $vramBefore = Get-VramMb
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $ok = $true
    $errMsg = $null
    $r = $null
    try {
        $r = Invoke-RestMethod -Uri "$apiUrl/api/generate" -Method Post -Body $body `
            -ContentType 'application/json' -TimeoutSec 900
    } catch {
        $errMsg = $_.Exception.Message
        $ok = $false
    }
    $sw.Stop()
    $vramAfter = Get-VramMb

    $ttftSec     = if ($r -and $r.prompt_eval_duration) { [math]::Round($r.prompt_eval_duration / 1e9, 2) } else { $null }
    $promptToks  = if ($r) { $r.prompt_eval_count } else { $null }

    $row = [pscustomobject]@{
        num_ctx        = $ctx
        ok             = $ok
        prompt_tokens  = $promptToks
        ttft_seconds   = $ttftSec
        vram_before_mb = $vramBefore
        vram_after_mb  = $vramAfter
        vram_delta_mb  = if ($vramBefore -and $vramAfter) { $vramAfter - $vramBefore } else { $null }
        wall_seconds   = [math]::Round($sw.Elapsed.TotalSeconds, 2)
        error          = $errMsg
    }
    $results += $row

    Write-Host ("  ok=$ok, prompt_tokens={0}, ttft={1} s, vram={2} MB (delta {3} MB), wall={4} s" `
        -f $promptToks, $ttftSec, $vramAfter, $row.vram_delta_mb, $row.wall_seconds)
    if ($errMsg) { Write-Host "  error: $errMsg" }
}

$summary = [pscustomobject]@{
    model         = $model
    timestamp     = (Get-Date).ToString('o')
    sizes_tested  = $Sizes
    required_size = $RequiredSize
    runs          = $results
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -Path $outFile -Encoding UTF8

Write-Host ""
Write-Host "Results -> $outFile"

$required = $results | Where-Object { $_.num_ctx -eq $RequiredSize }
if (-not $required) {
    Write-Host "Note: required size $RequiredSize was not in the test list, skipping pass/fail check."
    Write-Host 'RESULT: OK'
    exit 0
}
if (-not $required.ok) {
    Write-Host "RESULT: FAIL required context $RequiredSize did not complete: $($required.error)"
    exit 1
}

Write-Host 'RESULT: OK'
