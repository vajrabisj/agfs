# Tcl Agent Loop Reference

This document summarizes the current Tcl-based agent workflow so you can re-enable or extend it later without digging through history.

## Overview

- `examples/agent_task_loop.tcl` implements a QueueFS-driven agent loop entirely in Tcl.
- It watches a dequeue file (default `/queuefs/agent_tcl/dequeue`), processes each JSON task, and stores the result JSON under `/local/<results>/<agent>/<task-id>.json`.
- Local LLM calls are routed to Ollama (`http://localhost:11434/api/generate`) using `http::geturl`; the default model is `qwen3:4b` with a 120 s timeout.
- Tasks can be **single-step** (just `task`/`text`/`prompt`) or **multi-step** via a `steps` array. Each step records `{id,prompt,output}` in the result.

## Running the Agent

```bash
tclsh examples/agent_task_loop.tcl \
    -queue /queuefs/agent_tcl \
    -results /local/agent_results \
    -name tcl-agent \
    -model qwen3:4b \
    -ollama_url http://localhost:11434 \
    -ollama_timeout 120000
```

Flags:
- `-queue`: QueueFS path to monitor (must exist or be creatable).
- `-results`: Base directory to store results (default `/local/agent_results`).
- `-model`: Ollama model (default `qwen3:4b`).
- `-ollama_url`: Base URL for Ollama server.
- `-ollama_timeout`: Request timeout in milliseconds (default 120 000 ms).
- `-interval`: Polling interval in seconds (default 3 s).
- `-name`: Agent identifier; results go into `/local/.../<name>/`.

## Sample Tasks

### Single-Step
```
agfs:/> cat <<'EOF' > /queuefs/agent_tcl/enqueue
{"task":"summarize","text":"Write a haiku about Tcl agents"}
EOF
```

### Multi-Step
```
agfs:/> cat <<'EOF' > /queuefs/agent_tcl/enqueue
{
  "task": "research",
  "text": "Explain why Tcl is useful for AGFS agents",
  "steps": [
    {"id": "outline", "prompt": "List 3 angles to cover."},
    {"id": "analysis", "prompt": "Expand each angle (2 sentences)."},
    {"id": "summary", "prompt": "Produce a concise final summary."}
  ]
}
EOF
```

## Result Format

Each task produces `/local/<results>/<agent>/<task-id>.json` with:

```json
{
  "agent": "tcl-agent",
  "taskId": "<UUID>",
  "taskType": "research",
  "receivedAt": "2025-11-30T15:36:46+0800",
  "input": "...",
  "summary": "...",
  "status": "completed",
  "steps": [
    {"id": "outline", "prompt": "...", "output": "..."},
    {"id": "analysis", "prompt": "...", "output": "..."},
    {"id": "summary", "prompt": "...", "output": "..."}
  ]
}
```

## Key Implementation Notes

- `dict_get_default` helper avoids missing-key errors when parsing task payloads.
- `json_bool` converts Tcl truthy values to the JSON literal `true`/`false`, solving the earlier `json::write boolean` ambiguity.
- `call_ollama` handles HTTP status errors and malformed JSON; failures fall back to a simple echo summary so tasks never disappear silently.
- `ensure_remote_dir` ensures both queue and result directories exist (even when intermediate parents are missing).
- `normalize_steps` guards against malformed `steps` entries; empty or non-dict entries are skipped gracefully.

## Troubleshooting

- **No result file?** Ensure the agent is running, QueueFS path exists, and Ollama is reachable. Tail the agent logs for `Dequeued task …` lines.
- **LLM invocation failed:** Check Ollama logs and confirm the model name matches `ollama list`. Increase `-ollama_timeout` for slower prompts.
- **Malformed JSON error:** Validate your task payload with `jq` or similar before enqueueing.

## Next Ideas

- Add retry logic or exponential backoff around Ollama failures.
- Allow setting `system` prompts or temperature via task payload fields.
- Push intermediate step outputs back to QueueFS for streaming feedback.
