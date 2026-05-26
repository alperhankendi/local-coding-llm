#Requires -Version 7.0
# Verify OpenAI-compatible /v1/chat/completions returns a sensible response.
# This is the endpoint Cline (and most other agent clients) actually use.
#
# Usage:
#   .\test-chat-completion.ps1                              # default qwen3-coder:30b
#   .\test-chat-completion.ps1 -Model qwen2.5-coder:1.5b    # small model

param(
    [string]$Model = 'qwen3-coder:30b',
    [int]   $TimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'
$apiUrl = 'http://localhost:11434/v1/chat/completions'

$body = @{
    model       = $Model
    messages    = @(
        @{ role = 'user'; content = 'Reply with exactly the number 4 and nothing else. What is 2+2?' }
    )
    temperature = 0
    max_tokens  = 10
} | ConvertTo-Json -Depth 6

$sw = [Diagnostics.Stopwatch]::StartNew()
try {
    $resp = Invoke-RestMethod -Uri $apiUrl -Method Post -Body $body `
        -ContentType 'application/json' -TimeoutSec $TimeoutSeconds
} catch {
    Write-Host "RESULT: FAIL request failed: $($_.Exception.Message)"
    exit 1
}
$sw.Stop()

$reply = $resp.choices[0].message.content
if ([string]::IsNullOrWhiteSpace($reply)) {
    Write-Host 'RESULT: FAIL no content in response'
    exit 1
}

Write-Host ("Model:   {0}" -f $Model)
Write-Host ("Reply:   '{0}'" -f $reply.Trim())
Write-Host ("Elapsed: {0:N2} s" -f $sw.Elapsed.TotalSeconds)
if ($resp.usage) {
    Write-Host ("Tokens:  prompt={0}, completion={1}" -f $resp.usage.prompt_tokens, $resp.usage.completion_tokens)
}

if ($reply -notmatch '4') {
    Write-Host "RESULT: FAIL reply does not contain '4'"
    exit 1
}
if ($sw.Elapsed.TotalSeconds -gt $TimeoutSeconds) {
    Write-Host "RESULT: FAIL response took more than $TimeoutSeconds seconds"
    exit 1
}

Write-Host 'RESULT: OK'
