# SkillsFS MVP

SkillsFS is a new AGFS plugin that turns a single skill into a tiny filesystem.
It is the first step toward the Skills-FS vision: write parameters into a skill,
read the result lazily, and inspect `status`/`log` for observability.

## Build

```bash
cd skillsfs
make                 # produces libskillsfs.so
```

Copy the `.so` to your AGFS server (e.g. `/app/plugins/libskillsfs.so`).

## Mount

You can mount it via config or CLI. Example CLI:

```bash
agfs mount skillsfs /skills/demo \
    skill_name=demo-research \
    instructions="Echo payload with timestamps" \
    metadata="owner=vajra,env=dev" \
    cache_ttl_seconds=600
```

Mounting exposes these files under `/skills/demo`:

| Path          | Description                                                        |
|---------------|--------------------------------------------------------------------|
| `metadata`    | Free-form metadata (read/write).                                   |
| `instructions`| Human instructions (read/write).                                   |
| `execute`     | Write JSON or text payloads here to queue an execution.            |
| `result`      | Read to trigger lazy execution (first read runs, later reads hit cache). |
| `status`      | JSON blob with state, cache info, last duration.                   |
| `log`         | Append-only log for observability.                                 |

## Usage Example

```bash
# queue new run
echo '{"query":"latest Tcl agent news","top_k":3}' > /skills/demo/execute

# first read runs the skill
cat /skills/demo/result

# repeated reads within cache_ttl hit the cached result
cat /skills/demo/result

# inspect status/log
cat /skills/demo/status | jq .
tail -f /skills/demo/log
```

This MVP simply echoes the payload with timestamps, but it already demonstrates
the `execute → result` lazy-evaluation loop, TTL caching, and observability hooks.
Future iterations will plug in real instructions, dependency graphs, and templates.
