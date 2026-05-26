# Local Coding LLM Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reproducible Windows-native setup that installs Ollama, pulls Qwen3-Coder-30B-A3B, wires it into the Cline VSCode extension, and proves end to end that the local coding agent works on the user's RTX 4080 hardware.

**Architecture:** Pure script project. Deliverables are PowerShell scripts, a handful of fixtures, and one short README. There is no application server, library, or domain code. Scripts are organized into four buckets: install, test, benchmark, validation. Install scripts run once in order. Test, benchmark, and validation scripts run independently against the live Ollama service.

**Tech Stack:** PowerShell 7+, Ollama, NVIDIA CUDA driver, VSCode + Cline extension (`saoudrizwan.claude-dev`), Python 3.11+ (for fixture verification only), Pytest.

**Source of truth:** [docs/superpowers/specs/2026-05-26-local-coding-llm-design.md](../specs/2026-05-26-local-coding-llm-design.md). When in doubt, the spec wins.

---

## File Structure

```
d:\workspace\run-local-model\
    README.md
    .gitignore                                       (already created)
    docs\superpowers\specs\
        2026-05-26-local-coding-llm-design.md        (already created)
    docs\superpowers\plans\
        2026-05-26-local-coding-llm.md               (this file)
    scripts\
        run-all-install.ps1
        install\
            01-install-ollama.ps1
            02-configure-storage.ps1
            03-pull-model.ps1
            04-install-vscode-cline.ps1
        test\
            test-ollama-health.ps1
            test-chat-completion.ps1
            test-tool-calling.ps1
        benchmark\
            benchmark-throughput.ps1
            benchmark-context.ps1
        validation\
            validate-coding-tasks.ps1
            validate-cline-e2e.md
    tests\fixtures\
        task-01-fizzbuzz\        (README.md, prompt.txt, verify.ps1)
        task-02-refactor\        (README.md, input\, prompt.txt, verify.ps1)
        task-03-bug-fix\         (README.md, input\, prompt.txt, verify.ps1)
        task-04-from-spec\       (README.md, prompt.txt, verify.ps1)
    benchmark-results\           (gitignored, created at runtime)
```

---

## Conventions Used Across All Scripts

These rules apply to every PowerShell script. The reader should not need to relearn them script by script.

1. **Strict mode.** Start each script with `#Requires -Version 7.0` and `$ErrorActionPreference = 'Stop'`.
2. **Idempotency first.** Before any work, check whether the work is already done. If yes, print a one line note and emit `RESULT: OK`, exit 0.
3. **Preconditions second.** Verify prerequisites (Ollama installed, service running, env vars). On any missing prerequisite, emit `RESULT: FAIL <reason>` and exit 1.
4. **Last line is structured.** Every script's final line is exactly one of `RESULT: OK` or `RESULT: FAIL <one line reason>`. Nothing else. Composability depends on this.
5. **No em dashes** anywhere in script output or comments. Use commas, parentheses, semicolons, or two short sentences.
6. **No `Co-Authored-By: Claude`** lines in any commit message. Ever.
7. **One commit per task.** Each task ends with a commit step. Commits are signed (`commit.gpgsign=true` already set globally).
8. **PowerShell only.** Do not introduce bash or batch scripts.

---

## Phase 1: Install Scripts and Orchestrator

### Task 1: scripts/install/01-install-ollama.ps1

**Files:** Create `scripts/install/01-install-ollama.ps1`.

**Responsibility:** Install the Ollama Windows binary if not already on PATH.

**Idempotency:** If `Get-Command ollama` succeeds, print the existing version and exit OK without doing anything else.

**Preconditions:** PowerShell 7. Internet access for the installer download.

**Effect on success:** `ollama` is on the system PATH and `ollama --version` works in a new shell.

**Behavior:**
* Download `OllamaSetup.exe` from `https://ollama.com/download/OllamaSetup.exe` to `$env:TEMP`.
* Run installer silently (`/SILENT` flag), wait for completion, check exit code.
* Refresh the current shell's PATH from Machine + User scopes so the verification step can find the new binary.
* Verify with `Get-Command ollama` after install. Fail if not found.

**Steps:**
- [ ] **1.1** Write the script.
- [ ] **1.2** Syntax check: `pwsh -NoProfile -Command "[scriptblock]::Create((Get-Content -Raw scripts/install/01-install-ollama.ps1)) | Out-Null; 'syntax ok'"`. Expected: `syntax ok`.
- [ ] **1.3** Commit: `feat(install): add Ollama installer script`.

---

### Task 2: scripts/install/02-configure-storage.ps1

**Files:** Create `scripts/install/02-configure-storage.ps1`.

**Responsibility:** Point Ollama at `D:\ai-models\ollama` for model storage so the model files do not fill the C:\ system drive.

**Idempotency:** If `OLLAMA_MODELS` Machine env var already equals the target path AND the API responds, exit OK.

**Preconditions:** Ollama installed (Task 1 done). Running with admin rights (required for Machine scope env var and service restart).

**Effect on success:** `OLLAMA_MODELS=D:\ai-models\ollama` is set system wide. Ollama service has been restarted. The API at `http://localhost:11434/api/tags` responds.

**Behavior:**
* Create the directory `D:\ai-models\ollama` if missing.
* Read current Machine scope `OLLAMA_MODELS`. If different from target, set it via `[Environment]::SetEnvironmentVariable(..., 'Machine')` and update the current process env so the verification works.
* Restart the `Ollama` Windows service. If no such service is registered (Ollama may be running as a tray app), print guidance and continue.
* Hit `/api/tags` to confirm the API is reachable after restart.

**Steps:**
- [ ] **2.1** Write the script.
- [ ] **2.2** Syntax check (same pattern as Task 1).
- [ ] **2.3** Commit: `feat(install): point Ollama storage at D:\\`.

---

### Task 3: scripts/install/03-pull-model.ps1

**Files:** Create `scripts/install/03-pull-model.ps1`.

**Responsibility:** Pull `qwen3-coder:30b` into Ollama.

**Idempotency:** If `ollama list` already shows the model, exit OK.

**Preconditions:** Ollama installed AND storage configured AND service running (Tasks 1, 2 done).

**Effect on success:** Model is present in `ollama list`. Blob files exist under `D:\ai-models\ollama\models\blobs\` totaling roughly 17 to 19 GB.

**Behavior:**
* Check `ollama list` for the model. If present, exit OK.
* Run `ollama pull qwen3-coder:30b`. The download is roughly 18 GB; expect to wait.
* Re-check `ollama list` to confirm.
* Read `OLLAMA_MODELS` Machine env var, then sum the size of files under its `models\blobs\` subdirectory. Print the total in GB so the user can confirm the model landed on D:\.

**Steps:**
- [ ] **3.1** Write the script.
- [ ] **3.2** Syntax check.
- [ ] **3.3** Commit: `feat(install): pull qwen3-coder:30b model`.

---

### Task 4: scripts/install/04-install-vscode-cline.ps1

**Files:** Create `scripts/install/04-install-vscode-cline.ps1`.

**Responsibility:** Install the Cline VSCode extension (publisher.name `saoudrizwan.claude-dev`).

**Idempotency:** If `code --list-extensions` already includes `saoudrizwan.claude-dev`, exit OK.

**Preconditions:** VSCode `code` CLI on PATH (option checked during VSCode install).

**Effect on success:** Cline extension is installed. The script also prints the four manual UI steps needed to configure Cline (Provider = Ollama, Base URL = `http://localhost:11434`, Model = `qwen3-coder:30b`, Save). These cannot be scripted because Cline stores settings in its own webview, not VSCode settings.json.

**Steps:**
- [ ] **4.1** Write the script.
- [ ] **4.2** Syntax check.
- [ ] **4.3** Commit: `feat(install): install Cline VSCode extension`.

---

### Task 5: scripts/run-all-install.ps1

**Files:** Create `scripts/run-all-install.ps1`.

**Responsibility:** Run the four install scripts in order, stop on the first failure, print which step failed.

**Idempotency:** Inherits from the child scripts (each is idempotent).

**Preconditions:** PowerShell 7. Admin rights (because Task 2 needs them).

**Effect on success:** All four install scripts have run cleanly, ending with `RESULT: OK all install scripts completed`.

**Behavior:**
* Iterate over the four install script paths in order.
* For each, invoke it and check `$LASTEXITCODE`. Stop on first nonzero exit with a clear `RESULT: FAIL <script> exited with <code>`.

**Steps:**
- [ ] **5.1** Write the script.
- [ ] **5.2** Syntax check.
- [ ] **5.3** Commit: `feat(install): add orchestrator that runs all install scripts`.

---

## Phase 2: Execute Installation (Acceptance Gate)

### Task 6: Run the installer end to end

**Files:** none changed.

This task is destructive (installs software, downloads ~18 GB). Run in an elevated PowerShell 7 session.

**Steps:**
- [ ] **6.1** Open PowerShell 7 "Run as administrator". Confirm `Administrator:` in the title bar.
- [ ] **6.2** Run `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\run-all-install.ps1`. Expected: orchestrator ends with `RESULT: OK all install scripts completed`.
- [ ] **6.3** Confirm model on D:\: `Get-ChildItem D:\ai-models\ollama\models\blobs | Measure-Object Length -Sum` should report a total around 17 to 19 GB.
- [ ] **6.4** Confirm API responds: `(Invoke-RestMethod http://localhost:11434/api/tags).models.name` should list `qwen3-coder:30b`.

No commit (no file changes).

---

## Phase 3: Functional Test Scripts

### Task 7: scripts/test/test-ollama-health.ps1

**Files:** Create `scripts/test/test-ollama-health.ps1`.

**Responsibility:** Confirm the API is reachable, the target model is listed, and after a one token warmup the model is resident in VRAM (not CPU only).

**Behavior:**
* GET `/api/tags`, fail with reason if unreachable.
* Find `qwen3-coder:30b` in the model list, fail with the list of what is available if missing.
* POST a single token warmup via `/api/generate` (prompt `'hi'`, `num_predict = 1`).
* GET `/api/ps`, find the model, read `size_vram`. Fail if zero (model loaded on CPU only, usually a CUDA install problem).
* Print the model's VRAM usage in GB.

**Steps:**
- [ ] **7.1** Write the script.
- [ ] **7.2** Run it against live Ollama. Expected: ends with `RESULT: OK`, VRAM usage in the 9 to 12 GB range.
- [ ] **7.3** Negative path sanity: temporarily change the model name to a nonexistent one, run, confirm `RESULT: FAIL`. Revert.
- [ ] **7.4** Commit: `feat(test): add Ollama health check script`.

---

### Task 8: scripts/test/test-chat-completion.ps1

**Files:** Create `scripts/test/test-chat-completion.ps1`.

**Responsibility:** Send a small deterministic prompt to the OpenAI compatible `/v1/chat/completions` endpoint (the same one Cline uses), assert a non empty response containing the expected token, and bound the total elapsed time.

**Behavior:**
* POST a chat completion with `messages = [{ role: 'user', content: 'Reply with exactly the number 4 and nothing else. What is 2+2?' }]`, `temperature = 0`, `max_tokens = 10`.
* Measure wall clock with `[Diagnostics.Stopwatch]`.
* Fail if no content in response, if content does not contain `4`, or if elapsed exceeded 30 seconds.

**Steps:**
- [ ] **8.1** Write the script.
- [ ] **8.2** Run it. Expected: prints `Reply: '4'`, elapsed under 10 s, ends with `RESULT: OK`.
- [ ] **8.3** Commit: `feat(test): add chat completion sanity test`.

---

### Task 9: scripts/test/test-tool-calling.ps1

**Files:** Create `scripts/test/test-tool-calling.ps1`.

**Responsibility:** Verify the model returns valid `tool_calls` when given a tool definition. Cline cannot function without this.

**Behavior:**
* POST a chat completion with a `get_weather(city)` tool definition, `tool_choice = 'auto'`, and a user message that should clearly trigger the tool ("What is the weather in Istanbul right now? Use the available tool, do not guess.").
* Assert response contains a `tool_calls` array, first call's `function.name == 'get_weather'`, and `function.arguments` parses as JSON with a `city` field.
* Fail with the actual message content (so the user can see what went wrong) if `tool_calls` is missing.

**Steps:**
- [ ] **9.1** Write the script.
- [ ] **9.2** Run it. Expected: prints `Tool call ok: get_weather(city='Istanbul')` (casing may vary), ends with `RESULT: OK`.
- [ ] **9.3** Commit: `feat(test): add tool calling verification script`.

---

## Phase 4: Execute Functional Tests (Acceptance Gate)

### Task 10: Run all functional tests

**Files:** none changed.

**Steps:**
- [ ] **10.1** Run the three tests in order. All three must end with `RESULT: OK`.
- [ ] **10.2** Triage on failure:
    * `test-ollama-health` fails: re-check that Task 2 actually restarted the service and Task 3 pulled the model.
    * `test-chat-completion` fails: check NVIDIA driver version and confirm `size_vram > 0` from the health test.
    * `test-tool-calling` fails with "no tool_calls": Qwen3-Coder's tool template did not negotiate. See spec section 10 risks for fallback (try Continue.dev which has more permissive parsing).
- [ ] **10.3** Do not proceed to fixtures until all three pass.

No commit.

---

## Phase 5: Benchmark Scripts

### Task 11: scripts/benchmark/benchmark-throughput.ps1

**Files:** Create `scripts/benchmark/benchmark-throughput.ps1`.

**Responsibility:** Measure cold and warm prefill plus decode throughput. Fail if warm decode average is below 20 tok/s (spec acceptance threshold).

**Behavior:**
* Fixed list of five short prompts (Fibonacci, DB index explanation, EN-to-TR translation, regex, unit testing summary).
* Force unload via `keep_alive = 0` then run the first prompt as the cold measurement.
* Run all five prompts as warm measurements.
* For each call use `/api/generate` with `stream = false`, `num_predict = 200`, and compute `prefill_tps = prompt_eval_count / (prompt_eval_duration / 1e9)` and `decode_tps = eval_count / (eval_duration / 1e9)`.
* Write structured JSON to `benchmark-results\throughput-<timestamp>.json` containing cold result, all warm results, and the warm averages.
* Fail with the actual average if warm avg decode is below 20 tok/s.

**Steps:**
- [ ] **11.1** Write the script.
- [ ] **11.2** Run it. Expected: 2 to 4 minutes runtime, per-prompt rates printed, warm average 25 to 40 tok/s, ends with `RESULT: OK`.
- [ ] **11.3** Confirm result file: `Get-ChildItem benchmark-results\throughput-*.json | Select-Object -Last 1 | Get-Content -Raw | ConvertFrom-Json | Select model, warm_avg_decode_tps`.
- [ ] **11.4** Commit: `feat(benchmark): add throughput benchmark`.

---

### Task 12: scripts/benchmark/benchmark-context.ps1

**Files:** Create `scripts/benchmark/benchmark-context.ps1`.

**Responsibility:** For each of 8K, 32K, 64K context window sizes, force a reload with that `num_ctx`, send a padded prompt that fills most of the context, measure time to first token and VRAM usage. Fail if the 32K run does not complete (primary working context).

**Behavior:**
* Three context sizes: 8192, 32768, 65536.
* For each size: unload model (`keep_alive = 0`), build a prompt that fills roughly 80% of the context with repeating Lorem Ipsum padding, send via `/api/generate` with `num_ctx = <size>` and `num_predict = 5`, catch exceptions.
* Capture VRAM via `nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits` after each run.
* Write JSON to `benchmark-results\context-<timestamp>.json` with per-size: ok flag, prompt token count, TTFT seconds, VRAM MB, wall seconds, error message if any.
* Fail only if the 32K run did not complete. 64K is informational, not blocking.

**Steps:**
- [ ] **12.1** Write the script.
- [ ] **12.2** Run it. Expected: 8K and 32K complete cleanly, 64K may or may not (VRAM dependent), ends with `RESULT: OK`.
- [ ] **12.3** Commit: `feat(benchmark): add context window benchmark`.

---

## Phase 6: Execute Benchmarks (Acceptance Gate)

### Task 13: Run benchmarks and confirm acceptance

**Files:** none changed.

**Steps:**
- [ ] **13.1** Run `benchmark-throughput.ps1`. Must end `RESULT: OK` (warm decode avg >= 20 tok/s).
- [ ] **13.2** Run `benchmark-context.ps1`. Must end `RESULT: OK` (32K completes).
- [ ] **13.3** Inspect latest result files: `Get-ChildItem benchmark-results -File | Sort LastWriteTime -Descending | Select -First 2`. Two recent JSON files expected.

No commit.

---

## Phase 7: Test Fixtures

Each fixture is a self contained mini coding task. The validate script (Task 18) iterates over them.

### Task 14: tests/fixtures/task-01-fizzbuzz

**Files:**
* Create `tests/fixtures/task-01-fizzbuzz/README.md` (one paragraph: baseline test, model produces `fizzbuzz.py` printing 1..100 FizzBuzz)
* Create `tests/fixtures/task-01-fizzbuzz/prompt.txt`
* Create `tests/fixtures/task-01-fizzbuzz/verify.ps1`

**Prompt content (exact text in prompt.txt):**

> Produce a single Python file named fizzbuzz.py that, when executed, prints the FizzBuzz sequence from 1 through 100 inclusive, one value per line.
>
> Rules:
> - Multiples of 3 print Fizz.
> - Multiples of 5 print Buzz.
> - Multiples of both print FizzBuzz.
> - Other numbers print the number itself.
>
> Output exactly one fenced Python code block. The first line inside the block must be a comment with the exact filename: # fizzbuzz.py

**Verify behavior:**
* Assert `fizzbuzz.py` exists.
* Run `python fizzbuzz.py`, capture output, check exit code.
* Assert output has exactly 100 non-empty lines.
* Spot check positions 0 (`1`), 1 (`2`), 2 (`Fizz`), 4 (`Buzz`), 14 (`FizzBuzz`), 99 (`Buzz`).
* Exit 0 with `verify OK`, or exit 1 with `verify FAIL: <reason>`.

**Steps:**
- [ ] **14.1** Create README.md.
- [ ] **14.2** Create prompt.txt with the exact text above.
- [ ] **14.3** Create verify.ps1 per the behavior spec above.
- [ ] **14.4** Smoke test verifier: write a known good `fizzbuzz.py` to a temp dir, run verify, expect exit 0 and `verify OK`.
- [ ] **14.5** Commit: `test(fixture): add FizzBuzz baseline fixture`.

---

### Task 15: tests/fixtures/task-02-refactor

**Files:**
* Create `tests/fixtures/task-02-refactor/README.md`
* Create `tests/fixtures/task-02-refactor/input/messy.py`
* Create `tests/fixtures/task-02-refactor/input/test_messy.py`
* Create `tests/fixtures/task-02-refactor/prompt.txt`
* Create `tests/fixtures/task-02-refactor/verify.ps1`

**Input `messy.py` description (~30 lines, intentionally tangled):**
* A `doit(x, y, op)` calculator with branches for `add`, `sub`, `mul`, `div`. Include obvious code smells: a useless `for i in range(0, 1)` loop in the add branch, a pointless `r = r` self-assignment in sub, manual multiplication via a loop in mul, bare `Exception` raises for div-by-zero and bad op.
* A `process_list(items)` function that takes a list of mixed items: skips `None`, doubles positive ints, passes negative ints through, uppercases strings, ignores other types with `pass`.

**Input `test_messy.py` description (~25 lines):**
* Pytest tests that exercise both functions: `test_add`, `test_sub`, `test_mul_positive`, `test_mul_negative`, `test_div`, `test_div_zero` (expects exception), `test_bad_op` (expects exception), `test_process_list` asserting the input `[1, -2, None, 'hi', 3.14, 0]` produces `[2, -2, 'HI', 0]`.
* These tests must pass against the original (unrefactored) `messy.py`.

**Prompt content (exact text in prompt.txt):**

> Refactor the file messy.py so that:
> - All existing tests in test_messy.py still pass without modification.
> - Functions are smaller and have clearer names.
> - Obvious dead code (no-op loops, useless self-assignments) is removed.
> - Raise specific exception types (ValueError, ZeroDivisionError) instead of bare Exception.
>
> Output exactly one fenced Python code block containing the new contents of messy.py. The first line inside the block must be a comment with the exact filename: # messy.py
>
> Do not output the test file. Do not output explanatory prose.

**Verify behavior:**
* Assert `messy.py` exists.
* Assert `test_messy.py` exists (should have been copied from `input/` by the validator).
* Run `python -m pytest test_messy.py -q`. Exit 0 on green, exit 1 on red.

**Steps:**
- [ ] **15.1** Create README.md.
- [ ] **15.2** Create input/messy.py per the description above.
- [ ] **15.3** Create input/test_messy.py per the description above.
- [ ] **15.4** Create prompt.txt with the exact text above.
- [ ] **15.5** Create verify.ps1.
- [ ] **15.6** Smoke test: copy `input/*` to a temp dir, run verify there, expect exit 0 (original messy.py preserves behavior so tests pass).
- [ ] **15.7** Commit: `test(fixture): add refactor fixture`.

---

### Task 16: tests/fixtures/task-03-bug-fix

**Files:**
* Create `tests/fixtures/task-03-bug-fix/README.md`
* Create `tests/fixtures/task-03-bug-fix/input/calculator.py`
* Create `tests/fixtures/task-03-bug-fix/input/test_calculator.py`
* Create `tests/fixtures/task-03-bug-fix/prompt.txt`
* Create `tests/fixtures/task-03-bug-fix/verify.ps1`

**Input `calculator.py` description (~16 lines, one specific bug):**
* `add(a, b)` and `sub(a, b)`: trivially correct.
* `avg(values)`: raises `ValueError` on empty list. **Bug:** returns `sum(values) // len(values)` (integer division), so `avg([2, 3])` returns 2 instead of 2.5.
* `is_prime(n)`: trial division up to `n`. Correct.

**Input `test_calculator.py` description (~25 lines):**
* Tests for `add`, `sub`, `avg` integer result `[2,4,6] -> 4`, `avg` non-integer result `[2,3] -> 2.5` (this is the FAILING test), `avg` empty raises, `is_prime` true and false cases.

**Prompt content (exact text in prompt.txt):**

> The file calculator.py has a bug. Running pytest on test_calculator.py shows one failing test: test_avg_non_integer_result. Fix the bug with the minimum change possible. Do not modify any other behavior. Do not touch the test file.
>
> Output exactly one fenced Python code block containing the new contents of calculator.py. The first line inside the block must be a comment with the exact filename: # calculator.py
>
> Do not output the test file. Do not output explanatory prose.

**Verify behavior:**
* Same shape as Task 15: assert files exist, run `python -m pytest test_calculator.py -q`, propagate exit code.

**Steps:**
- [ ] **16.1** Create README.md.
- [ ] **16.2** Create input/calculator.py with the integer-division bug.
- [ ] **16.3** Create input/test_calculator.py including the failing test.
- [ ] **16.4** Create prompt.txt with the exact text above.
- [ ] **16.5** Create verify.ps1.
- [ ] **16.6** Smoke test, negative path: copy `input/*` to a temp dir, run verify, expect exit 1 (the bug is still present, verifier should discriminate).
- [ ] **16.7** Smoke test, positive path: copy `input/*` to another temp dir, manually fix `//` to `/` in calculator.py, run verify, expect exit 0.
- [ ] **16.8** Commit: `test(fixture): add bug fix fixture`.

---

### Task 17: tests/fixtures/task-04-from-spec

**Files:**
* Create `tests/fixtures/task-04-from-spec/README.md`
* Create `tests/fixtures/task-04-from-spec/prompt.txt`
* Create `tests/fixtures/task-04-from-spec/verify.ps1`

No `input/` directory; this fixture is from-scratch.

**Prompt content (exact text in prompt.txt):**

> Build a single Python file csv_group.py with the following CLI:
>
> Usage: python csv_group.py --by COLUMN
>
> Reads CSV data from stdin (header row required). Groups rows by the value in COLUMN. Prints, in alphabetical order of group key, one line per group of the form:
>
> GROUP_KEY: COUNT
>
> Example, given input:
>     name,team
>     alice,red
>     bob,blue
>     carol,red
>
> Running: python csv_group.py --by team
> Should print:
>     blue: 1
>     red: 2
>
> Rules:
> - Use only the Python standard library (argparse, csv, sys).
> - Exit 1 with an error to stderr if the column does not exist or stdin is empty.
>
> Output exactly one fenced Python code block. The first line inside the block must be a comment with the exact filename: # csv_group.py
>
> Do not output explanatory prose.

**Verify behavior:**
* Assert `csv_group.py` exists.
* Feed a fixed CSV (`name,team` header with rows: alice/red, bob/blue, carol/red, dave/green, eve/red) via stdin to `python csv_group.py --by team`.
* Assert exit 0 and output lines exactly: `blue: 1`, `green: 1`, `red: 3` (in that order).
* Negative: same CSV with `--by nope` (missing column), assert nonzero exit.

**Steps:**
- [ ] **17.1** Create README.md.
- [ ] **17.2** Create prompt.txt with the exact text above.
- [ ] **17.3** Create verify.ps1.
- [ ] **17.4** Smoke test: write a hand-correct `csv_group.py` to a temp dir, run verify, expect exit 0 with `verify OK`.
- [ ] **17.5** Commit: `test(fixture): add from-spec CLI fixture`.

---

## Phase 8: Validation Script

### Task 18: scripts/validation/validate-coding-tasks.ps1

**Files:** Create `scripts/validation/validate-coding-tasks.ps1`.

**Responsibility:** Iterate over `tests/fixtures/*`, send each prompt to Ollama, materialize the model's code blocks into files in a per-task output directory, copy any `input/` files alongside, run the fixture's `verify.ps1`, aggregate PASS or FAIL. Acceptance: at least 3 of 4 fixtures pass.

**Behavior:**
* Resolve `tests/fixtures/` and create a per-run output directory under `benchmark-results/validation-<timestamp>/`.
* Use a fixed system prompt that instructs the model to output exactly one fenced code block per file, with the first line being a comment containing the filename (`# fizzbuzz.py`, `// app.js`, etc.) and no prose around it.
* For each fixture in sorted order:
    * Skip if no `prompt.txt` or `verify.ps1`.
    * Copy any `input/*` files into the per-task output dir (so model edits start from them).
    * POST to `/v1/chat/completions` with `temperature = 0`, capture content.
    * Save raw output as `_raw_output.md` for debugging.
    * Parse fenced code blocks via regex, extract filename from the first line via a regex like `^[#/]+\s*([\w\.\-_/]+\.[\w]+)\s*$`, write each block's body to the matching file (creating subdirs as needed).
    * If no fileable code blocks: mark FAIL with reason "no files produced".
    * `Push-Location` into the output dir, run `verify.ps1`, capture `$LASTEXITCODE`, `Pop-Location`. PASS if exit 0.
* Print a summary table (PASS/FAIL per fixture, count, run artifact path).
* Emit `RESULT: OK` if pass count >= 3, otherwise `RESULT: FAIL only X of Y fixtures passed (need at least 3)`.

**Steps:**
- [ ] **18.1** Write the script.
- [ ] **18.2** Syntax check.
- [ ] **18.3** Commit: `feat(validation): add coding tasks validator`.

---

## Phase 9: Execute Validation (Acceptance Gate)

### Task 19: Run quality validation

**Files:** none changed.

**Steps:**
- [ ] **19.1** Run `validate-coding-tasks.ps1`. Expected: each fixture prints PASS or FAIL, summary at end, ends `RESULT: OK` if at least 3 of 4 passed.
- [ ] **19.2** If any fixture failed, inspect the per-task output:
    * `Get-ChildItem benchmark-results\validation-* -Directory | Sort LastWriteTime -Desc | Select -First 1`
    * Open `_raw_output.md` in the failed task's dir to see what the model actually produced.
    * Common causes: model wrote prose around the code block (strengthen the system prompt), or the filename header is wrong format.
- [ ] **19.3** One failure of four still meets acceptance per spec. Do not retroactively change the threshold.

No commit.

---

## Phase 10: Manual Checklist and README

### Task 20: scripts/validation/validate-cline-e2e.md

**Files:** Create `scripts/validation/validate-cline-e2e.md`.

**Responsibility:** Five-minute manual checklist that proves the Cline VSCode integration works end to end. Not automated because driving the Cline webview reliably from outside is not worth the engineering cost for a single-user project. Intended to be re-run quarterly or after any Ollama or Cline upgrade.

**Required sections:**
1. **Setup checks** (2 items): Ollama API responds with the model listed; VSCode is open in a scratch folder (not this repo, to avoid the agent operating on its own source).
2. **Walkthrough** (12 items): open Cline panel; verify provider/base URL/model are set correctly; type "Create a hello.py that prints hi from local llm", confirm a file-create tool call is proposed (not plain text); approve; verify file exists; ask to run it, confirm terminal command tool call, approve, see expected output; ask to change the message, confirm Cline reads then edits, approve, verify content; finally check multi-turn history is intact.
3. **Pass criteria:** all 12 walkthrough boxes checked. If step 4 (tool call proposal) fails, that means tool calling is not negotiating; re-run `scripts\test\test-tool-calling.ps1` and inspect Cline settings for a "force JSON" / "compatibility mode" toggle.

**Steps:**
- [ ] **20.1** Write the checklist following the structure above.
- [ ] **20.2** Commit: `docs(validation): add Cline e2e manual checklist`.

---

### Task 21: README.md

**Files:** Create `README.md` at the repo root.

**Responsibility:** Short orientation. Goal in one sentence, hardware tested table, 5-line quick start, layout table linking subfolders to their purpose, link to the spec for detail, conventions list.

**Required sections:**
1. **Title and one-paragraph description.** What the repo is, what stack.
2. **Hardware tested** (table): GPU, RAM, Disk, OS.
3. **Quick start** (4-5 PowerShell commands): run-all-install, then the three test scripts. Followed by one sentence on the manual Cline UI config (Provider Ollama, Base URL, Model).
4. **Layout** (table): one row per top-level folder, one-line purpose each.
5. **Detail:** link to `docs/superpowers/specs/2026-05-26-local-coding-llm-design.md`.
6. **Conventions:** the bullet list from this plan's Conventions section (strict mode, idempotency, RESULT line, no em dashes).

**Steps:**
- [ ] **21.1** Write README.md per the section list above.
- [ ] **21.2** Commit: `docs: add README with quick start and layout`.

---

## Phase 11: Final Acceptance

### Task 22: Final acceptance run

**Files:** none changed (unless step 4 resolves a deferred decision).

Confirms spec section 8.1 success criteria for the whole setup:
* Layer 1: all functional tests pass.
* Layer 2: warm decode at or above 20 tok/s, 32K context fits.
* Layer 3: at least 3 of 4 fixtures pass.
* Layer 4: manual checklist all checked.

**Steps:**
- [ ] **22.1** Re-run all four layers in order: 3 functional tests, 2 benchmarks, 1 validation. Every script's last line must be `RESULT: OK`.
- [ ] **22.2** Walk through `scripts\validation\validate-cline-e2e.md` and tick every box.
- [ ] **22.3** Push all commits: `git push origin main`.
- [ ] **22.4** If acceptance resolved any spec section 9 deferred decision (final `num_ctx`, GPU layer pin, parallel slots), edit the spec to record the decision, commit, push.

The setup is complete.
