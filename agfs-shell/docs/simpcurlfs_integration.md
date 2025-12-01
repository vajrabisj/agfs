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
