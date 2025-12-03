#!/usr/bin/env tclsh
#
# HTMX dashboard powered by Wapp (https://wapp.tcl.tk)

# -----------------------------------------------------------------------------
# Bootstrap Wapp + dependencies
# -----------------------------------------------------------------------------

set default_wapp_root "/Users/vajra/Clang/llm4.tcl/Wapp/wapp"
set wapp_root [expr {[info exists ::env(WAPP_ROOT)] && [file isdirectory $::env(WAPP_ROOT)] ? $::env(WAPP_ROOT) : $default_wapp_root}]

if {![file exists [file join $wapp_root wapp.tcl]]} {
    puts stderr "wapp.tcl not found under $wapp_root\nSet WAPP_ROOT to your wapp checkout."
    exit 1
}

source [file join $wapp_root wapp.tcl]
package require http

# -----------------------------------------------------------------------------
# Shared config + helpers
# -----------------------------------------------------------------------------

namespace eval ::htmx_dash {
    variable api_base [expr {[info exists ::env(AGFS_API_BASE)] ? $::env(AGFS_API_BASE) : "http://localhost:8080/api/v1"}]
    variable poll_attempts [expr {[info exists ::env(AGFS_POLL_ATTEMPTS)] ? int($::env(AGFS_POLL_ATTEMPTS)) : 30}]
    variable poll_delay [expr {[info exists ::env(AGFS_POLL_DELAY)] ? double($::env(AGFS_POLL_DELAY)) : 2.0}]
    variable summary_default [expr {[info exists ::env(AGFS_SUMMARY_FORMAT)] ? $::env(AGFS_SUMMARY_FORMAT) : "bullet list"}]

    ::http::config -useragent "agfs-htmx-wapp/0.1"
}

proc ::htmx_dash::json_escape {text} {
    set utf [encoding convertto utf-8 $text]
    binary scan $utf cu* codes
    set out ""
    foreach code $codes {
        if {$code < 0} { set code [expr {$code + 256}] }
        switch -- $code {
            8  { append out "\\b" }
            9  { append out "\\t" }
            10 { append out "\\n" }
            12 { append out "\\f" }
            13 { append out "\\r" }
            34 { append out "\\\"" }
            92 { append out "\\\\" }
            default {
                if {$code < 32} {
                    append out [format "\\u%04x" $code]
                } else {
                    append out [format "%c" $code]
                }
            }
        }
    }
    return $out
}

proc ::htmx_dash::url_encode {text} {
    set bytes [encoding convertto utf-8 $text]
    binary scan $bytes cu* codes
    set out ""
    foreach code $codes {
        if {$code < 0} { set code [expr {$code + 256}] }
        if {($code >= 48 && $code <= 57)
            || ($code >= 65 && $code <= 90)
            || ($code >= 97 && $code <= 122)
            || $code in {45 95 46 126}
            || $code == 47} {
            append out [format "%c" $code]
        } else {
            append out %[string toupper [format "%02x" $code]]
        }
    }
    return $out
}

proc ::htmx_dash::request {method path {ctype ""} {body ""}} {
    variable api_base
    set url "${api_base}/files?path=[url_encode $path]"
    set opts [list -method $method -timeout 120000]
    if {$body ne ""} {
        lappend opts -query $body
    }
    if {$ctype ne ""} {
        lappend opts -headers [list Content-Type $ctype]
        lappend opts -type $ctype
    }
    set token [eval [list ::http::geturl $url] $opts]
    set status [::http::status $token]
    set code [::http::ncode $token]
    set data [::http::data $token]
    set err ""
    if {$status ne "ok"} {
        set err [::http::error $token]
    }
    ::http::cleanup $token
    return [list $code $data $err]
}

proc ::htmx_dash::agfs_put {path body {ctype "application/json"}} {
    lassign [request PUT $path $ctype $body] code _ err
    if {$code < 200 || $code >= 300} {
        error "PUT $path failed (HTTP $code): $err"
    }
}

proc ::htmx_dash::agfs_get {path} {
    lassign [request GET $path] code data err
    if {$code >= 200 && $code < 300} {
        return [list true $data]
    }
    return [list false $err]
}

proc ::htmx_dash::poll_file {path} {
    variable poll_attempts
    variable poll_delay
    set delay_ms [expr {int($poll_delay * 1000)}]
    for {set i 0} {$i < $poll_attempts} {incr i} {
        lassign [agfs_get $path] ok payload
        if {$ok && [string trim $payload] ne ""} {
            return $payload
        }
        after $delay_ms
    }
    error "Timed out waiting for $path"
}

proc ::htmx_dash::run_search {query max_results} {
    if {$max_results < 1} { set max_results 1 }
    set payload [format "{\"query\":\"%s\",\"max_results\":%d}" [json_escape $query] $max_results]
    agfs_put "/web/request" $payload
    return [poll_file "/web/response.txt"]
}

proc ::htmx_dash::run_summary {text format} {
    set payload [format "{\"text\":\"%s\",\"format\":\"%s\"}" [json_escape $text] [json_escape $format]]
    agfs_put "/summary/request" $payload
    return [poll_file "/summary/response.txt"]
}

proc ::htmx_dash::run_trend {query max_results format} {
    set search_text [run_search $query $max_results]
    set summary_text [run_summary $search_text $format]
    set analysis_prompt "You are a cautious financial analyst. Based on the summary below, outline possible short-term impacts on Tesla stock. Use bullet points and highlight major catalysts vs risks."
    set analysis_text [run_summary "${summary_text}\n\n---\n${analysis_prompt}" "trend analysis"]
    return [dict create search $search_text summary $summary_text analysis $analysis_text]
}

proc ::htmx_dash::html_escape {text} {
    string map {& &amp; < &lt; > &gt; \" &quot; ' &#39;} $text
}

proc ::htmx_dash::render_card {title body css_class} {
    set escaped_body [html_escape $body]
    set escaped_title [html_escape $title]
    return [format {<section class="%s">
  <h2>%s</h2>
  <div class="markdown" data-raw="%s">
    <pre class="fallback">%s</pre>
  </div>
</section>} $css_class $escaped_title $escaped_body $escaped_body]
}

proc ::htmx_dash::render_error {message} {
    return [format {<section class="card"><h2>提示</h2><p class="muted">%s</p></section>} [html_escape $message]]
}

proc ::htmx_dash::safe_int {value default} {
    if {$value eq ""} { return $default }
    if {![regexp {^-?\d+$} $value]} { return $default }
    return [expr {int($value)}]
}

proc ::htmx_dash::render_layout {} {
    wapp-content-security-policy \
        "default-src 'self' https://unpkg.com https://cdn.jsdelivr.net; style-src 'self' 'unsafe-inline'; script-src 'self' https://unpkg.com https://cdn.jsdelivr.net 'unsafe-inline'; connect-src 'self'; img-src 'self' data:"
    wapp-mimetype "text/html; charset=utf-8"
    wapp-subst {
<!DOCTYPE html>
<html lang="zh-Hans">
  <head>
    <meta charset="utf-8" />
    <title>AGFS HTMX Console (Tcl/Wapp)</title>
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
      button:hover { transform: translateY(-1px); }
      #results { margin-top: 2rem; }
      .pinned-grid { display: grid; gap: 1rem; }
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
      }
      .markdown {
        margin-top: 1rem;
        line-height: 1.6;
        word-break: break-word;
        overflow-wrap: anywhere;
      }
      .markdown pre {
        background: rgba(15, 23, 42, 0.9);
        border-radius: 12px;
        padding: 1rem;
        overflow-x: auto;
        white-space: pre-wrap;
      }
      .indicator.htmx-indicator {
        opacity: 0;
        transition: opacity 0.2s ease;
        margin-top: 0.5rem;
      }
      .indicator.htmx-request { opacity: 1; }
    </style>
  </head>
  <body>
    <main class="app">
      <h1>AGFS 多工具面板 (Tcl/Wapp)</h1>
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
        <div class="buttons">
          <button
            type="button"
            hx-post="/search"
            hx-target="#card-stack"
            hx-swap="innerHTML"
            hx-indicator=".indicator"
            hx-include="#control-form">
            Search (simp)
          </button>
          <button
            type="button"
            hx-post="/summary"
            hx-target="#card-stack"
            hx-swap="innerHTML"
            hx-indicator=".indicator"
            hx-include="#control-form">
            Summarize (sum)
          </button>
          <button
            type="button"
            hx-post="/trend"
            hx-target="#card-stack"
            hx-swap="innerHTML"
            hx-indicator=".indicator"
            hx-include="#control-form">
            Trend Agent
          </button>
        </div>
      </form>
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
    }
}

proc ::htmx_dash::respond {html {code ""}} {
    if {$code ne ""} {
        wapp-reply-code $code
    }
    wapp-mimetype "text/html; charset=utf-8"
    wapp-trim $html
}

proc wapp-default {} {
    ::htmx_dash::render_layout
}

proc ::htmx_dash::require_param {name message} {
    set value [string trim [wapp-param $name ""]]
    if {$value eq ""} {
        ::htmx_dash::respond [::htmx_dash::render_error $message] "400 Bad Request"
        return -code return
    }
    return $value
}

proc ::htmx_dash::handle_errors {body} {
    if {[catch $body err opts]} {
        ::htmx_dash::respond [::htmx_dash::render_error $err] "500 Internal Server Error"
        return -options $opts -code error $err
    }
}

proc wapp-page-search {} {
    ::htmx_dash::handle_errors {
        set query [::htmx_dash::require_param query "请输入查询内容"]
        set max [::htmx_dash::safe_int [wapp-param max_results 2] 2]
        set result [::htmx_dash::run_search $query $max]
        ::htmx_dash::respond [::htmx_dash::render_card "Search Result" $result "card search-card"]
    }
}

proc wapp-page-summary {} {
    ::htmx_dash::handle_errors {
        variable ::htmx_dash::summary_default
        lassign [::htmx_dash::agfs_get "/web/response.txt"] ok text
        if {!$ok || [string trim $text] eq ""} {
            ::htmx_dash::respond [::htmx_dash::render_error "还没有搜索结果，请先点击 Search"] "400 Bad Request"
            return
        }
        set format [wapp-param summary_format $summary_default]
        set summary [::htmx_dash::run_summary $text $format]
        set html ""
        append html [::htmx_dash::render_card "Summary Result" $summary "card summary-card"]
        append html [::htmx_dash::render_card "Search Result" $text "card search-card"]
        ::htmx_dash::respond $html
    }
}

proc wapp-page-trend {} {
    ::htmx_dash::handle_errors {
        set query [::htmx_dash::require_param query "请输入查询内容"]
        set max [::htmx_dash::safe_int [wapp-param max_results 2] 2]
        variable ::htmx_dash::summary_default
        set format [wapp-param summary_format $summary_default]
        set bundle [::htmx_dash::run_trend $query $max $format]
        set html ""
        append html [::htmx_dash::render_card "Trend Analysis" [dict get $bundle analysis] "card trend-card"]
        append html [::htmx_dash::render_card "Summary Result" [dict get $bundle summary] "card summary-card"]
        append html [::htmx_dash::render_card "Search Result" [dict get $bundle search] "card search-card"]
        ::htmx_dash::respond $html
    }
}

# -----------------------------------------------------------------------------
# Entrypoint
# -----------------------------------------------------------------------------

if {[llength $argv] == 0} {
    set port [expr {[info exists ::env(AGFS_HTMX_TCL_PORT)] ? $::env(AGFS_HTMX_TCL_PORT) : 8788}]
    set argv [list --server $port]
}

puts "Starting Wapp dashboard with API base: $::htmx_dash::api_base"
wapp-start $argv
