# Cline End to End Manual Validation

Use this after `validate-coding-tasks.ps1` passes. Five minutes. Run quarterly or after any Ollama or Cline upgrade.

## Setup

- [ ] Ollama API responds with the target model listed:
  ```powershell
  (Invoke-RestMethod http://localhost:11434/api/tags).models.name
  ```
  Output should include `qwen3-coder:30b`.

- [ ] VSCode is open in a **scratch folder**, not this repo. The agent should not be testing against its own source.

## Walkthrough

- [ ] 1. Open the Cline panel from the activity bar.
- [ ] 2. Provider is set to **Ollama**, Base URL is `http://localhost:11434`, Model is `qwen3-coder:30b`. Save if any of these had to be set.
- [ ] 3. New chat, type: `Create a hello.py that prints "hi from local llm"`. Send.
- [ ] 4. Cline proposes a **tool call to create the file** (diff or file-create card), NOT plain text in chat.
- [ ] 5. Approve the file create. Confirm `hello.py` exists in the workspace.
- [ ] 6. In the same chat, type: `Now run it and show me the output`. Send.
- [ ] 7. Cline proposes a **terminal command** (`python hello.py` or similar). Approve it.
- [ ] 8. Terminal output contains `hi from local llm`.
- [ ] 9. In the same chat, type: `Change the message to "hi from <your-name>"`. Send.
- [ ] 10. Cline **reads the existing file** and proposes an edit (full rewrite is also acceptable). Approve.
- [ ] 11. Confirm `hello.py` now contains the new message.
- [ ] 12. Multi-turn check: chat panel shows the full conversation history, not just the latest turn.

## Pass criteria

All twelve boxes checked. Most common failure: step 4 (Cline gets text instead of a tool call) means tool calling is not negotiating. Re-run:
```powershell
pwsh -File scripts\test\test-tool-calling.ps1
```
and inspect Cline settings for any "force JSON" or "compatibility mode" toggle.
