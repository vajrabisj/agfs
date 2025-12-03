#!/usr/bin/env tclsh
#
# Minimal HTMX dashboard backed by twebserver (Tcl).
# Mirrors the Python version but stays fully Tcl-native.

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

set default_api_base [expr {[info exists ::env(AGFS_API_BASE)] ? $::env(AGFS_API_BASE) : "http://localhost:8080/api/v1"}]
set default_poll_attempts [expr {[info exists ::env(AGFS_POLL_ATTEMPTS)] ? $::env(AGFS_POLL_ATTEMPTS) : 30}]
set default_poll_delay [expr {[info exists ::env(AGFS_POLL_DELAY)] ? $::env(AGFS_POLL_DELAY) : 2}]
set default_listen_port [expr {[info exists ::env(AGFS_HTMX_TCL_PORT)] ? $::env(AGFS_HTMX_TCL_PORT) : 8788}]
set tweb_build [expr {[info exists ::env(TWEBSERVER_BUILD)] ? $::env(TWEBSERVER_BUILD) : "/Users/vajra/Clang/twebserver/build"}]

foreach path [list $tweb_build /opt/homebrew/Cellar/tcl-tk/9.0.2/lib/tcl9.0 /opt/homebrew/lib] {
    if {[file exists $path]} {
        lappend auto_path $path
    }
}

package require twebserver

# ---------------------------------------------------------------------------
# Worker initialization script (evaluated inside server thread)
# ---------------------------------------------------------------------------

set template {
    lappend auto_path %TWEBSERVER_BUILD%
    package require twebserver
    package require http

    namespace eval ::agfs_htmx_worker {
        variable api_base "%API_BASE%"
        variable poll_attempts %POLL_ATTEMPTS%
        variable poll_delay %POLL_DELAY%
        variable summary_default "bullet list"

        ::http::config -useragent "agfs-htmx-tcl/0.1"

        proc json_escape {text} {
            set utf [encoding convertto utf-8 $text]
            binary scan $utf cu* codes
            set out ""
            foreach code $codes {
                if {$code < 0} { set code [expr {$code + 256}] }
                switch -- $code {
                    8 { append out "\\b" }
                    9 { append out "\\t" }
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

        proc url_encode {text} {
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

        proc http_request {method path {ctype ""} {body ""}} {
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

        proc agfs_put {path body {ctype "application/json"}} {
            lassign [http_request PUT $path $ctype $body] code _ err
            if {$code < 200 || $code >= 300} {
                error "PUT $path failed (HTTP $code): $err"
            }
        }

        proc agfs_get {path} {
            lassign [http_request GET $path] code data err
            if {$code >= 200 && $code < 300} {
                return [list true $data]
            }
            return [list false $err]
        }

        proc poll_file {path} {
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

        proc run_search {query max_results} {
            if {$max_results < 1} { set max_results 1 }
            set payload [format "{\"query\":\"%s\",\"max_results\":%d}" [json_escape $query] $max_results]
            agfs_put "/web/request" $payload
            return [poll_file "/web/response.txt"]
        }

        proc run_summary {text format} {
            set payload [format "{\"text\":\"%s\",\"format\":\"%s\"}" [json_escape $text] [json_escape $format]]
            agfs_put "/summary/request" $payload
            return [poll_file "/summary/response.txt"]
        }

        proc run_trend {query max_results format} {
            set search_text [run_search $query $max_results]
            set summary_text [run_summary $search_text $format]
            set analysis_prompt "You are a cautious financial analyst. Based on the summary below, outline possible short-term impacts on Tesla stock. Use bullet points and highlight major catalysts vs risks."
            set analysis_request "${summary_text}\n\n---\n${analysis_prompt}"
            set analysis_text [run_summary $analysis_request "trend analysis"]
            return [dict create search $search_text summary $summary_text analysis $analysis_text]
        }

        proc html_escape {text} {
            string map {& &amp; < &lt; > &gt; \" &quot; ' &#39;} $text
        }

        proc render_card {title body css_class} {
            set escaped_body [html_escape $body]
            set escaped_title [html_escape $title]
            return [format {<section class="%s">
  <h2>%s</h2>
  <div class="markdown" data-raw="%s">
    <pre class="fallback">%s</pre>
  </div>
</section>} $css_class $escaped_title $escaped_body $escaped_body]
        }

        proc render_error {message} {
            return [format {<section class="card"><h2>提示</h2><p class="muted">%s</p></section>} [html_escape $message]]
        }

        proc render_layout {} {
            return {<!DOCTYPE html>
<html lang="zh-Hans">
  <head>
    <meta charset="utf-8" />
    <title>AGFS HTMX Console (Tcl)</title>
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
      button:hover {
        transform: translateY(-1px);
        box-shadow: 0 8px 30px rgba(56, 189, 248, 0.35);
      }
      #results {
        margin-top: 2rem;
      }
      .pinned-grid {
        display: grid;
        gap: 1rem;
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
      .indicator.htmx-request {
        opacity: 1;
      }
    </style>
  </head>
  <body>
    <main class="app">
      <h1>AGFS 多工具面板 (Tcl)</h1>
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
            hx-post="/action/search"
            hx-target="#card-stack"
            hx-swap="innerHTML"
            hx-indicator=".indicator"
            hx-include="#control-form">
            Search (simp)
          </button>
          <button
            type="button"
            hx-post="/action/summary"
            hx-target="#card-stack"
            hx-swap="innerHTML"
            hx-indicator=".indicator"
            hx-include="#control-form">
            Summarize (sum)
          </button>
          <button
            type="button"
            hx-post="/action/trend"
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
</html>}
        }

        proc get_form_fields {req} {
            set fields {}
            puts stderr "GET_FORM_FIELDS: starting..."
            if {[catch {::twebserver::get_form $req} form] == 0} {
                puts stderr "GET_FORM_FIELDS: get_form succeeded, form size=[dict size $form]"
                puts stderr "GET_FORM_FIELDS: form dict: $form"
                if {[dict exists $form fields]} {
                    set fields [dict get $form fields]
                    puts stderr "GET_FORM_FIELDS: got fields from get_form, size=[dict size $fields]"
                    puts stderr "GET_FORM_FIELDS: fields dict: $fields"
                    # Check the actual structure of fields
                    foreach key [dict keys $fields] {
                        set field_info [dict get $fields $key]
                        puts stderr "GET_FORM_FIELDS: field '$key' = '$field_info' (type: [llength $field_info])"
                        if {[dict exists $field_info value]} {
                            puts stderr "GET_FORM_FIELDS:   has 'value' key: [dict get $field_info value]"
                        }
                    }
                }
            } else {
                puts stderr "GET_FORM_FIELDS: get_form failed: $form"
            }
            if {[dict size $fields] == 0} {
                puts stderr "GET_FORM_FIELDS: trying request body..."
                if {[dict exists $req body]} {
                    set body [dict get $req body]
                    puts stderr "GET_FORM_FIELDS: body='$body'"
                    if {$body ne ""} {
                        set parsed [::twebserver::parse_query $body]
                        puts stderr "GET_FORM_FIELDS: parsed from body: $parsed"
                        foreach {key value} $parsed {
                            dict set fields $key [dict create value $value]
                        }
                    }
                }
            }
            if {[dict size $fields] == 0 && [dict exists $req queryString]} {
                puts stderr "GET_FORM_FIELDS: trying query string..."
                set query_str [dict get $req queryString]
                puts stderr "GET_FORM_FIELDS: queryString='$query_str'"
                if {$query_str ne ""} {
                    set parsed [::twebserver::parse_query $query_str]
                    puts stderr "GET_FORM_FIELDS: parsed from query: $parsed"
                    foreach {key value} $parsed {
                        dict set fields $key [dict create value $value]
                    }
                }
            }
            puts stderr "GET_FORM_FIELDS: returning fields, size=[dict size $fields]"
            return $fields
        }

        proc field_value {fields key {default ""}} {
            if {![dict exists $fields $key value]} {
                return $default
            }
            return [dict get $fields $key value]
        }

        proc safe_int {value default} {
            if {$value eq ""} { return $default }
            if {![regexp {^-?\d+$} $value]} { return $default }
            return $value
        }

        proc handle_search {fields} {
            set query [string trim [field_value $fields query]]
            if {$query eq ""} {
                return [::twebserver::build_response 400 text/html [render_error "请输入查询内容"]]
            }
            set max_results [safe_int [field_value $fields max_results "2"] 2]
            set result [run_search $query $max_results]
            return [::twebserver::build_response 200 text/html [render_card "Search Result" $result "card search-card"]]
        }

        proc handle_summary {fields} {
            variable summary_default
            set format [field_value $fields summary_format $summary_default]
            lassign [agfs_get "/web/response.txt"] ok text
            if {!$ok || [string trim $text] eq ""} {
                return [::twebserver::build_response 400 text/html [render_error "还没有搜索结果，请先点击 Search"]]
            }
            set summary [run_summary $text $format]
            set body [render_card "Summary Result" $summary "card summary-card"]
            append body [render_card "Search Result" $text "card search-card"]
            return [::twebserver::build_response 200 text/html $body]
        }

        proc handle_trend {fields} {
            variable summary_default
            set query [string trim [field_value $fields query]]
            if {$query eq ""} {
                return [::twebserver::build_response 400 text/html [render_error "请输入查询内容"]]
            }
            set max_results [safe_int [field_value $fields max_results "2"] 2]
            set format [field_value $fields summary_format $summary_default]
            set bundle [run_trend $query $max_results $format]
            set body ""
            append body [render_card "Trend Analysis" [dict get $bundle analysis] "card trend-card"]
            append body [render_card "Summary Result" [dict get $bundle summary] "card summary-card"]
            append body [render_card "Search Result" [dict get $bundle search] "card search-card"]
            return [::twebserver::build_response 200 text/html $body]
        }

        proc dispatch {ctx req} {
            set method [dict get $req httpMethod]
            set path [dict get $req path]
            if {$method eq "GET" && $path eq "/"} {
                return [::twebserver::build_response 200 text/html [render_layout]]
            }
            if {$method eq "POST"} {
                puts stderr "POST request to path: $path"
                if {$path eq "/test"} {
                    puts stderr "Test endpoint hit"
                    return [::twebserver::build_response 200 text/plain "test ok"]
                }
                set fields [get_form_fields $req]
                # Debug logging
                puts stderr "DEBUG: path=$path, fields size=[dict size $fields]"
                if {[dict size $fields] > 0} {
                    puts stderr "DEBUG: field keys: [dict keys $fields]"
                    foreach key [dict keys $fields] {
                        set val [field_value $fields $key]
                        puts stderr "DEBUG:   $key = '$val'"
                    }
                }
                switch -- $path {
                    "/action/search" { return [handle_search $fields] }
                    "/action/summary" { return [handle_summary $fields] }
                    "/action/trend" { return [handle_trend $fields] }
                }
            }
            return [::twebserver::build_response 404 text/plain "not found"]
        }
    }

    proc process_conn {ctx req} {
        puts stderr "=== PROCESS_CONN CALLED ==="
        puts stderr "Context keys: [dict keys $ctx]"
        puts stderr "Request keys: [dict keys $req]"
        set conn [dict get $ctx conn]
        puts stderr "PROCESS_CONN: method=[dict get $req httpMethod], path=[dict get $req path]"
        if {[catch {::agfs_htmx_worker::dispatch $ctx $req} res]} {
            puts stderr "ERROR in dispatch: $res"
            set res [::twebserver::build_response 500 text/html [::agfs_htmx_worker::render_error $res]]
        }
        ::twebserver::return_response $conn $res
    }
}

set init_script [string map [list \
    %API_BASE% $default_api_base \
    %POLL_ATTEMPTS% $default_poll_attempts \
    %POLL_DELAY% $default_poll_delay \
    %TWEBSERVER_BUILD% $tweb_build] $template]

set config_dict [dict create rootdir [file dirname [info script]]]
set server_handle [::twebserver::create_server $config_dict process_conn $init_script]

::twebserver::listen_server -http -num_threads 4 $server_handle $default_listen_port

puts "Tcl HTMX dashboard running at http://localhost:$default_listen_port"
puts "API base: $default_api_base"
puts "Press Ctrl+C to stop."

::twebserver::wait_signal
