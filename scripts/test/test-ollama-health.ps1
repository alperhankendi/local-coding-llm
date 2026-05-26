#Requires -Version 7.0
# Verify Ollama API is reachable, target model is listed, and after a tiny warmup
# the model is resident on GPU (not CPU only).
#
# Usage:
#   .\test-ollama-health.ps1                              # default qwen3-coder:30b
#   .\test-ollama-health.ps1 -Model qwen2.5-coder:1.5b    # small model

param(
    [string]$Model = 'qwen3-coder:30b'
)

$ErrorActionPreference = 'Stop'
$model  = $Model
$apiUrl = 'http://localhost:11434'

# 1. API reachable
try {
    $tags = Invoke-RestMethod -Uri "$apiUrl/api/tags" -TimeoutSec 10
} catch {
    Write-Host "RESULT: FAIL /api/tags unreachable: $($_.Exception.Message)"
    exit 1
}

# 2. Target model listed
$hasModel = $tags.models | Where-Object { $_.name -eq $model }
if (-not $hasModel) {
    $available = ($tags.models.name | Sort-Object) -join ', '
    Write-Host "RESULT: FAIL model '$model' not found. Available: $available"
    exit 1
}
Write-Host ("Model {0} found, size {1:N2} GB on disk" -f $model, ($hasModel.size / 1GB))

# 3. Warm up so the model gets loaded onto GPU
Write-Host 'Warming up the model (one-token generate)...'
$warmBody = @{
    model   = $model
    prompt  = 'hi'
    stream  = $false
    options = @{ num_predict = 1 }
} | ConvertTo-Json
try {
    Invoke-RestMethod -Uri "$apiUrl/api/generate" -Method Post -Body $warmBody `
        -ContentType 'application/json' -TimeoutSec 180 | Out-Null
} catch {
    Write-Host "RESULT: FAIL warmup generate failed: $($_.Exception.Message)"
    exit 1
}

# 4. Inspect /api/ps to confirm the model is resident on GPU
$ps = Invoke-RestMethod -Uri "$apiUrl/api/ps" -TimeoutSec 10
$running = $ps.models | Where-Object { $_.name -eq $model }
if (-not $running) {
    Write-Host 'RESULT: FAIL model not visible in /api/ps after warmup'
    exit 1
}

$vramBytes = [int64]$running.size_vram
if ($vramBytes -eq 0) {
    Write-Host 'RESULT: FAIL model loaded on CPU only (size_vram = 0). Check NVIDIA driver and CUDA install.'
    exit 1
}
Write-Host ("Model resident on GPU, VRAM usage {0:N2} GB" -f ($vramBytes / 1GB))

Write-Host 'RESULT: OK'
