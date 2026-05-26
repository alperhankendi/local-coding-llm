#Requires -Version 7.0
# Verify model returns valid tool_calls when given a tool definition.
# Cline (and any agent client) cannot function without this.
#
# IMPORTANT, model size requirement:
#   Tool calling needs a model that actually has a tool calling chat template.
#   Small models (1.5b and under) typically do NOT, and instead embed the JSON
#   inside the message content as a code block. Use 7b+ coder models, or any
#   model documented to support tools (llama3.2:3b, mistral, qwen3 coder, etc.).
#   This test will FAIL on models without native tool support, which is correct
#   behavior, not a bug in the test.
#
# Usage:
#   .\test-tool-calling.ps1                              # default qwen3-coder:30b
#   .\test-tool-calling.ps1 -Model llama3.2:3b           # alt small model with tools

param(
    [string]$Model = 'qwen3-coder:30b',
    [int]   $TimeoutSeconds = 60
)

$ErrorActionPreference = 'Stop'
$apiUrl = 'http://localhost:11434/v1/chat/completions'

$body = @{
    model       = $Model
    messages    = @(
        @{ role = 'user'; content = 'What is the weather in Istanbul right now? Use the available tool, do not guess.' }
    )
    tools       = @(
        @{
            type     = 'function'
            function = @{
                name        = 'get_weather'
                description = 'Get the current weather for a city.'
                parameters  = @{
                    type       = 'object'
                    properties = @{
                        city = @{ type = 'string'; description = 'City name' }
                    }
                    required   = @('city')
                }
            }
        }
    )
    tool_choice = 'auto'
    temperature = 0
} | ConvertTo-Json -Depth 10

try {
    $resp = Invoke-RestMethod -Uri $apiUrl -Method Post -Body $body `
        -ContentType 'application/json' -TimeoutSec $TimeoutSeconds
} catch {
    Write-Host "RESULT: FAIL request failed: $($_.Exception.Message)"
    exit 1
}

$msg   = $resp.choices[0].message
$calls = $msg.tool_calls

if (-not $calls -or $calls.Count -eq 0) {
    Write-Host "RESULT: FAIL no tool_calls in response."
    Write-Host "Message content was: '$($msg.content)'"
    Write-Host "Finish reason: $($resp.choices[0].finish_reason)"
    exit 1
}

$first = $calls[0]
if ($first.function.name -ne 'get_weather') {
    Write-Host "RESULT: FAIL expected function name 'get_weather', got '$($first.function.name)'"
    exit 1
}

try {
    $argsObj = $first.function.arguments | ConvertFrom-Json
} catch {
    Write-Host "RESULT: FAIL function arguments are not valid JSON: $($first.function.arguments)"
    exit 1
}

if (-not $argsObj.city) {
    Write-Host "RESULT: FAIL no 'city' field in arguments: $($first.function.arguments)"
    exit 1
}

Write-Host ("Model:     {0}" -f $Model)
Write-Host ("Tool call: {0}(city='{1}')" -f $first.function.name, $argsObj.city)
Write-Host ("Call ID:   {0}" -f $first.id)
Write-Host 'RESULT: OK'
