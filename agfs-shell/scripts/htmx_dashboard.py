#!/usr/bin/env python3
"""
Minimal HTMX single-page app for AGFS tool/agent workflows.
Serves a small UI with one input box and multiple buttons:
  - Search (simpcurlfs)
  - Summarize (summaryfs)
  - Trend (search + summarize + opinionated analysis)
"""

from __future__ import annotations

import argparse
import html
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, HTTPServer


INDEX_HTML = """<!DOCTYPE html>
<html lang="zh-Hans">
  <head>
    <meta charset="utf-8" />
    <title>AGFS HTMX Console</title>
    <script src="https://unpkg.com/htmx.org@1.9.12"></script>
    <script src="https://cdn.jsdelivr.net/npm/marked@12.0.2/marked.min.js"></script>
    <style>
      :root {
        color-scheme: light dark;
        font-family: "Inter", "Segoe UI", sans-serif;
        --bg: #0f172a;
        --fg: #f1f5f9;
        --card: rgba(15, 23, 42, 0.85);
        --accent: #38bdf8;
        --muted: #94a3b8;
      }
      body {
        margin: 0;
        background: radial-gradient(circle at top, #1e1b4b, #020617 60%);
        color: var(--fg);
        min-height: 100vh;
        display: flex;
        justify-content: center;
        padding: 2rem;
      }
      .app {
        width: min(960px, 100%);
        background: rgba(2, 6, 23, 0.6);
        border-radius: 24px;
        padding: 2.5rem;
        backdrop-filter: blur(10px);
        box-shadow: 0 20px 80px rgba(2, 6, 23, 0.6);
      }
      h1 {
        margin-top: 0;
        font-size: 2rem;
      }
      form {
        display: grid;
        gap: 1rem;
        margin-bottom: 1.5rem;
      }
      label {
        font-size: 0.95rem;
        color: var(--muted);
      }
      input[type="text"],
      input[type="number"],
      select {
        width: 100%;
        padding: 0.75rem;
        border-radius: 12px;
        border: 1px solid rgba(148, 163, 184, 0.4);
        background: rgba(15, 23, 42, 0.7);
        color: var(--fg);
        font-size: 1rem;
      }
      .buttons {
        display: flex;
        flex-wrap: wrap;
        gap: 0.75rem;
      }
      button {
        flex: 1;
        min-width: 120px;
        border: none;
        border-radius: 999px;
        padding: 0.85rem 1.25rem;
        font-size: 1rem;
        font-weight: 600;
        background: linear-gradient(135deg, #38bdf8, #818cf8);
        color: #020617;
        cursor: pointer;
        transition: transform 0.15s ease, box-shadow 0.15s ease;
      }
      button:hover {
        transform: translateY(-1px);
        box-shadow: 0 8px 30px rgba(56, 189, 248, 0.35);
      }
      button:disabled {
        opacity: 0.6;
        cursor: not-allowed;
      }
      #results {
        margin-top: 2rem;
      }
      .pinned-grid {
        display: grid;
        gap: 1rem;
      }
      .card-group {
        display: grid;
        gap: 1rem;
      }
      .placeholder-card .placeholder {
        color: var(--muted);
        font-style: italic;
      }
      .card {
        background: var(--card);
        border-radius: 18px;
        padding: 1.5rem;
        border: 1px solid rgba(148, 163, 184, 0.2);
        word-break: break-word;
        overflow-wrap: anywhere;
      }
      .card h2 {
        margin-top: 0;
        font-size: 1.2rem;
        letter-spacing: 0.04em;
        color: var(--muted);
        word-break: break-word;
        overflow-wrap: anywhere;
      }
      .markdown {
        margin-top: 1rem;
        line-height: 1.6;
        word-break: break-word;
        overflow-wrap: anywhere;
      }
      .markdown ul {
        padding-left: 1.2rem;
      }
      .markdown code {
        font-family: "JetBrains Mono", "SFMono-Regular", monospace;
        background: rgba(15, 23, 42, 0.9);
        padding: 0.15rem 0.4rem;
        border-radius: 6px;
      }
      .markdown pre {
        background: rgba(15, 23, 42, 0.9);
        border-radius: 12px;
        padding: 1rem;
        overflow-x: auto;
        word-break: break-word;
        overflow-wrap: anywhere;
        white-space: pre-wrap;
      }
      .muted {
        color: var(--muted);
        font-size: 0.95rem;
      }
      .indicator.htmx-indicator {
        opacity: 0;
        transition: opacity 0.2s ease;
        margin-top: 0.5rem;
      }
      .indicator.htmx-request {
        opacity: 1;
      }
    </style>
  </head>
  <body>
    <main class="app">
      <h1>AGFS 多工具面板</h1>
      <form id="control-form">
        <div>
          <label>输入内容 / Query</label>
          <input type="text" name="query" placeholder="最新的特斯拉新闻" required />
        </div>
        <div style="display:flex; gap:1rem; flex-wrap:wrap;">
          <div style="flex:1 1 220px; min-width:180px;">
            <label>最大结果数</label>
            <input type="number" name="max_results" value="2" min="1" max="5" />
          </div>
          <div style="flex:0 0 220px; min-width:160px;">
            <label>摘要样式</label>
            <select name="summary_format">
              <option value="bullet list">项目符号列表</option>
              <option value="short memo">简短备忘</option>
              <option value="executive summary">高管摘要</option>
              <option value="trend analysis">趋势分析</option>
            </select>
          </div>
        </div>
      </form>
      <div class="buttons">
        <button
          hx-post="/action/search"
          hx-target="#card-stack"
          hx-swap="innerHTML"
          hx-indicator=".indicator"
          hx-include="#control-form">
          Search (simp)
        </button>
        <button
          hx-post="/action/summary"
          hx-target="#card-stack"
          hx-swap="innerHTML"
          hx-indicator=".indicator"
          hx-include="#control-form">
          Summarize (sum)
        </button>
        <button
          hx-post="/action/trend"
          hx-target="#card-stack"
          hx-swap="innerHTML"
          hx-indicator=".indicator"
          hx-include="#control-form">
          Trend Agent
        </button>
      </div>
      <div class="indicator htmx-indicator">处理中...</div>
      <div id="results">
        <div class="pinned-grid" id="card-stack"></div>
      </div>
    </main>
    <script>
      function renderMarkdown(scope) {
        const blocks = scope.querySelectorAll(".markdown[data-rendered!='1']");
        blocks.forEach((el) => {
          const raw = el.dataset.raw || "";
          if (window.marked) {
            el.innerHTML = marked.parse(raw);
          } else {
            const fallback = el.querySelector(".fallback");
            if (fallback) {
              fallback.textContent = raw;
            } else {
              el.textContent = raw;
            }
          }
          el.dataset.rendered = "1";
        });
      }
      document.body.addEventListener("htmx:afterSwap", (evt) => {
        renderMarkdown(evt.detail.target);
      });
      renderMarkdown(document);
    </script>
  </body>
</html>
"""


class Config:
    def __init__(
        self,
        api_base: str,
        poll_attempts: int = 30,
        poll_delay: float = 2.0,
    ) -> None:
        self.api_base = api_base.rstrip("/")
        self.poll_attempts = poll_attempts
        self.poll_delay = poll_delay


def agfs_put(api_base: str, path: str, payload: str, content_type: str = "application/json") -> None:
    url = f"{api_base}/files?path={urllib.parse.quote(path, safe='/')}"
    data = payload.encode("utf-8")
    req = urllib.request.Request(url, data=data, method="PUT")
    req.add_header("Content-Type", content_type)
    with urllib.request.urlopen(req, timeout=60) as resp:  # noqa: S310
        resp.read()


def agfs_get(api_base: str, path: str) -> str:
    url = f"{api_base}/files?path={urllib.parse.quote(path, safe='/')}"
    req = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(req, timeout=60) as resp:  # noqa: S310
        return resp.read().decode("utf-8")


def poll_file(config: Config, path: str) -> str:
    for _ in range(config.poll_attempts):
        try:
            content = agfs_get(config.api_base, path)
            if content.strip():
                return content
        except urllib.error.HTTPError:
            pass
        time.sleep(config.poll_delay)
    raise RuntimeError(f"Timed out waiting for {path}")


def run_search(config: Config, query: str, max_results: int) -> str:
    payload = json.dumps({"query": query, "max_results": max(1, max_results)})
    agfs_put(config.api_base, "/web/request", payload)
    return poll_file(config, "/web/response.txt")


def run_summary(config: Config, text: str, fmt: str) -> str:
    payload = json.dumps({"text": text, "format": fmt})
    agfs_put(config.api_base, "/summary/request", payload)
    return poll_file(config, "/summary/response.txt")


def run_trend(config: Config, query: str, max_results: int, fmt: str) -> dict[str, str]:
    search_text = run_search(config, query, max_results)
    summary_text = run_summary(config, search_text, fmt)
    analysis_prompt = (
        "You are a cautious financial analyst. Based on the summary below, "
        "outline possible short-term impacts on Tesla stock. "
        "Use bullet points and highlight major catalysts vs risks."
    )
    analysis_request = f"{summary_text}\n\n---\n{analysis_prompt}"
    analysis_text = run_summary(config, analysis_request, "trend analysis")
    return {
        "search": search_text,
        "summary": summary_text,
        "analysis": analysis_text,
    }


def render_card(title: str, body: str, css_class: str = "card") -> str:
    escaped = html.escape(body)
    return (
        f'<section class="{css_class}">'
        f"<h2>{html.escape(title)}</h2>"
        f'<div class="markdown" data-raw="{escaped}">'
        f"<pre class=\"fallback\">{escaped}</pre>"
        "</div>"
        "</section>"
    )


def render_error(message: str) -> str:
    return f'<section class="card"><h2>提示</h2><p class="muted">{html.escape(message)}</p></section>'


class DashboardHandler(BaseHTTPRequestHandler):
    server: "DashboardServer"  # type: ignore[assignment]

    def do_GET(self) -> None:  # noqa: N802
        if self.path in ("/", "/index.html"):
            self.respond(HTTPStatus.OK, INDEX_HTML)
        else:
            self.respond(HTTPStatus.NOT_FOUND, "<h1>404</h1>")

    def do_POST(self) -> None:  # noqa: N802
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length).decode("utf-8")
        params = urllib.parse.parse_qs(raw)
        query = params.get("query", [""])[0].strip()
        max_results = int(params.get("max_results", ["2"])[0] or "2")
        summary_format = params.get("summary_format", ["bullet list"])[0]

        try:
            if self.path == "/action/search":
                if not query:
                    self.respond(HTTPStatus.BAD_REQUEST, render_error("请输入查询内容"))
                    return
                text = run_search(self.server.config, query, max_results)
                self.respond(HTTPStatus.OK, render_card("Search Result", text, "card search-card"))
            elif self.path == "/action/summary":
                text = agfs_get(self.server.config.api_base, "/web/response.txt").strip()
                if not text:
                    self.respond(HTTPStatus.BAD_REQUEST, render_error("还没有搜索结果，请先点击 Search"))
                    return
                summary = run_summary(self.server.config, text, summary_format)
                cards = [
                    render_card("Summary Result", summary, "card summary-card"),
                    render_card("Search Result", text, "card search-card"),
                ]
                self.respond(HTTPStatus.OK, "".join(cards))
            elif self.path == "/action/trend":
                if not query:
                    self.respond(HTTPStatus.BAD_REQUEST, render_error("请输入查询内容"))
                    return
                bundle = run_trend(self.server.config, query, max_results, summary_format)
                cards = [
                    render_card("Trend Analysis", bundle["analysis"], "card trend-card"),
                    render_card("Summary Result", bundle["summary"], "card summary-card"),
                    render_card("Search Result", bundle["search"], "card search-card"),
                ]
                self.respond(HTTPStatus.OK, "".join(cards))
            else:
                self.respond(HTTPStatus.NOT_FOUND, render_error("未知操作"))
        except Exception as exc:  # noqa: BLE001
            self.respond(HTTPStatus.INTERNAL_SERVER_ERROR, render_error(str(exc)))

    def respond(self, status: HTTPStatus, content: str) -> None:
        body = content.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args) -> None:  # noqa: A003
        # Quieter logging
        print(f"[htmx-dashboard] {self.address_string()} - {format % args}")


class DashboardServer(HTTPServer):
    def __init__(self, addr: tuple[str, int], handler: type[DashboardHandler], config: Config) -> None:
        super().__init__(addr, handler)
        self.config = config


def main() -> None:
    parser = argparse.ArgumentParser(description="AGFS HTMX console")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--api-base", default=os.environ.get("AGFS_API_BASE", "http://localhost:8080/api/v1"))
    parser.add_argument("--poll-attempts", type=int, default=int(os.environ.get("AGFS_POLL_ATTEMPTS", "30")))
    parser.add_argument("--poll-delay", type=float, default=float(os.environ.get("AGFS_POLL_DELAY", "2")))
    args = parser.parse_args()

    config = Config(api_base=args.api_base, poll_attempts=args.poll_attempts, poll_delay=args.poll_delay)
    server = DashboardServer((args.host, args.port), DashboardHandler, config)
    print(f"Serving HTMX dashboard at http://{args.host}:{args.port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.server_close()


if __name__ == "__main__":
    main()
