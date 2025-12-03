# SummaryFS (C Plugin)

A simple AGFS filesystem plugin that turns local Ollama (default model
`qwen3:4b`) into a file-based summary tool. It mirrors the workflow of
simpcurlfs: write to `/summary/request`, then read `/summary/response.*`.

## Files

- `/summary/request` – write JSON `{ "text": "...", "format": "markdown" }`
- `/summary/response.json` – raw Ollama JSON response
- `/summary/response.txt` – plain-text summary extracted from `response`

## Configuration keys

- `model` (default `qwen3:4b`)
- `ollama_url` (default `http://localhost:11434/api/generate`)
- `timeout_ms` (default `120000`)
- `system_prompt` (optional custom instructions)

## Building

```bash
cd summaryfs
make            # produces libsummaryfs.(so|dylib)
```

Requires `gcc/clang`, `libcurl`, and the bundled `yyjson` source.

## Deploying

1. Copy the compiled library into `/app/plugins` inside the AGFS container
   (or use `make install` if this repo sits next to `agfs-server`).
2. Ensure `external_plugins` is enabled in `config.yaml`:
   ```yaml
   external_plugins:
     enabled: true
     plugin_dir: "./plugins"
     auto_load: true
   ```
3. Load and mount the plugin:
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
                  "ollama_url": "http://localhost:11434",
                  "model": "qwen3:4b",
                  "timeout_ms": 120000
              }
            }'
   ```

After挂载成功，`ls /summary` 会出现 `request`, `response.json`, `response.txt`。

## Usage

1. 写入请求：
   ```bash
   echo '{"text":"Summarize AGFS architecture","format":"bullet list"}' > /summary/request
   ```
2. 读取结果：
   ```bash
   cat /summary/response.txt
   cat /summary/response.json
   ```

将 `/summary/response.*` 复制到你自己的流水线目录，即可供其他 Agent 继续处理。
