# SummaryFS (C Plugin)

SummaryFS exposes OpenAI Chat Completion as a file-based summarizer for AGFS.
Write to `/summary/request`, then read `/summary/response.*` just像使用其他
虚拟文件系统一样。

## Files
- `/summary/request` – 支持 JSON `{ "text": "...", "format": "markdown" }`
  或直接写纯文本。
- `/summary/response.json` – OpenAI 的原始响应。
- `/summary/response.txt` – 解析后的纯文本摘要。

## Configuration keys
- `openai_model` (默认 `gpt-4o-mini`)
- `openai_endpoint` (默认 `https://api.openai.com/v1/chat/completions`)
- `openai_api_key` / `openai_api_key_env` (若都为空则 fallback 到环境变量 `OPENAI_API_KEY`)
- `timeout_ms` (默认 `120000`)
- `temperature` (默认 `0.2`)
- `system_prompt` (可选)

## Building
```bash
cd summaryfs
make            # produces libsummaryfs.(so|dylib)
```
需要 gcc/clang、libcurl、yyjson。

## Deploying
1. 将生成的 `.so/.dylib` 复制到容器 `/app/plugins`（或在宿主挂载该目录）。
2. `config.yaml` 开启 external_plugins：
   ```yaml
   external_plugins:
     enabled: true
     plugin_dir: "./plugins"
     auto_load: true
   ```
3. 加载 + 挂载：
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

## Usage
```bash
agfs:/> echo '{"text":"Summarize AGFS architecture","format":"bullet list"}' > /summary/request
agfs:/> echo 'Or just plain text' > /summary/request
agfs:/> cat /summary/response.txt
agfs:/> cat /summary/response.json
```

把 `/summary/response.*` 拷贝到流水线目录即可供其他 Agent 使用。
