# SimpCurlFS Integration Guide

This guide captures the full workflow for running AGFS in Docker with the `simpcurlfs` plugin (Perplexity Search interface), including environment setup, plugin loading, mounting, and shell interaction.

---

## 1. Preparing the plugin on the host

1. Build the plugin locally (see `simpcurlfs/README.md` for details). The output is `libsimpcurlfs.so` (Linux) or `libsimpcurlfs.dylib` (macOS).
2. Copy the compiled library to a host directory you can volume-mount into the container, e.g.:
   ```bash
   mkdir -p /Users/vajra/agfs/plugins
   cp libsimpcurlfs.so /Users/vajra/agfs/plugins/
   cp libsimpcurlfs.dylib /Users/vajra/agfs/plugins/   # optional macOS build
   ```

---

## 2. Running AGFS in Docker

Run AGFS with:
```bash
docker run --rm \
  --name agfs-server \
  -p 8080:8080 \
  -e PERPLEXITY_API_KEY="$PERPLEXITY_API_KEY" \
  -v /Users/vajra/agfs/plugins:/app/plugins \
  c4pt0r/agfs-server:latest
```

- `-e PERPLEXITY_API_KEY=...` ensures the plugin can reach Perplexity.
- `-v /Users/.../plugins:/app/plugins` makes your plugin libraries available inside the container.
- If you have a custom `config.yaml`, mount it similarly: `-v /path/to/config.yaml:/app/config.yaml`.

> If you want a persistent container, drop `--rm` and use `docker stop/start agfs-server`.

---

## 3. Enabling external plugins in config.yaml

Inside the container (or your custom `config.yaml`), ensure:
```yaml
external_plugins:
  enabled: true
  plugin_dir: "./plugins"
  auto_load: true
```
This allows AGFS to discover `libsimpcurlfs.*` under `/app/plugins`.

---

## 4. Loading the plugin

If `auto_load` is true and the library sits in `plugin_dir`, AGFS may auto-load it on startup. Otherwise, load it manually via REST:

```bash
curl -X POST http://localhost:8080/api/v1/plugins/load \
  -H "Content-Type: application/json" \
  -d '{"library_path":"/app/plugins/libsimpcurlfs.so"}'
```

You should see a success response (e.g. `{"status":"ok"}`).

---

## 5. Mounting the filesystem

### Via REST
```bash
curl -X POST http://localhost:8080/api/v1/mounts \
  -H "Content-Type: application/json" \
  -d '{
        "path": "/web",
        "fstype": "simpcurlfs",
        "config": {
          "api_key_env": "PERPLEXITY_API_KEY",
          "default_max_results": 3
        }
      }'
```

### Via agfs-shell
If you prefer CLI:
```
agfs:/> mount simpcurlfs /web api_key_env=PERPLEXITY_API_KEY default_max_results=3
```

Either method exposes `/web` with files `request`, `response.json`, `response.txt`.

---

## 6. Using the plugin from agfs-shell

1. Verify the mount:
   ```
   agfs:/> ls /web
   request
   response.json
   response.txt
   ```
2. Submit a query:
   ```
   agfs:/> echo '{"query":"llm agents in 2025","max_results":2}' > /web/request
   ```
   (The plugin calls Perplexity; ensure `PERPLEXITY_API_KEY` is set or pass `api_key=...` in the mount config.)
3. Read results:
   ```
   agfs:/> cat /web/response.txt
   agfs:/> cat /web/response.json
   ```

If no API key is found, the plugin prints `PERPLEXITY_API_KEY is not set...`. Fix by restarting the container with `-e` or remounting `/web` with `api_key=YOUR_KEY`.

---

## 7. Tips & Troubleshooting

- **Keeping plugin files**: If you install the plugin inside a temporary container, copy the `.so/.dylib` back to the host (`docker cp agfs-server:/app/plugins/... /host/path`) so you can mount it into new containers.
- **Mount not found**: `ls /web` returning “not found” means the plugin wasn’t loaded or mounted. Re-run the load/mount steps.
- **Multiple containers**: Only one container named `agfs-server` can run at a	time. Stop existing ones (`docker stop agfs-server`) before launching a new instance.
- **Persisting agent state**: If you need your configuration baked in, consider `docker commit agfs-server agfs-server-simpcurl:latest` and run from that image.

This setup makes `/web/request` a shared “Perplexity tool” that any AGFS client (Tcl agent, Python script, agfs-shell) can use by writing JSON to the file. The plugin handles the API call, stores the raw response and a readable summary, and keeps the workflow entirely within AGFS’s “everything is a file” model.

---

## 8. Updating the Git Repository

If your local changes need to be pushed back to the upstream repo (e.g., `github.com/vajrabisj/agfs`), use either HTTPS+PAT or SSH. Typical workflow:

1. **Set Git identity (if needed)**
   ```bash
   git config --global user.name "Your Name"
   git config --global user.email "you@example.com"
   ```
2. **(HTTPS) Generate a Personal Access Token**
   - GitHub → Settings → Developer settings → Personal access tokens.
   - Create a token with `repo` scope.
   - Next time `git push` prompts for username/password, enter your GitHub username and use the token as the password.
3. **(SSH) Add a key**
   ```bash
   ssh-keygen -t ed25519 -C "you@example.com"
   cat ~/.ssh/id_ed25519.pub   # copy into GitHub Settings → SSH keys
   git remote set-url origin git@github.com:vajrabisj/agfs.git
   ssh -T git@github.com       # test connectivity
   ```
4. **Push changes**
   ```bash
   git add .
   git commit -m "Describe your change"
   git push origin <branch>
   ```

If authentication fails with `Invalid username or token`, ensure the PAT/SSH key above is configured; GitHub no longer accepts account passwords for Git operations.

---

## 9. Wiring the Plugin into a Multi-Agent Pipeline

Once `/web` is mounted, you can treat `simpcurlfs` as just another tool in a multi-step workflow:

1. **Trigger search** (any agent)
   ```bash
   agfs:/> echo '{"query":"llm agents in 2025","max_results":2}' > /web/request
   ```
   This immediately calls Perplexity; the latest results are stored at:
   - `/web/response.json` (raw JSON)
   - `/web/response.txt` (formatted summary)

2. **Persist results for downstream agents**
   `/web/response.*` are overwritten each time a new request runs. After reading them, copy the data into your task directory (e.g., under `/local/pipeline/<task_id>/`):
   ```tcl
   set task_dir "/local/pipeline/$task_id"
   file mkdir $task_dir
   set raw [$client cat "/web/response.json"]
   set summary [$client cat "/web/response.txt"]
   $client write "$task_dir/web.json" $raw
   $client write "$task_dir/web.txt" $summary
   ```
   Include these paths in the payload you enqueue for the next agent.

3. **Pass work to the next queue**
   Agents typically coordinate via QueueFS:
   ```tcl
   set payload [json::write object \
       id [json::write string $task_id] \
       web_summary_path [json::write string "$task_dir/web.txt"]]
   $client write "/queuefs/step2/enqueue" $payload
   ```
   The next agent reads `/queuefs/step2/dequeue`, fetches `web_summary_path`, and continues processing (e.g., generating a final report or inserting data into SQLFS).

4. **General flow for multi-step agents**
   - **Step 1 agent**: listens to `/queuefs/step1/dequeue`, invokes `/web/request`, writes `/local/pipeline/<id>/web.*`, enqueues the next step.
   - **Step 2 agent**: listens to `/queuefs/step2/dequeue`, reads `/local/pipeline/<id>/web.*`, performs its logic, enqueues `/queuefs/step3`, etc.
   - **Shared storage** (LocalFS/S3FS/SQLFS/KVFS) holds intermediate files/results; **QueueFS** is only for passing task metadata (`id`, `paths`, `status`).

This approach keeps each agent simple (it only “watches” its queue), while AGFS provides all required tools—simpcurlfs for web search, LocalFS/S3FS for storing outputs, SQLFS/KVFS for structured state, etc. Copying `/web/response.*` into your own directory ensures the data remains available even after the next search overwrites the plugin’s internal buffer.

### Example End-to-End Flow

1. **Broadcast task to multiple agents** (from `agfs-sdk/tcl`):
   ```bash
   tclsh examples/broadcast_tasks.tcl \
       -agents agent1,agent2 \
       -queue_prefix /queuefs/agent \
       -task "Research recent progress on Tcl agents" \
       -results_root /local/pipeline
   ```

2. **Start agent loops** (each watches its queue):
   ```bash
   tclsh examples/agent_task_loop.tcl \
       -name agent1 \
       -queue /queuefs/agent1 \
       -results /local/pipeline \
       -model qwen3:4b

   tclsh examples/agent_task_loop.tcl \
       -name agent2 \
       -queue /queuefs/agent2 \
       -results /local/pipeline \
       -model qwen3:4b
   ```
   每个 Agent 将 simpcurlfs 的结果复制到 `/local/pipeline/<root_task>/<agent>/web.{json,txt}`，待后续使用。

3. **汇总下一阶段**（可选）  
   如果需要新的 Agent 合并两个结果，可以手动 enqueue 到 `/queuefs/agent3`：
   ```bash
   cat <<'EOF' > /queuefs/agent3/enqueue
   {
     "task_id": "task-xxxx-summary",
     "parent_task": "task-xxxx",
     "description": "Combine agent1 + agent2 results into a final report.",
     "input_files": [
       "/local/pipeline/task-xxxx/agent1/web.txt",
       "/local/pipeline/task-xxxx/agent2/web.txt"
     ],
     "result_dir": "/local/pipeline/task-xxxx/final"
   }
   EOF
   ```
   再启动 `agent_task_loop.tcl -queue /queuefs/agent3 ...` 即可继续处理。

---

## 10. SummaryFS（OpenAI 摘要插件）

`summaryfs` 现已改为直接调用 OpenAI Chat Completions（默认 `gpt-4o-mini`），不再依赖本地 Ollama。你只需要提供 `OPENAI_API_KEY` 即可。

### 编译

```bash
cd summaryfs
make    # 生成 libsummaryfs.(so|dylib)
```

### 放入容器 / plugins 目录

```bash
mkdir -p /Users/vajra/agfs/plugins
cp libsummaryfs.* /Users/vajra/agfs/plugins/

docker run --rm \
  --name agfs-server \
  -p 8080:8080 \
  -e PERPLEXITY_API_KEY="$PERPLEXITY_API_KEY" \
  -e OPENAI_API_KEY="$OPENAI_API_KEY" \
  -v /Users/vajra/agfs/plugins:/app/plugins \
  c4pt0r/agfs-server:latest
```

### 加载与挂载

```bash
curl -X POST http://localhost:8080/api/v1/plugins/load \
  -H "Content-Type: application/json" \
  -d '{"library_path":"/app/plugins/libsummaryfs.so"}'

curl -X POST http://localhost:8080/api/v1/mounts \
  -H "Content-Type: application/json" \
  -d '{
        "path": "/summary",
        "fstype": "summaryfs",
        "config": {
          "openai_model": "gpt-4o-mini",
          "openai_endpoint": "https://api.openai.com/v1/chat/completions",
          "openai_api_key_env": "OPENAI_API_KEY",
          "timeout_ms": 120000,
          "temperature": 0.2
        }
      }'
```

或在 agfs-shell 里：

```
agfs:/> mount summaryfs /summary openai_model=gpt-4o-mini openai_api_key_env=OPENAI_API_KEY
```

### 使用

```
agfs:/> echo '{"text":"Summarize AGFS architecture","format":"bullet list"}' > /summary/request
agfs:/> echo 'Just summarize this note' > /summary/request
agfs:/> cat /summary/response.txt
agfs:/> cat /summary/response.json
```

### 与 simpcurlfs 配合

1. AgentA 通过 `/web/request` 获取搜索内容，写到 `/local/.../web.txt`。
2. AgentB 读取该文件，写入 `/summary/request`，即可由 OpenAI 生成统一摘要。
3. AgentB 将 `/summary/response.txt` 保存到自己的结果目录，再进入下游流程。

所有 Agent 都可以通过 `/summary` 共享这一 OpenAI 摘要工具，无需各自集成 OpenAI SDK。

---

## 11. 自定义 Docker 镜像（内置两个插件）

为了避免每次复制/编译插件，可直接在仓库里构建一个新的 AGFS 镜像。`agfs-shell/docker-image/Dockerfile` 已经包含：
- 基于 `c4pt0r/agfs-server:latest`
- 安装 build 依赖，编译 `simpcurlfs`/`summaryfs`
- 将生成的 `.so` 复制到 `/app/plugins`
- 拷贝预配置的 `config.yaml`（自动启用 `/web` 和 `/summary`）

### 构建

在 `agfs-shell` 目录执行：
```bash
docker build -f docker-image/Dockerfile -t agfs-server-with-plugins .
```

### 运行

```bash
docker run --rm \
  --name agfs-server \
  -p 8080:8080 \
  -e PERPLEXITY_API_KEY="$PERPLEXITY_API_KEY" \
  -e OPENAI_API_KEY="$OPENAI_API_KEY" \
  agfs-server-with-plugins:latest
```

容器启动后 `/web` 和 `/summary` 已自动挂载，无需再手动 `load`/`mount`。只要在 `docker run` 时传入正确的环境变量即可。
