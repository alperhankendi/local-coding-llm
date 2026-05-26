#Requires -Version 7.0
# Measure cold and warm prefill+decode tokens-per-second for a model.
# Writes timestamped JSON to benchmark-results\throughput-<ts>.json.
#
# Usage:
#   .\benchmark-throughput.ps1                              # default qwen3-coder:30b
#   .\benchmark-throughput.ps1 -Model qwen2.5-coder:1.5b    # small model
#   .\benchmark-throughput.ps1 -MinWarmDecodeTps 10         # custom threshold

param(
    [string]$Model              = 'qwen3-coder:30b',
    [int]   $NumPredict         = 200,
    [double]$MinWarmDecodeTps   = 20.0
)

$ErrorActionPreference = 'Stop'
$model  = $Model
$apiUrl = 'http://localhost:11434'

$prompts = @(
    'Write a Python function that returns the nth Fibonacci number iteratively.'
    'Explain in one short paragraph what a database index is.'
    'Translate to Turkish, one line: Hello, how are you today?'
    'Write a regex that matches a US phone number in 555-555-5555 format.'
    'Summarize the benefits of unit testing in three bullet points.'
)

$resultsDir = Join-Path $PSScriptRoot '..\..\benchmark-results'
New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
$outFile = Join-Path $resultsDir ("throughput-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')

function Invoke-Bench {
    param([string]$prompt)
    $body = @{
        model   = $model
        prompt  = $prompt
        stream  = $false
        options = @{ num_predict = $NumPredict }
    } | ConvertTo-Json
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $r  = Invoke-RestMethod -Uri "$apiUrl/api/generate" -Method Post -Body $body `
        -ContentType 'application/json' -TimeoutSec 600
    $sw.Stop()

    $prefillTps = if ($r.prompt_eval_duration -gt 0) { $r.prompt_eval_count / ($r.prompt_eval_duration / 1e9) } else { 0 }
    $decodeTps  = if ($r.eval_duration -gt 0)        { $r.eval_count        / ($r.eval_duration / 1e9) }        else { 0 }

    return [pscustomobject]@{
        prompt                  = $prompt
        prompt_eval_count       = $r.prompt_eval_count
        prompt_eval_duration_ns = $r.prompt_eval_duration
        eval_count              = $r.eval_count
        eval_duration_ns        = $r.eval_duration
        wall_seconds            = [math]::Round($sw.Elapsed.TotalSeconds, 3)
        prefill_tps             = [math]::Round($prefillTps, 1)
        decode_tps              = [math]::Round($decodeTps, 1)
    }
}

# Unload model (keep_alive = 0) then reload for the cold measurement
Write-Host "Unloading model $model for cold measurement..."
try {
    Invoke-RestMethod -Uri "$apiUrl/api/generate" -Method Post -Body (@{
        model = $model; prompt = ''; keep_alive = 0
    } | ConvertTo-Json) -ContentType 'application/json' -TimeoutSec 30 | Out-Null
} catch {
    Write-Host "RESULT: FAIL could not request unload: $($_.Exception.Message)"
    exit 1
}
Start-Sleep -Seconds 3

Write-Host "Cold run (first prompt after unload, includes model load time)..."
try {
    $cold = Invoke-Bench -prompt $prompts[0]
} catch {
    Write-Host "RESULT: FAIL cold run failed: $($_.Exception.Message)"
    exit 1
}
Write-Host ("  prefill {0,5:N1} tok/s, decode {1,5:N1} tok/s, wall {2,5:N2} s" -f $cold.prefill_tps, $cold.decode_tps, $cold.wall_seconds)

Write-Host "Warm runs (5 prompts)..."
$warm = @()
for ($i = 0; $i -lt $prompts.Count; $i++) {
    try {
        $r = Invoke-Bench -prompt $prompts[$i]
    } catch {
        Write-Host "RESULT: FAIL warm run [$i] failed: $($_.Exception.Message)"
        exit 1
    }
    Write-Host ("  [{0}] prefill {1,5:N1} tok/s, decode {2,5:N1} tok/s" -f $i, $r.prefill_tps, $r.decode_tps)
    $warm += $r
}

$warmAvgDecode  = [math]::Round(($warm.decode_tps  | Measure-Object -Average).Average, 1)
$warmAvgPrefill = [math]::Round(($warm.prefill_tps | Measure-Object -Average).Average, 1)

$summary = [pscustomobject]@{
    model                 = $model
    timestamp             = (Get-Date).ToString('o')
    num_predict           = $NumPredict
    min_warm_decode_tps   = $MinWarmDecodeTps
    cold                  = $cold
    warm                  = $warm
    warm_avg_decode_tps   = $warmAvgDecode
    warm_avg_prefill_tps  = $warmAvgPrefill
}

$summary | ConvertTo-Json -Depth 8 | Set-Content -Path $outFile -Encoding UTF8

Write-Host ""
Write-Host ("Warm avg: prefill {0:N1} tok/s, decode {1:N1} tok/s" -f $warmAvgPrefill, $warmAvgDecode)
Write-Host "Results -> $outFile"

if ($warmAvgDecode -lt $MinWarmDecodeTps) {
    Write-Host ("RESULT: FAIL warm decode avg {0:N1} tok/s is below threshold {1:N1} tok/s" -f $warmAvgDecode, $MinWarmDecodeTps)
    exit 1
}

Write-Host 'RESULT: OK'
