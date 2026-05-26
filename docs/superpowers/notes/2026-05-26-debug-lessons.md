# Debug Lessons From The 2026-05-26 Setup Run

Things that cost us time during the live setup. Written so the next person (or future self) does not pay the same toll.

## 1. OLLAMA_MODELS is the models directory itself, not a parent

Lost roughly 30 minutes here.

The intuition is "set OLLAMA_MODELS to some root directory, Ollama will create a `models\` subdirectory inside it." That is wrong.

`OLLAMA_MODELS` points at the **models directory itself**. Files land at:

```
$OLLAMA_MODELS\blobs\
$OLLAMA_MODELS\manifests\
```

NOT at `$OLLAMA_MODELS\models\blobs\`.

If you move an existing `.ollama\models\` directory verbatim into your target path, Ollama will see no models (logged as `total blobs: 0`) because it looks one level too high. Either:

* Move the **contents** of `.ollama\models\` directly into `$OLLAMA_MODELS\`, or
* Set `$OLLAMA_MODELS` to `<your-target>\models` (awkward naming).

We picked option A. `02-configure-storage.ps1` now creates `D:\ai-models\ollama\` and expects `blobs\` and `manifests\` at the top level.

How to confirm Ollama is reading the right path: enable `OLLAMA_DEBUG=1` and grep stderr for `OLLAMA_MODELS:` and `total blobs:`. If `total blobs: 0` while you know files exist on disk, you have a path mismatch, not an Ollama bug.

## 2. The Ollama tray app does not pick up runtime environment changes

Lost roughly 45 minutes here.

The Ollama Windows installer registers `ollama app.exe` to auto-start at user login. That tray app spawns `ollama.exe serve` as a child process. The chain of environment inheritance is:

```
login -> explorer.exe -> ollama app.exe -> ollama serve
```

`explorer.exe` reads its environment from the registry at login time. After login, if you change a User-scope env var via `[Environment]::SetEnvironmentVariable(..., 'User')`, neither `explorer.exe` nor any of its existing children see the change. Killing the tray app and re-launching from your terminal also fails if you use `Start-Process` because, depending on the PowerShell version and process configuration, the new tray process may still inherit explorer's stale environment.

What worked: launch `ollama serve` ourselves using .NET `ProcessStartInfo` with an explicit `Environment` dictionary:

```powershell
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'C:\Users\ahank\AppData\Local\Programs\Ollama\ollama.exe'
$psi.Arguments = 'serve'
$psi.UseShellExecute = $false
foreach ($e in [Environment]::GetEnvironmentVariables('Process').GetEnumerator()) {
    $psi.Environment[$e.Key] = [string]$e.Value
}
$psi.Environment['OLLAMA_MODELS'] = 'D:\ai-models\ollama'
[System.Diagnostics.Process]::Start($psi)
```

This is what `02-configure-storage.ps1` does. The tray app is bypassed entirely (no tray icon in this session).

For persistence across reboots without re-running the script, set `OLLAMA_MODELS` in **Machine scope** from an elevated shell once:

```powershell
[Environment]::SetEnvironmentVariable('OLLAMA_MODELS','D:\ai-models\ollama','Machine')
```

Machine-scope env vars are loaded by Windows at boot and are visible to the tray app's auto-launch at login. `02-configure-storage.ps1` does this automatically when it detects it is running elevated.

## 3. Models output filenames in three different ways. Parse all three

The validator parses `/v1/chat/completions` text output to extract files. Different model classes use different conventions:

| Style | Looks like | Example model |
|---|---|---|
| Standard fenced, filename inside | ` ```python\n# foo.py\n... ``` ` | qwen2.5-coder:1.5b (when it works) |
| Fenced, filename before the fence | ` # foo.py\n\n```python\n... ``` ` | qwen2.5-coder:1.5b (sometimes) |
| No fence, filename as comment header | ` # foo.py\n<code>\n` | qwen3-coder:30b (took the "no prose outside code blocks" instruction literally) |

If your parser only handles the first style, 30B output looks empty. Our validator now handles all three with a fence-based primary path and a raw-mode fallback that detects `^[#/]+\s*([\w\.\-_/]+\.[\w]+)\s*$` section markers. The raw-mode fallback also strips standalone ` ``` ` lines that the model emits asymmetrically (closing fence with no opening, or vice versa).

## 4. Models cannot refactor what they cannot see

The original validator design copied `tests\fixtures\<task>\input\*` into the per-task working directory so the verify script could run. But the input files were never put into the **prompt** sent to the model. The model was asked "refactor messy.py to satisfy these constraints" with no way to see `messy.py`. Both 1.5B and 30B hallucinated unrelated code in response.

Fix: the validator now reads any `input\` files and prepends their contents to the prompt as labeled reference blocks. With this change, 30B passes the refactor and bug-fix fixtures correctly.

Lesson: copying files for verification is not the same as making them visible to the model. If a task assumes the model can read existing source, the validator must include that source in the prompt.

## 5. Tool calling needs a 7B-plus model. 1.5B is not enough

`/v1/chat/completions` has a structured `tool_calls` array in the response. Models trained with native tool-calling templates fill it. Smaller models (1.5B class) do not, even when given the same tool definitions. They emit the call as a JSON code block inside `message.content`:

```
message.content =
  ```json
  { "name": "get_weather", "arguments": { "city": "Istanbul" } }
  ```
```

Cline (and most other agent clients) only read the structured `tool_calls` field. The embedded-JSON fallback is invisible to them. Practical rule:

* Use 7B-plus models for any flow that requires real tool calling.
* Small models are still useful for iterating on validators, parsers, prompts, and the test pipeline itself.

`test-tool-calling.ps1` now documents this requirement in its header. It is the FIRST functional test that fails on a model below the tool-calling threshold, which is the right place to discover the issue.

## 6. PowerShell unwraps single-element arrays. Index with [-1] gives a char

Classic PowerShell gotcha. When you do:

```powershell
$lines = ($string -split "`n") | Where-Object { ... }
$last = $lines[-1].Trim()    # may fail with "Method 'Trim' not found on System.Char"
```

If the pipeline returned a single string, `$lines` is a string (not an array of one), and `[-1]` indexes the last character of that string, yielding a `[char]`. `[char]` has no `Trim` method.

Fix: force an array with `@()`:

```powershell
$lines = @(($string -split "`n") | Where-Object { ... })
$last = [string]$lines[$lines.Count - 1]
```

We hit this in the validator's "look at the last line before a code block" path.

## 7. Per-session vs. per-shell PATH refresh

Windows installers (Ollama, VSCode) write themselves into the registry `PATH` but do not update env in already-running shells. Every script that depends on a newly-installed binary needs to refresh PATH at the top:

```powershell
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + `
            [Environment]::GetEnvironmentVariable('Path', 'User')
```

We added this to every script that looks for `ollama` or `code`. Without it, scripts fail their precondition check with "ollama is not installed" even though it just got installed in the previous step.

## 8. Per-session pinentry caching

`commit.gpgsign=true` is set globally. The first signed commit in a fresh GPG session triggers `pinentry-qt` for the passphrase. This dialog can launch behind other windows. If it times out (default 30 s on this setup), the commit fails with `signing failed: Timeout`. Once the passphrase is entered, gpg-agent caches it and subsequent commits sign instantly.

If a commit fails with this error, look for a hidden pinentry dialog or trigger one manually by signing a dummy file:

```powershell
"test" | gpg --clearsign --local-user <YOUR_KEY_ID>
```

The user-visible symptom in this session was that the first commit of a session would time out, but the next attempt seconds later would succeed because the dialog had been brought to focus.
