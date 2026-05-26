# TODO, future work

Items pulled from the 2026-05-26 research report (see notes for full context). These are
"if you want to push past the current setup" ideas. Ranked roughly by effort vs payoff.

Not committing to any of these. Tracked here so they are not forgotten.

---

## Sıçrama (jumping ahead) candidates

- [ ] **Switch to Unsloth UD-Q4_K_XL quant of Qwen3-Coder-30B-A3B.** Same VRAM footprint as current Q4_K_M (~17.7 GB vs 17.3 GB), but dynamic quantization scores 60.9% on Aider Polyglot vs 61.8% for bf16 (basically full-precision quality). Tool-calling-aware imatrix calibration. Source: https://huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF. Verify file dates on HF before downloading (calibration set was refreshed for tool calling).

- [ ] **Replace Ollama with llama.cpp server directly.** Ollama bundles a llama.cpp build that lags upstream by 2 to 4 weeks. Building llama-server yourself with CUDA gets newer kernels and finer control of `--flash-attn`, `--cache-type-k q8_0`, `--cache-type-v q8_0`, `--ubatch-size`. Expected 5-15% more decode tok/s and meaningfully faster prefill. Trade-off: lose Ollama's model management. Command sketch:
  ```
  llama-server -m qwen3-coder.gguf -ngl 99 --flash-attn --ctx-size 65536 \
    --cache-type-k q8_0 --cache-type-v q8_0 --port 11434
  ```

- [ ] **WSL2 + vLLM for max throughput.** Recent benchmark: vLLM 208 tok/s vs Ollama 144 tok/s on the same MoE class model. Only on Linux/WSL though, and GGUF support is second-class (AWQ or FP8 weights preferred). Setup is hours not minutes. Worth it if the model stays loaded all day. Source: https://allenkuo.medium.com/qwen3-6-35b-a3b-on-desktop-blackwell-the-first-time-vllm-beats-ollama-on-decode-f139f445f926

- [ ] **Try Roo Code as a Cline alternative.** Cline fork with model-per-mode routing: send Architect/planning to a "thinker" model, send Code to Qwen3-Coder. Also has Architect/Code/Debug/Ask/Orchestrator modes and tighter command allowlist. Same Ollama backend, 15 minutes to try. Source: https://www.qodo.ai/blog/roo-code-vs-cline/

- [ ] **Add Context7 MCP server to Cline.** Fetches current, version-specific library docs into context every turn. Fixes Qwen's stale-training-data errors on fast-moving libraries. Combine with the official Filesystem and Git MCP servers as a starter pack. Each MCP server burns 2-5K tokens of schema per request though, so keep the set lean.

- [ ] **Add Continue.dev alongside Cline for repo RAG.** Cline does not have a repo embedder. Many power users run Cline for agentic tasks + Continue.dev for chat, autocomplete, and RAG over the codebase, sharing the same Ollama backend. Continue's embedding indexer + reranker can use local embeddings like `nomic-embed-text` via Ollama. Source: https://docs.continue.dev/guides/custom-code-rag

## Hardware upgrade path

- [ ] **24 GB GPU.** The 16 GB ceiling is the binding constraint for everything in this setup. Options:
    - Used RTX 3090 (~$700-900): comfortably runs Q6_K + 64K context
    - RTX 4090: Qwen3-Coder-30B-A3B at 73-87 tok/s decode
    - RTX 5090 (32 GB): opens Q8_0 + room for a draft model

## Speculative wait list

- [ ] **Qwen3-Coder-Next-80B-A3B.** Released Feb 2026. Reports SWE-bench Verified >70% with SWE-Agent scaffold. 80B total weights do not fit in 16 GB even at Q2, so this is a "wait for 24 GB GPU" model.
- [ ] **GLM-4.5-Air-106B-A12B.** Reports of stronger agent and tool-use behavior than Qwen3-Coder. Total weights are large but Q3/Q4 quants exist that might fit. Worth a bake-off when ready.

## Things to verify on this machine

- [ ] **Does Cline override Modelfile PARAMETER values?** The `qwen3-coder-tuned` Modelfile sets temperature 0.7, top_p 0.8, top_k 20, min_p 0.01, repeat_penalty 1.05. To check: set `temperature 0.01` in the Modelfile, send the same prompt to Cline twice, check determinism. If outputs differ, Cline is overriding and the params must be set in Cline UI instead.

- [ ] **Re-benchmark with FA + KV q8_0 active.** Compare warm decode tok/s and 32K TTFT against the 2026-05-26 baseline (55.5 tok/s and 10.8 s). Expect 1-1.5 GB freed VRAM and a small decode bump.

- [ ] **Cold-boot persistence test.** After a reboot, does the tray app auto-start with OLLAMA_MODELS / OLLAMA_FLASH_ATTENTION / OLLAMA_KV_CACHE_TYPE intact? Requires Machine scope to be set (admin one-shot). Easy way to check: reboot, run `test-ollama-health.ps1`, confirm the model lives on D:\.

## Explicitly out of scope

- Speculative decoding for Qwen3-Coder-30B-A3B. Independently benchmarked dead-end for this exact MoE class on Ampere/Ada. Save it for dense models. Source: https://github.com/thc1006/qwen3.6-speculative-decoding-rtx3090
- Q8_0 with CPU offload. Decode drops to single digits, quality bump not worth the latency.
- num_ctx 262144 with YaRN. KV cache pre-allocation pushes model weights to RAM. Use the actual working size (32K-65K).
- Long roleplay/persona system prompts. Hurt local models, eat context, do not change behavior much.
