#Requires -Version 7.0
# Install Ollama on Windows if not already installed.
# Idempotent: skips install if 'ollama' is already on PATH.

$ErrorActionPreference = 'Stop'
$installerUrl  = 'https://ollama.com/download/OllamaSetup.exe'
$installerPath = Join-Path $env:TEMP 'OllamaSetup.exe'

# Refresh PATH from registry first (Ollama may have been installed in a prior session
# but this shell still has the old PATH).
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + `
            [Environment]::GetEnvironmentVariable('Path', 'User')

if (Get-Command ollama -ErrorAction SilentlyContinue) {
    $version = (& ollama --version 2>&1) -join ' '
    Write-Host "Ollama already installed: $version"
    Write-Host 'RESULT: OK'
    exit 0
}

Write-Host "Downloading Ollama installer from $installerUrl"
try {
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
} catch {
    Write-Host "RESULT: FAIL could not download installer: $($_.Exception.Message)"
    exit 1
}

Write-Host 'Running installer silently (this can take 1 to 2 minutes)'
$proc = Start-Process -FilePath $installerPath -ArgumentList '/SILENT' -Wait -PassThru
if ($proc.ExitCode -ne 0) {
    Write-Host "RESULT: FAIL installer exit code $($proc.ExitCode)"
    exit 1
}

# Refresh PATH for current session so the freshly installed ollama is visible
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + `
            [Environment]::GetEnvironmentVariable('Path', 'User')

if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
    Write-Host 'RESULT: FAIL ollama not found on PATH after install. Try opening a new shell.'
    exit 1
}

Write-Host "Installed: $((& ollama --version 2>&1) -join ' ')"
Write-Host 'RESULT: OK'
