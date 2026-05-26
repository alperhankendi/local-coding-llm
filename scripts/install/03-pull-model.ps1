#Requires -Version 7.0
# Pull a model into Ollama.
# Idempotent: skips if model already in 'ollama list'.
#
# Usage:
#   .\03-pull-model.ps1                              # default qwen3-coder:30b
#   .\03-pull-model.ps1 -Model qwen2.5-coder:1.5b    # small model for testing

param(
    [string]$Model = 'qwen3-coder:30b'
)

$ErrorActionPreference = 'Stop'
$model = $Model

# Refresh PATH from registry first
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + `
            [Environment]::GetEnvironmentVariable('Path', 'User')

if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
    Write-Host 'RESULT: FAIL Ollama is not installed. Run 01-install-ollama.ps1 first.'
    exit 1
}

# Verify API is up before attempting pull
try {
    Invoke-RestMethod -Uri 'http://localhost:11434/api/tags' -TimeoutSec 5 | Out-Null
} catch {
    Write-Host "RESULT: FAIL Ollama API not reachable. Run 02-configure-storage.ps1 first or start Ollama."
    exit 1
}

# Check if model already present
$existing = & ollama list 2>$null | Select-String -SimpleMatch $model
if ($existing) {
    Write-Host "Model $model already present:"
    Write-Host "  $existing"
    Write-Host 'RESULT: OK'
    exit 0
}

# Check free space on the storage drive before downloading ~18 GB
$modelsRoot = [Environment]::GetEnvironmentVariable('OLLAMA_MODELS', 'User')
if (-not $modelsRoot) {
    $modelsRoot = [Environment]::GetEnvironmentVariable('OLLAMA_MODELS', 'Machine')
}
if ($modelsRoot) {
    $driveLetter = (Split-Path -Qualifier $modelsRoot).TrimEnd(':')
    $drive = Get-PSDrive -Name $driveLetter -ErrorAction SilentlyContinue
    if ($drive) {
        $freeGb = [math]::Round($drive.Free / 1GB, 1)
        Write-Host "Storage root: $modelsRoot (drive ${driveLetter}: has ${freeGb} GB free)"
        if ($drive.Free -lt 25GB) {
            Write-Host "RESULT: FAIL not enough free space on ${driveLetter}: (need ~25 GB, have ${freeGb} GB)"
            exit 1
        }
    }
}

Write-Host ""
Write-Host "Pulling $model. Size depends on the model (1.5b is ~1 GB, 30b is ~18 GB)."
Write-Host "Progress will stream below."
Write-Host ""

& ollama pull $model
if ($LASTEXITCODE -ne 0) {
    Write-Host "RESULT: FAIL ollama pull exited with code $LASTEXITCODE"
    exit 1
}

# Verify model is now listed
$verify = & ollama list 2>$null | Select-String -SimpleMatch $model
if (-not $verify) {
    Write-Host "RESULT: FAIL $model not listed after pull"
    exit 1
}
Write-Host ""
Write-Host "Pulled successfully:"
Write-Host "  $verify"

# Confirm blob files landed under the configured storage path.
# Note: OLLAMA_MODELS points at the models dir itself, blobs are at $OLLAMA_MODELS\blobs
# (NOT $OLLAMA_MODELS\models\blobs).
if ($modelsRoot) {
    $blobsDir = Join-Path $modelsRoot 'blobs'
    if (Test-Path $blobsDir) {
        $blobFiles = Get-ChildItem $blobsDir -File -ErrorAction SilentlyContinue
        $totalGb = [math]::Round(($blobFiles | Measure-Object Length -Sum).Sum / 1GB, 2)
        Write-Host "Blob storage at ${blobsDir}: ${totalGb} GB across $($blobFiles.Count) files"
    } else {
        Write-Host "RESULT: FAIL expected blobs dir not found at $blobsDir. Model may have gone to default location; check 02-configure-storage.ps1 ran successfully."
        exit 1
    }
}

Write-Host 'RESULT: OK'
