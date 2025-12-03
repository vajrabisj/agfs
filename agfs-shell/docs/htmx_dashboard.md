# HTMX Multi-Tool Dashboard

一个最小化的 Web UI（单页应用），演示“同一输入 + 多按钮”如何分别驱动不同的 AGFS 工具/agent：

- **Search (simp)**：触发 `simpcurlfs`，把输入写入 `/web/request` 并把 `/web/response.txt` 渲染为 Markdown。
- **Summarize (sum)**：读取现有 `/web/response.txt`，调用 `summaryfs` 输出 `/summary/response.txt`，展示 Markdown。
- **Trend Agent**：自动跑完“搜索 → 摘要 → 分析”三步，并使用 `summaryfs` 生成额外的趋势解读。

## 启动步骤

1. 确保 AGFS 服务器和插件已运行（建议直接使用 `scripts/run_agfs_stack.sh`）。
2. Python 版本（Flask-free）：在另一个终端运行：
   ```bash
   python scripts/htmx_dashboard.py --port 8787
   ```
   环境变量 `AGFS_API_BASE`/`AGFS_POLL_*` 可覆写默认值；脚本仅使用标准库，无额外依赖。
3. Tcl/Wapp 版本（推荐）：依赖 [Wapp](https://wapp.tcl.tk) 框架。默认脚本会在 `/Users/vajra/Clang/llm4.tcl/Wapp/wapp` 查找 `wapp.tcl`，也可通过 `WAPP_ROOT` 覆盖。
   ```bash
   tclsh tcl/examples/htmx_dashboard_wapp.tcl        # 默认监听 8788，可用 AGFS_HTMX_TCL_PORT 覆盖
   ```
   Wapp 版本与 Python 版本共享同一 UI 与行为，且内置路由更健壮。
4. （可选）若仍需 twebserver 版本，可运行 `tcl/examples/htmx_dashboard.tcl`，但其 POST 解析依赖环境更脆弱。
5. 打开浏览器访问对应端口，例如 `http://localhost:8787`（Python）或 `http://localhost:8788`（Wapp）。

## 界面说明

- 顶部输入框填写查询内容，`Max Results` 和 `Summary Style` 用于控制写入 `/web/request` 与 `/summary/request` 的参数。
- 三个按钮均通过 HTMX `hx-post` 调用后端脚本，并刷新同一个 `#card-stack` 容器（无历史）：
  - `Search (simp)`：仅调用 `simpcurlfs`，渲染最新搜索卡片。
  - `Summarize (sum)`：读取 `/web/response.txt`，返回 “Summary → Search” 两张卡片（摘要永远在上）。
  - `Trend Agent`：重新跑搜索 + 摘要 + 分析，并按 “Trend → Summary → Search” 顺序覆盖容器。
- Markdown 渲染使用前端 `marked`（附 `<pre>` 退化显示防止 CDN 不可用），卡片文本开启 `word-break/overflow-wrap` 以适配窄屏。

## 自定义点子

- 想要把某个按钮改成真正的多 agent：把按钮改为向 `/queuefs/.../enqueue` 写 JSON，让后端 Tcl agent 接续任务。
- 可再加按钮链接到 HeartbeatFS、KVFS 等工具，比如“Store insight” 或 “Ping agent health”。
- 若要部署到公网，把脚本挂在反向代理后并设置 API 鉴权；HTMX/Marked 都走 CDN，如需离线可改为本地静态资源。
