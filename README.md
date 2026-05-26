# local-coding-llm

Reproducible scripts for running a local coding LLM on Windows with an NVIDIA GPU. The stack is Ollama serving Qwen3-Coder-30B-A3B, consumed by the Cline VSCode extension as an in-IDE coding agent.

See [docs/superpowers/specs/2026-05-26-local-coding-llm-design.md](docs/superpowers/specs/2026-05-26-local-coding-llm-design.md) for the full design and [docs/superpowers/plans/2026-05-26-local-coding-llm.md](docs/superpowers/plans/2026-05-26-local-coding-llm.md) for the implementation plan.

## Hardware tested

| Resource | Value |
|---|---|
| GPU | NVIDIA GeForce RTX 4080, 16 GB VRAM |
| RAM | 32 GB |
| Disk | 500 GB free on D:\ |
| OS | Windows 11 Pro |

## Quick start

From an elevated PowerShell 7 session (admin needed for Machine-scope env var in step 02):

```powershell
cd d:\workspace\run-local-model
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\run-all-install.ps1
```

This runs:
1. `01-install-ollama.ps1`     install Ollama if missing
2. `02-configure-storage.ps1`  point OLLAMA_MODELS at D:\ai-models\ollama and start ollama serve with that env
3. `03-pull-model.ps1`         download qwen3-coder:30b (~18 GB)
4. `04-install-vscode-cline.ps1` install Cline VSCode extension

After install, configure Cline manually in VSCode:
1. Click the Cline icon in the activity bar
2. Set API Provider = Ollama, Base URL = `http://localhost:11434`, Model = `qwen3-coder:30b`

## Measured performance, 2026-05-26 acceptance run

Hardware as above (RTX 4080 16 GB, 32 GB RAM, D:\ SSD).

**qwen3-coder:30b (Q4_K_M, ~17 GB on disk, 14.16 GB VRAM resident):**

| Layer | Result |
|---|---|
| test-ollama-health | PASS, VRAM 14.16 GB |
| test-chat-completion | PASS, 2.61 s end to end |
| test-tool-calling | PASS, valid `tool_calls` field returned |
| benchmark-throughput | warm decode avg 55.5 tok/s, warm prefill avg 279 tok/s |
| benchmark-context, 8K | TTFT 2.97 s, VRAM 15.7 GB |
| benchmark-context, 32K | TTFT 10.8 s, VRAM 15.5 GB (agent sweet spot) |
| benchmark-context, 64K | TTFT 29.6 s, VRAM 15.7 GB (works but slow) |
| validate-coding-tasks | 4 of 4 fixtures PASS, gen 3.7 to 7.2 s each |
| validate-cline-e2e | 12 of 12 checklist items PASS |

**qwen2.5-coder:1.5b (used for fast pipeline iteration only):**

| Layer | Result |
|---|---|
| test-ollama-health | PASS, VRAM 1.31 GB |
| test-chat-completion | PASS, 3.76 s |
| test-tool-calling | FAIL (model embeds JSON in content, not `tool_calls` field) |
| benchmark-throughput | warm decode avg 330 tok/s |
| validate-coding-tasks | 1 of 4 PASS (model too small for refactor/bug-fix/from-spec, even with input context) |

Use 1.5B for iterating on the validator and scripts. Use 30B for actual coding work and any tool-calling test.

## Iterating with a small model

Most scripts accept `-Model <name>`. Use a tiny model (~1 GB) to iterate on the pipeline before running expensive tests:

```powershell
pwsh -File scripts\install\03-pull-model.ps1                 -Model qwen2.5-coder:1.5b
pwsh -File scripts\test\test-ollama-health.ps1               -Model qwen2.5-coder:1.5b
pwsh -File scripts\test\test-chat-completion.ps1             -Model qwen2.5-coder:1.5b
pwsh -File scripts\benchmark\benchmark-throughput.ps1        -Model qwen2.5-coder:1.5b
pwsh -File scripts\validation\validate-coding-tasks.ps1      -Model qwen2.5-coder:1.5b -MinPass 1
```

Note: tool calling needs a 7B+ model. 1.5B models embed the call as JSON in message text instead of using the OpenAI `tool_calls` field. Use `qwen3-coder:30b` (or `llama3.2:3b` for a smaller alternative) for `test-tool-calling.ps1`.

## Layout

| Folder | Purpose |
|---|---|
| `scripts\install\` | Numbered install steps. Run in order via `run-all-install.ps1`. |
| `scripts\test\` | Functional tests. Confirms the pipeline is wired up. |
| `scripts\benchmark\` | Throughput and context-window measurement. |
| `scripts\validation\` | Quality validation (coding tasks) and the manual e2e checklist. |
| `tests\fixtures\` | Coding-task fixtures used by `validate-coding-tasks.ps1`. |
| `docs\superpowers\specs\` | Design spec, source of truth for what this project does and why. |
| `docs\superpowers\plans\` | Implementation plan. |
| `benchmark-results\` | Gitignored. JSON results from benchmark and validation runs. |

## Conventions

Every PowerShell script:

* Begins with `#Requires -Version 7.0` and `$ErrorActionPreference = 'Stop'`.
* Is idempotent. Re-running causes no harm.
* Ends with a single `RESULT: OK` or `RESULT: FAIL <reason>` line.
* Uses no em dashes in output or comments.

## Notes

**Storage layout:** `OLLAMA_MODELS` points at a directory containing `blobs\` and `manifests\` subdirs directly. Common mistake: leaving the model in `<root>\models\blobs\` (one level too deep).

**Tray app vs. direct serve:** the Ollama Windows tray app does not reliably propagate runtime env-var changes. Script `02-configure-storage.ps1` kills the tray and starts `ollama serve` itself via `.NET ProcessStartInfo` with an explicit environment.

**Reboot persistence:** to keep the storage path across reboots without re-running the script, set `OLLAMA_MODELS` in Machine scope from an elevated shell once:
```powershell
[Environment]::SetEnvironmentVariable('OLLAMA_MODELS','D:\ai-models\ollama','Machine')
```
Script 02 does this automatically when run elevated.

**Acceptance thresholds:** `validate-coding-tasks.ps1` defaults to `-MinPass 3` (production threshold for the 30B model). Use `-MinPass 1` when iterating with small models.
