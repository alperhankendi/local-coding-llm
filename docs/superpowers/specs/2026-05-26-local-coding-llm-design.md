# Local Coding LLM Setup, Design Spec

**Date:** 2026-05-26
**Author:** <ahankendi@gmail.com>
**Status:** Draft, pending user approval

## 1. Goal

Run a strong open-weight coding LLM fully locally on the user's Windows workstation, served through an OpenAI compatible HTTP endpoint, and consumed by the Cline VSCode extension as an in-IDE coding agent. The setup must be reproducible from scripts, verifiable through automated tests, and tunable for the user's specific hardware.

## 2. Non Goals

The following are intentionally out of scope for this spec:

* Multi user serving or production hosting.
* GPU sharing across multiple concurrent agents.
* Fine tuning or LoRA training of the model.
* Cloud fallback or hybrid routing to a remote provider.
* CLI agent clients (opencode, aider). They can be added later, but the initial setup targets Cline only.
* Linux or WSL deployment. Pure Windows path.

## 3. Hardware Context

| Resource  | Value                               |
| --------- | ----------------------------------- |
| GPU       | NVIDIA GeForce RTX 4080, 16 GB VRAM |
| RAM       | 32 GB                               |
| Free disk | 500 GB on D:\ (SSD)                 |
| OS        | Windows 11 Pro                      |

The model footprint plus context window must fit within these limits without swapping to system RAM in a way that destroys throughput.

## 4. Model Selection

**Chosen model:** Qwen3-Coder-30B-A3B (Q4\_K\_M GGUF).

Rationale:

* Mixture of Experts architecture. 30B total parameters but only about 3B active per token, which gives strong throughput on a 16 GB GPU.
* Coding focused training. Outperforms general purpose 30B class models on tool calling and code edit tasks.
* Q4\_K\_M quantization fits the model weights in roughly 18 GB. With layer offload tuning, decode speed lands in the 25 to 40 tokens per second range on this hardware.
* Available through Ollama's official model registry, no manual GGUF assembly required.

Alternative considered: Qwen2.5-Coder-32B was rejected for the primary workflow because dense 32B at Q4 lands in the 5 to 12 tokens per second range on this GPU, which is too slow for an interactive agent loop. It may be added later as a "deep think" model.

## 5. Architecture

```
+--------------------------------------------------------------+
|  VSCode                                                      |
|    Cline extension                                           |
|         |                                                    |
|         | HTTP, OpenAI Chat Completions API                  |
|         v                                                    |
|  Ollama server, localhost:11434, Windows background service  |
|         |                                                    |
|         | llama.cpp runtime, CUDA backend                    |
|         v                                                    |
|  qwen3-coder:30b GGUF, ~18 GB, stored on D:\                 |
+--------------------------------------------------------------+
```

Three independent components:

1. **Ollama service.** Hosts the model. Installed once, runs in the background. Single responsibility: load GGUF into GPU and serve HTTP.
2. **Cline VSCode extension.** Runs the agent loop, read, write, execute. Calls Ollama only for text generation. Single responsibility: translate user intent into tool calls.
3. **This project repo.** Contains setup scripts, test fixtures, and documentation. Has no runtime role. It exists for reproducibility.

### 5.1 Interface Boundaries

* Between Cline and Ollama: standard OpenAI Chat Completions API at `http://localhost:11434/v1/chat/completions`. If the backend is later swapped to llama.cpp server or LM Studio, Cline does not need to change.
* Between model files and runtime: Ollama's Modelfile. Quantization and context window changes happen there, not in any script that consumes the model.

### 5.2 Storage Layout

Model files are kept off the C:\ system drive to preserve OS free space and to put them on the larger user drive.

```
D:\ai-models\ollama\          (Ollama OLLAMA_MODELS root)
    models\
        blobs\
        manifests\
```

The `OLLAMA_MODELS` environment variable is set system wide so the Ollama service picks it up on startup.

## 6. Repo Layout

```
d:\workspace\run-local-model\
    README.md                           (English, brief setup and usage)
    docs\
        superpowers\
            specs\
                2026-05-26-local-coding-llm-design.md
    scripts\
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
        run-all-install.ps1
    tests\
        fixtures\
            task-01-fizzbuzz\
            task-02-refactor\
            task-03-bug-fix\
            task-04-from-spec\
    benchmark-results\                  (gitignored, output dir)
```

## 7. Script Design Rules

These rules apply to every PowerShell script in `scripts\`:

1. **Single responsibility.** One script does one thing. Install does not configure. Configure does not pull.
2. **Idempotent.** Running a script twice causes no harm. Each script begins by checking whether its work is already done.
3. **Numbered prefixes only in** **`install\`.** Install scripts have a strict order. Test, benchmark, and validation scripts are independent.
4. **Precondition checks.** Each script verifies what it depends on before doing work. A failed precondition produces a clear error, never a silent partial run.
5. **Structured final line.** Every script's last line is `RESULT: OK` or `RESULT: FAIL <reason>`. This makes scripts composable and machine readable.
6. **PowerShell only for now.** Windows is the only target. Shell scripts can be added later if WSL becomes a path.
7. **No em dashes in script output or comments.** Style consistency with project docs.

### 7.1 Install Script Responsibilities

| Script                        | Responsibility                                                                                                                                                                |
| ----------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `01-install-ollama.ps1`       | Download Ollama installer, run silently, verify `ollama` is on PATH. If already installed at correct version, skip.                                                           |
| `02-configure-storage.ps1`    | Create `D:\ai-models\ollama`, set `OLLAMA_MODELS` system env var, restart Ollama service so the change takes effect.                                                          |
| `03-pull-model.ps1`           | Run `ollama pull qwen3-coder:30b`. Verify the model appears in `ollama list` and its files live under `D:\`.                                                                  |
| `04-install-vscode-cline.ps1` | Detect VSCode CLI, install Cline extension via `code --install-extension`, write a config snippet pointing at local Ollama, print manual steps for any UI only configuration. |

### 7.2 Test Script Responsibilities

| Script                     | Responsibility                                                                                                        |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `test-ollama-health.ps1`   | GET `/api/tags` returns 200, GPU info shows CUDA active, target model is listed.                                      |
| `test-chat-completion.ps1` | POST a small prompt, assert a non empty response inside 10 seconds.                                                   |
| `test-tool-calling.ps1`    | POST a prompt with a sample tool definition, assert the model returns valid `tool_calls` JSON. Cline depends on this. |

### 7.3 Benchmark Script Responsibilities

| Script                     | Responsibility                                                                                                                                     |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `benchmark-throughput.ps1` | Five prompts, measure cold and warm prefill tokens per second and decode tokens per second. Write results to `benchmark-results\<timestamp>.json`. |
| `benchmark-context.ps1`    | Run prompts at 8K, 32K, 64K context. Record VRAM usage and time to first token at each size.                                                       |

### 7.4 Validation Script Responsibilities

| Script                      | Responsibility                                                                                                                                       |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `validate-coding-tasks.ps1` | For each fixture under `tests\fixtures\`, send the fixture prompt to Ollama, capture output, run the fixture's `verify.ps1`, aggregate PASS or FAIL. |
| `validate-cline-e2e.md`     | Manual checklist for end to end Cline behavior. Not automated because driving the VSCode UI reliably is not worth the setup cost for this project.   |

### 7.5 Orchestration

`scripts\run-all-install.ps1` invokes the four install scripts in order. Test, benchmark, and validation scripts are run individually because they serve different intents and run on different cadences.

## 8. Test Strategy

Four verification layers, each answering a different question.

### Layer 1, Functional Tests

**Question: Is the pipeline wired up?** Quality is irrelevant, only connectivity.

Located in `scripts\test\`. Runs in under one minute. Must pass before any other layer is meaningful.

### Layer 2, Performance Benchmarks

**Question: Is it fast enough to be usable inside an agent loop?**

Located in `scripts\benchmark\`. Acceptance: warm decode at or above 20 tokens per second on the chosen quantization, 32K context fits entirely on GPU.

### Layer 3, Quality Validation

**Question: Can it actually do my coding tasks?**

Four real fixtures under `tests\fixtures\`. Each fixture is a self contained mini project:

```
task-02-refactor\
    README.md           (task statement)
    input\              (starting code given to the model)
        messy.py
    prompt.txt          (exact prompt sent to the model)
    expected\           (reference solution, not strict match)
        refactored.py
    verify.ps1          (automated checks: syntax valid, tests pass)
```

The four fixtures are picked to span size and difficulty:

1. **task-01-fizzbuzz.** Baseline. If this fails, the setup itself is broken.
2. **task-02-refactor.** 80 line messy file, asked to clean while preserving behavior and passing existing tests. Exercises reading plus editing.
3. **task-03-bug-fix.** A failing test is provided, the model must diagnose and fix with minimal changes. Exercises diagnostic reasoning and edit discipline.
4. **task-04-from-spec.** A short specification (for example "build a CLI that reads a CSV and groups rows by date"), implemented from scratch.

`validate-coding-tasks.ps1` runs all fixtures and reports a PASS or FAIL count.

### Layer 4, End to End Agent Behavior

**Question: Does the full Cline plus Ollama experience work in practice?**

A short manual checklist in `validate-cline-e2e.md`. Five minutes to run. Covers: model detected by Cline, tool calls fire (not just text), diff approval flow works, terminal command execution works, multi turn editing works.

### 8.1 Success Criteria for the Whole Setup

Setup is considered complete when:

* Layer 1: all functional tests pass.
* Layer 2: warm decode at or above 20 tokens per second, 32K context VRAM resident.
* Layer 3: at least 3 of 4 fixtures pass.
* Layer 4: manual checklist all checked.

## 9. Open Decisions, Resolved On 2026-05-26 Acceptance Run

All three deferred decisions were resolved during the live acceptance run on the user's RTX 4080:

* **`num_ctx` value.** 32K is the sweet spot for agent use. Measured time to first token: 8K = 2.97 s, 32K = 10.8 s, 64K = 29.57 s. 32K fits comfortably (VRAM 15.5 GB, peak 15.7 GB). 64K technically completes but the 30 s first-token wait is too painful for an agent loop. Use Cline default (likely Ollama default 8K or 32K depending on Modelfile).
* **GPU layer offload.** Ollama autodetect was correct. No manual pinning needed. Cold load 14.16 GB VRAM, full GPU residency confirmed by `/api/ps` (`size_vram > 0`).
* **Parallel slots.** Left at default (off) for single user. Not revisited.

Measured throughput, qwen3-coder:30b, Q4_K_M, RTX 4080 16 GB:

| Metric | Value |
|---|---|
| Cold load wall time | 23.8 s (model into VRAM) plus 10.56 s for first prompt |
| Warm prefill avg | 279 tok/s |
| Warm decode avg | 55.5 tok/s |
| VRAM resident | 14.16 GB |

## 10. Risks and Mitigations, with Acceptance Outcomes

| Risk | Predicted | Materialized? | Outcome and notes |
|---|---|---|---|
| Qwen3-Coder-30B-A3B does not fit in 16 GB at desired context size | Medium | Partial | 32K fits cleanly (15.5 GB). 64K technically completes but TTFT is 29.6 s, impractical for agent use. Recommendation: pick 32K, do not try 64K in production. |
| Cline's Ollama integration does not parse tool calls correctly for Qwen3-Coder | Low | No | `test-tool-calling.ps1` confirmed `tool_calls` field is returned correctly. Cline e2e walkthrough confirmed the file-create, terminal-execute, and edit flows all work. |
| Ollama Windows service does not honor OLLAMA_MODELS env var | Low | YES, much bigger than predicted | The Ollama tray app inherits its environment from login time, not from runtime registry changes. PowerShell's `Start-Process` did not propagate runtime env changes either. The fix was non-trivial: kill the tray, launch `ollama serve` ourselves via .NET `ProcessStartInfo` with an explicit `Environment` dictionary, and for reboot persistence set `OLLAMA_MODELS` in Machine scope (admin once). Also discovered that `OLLAMA_MODELS` points at the models directory itself (containing `blobs\` and `manifests\` directly), NOT a parent containing `models\`. See [docs/superpowers/notes/2026-05-26-debug-lessons.md](../notes/2026-05-26-debug-lessons.md). |
| Throughput below 20 tokens per second despite the model fitting | Medium | No | Measured warm decode 55.5 tok/s, comfortably above threshold. CUDA detection worked first try, no manual layer pinning needed. |
| Validator parser does not capture model output format | Not anticipated | YES | 30B omitted triple-backtick fences when told "no prose outside code blocks" (took the instruction literally, no fences = no extra text). Required (a) strengthening system prompt to mandate fences explicitly, (b) adding a raw-mode fallback parser that detects `# filename.ext\n<code>` sections without fences, and (c) including input/ file contents in the prompt so refactor and bug-fix tasks have context. After fixes, 4/4 fixtures pass. |
| Small models (1.5B class) cannot do OpenAI-standard tool calling | Not anticipated | YES | `qwen2.5-coder:1.5b` (used as a fast iteration target) embeds the call as JSON inside `message.content` rather than using the `tool_calls` field. Cline cannot parse this fallback. Test scripts now document that tool calling needs a 7B+ model. |

