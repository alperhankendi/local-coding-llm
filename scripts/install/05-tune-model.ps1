#Requires -Version 7.0
# Create a tuned variant of a base Ollama model with Qwen-recommended sampler params.
# Idempotent: skips create if the tuned variant already exists.
#
# Background: Ollama defaults are wrong for Qwen3-Coder. Qwen's own model card prescribes
# temperature=0.7, top_p=0.8, top_k=20, min_p=0.01, repeat_penalty=1.05.
# Cline and Ollama defaults miss several of these (top_k unset, min_p unset).
# A Modelfile bakes the right params permanently, so any client gets them.
#
# Note: Cline sends its own sampler params over the OpenAI API and may override these.
# Verify by running test-chat-completion with temperature=0.01 in the Modelfile and
# checking if output is deterministic. If not, set the params in Cline UI instead.
#
# Usage:
#   .\05-tune-model.ps1                                          # default: tune qwen3-coder:30b
#   .\05-tune-model.ps1 -BaseModel qwen2.5-coder:1.5b            # small model variant
#   .\05-tune-model.ps1 -BaseModel qwen3-coder:30b -NumCtx 65536 # extended context

param(
    [string]$BaseModel = 'qwen3-coder:30b',
    [string]$TunedName,
    [int]   $NumCtx    = 32768
)

$ErrorActionPreference = 'Stop'

# Refresh PATH
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + `
            [Environment]::GetEnvironmentVariable('Path', 'User')

if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
    Write-Host 'RESULT: FAIL Ollama is not installed. Run 01-install-ollama.ps1 first.'
    exit 1
}

# Default tuned name: <base>-tuned (strip tag, append -tuned)
if (-not $TunedName) {
    $baseShort = ($BaseModel -split ':')[0]
    $TunedName = "$baseShort-tuned"
}

# Check that the base model exists
$baseExists = & ollama list 2>$null | Select-String -SimpleMatch $BaseModel
if (-not $baseExists) {
    Write-Host "RESULT: FAIL base model $BaseModel not found. Run 03-pull-model.ps1 first."
    exit 1
}

# Idempotency: skip if tuned variant already present
$tunedExists = & ollama list 2>$null | Select-String -SimpleMatch $TunedName
if ($tunedExists) {
    Write-Host "$TunedName already exists:"
    Write-Host "  $tunedExists"
    Write-Host 'RESULT: OK'
    exit 0
}

# Build a Modelfile with Qwen's recommended sampler defaults + chosen context size.
# These values come from the official Qwen3-Coder model card on HuggingFace.
$modelfile = @"
FROM $BaseModel

PARAMETER temperature 0.7
PARAMETER top_p 0.8
PARAMETER top_k 20
PARAMETER min_p 0.01
PARAMETER repeat_penalty 1.05
PARAMETER num_ctx $NumCtx
"@

$tempFile = Join-Path $env:TEMP "Modelfile-$([Guid]::NewGuid()).txt"
Set-Content -Path $tempFile -Value $modelfile -Encoding UTF8

Write-Host "Creating $TunedName from $BaseModel (num_ctx=$NumCtx, Qwen sampler defaults)..."
& ollama create $TunedName -f $tempFile
$rc = $LASTEXITCODE
Remove-Item $tempFile -ErrorAction SilentlyContinue

if ($rc -ne 0) {
    Write-Host "RESULT: FAIL ollama create exited with $rc"
    exit 1
}

$verify = & ollama list 2>$null | Select-String -SimpleMatch $TunedName
if (-not $verify) {
    Write-Host "RESULT: FAIL $TunedName not listed after create"
    exit 1
}
Write-Host "Created:"
Write-Host "  $verify"

Write-Host ""
Write-Host "Next step: in Cline settings, switch the Model from $BaseModel to $TunedName."
Write-Host "  Cline params will still override these defaults if Cline UI has its own sampler set."
Write-Host "  Verify by sending the same prompt twice and checking determinism."

Write-Host 'RESULT: OK'
