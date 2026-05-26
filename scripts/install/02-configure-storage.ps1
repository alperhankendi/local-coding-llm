#Requires -Version 7.0
# Configure Ollama to store models on D:\ai-models\ollama and start ollama serve
# with that path explicitly in its environment.
#
# Idempotent: if API already responds AND blobs already live at the target, exit OK.
#
# IMPORTANT note on Ollama storage:
#   OLLAMA_MODELS is the models directory itself (containing blobs\ and manifests\),
#   NOT the parent of a models/ subdirectory. Common mistake: setting it to a path
#   under which Ollama then creates blobs\ and manifests\ subdirs directly.
#
# IMPORTANT note on env inheritance:
#   The Ollama tray app (auto-started at login) and PowerShell's Start-Process do NOT
#   reliably propagate runtime env changes. We start `ollama serve` ourselves using
#   .NET ProcessStartInfo with an explicit Environment dictionary. This bypasses the
#   tray app entirely.
#
# Reboot persistence: this script must be run after each reboot, OR the tray app's
# auto-start at login should be disabled (Settings > Apps > Startup > Ollama OFF) so
# it does not steal port 11434 with the wrong storage path. To make storage persistent
# without disabling auto-start, set OLLAMA_MODELS in Machine scope from an elevated
# shell once: [Environment]::SetEnvironmentVariable('OLLAMA_MODELS','D:\ai-models\ollama','Machine')

$ErrorActionPreference = 'Stop'
$targetPath  = 'D:\ai-models\ollama'
$envName     = 'OLLAMA_MODELS'
$apiUrl      = 'http://localhost:11434/api/tags'
$ollamaExe   = 'C:\Users\ahank\AppData\Local\Programs\Ollama\ollama.exe'

# Refresh PATH from registry
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + `
            [Environment]::GetEnvironmentVariable('Path', 'User')

if (-not (Test-Path $ollamaExe)) {
    if (Get-Command ollama -ErrorAction SilentlyContinue) {
        $ollamaExe = (Get-Command ollama).Source
    } else {
        Write-Host 'RESULT: FAIL Ollama is not installed. Run 01-install-ollama.ps1 first.'
        exit 1
    }
}

# 1. Ensure target directory exists
if (-not (Test-Path $targetPath)) {
    Write-Host "Creating $targetPath"
    New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
}

# 2. Set OLLAMA_MODELS in registry. Prefer Machine scope (survives across users,
#    and is seen by tray app auto-started at login). Falls back to User scope if
#    not running elevated.
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    $currentMachine = [Environment]::GetEnvironmentVariable($envName, 'Machine')
    if ($currentMachine -ne $targetPath) {
        Write-Host "Setting $envName = $targetPath (Machine scope, admin)"
        [Environment]::SetEnvironmentVariable($envName, $targetPath, 'Machine')
    }
    # Clear conflicting User scope value if any (User overrides Machine for user processes)
    $currentUser = [Environment]::GetEnvironmentVariable($envName, 'User')
    if ($currentUser -and $currentUser -ne $targetPath) {
        Write-Host "Clearing conflicting $envName User scope value (was: '$currentUser')"
        [Environment]::SetEnvironmentVariable($envName, $null, 'User')
    }
} else {
    Write-Host "Note: not running elevated. Setting $envName in User scope only."
    Write-Host "      For persistence across reboots, run once from admin pwsh:"
    Write-Host "        [Environment]::SetEnvironmentVariable('OLLAMA_MODELS','$targetPath','Machine')"
    $currentUser = [Environment]::GetEnvironmentVariable($envName, 'User')
    if ($currentUser -ne $targetPath) {
        Write-Host "Setting $envName = $targetPath (User scope)"
        [Environment]::SetEnvironmentVariable($envName, $targetPath, 'User')
    }
}
$env:OLLAMA_MODELS = $targetPath

# 3. Quick health check: if API already responds AND blobs dir at target has files,
#    we are already correctly configured.
$apiUpAlready = $false
try {
    Invoke-RestMethod -Uri $apiUrl -TimeoutSec 3 | Out-Null
    $apiUpAlready = $true
} catch { }
$blobsAtTarget = Test-Path (Join-Path $targetPath 'blobs')
$blobCount = if ($blobsAtTarget) { (Get-ChildItem (Join-Path $targetPath 'blobs') -File -ErrorAction SilentlyContinue).Count } else { 0 }

if ($apiUpAlready -and $blobCount -gt 0) {
    Write-Host "API already up and blobs already at $targetPath ($blobCount files). No restart needed."
    Write-Host 'RESULT: OK'
    exit 0
}

# 4. Stop any running Ollama (tray, serve, or service)
$svc = Get-Service -Name 'Ollama' -ErrorAction SilentlyContinue
if ($svc) {
    Write-Host "Stopping Ollama Windows service (status was: $($svc.Status))"
    Stop-Service -Name 'Ollama' -Force
}
$procs = Get-Process -Name 'ollama', 'ollama app' -ErrorAction SilentlyContinue
if ($procs) {
    Write-Host "Stopping running Ollama processes: $(($procs.Name | Sort-Object -Unique) -join ', ')"
    $procs | Stop-Process -Force
    Start-Sleep -Seconds 2
}

# 5. Start ollama serve via .NET ProcessStartInfo with explicit env
Write-Host "Launching $ollamaExe serve with explicit $envName = $targetPath"
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName        = $ollamaExe
$psi.Arguments       = 'serve'
$psi.UseShellExecute = $false
$psi.CreateNoWindow  = $true
# Copy parent env first so child has PATH, USERPROFILE, etc.
foreach ($e in [Environment]::GetEnvironmentVariables('Process').GetEnumerator()) {
    $psi.Environment[$e.Key] = [string]$e.Value
}
$psi.Environment[$envName] = $targetPath

$proc = [System.Diagnostics.Process]::Start($psi)
Write-Host "Started ollama serve, PID $($proc.Id)"

# 6. Wait for API to come back up
$deadline = (Get-Date).AddSeconds(30)
$apiBack = $false
while ((Get-Date) -lt $deadline) {
    try {
        $tags = Invoke-RestMethod -Uri $apiUrl -TimeoutSec 3
        $apiBack = $true
        break
    } catch {
        Start-Sleep -Milliseconds 500
    }
}

if (-not $apiBack) {
    Write-Host 'RESULT: FAIL Ollama API not reachable within 30 seconds after restart.'
    exit 1
}

Write-Host "Ollama API reachable, $($tags.models.Count) models visible to the server."
foreach ($m in $tags.models) {
    Write-Host ("  {0,-25} {1,6:N2} GB" -f $m.name, ($m.size / 1GB))
}

Write-Host 'RESULT: OK'
