#Requires -Version 7.0
# Run all install scripts in order. Stops on the first failure.
#
# Usage:
#   .\run-all-install.ps1                              # production model (qwen3-coder:30b)
#   .\run-all-install.ps1 -Model qwen2.5-coder:1.5b    # small test model

param(
    [string]$Model = 'qwen3-coder:30b'
)

$ErrorActionPreference = 'Stop'

$installDir = Join-Path $PSScriptRoot 'install'

# Scripts run in this exact order. 03 takes a model name so it can be parametrized
# (the others have no parameters).
$plan = @(
    @{ Path = '01-install-ollama.ps1';       Args = @() }
    @{ Path = '02-configure-storage.ps1';    Args = @() }
    @{ Path = '03-pull-model.ps1';           Args = @('-Model', $Model) }
    @{ Path = '04-install-vscode-cline.ps1'; Args = @() }
)

foreach ($step in $plan) {
    $script = Join-Path $installDir $step.Path
    Write-Host ""
    Write-Host "===== Running $($step.Path) ====="
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $script @($step.Args)
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "RESULT: FAIL $($step.Path) exited with $LASTEXITCODE"
        exit 1
    }
}

Write-Host ""
Write-Host 'RESULT: OK all install scripts completed'
