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

## MCP Integration

Pair SkillsFS with the `agfs-mcp` server to let Claude/Cursor auto-discover skills:

1. Mount your skills under `/skills/...` (or configure another base path).
2. 安装/更新 MCP 服务器：
   ```bash
   cd /Users/vajra/Clang/agfs/agfs-mcp
   uv pip install -e .
   ```
3. 手动启动（调试）：
   ```bash
   AGFS_SERVER_URL=http://localhost:8080 \
   SKILLS_BASE_PATH=/skills \
   uv run agfs-mcp
   ```
4. 把 MCP server 注册到 Claude Code：
   ```bash
   claude mcp add --transport stdio skillsfs \
     --env AGFS_SERVER_URL=http://localhost:8080 \
     --env SKILLS_BASE_PATH=/skills \
     -- /bin/sh -c 'cd /Users/vajra/Clang/agfs/agfs-mcp && uv run agfs-mcp'
   ```
   （若 `claude mcp add` 不支持 `--from/--project`，务必记得加上 `--` 后的 `/bin/sh -c ...`）
5. 需要自动化时，可直接运行：
   ```bash
   ./scripts/setup_skillsfs_mcp.sh
   ```
   该脚本会：进入 `agfs-mcp`、`uv pip install -e .`，并尝试用上面的命令把 `skillsfs` MCP server 注册到 Claude Code。

之后在 Claude Code/Claude Desktop 里就能看到 `skill_<name>` 工具。模型调用时，MCP 服务器会把 `params` 写入 `/execute`、读取 `/result` 与 `/status`，实现自然语言触发 SkillsFS。
