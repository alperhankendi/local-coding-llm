#Requires -Version 7.0
# Install the Cline VSCode extension and print the manual config steps that cannot be scripted.
# Idempotent: skips install if extension is already listed.

$ErrorActionPreference = 'Stop'
$extensionId = 'saoudrizwan.claude-dev'   # Cline extension <publisher>.<name>

# Refresh PATH so 'code' is found if VSCode was just installed
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + `
            [Environment]::GetEnvironmentVariable('Path', 'User')

if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
    Write-Host 'RESULT: FAIL VSCode CLI (code) not found on PATH.'
    Write-Host '   Install VSCode and check the "Add to PATH" option in the installer.'
    Write-Host '   Then open a new shell and re-run this script.'
    exit 1
}

$installed = & code --list-extensions 2>&1
if ($installed -contains $extensionId) {
    Write-Host "Cline ($extensionId) already installed"
} else {
    Write-Host "Installing $extensionId"
    & code --install-extension $extensionId
    if ($LASTEXITCODE -ne 0) {
        Write-Host "RESULT: FAIL 'code --install-extension' exited with $LASTEXITCODE"
        exit 1
    }
}

Write-Host ''
Write-Host 'Manual configuration steps for Cline (UI only, cannot be scripted):'
Write-Host '  1. Open VSCode, click the Cline icon in the activity bar.'
Write-Host '  2. In Cline settings, set API Provider to "Ollama".'
Write-Host '  3. Set Base URL to http://localhost:11434'
Write-Host '  4. Select Model: qwen3-coder:30b (or whichever model you pulled).'
Write-Host '  5. Save settings.'
Write-Host ''
Write-Host 'RESULT: OK'
