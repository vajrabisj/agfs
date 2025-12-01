# SimpCurlFS (C Plugin)

A minimal AGFS filesystem plugin, implemented in C, that turns the Perplexity
Search API into a virtual directory. It is inspired by the `simpcurl.c`
utility inside `~/Clang/perplex-page/` and reuses the same `yyjson`
implementation plus libcurl.

## Features

- `write /web/request` with JSON `{ "query": "...", "max_results": 3 }` to
  trigger a Perplexity search.
- `cat /web/response.json` returns the raw JSON from the API.
- `cat /web/response.txt` returns a human-readable summary (top N results).
- Configurable via plugin config JSON or environment variables.

## Files

```
/request        # write-only (JSON payload)
/response.json  # last raw response
/response.txt   # formatted summary
```

## Building

This folder contains `simpcurlfs.c`, `yyjson.c`, `yyjson.h`, and a Makefile.
To build the dynamic library (macOS example):

```bash
cd agfs-shell/simpcurlfs
make            # produces libsimpcurlfs.dylib
```

Requirements:
- `gcc` or `clang`
- `libcurl` development headers/libraries inside the build environment

If you need to cross-build inside the AGFS Docker image, install libcurl
first, e.g. `apk add curl-dev` (Alpine) or `apt-get install libcurl4-openssl-dev` (Debian/Ubuntu).

## Deploying into agfs-server

1. Copy the folder into `agfs-server/examples/simpcurlfs` (or run `make install`
   to place the compiled library under `agfs-server/plugins`).
2. Build the shared library inside the container or host.
3. Ensure the resulting `.so/.dylib` is available under
   `/app/plugins/libsimpcurlfs.*` inside the container.
4. Enable external plugins (if not already) in `config.yaml`:
   ```yaml
   external_plugins:
     enabled: true
     plugin_dir: "./plugins"
     auto_load: true
   ```
5. Mount the plugin via API or by adding to `plugin_paths`:
   ```yaml
   external_plugins:
     plugin_paths:
       - "./plugins/libsimpcurlfs.dylib"
   ```
6. Mount the filesystem using the plugin name `simpcurlfs`:
   ```yaml
   plugins:
     simpcurlfs:
       enabled: true
       path: /web
       config:
         api_key_env: "PERPLEXITY_API_KEY"
         default_max_results: 3
   ```
   > Note: `api_key` can also be passed explicitly in config.

At runtime you can also POST to `/api/v1/plugins/load` with the
library path. Once loaded, `ls /web` will show
`request`, `response.json`, `response.txt`.

## Request Format

```
{
  "query": "search text",
  "max_results": 3
}
```

- `query` (string) is required.
- `max_results` (int) overrides the default (falls back to
  `default_max_results` in config).
- If you send plain text instead of JSON, the whole payload is treated as
  the query string.

## Environment / Config

- `api_key`: string containing the Perplexity API key.
- `api_key_env`: name of an environment variable that stores the key
  (default `PERPLEXITY_API_KEY`). If both `api_key` and `api_key_env` are
  missing, the plugin tries to read `PERPLEXITY_API_KEY` directly.
- `endpoint`: optional override of the Perplexity endpoint.
- `default_max_results`: fallback integer (default 3).

## Example Workflow

1. Start AGFS server with the plugin mounted at `/web`.
2. Enqueue a request:
   ```bash
   echo '{"query":"llm agents in 2025","max_results":2}' > /web/request
   ```
3. Read results:
   ```bash
   cat /web/response.txt
   cat /web/response.json
   ```

This makes `simpcurl` functionality available to every AGFS client via the
standard file interface.
