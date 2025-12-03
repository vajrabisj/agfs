# SkillsFS (MVP)

SkillsFS exposes a single skill as a tiny filesystem. It demonstrates the
`execute → result` lazy-evaluation loop discussed in the Skills-FS proposal.

Paths:

- `/metadata` – free-form metadata string (read/write)
- `/instructions` – execution instructions (read/write)
- `/execute` – write parameters to trigger execution (JSON or plain text)
- `/result` – read to get the latest result (first read after `/execute` runs the skill, later reads hit the cache)
- `/status` – JSON blob with state, timestamps, cache info
- `/log` – append-only execution log

Config (example):

```yaml
skillsfs:
  enabled: true
  path: /skills/demo
  config:
    skill_name: "demo-skill"
    instructions: "Echo back payload with timestamp"
    metadata: "owner=vajra"
    cache_ttl_seconds: 3600
```

This MVP keeps the execution logic inside the plugin and simply echoes the
latest payload. It already demonstrates:

- Writing `/execute` marks the skill as pending
- First read of `/result` runs the action and caches the output
- `/status` + `/log` capture progress and timing

Future iterations will add dependency graphs, template rendering, and richer
instruction processing.
