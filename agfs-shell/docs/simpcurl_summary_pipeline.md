# SimpcurlFS ➜ SummaryFS Workflow

记录当前可用的 5 个步骤，直接照做即可把 Perplexity 检索结果送入 OpenAI 汇总。

1. **启动预装插件源码的 AGFS 容器**

   ```bash
   docker run --rm --name agfs-server -p 8080:8080 \
     -e PERPLEXITY_API_KEY="$PERPLEXITY_API_KEY" \
     -e OPENAI_API_KEY="$OPENAI_API_KEY" \
     -v /Users/vajra/agfs/plugins:/data/plugins \
     -v /Users/vajra/agfs/data:/data \
     c4pt0r/agfs-server:latest
   ```

2. **在容器里编译 Linux 版本插件并复制到 /app/plugins**

   ```bash
   docker exec -it agfs-server sh -c '
     apk add --no-cache gcc musl-dev curl-dev ca-certificates make &&
     update-ca-certificates &&
     mkdir -p /app/plugins &&
     cd /data/plugins/simpcurlfs && make clean && make && cp libsimpcurlfs.so /app/plugins/ &&
     cd /data/plugins/summaryfs && make clean && make && cp libsummaryfs.so /app/plugins/
   '
   ```

3. **在 agfs-shell 中加载并挂载文件系统**

   ```text
   mount simpcurlfs /web api_key_env=PERPLEXITY_API_KEY default_max_results=3

   mount summaryfs /summary \
       api_provider=openai \
       model=gpt-4o-mini \
       timeout_ms=60000
   ```

4. **写入检索请求并等待 /web/response.txt**

   ```bash
   echo '{"query":"llm agents in 2025","max_results":2}' > /web/request
   # 通过 ls /web 或 cat /web/response.txt 验证输出
   ```

5. **通过 REST API 把检索结果推送给 SummaryFS，然后读取汇总**

   ```bash
   curl -s "http://localhost:8080/api/v1/files?path=/web/response.txt" \
     | curl -X PUT -H "Content-Type: text/plain" --data-binary @- \
         "http://localhost:8080/api/v1/files?path=/summary/request"

   curl -s "http://localhost:8080/api/v1/files?path=/summary/response.txt"
   ```

完成上述 5 步后，`/summary/response.txt` 会包含 OpenAI 生成的汇总结果，可供后续 agent 或脚本继续使用。

## 脚本自动化

- **一键启动服务器**：执行 `scripts/run_agfs_stack.sh`。脚本会检查 `PERPLEXITY_API_KEY` 与 `OPENAI_API_KEY`，构建 `docker-image/Dockerfile`，并以 `agfs-server` 名称启动容器（默认数据目录 `./data`，端口 8080，可用 `AGFS_*` 环境变量覆盖）。
- **自动跑完整流水线**：服务器就绪后，运行 `scripts/run_search_and_summary.sh "your query"`。脚本会向 `/web/request` 写入检索 JSON，轮询 `/web/response.txt`，随后把结果打包成 `{text, format}` JSON 发往 `/summary/request` 并打印最终 `/summary/response.txt`。可通过 `AGFS_MAX_RESULTS`、`AGFS_SUMMARY_FORMAT`、`AGFS_POLL_*` 环境变量调整。
  - 设置 `AGFS_PRINT_SEARCH=0` 可以关闭原始搜索结果的输出（默认打印原文和汇总）。
- **Tcl 版本脚本**：`scripts/run_search_and_summary.tcl` 具备同样逻辑，支持相同的环境变量。使用方式：`tclsh scripts/run_search_and_summary.tcl "your query"`。
