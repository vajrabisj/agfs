#!/usr/bin/env tclsh
#
# Simplified agent loop for AGFS QueueFS.
# Mirrors the Python example (agfs-mcp/demos/task_loop.py) but implemented in Tcl.
#
# The agent watches a QueueFS dequeue file, processes tasks (simulated here with
# a tiny summarizer), and stores JSON results back into AGFS so that other
# components can pick them up.

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file dirname [file dirname $script_dir]]
set auto_path [linsert $auto_path 0 $repo_root]

package require agfs
package require json
package require http

proc usage {} {
    puts "Usage: tclsh examples/agent_task_loop.tcl ?options?"
    puts "Options:"
    puts "  -queue PATH       QueueFS path (default: /queuefs/agent_tcl)"
    puts "  -results PATH     Directory for results (default: /local/agent_results)"
    puts "  -api URL          AGFS API base URL (default: http://localhost:8080)"
    puts "  -interval SEC     Poll interval in seconds (default: 3)"
    puts "  -name NAME        Agent name (default: tcl-agent)"
    puts "  -model NAME       Ollama model to use (default: qwen3:4b)"
    puts "  -ollama_url URL   Ollama base URL (default: http://localhost:11434)"
    puts "  -ollama_timeout MS   Ollama request timeout in ms (default: 120000)"
    puts "  -help             Show this message"
    exit 0
}

proc parse_args {argv} {
    array set opts {
        -queue /queuefs/agent_tcl
        -results /local/agent_results
        -api http://localhost:8080
        -interval 3
        -name tcl-agent
        -model qwen3:4b
        -ollama_url http://localhost:11434
        -ollama_timeout 120000
        -tool_dir ""
    }
    for {set i 0} {$i < [llength $argv]} {incr i} {
        set key [lindex $argv $i]
        switch -- $key {
            -queue - -results - -api - -interval - -name - -model - -ollama_url - -ollama_timeout - -tool_dir {
                if {$i == [expr {[llength $argv]-1}]} {
                    error "Missing value for $key"
                }
                set opts($key) [lindex $argv [incr i]]
            }
            -help { usage }
            default {
                error "Unknown option: $key (use -help)"
            }
        }
    }
    if {[string is double -strict $opts(-interval)] == 0 || $opts(-interval) <= 0} {
        error "-interval must be a positive number of seconds"
    }
    if {[string is integer -strict $opts(-ollama_timeout)] == 0 || $opts(-ollama_timeout) <= 0} {
        error "-ollama_timeout must be a positive integer (milliseconds)"
    }
    return [dict create \
        queue $opts(-queue) \
        results $opts(-results) \
        api $opts(-api) \
        interval $opts(-interval) \
        name $opts(-name) \
        model $opts(-model) \
        ollama_url $opts(-ollama_url) \
        ollama_timeout $opts(-ollama_timeout) \
        tool_dir $opts(-tool_dir)]
}

proc log {msg} {
    puts "[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}] :: $msg"
    flush stdout
}

proc dict_get_default {dictValue key default} {
    if {[dict exists $dictValue $key]} {
        return [dict get $dictValue $key]
    }
    return $default
}

proc json_bool {value} {
    if {$value in {1 true True TRUE yes Yes}} {
        return true
    }
    return false
}

proc ensure_remote_dir {client path} {
    set norm [string trimright $path "/"]
    if {$norm eq "" || $norm eq "/"} {
        return
    }
    set segments [split $norm "/"]
    set current ""
    foreach seg $segments {
        if {$seg eq ""} {
            continue
        }
        append current "/" $seg
        if {[catch {$client stat $current}]} {
            if {[catch {$client mkdir $current} err]} {
                set lower [string tolower $err]
                if {[string match "*exists*" $lower] || [string match "*already*" $lower]} {
                    continue
                }
                if {[string match "*not allowed*" $lower]} {
                    continue
                }
                if {[string match "*permission*" $lower]} {
                    continue
                }
                if {[string match "*not found*" $lower]} {
                    continue
                }
                log "Warning: failed to ensure $current: $err"
            } else {
                log "Created remote directory: $current"
            }
        }
    }
}

proc fetch_task {client queue_path} {
    if {[catch {set payload [$client cat "$queue_path/dequeue"]} err]} {
        log "Failed to dequeue: $err"
        return ""
    }
    set trimmed [string trim $payload]
    if {$trimmed eq "" || $trimmed eq "{}"} {
        return ""
    }
    if {[catch {set task [agfs::ParseJson $trimmed]} parseErr]} {
        log "Warning: cannot parse task JSON: $parseErr"
        return ""
    }
    if {[dict size $task] == 0} {
        return ""
    }
    return $task
}

proc extract_task_payload {task_dict} {
    set raw [dict_get_default $task_dict data ""]
    # QueueFS keeps trailing newline in data.
    set trimmed [string trim $raw]
    if {$trimmed eq ""} {
        return [dict create text "" summary "No content provided"]
    }
    if {[catch {set parsed [agfs::ParseJson $trimmed]}]} {
        return [dict create text $trimmed summary ""]
    }
    return $parsed
}

proc normalize_steps {steps_value} {
    set normalized {}
    if {$steps_value eq ""} {
        return $normalized
    }
    foreach step $steps_value {
        if {[catch {dict size $step}]} {
            continue
        }
        lappend normalized $step
    }
    return $normalized
}

proc build_result_json {agent_name task_id payload_dict text_summary step_outputs} {
    set received [clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S%z}]
    set input_text [dict_get_default $payload_dict text [dict_get_default $payload_dict input ""]]
    set task_type [dict_get_default $payload_dict task "text"]

    set summary $text_summary
    if {$summary eq ""} {
        set summary [format "Agent %s processed %d characters for %s task" \
            $agent_name [string length $input_text] $task_type]
    }

    set step_array {}
    set steps_json [json::write array]
    foreach step_entry $step_outputs {
        set step_id [dict_get_default $step_entry id ""]
        set step_prompt [dict_get_default $step_entry prompt ""]
        set step_output [dict_get_default $step_entry output ""]
        lappend step_array [json::write object \
            id [json::write string $step_id] \
            prompt [json::write string $step_prompt] \
            output [json::write string $step_output]]
    }
    if {[llength $step_array] > 0} {
        set steps_json [json::write array {*}$step_array]
    }

    return [json::write object \
        agent [json::write string $agent_name] \
        taskId [json::write string $task_id] \
        taskType [json::write string $task_type] \
        receivedAt [json::write string $received] \
        input [json::write string $input_text] \
        summary [json::write string $summary] \
        status [json::write string "completed"] \
        steps $steps_json]
}

proc call_ollama {opts prompt} {
    set url [dict get $opts ollama_url]
    set model [dict get $opts model]
    set timeout_ms [dict get $opts ollama_timeout]
    set payload [json::write object \
        model [json::write string $model] \
        prompt [json::write string $prompt] \
        stream [json_bool false]]
    set headers [list Content-Type application/json Accept application/json]
    set token [::http::geturl "$url/api/generate" \
        -method POST \
        -headers $headers \
        -timeout $timeout_ms \
        -type "application/json" \
        -query $payload]
    set status [::http::status $token]
    set ncode [::http::ncode $token]
    set body [::http::data $token]
    ::http::cleanup $token
    if {$status ne "ok" || $ncode < 200 || $ncode >= 300} {
        error "Ollama HTTP $ncode: $status"
    }
    if {[catch {set parsed [agfs::ParseJson $body]} err]} {
        error "Failed to parse Ollama response: $err"
    }
    if {![dict exists $parsed response]} {
        error "Ollama response missing 'response' field"
    }
    return [string trim [dict get $parsed response]]
}

proc run_local_tool_step {opts tool_name arg_string} {
    set tool_dir [dict_get_default $opts tool_dir ""]
    if {$tool_dir eq ""} {
        error "tool_dir not configured"
    }
    set script_path [file join $tool_dir "${tool_name}.tcl"]
    if {![file exists $script_path]} {
        error "tool '$tool_name' not found in $tool_dir"
    }
    set arg_list {}
    set trimmed [string trim $arg_string]
    if {$trimmed ne ""} {
        if {[catch {set arg_list [list {*}$trimmed]}]} {
            set arg_list [list $trimmed]
        }
    }
    set cmd [list /opt/homebrew/bin/tclsh9.0 $script_path]
    if {[llength $arg_list] > 0} {
        set cmd [concat $cmd $arg_list]
    }
    if {[catch {set output [exec {*}$cmd]} err]} {
        error $err
    }
    return [string trim $output]
}

proc run_task_with_model {opts payload_dict} {
    set base_text [string trim [dict_get_default $payload_dict text [dict_get_default $payload_dict input ""]]]
    set explicit_prompt [string trim [dict_get_default $payload_dict prompt ""]]
    set steps_raw [dict_get_default $payload_dict steps {}]
    set steps_list [normalize_steps $steps_raw]
    set step_outputs {}

    if {[llength $steps_list] == 0} {
        set final_prompt ""
        if {$explicit_prompt ne ""} {
            set final_prompt $explicit_prompt
        } elseif {$base_text ne ""} {
            set final_prompt "Summarize the following request:\n$base_text"
        } else {
            set final_prompt "Provide a status update for the agent."
        }
        set llm_output [call_ollama $opts $final_prompt]
        return [dict create summary $llm_output steps $step_outputs]
    }

    set previous ""
    set idx 0
    foreach step_dict $steps_list {
        incr idx
        set step_prompt [dict_get_default $step_dict prompt ""]
        if {$step_prompt eq ""} {
            continue
        }
        set step_id [dict_get_default $step_dict id [format "step-%d" $idx]]
        set trimmed_prompt [string trim $step_prompt]
        set llm_output ""
        if {[regexp -nocase {^tool:([a-z0-9_./-]+)\s*(.*)$} $trimmed_prompt -> tool_name tool_args]} {
            if {[catch {set tool_result [run_local_tool_step $opts $tool_name $tool_args]} tool_err]} {
                set llm_output "Tool $tool_name failed: $tool_err"
            } else {
                set llm_output $tool_result
            }
        } else {
            set context ""
            if {$base_text ne ""} {
                append context "Task context:\n$base_text\n\n"
            }
            if {$previous ne ""} {
                append context "Previous result:\n$previous\n\n"
            }
            append context "Step instructions:\n$step_prompt"
            set llm_output [call_ollama $opts $context]
        }
        lappend step_outputs [dict create id $step_id prompt $step_prompt output $llm_output]
        set previous $llm_output
    }

    if {$previous eq ""} {
        set previous [format "Agent %s processed %d characters." [dict get $opts name] [string length $base_text]]
    }

    return [dict create summary $previous steps $step_outputs]
}

proc handle_task {client opts task_dict} {
    set agent_name [dict get $opts name]
    set results_dir [dict get $opts results]

    set task_id [dict_get_default $task_dict id [format "task-%s" [clock clicks]]]
    set payload_dict [extract_task_payload $task_dict]
    set input_text [dict_get_default $payload_dict text [dict_get_default $payload_dict input ""]]

    set summary ""
    set step_outputs {}
    if {[catch {
        set llm_result [run_task_with_model $opts $payload_dict]
    } err]} {
        log "✗ LLM invocation failed: $err"
        set processed [string trim [string map {\n " "} $input_text]]
        if {$processed ne ""} {
            set summary [format "Fallback (%s): %s" $agent_name $processed]
        } else {
            set summary "Agent $agent_name encountered an error while processing."
        }
    } else {
        set summary [dict_get_default $llm_result summary ""]
        set step_outputs [dict_get_default $llm_result steps {}]
    }

    set result_json [build_result_json $agent_name $task_id $payload_dict $summary $step_outputs]

    set agent_results_dir "$results_dir/$agent_name"
    ensure_remote_dir $client $agent_results_dir

    set output_path "$agent_results_dir/$task_id.json"
    $client write $output_path $result_json
    log "✓ Task $task_id processed -> $output_path"
}

proc main {} {
    set opts [parse_args $::argv]

    set tool_dir [dict_get_default $opts tool_dir ""]
    if {$tool_dir eq ""} {
        if {[info exists ::env(AGFS_TOOL_DIR)] && $::env(AGFS_TOOL_DIR) ne ""} {
            set tool_dir $::env(AGFS_TOOL_DIR)
        } else {
            set tool_dir "/Users/vajra/Clang/wapptclsh-agent/tools/generated"
        }
    }
    dict set opts tool_dir $tool_dir

    set api [dict get $opts api]
    set queue_path [dict get $opts queue]
    set results_dir [dict get $opts results]
    set interval_ms [expr {int([dict get $opts interval] * 1000)}]

    set client [agfs::AGFSClient -api_base $api -timeout 10]

    log "Tcl agent '[dict get $opts name]' connecting to $api"
    log "Watching queue: $queue_path"
    log "Saving results under: $results_dir"
    log "LLM model: [dict get $opts model] via [dict get $opts ollama_url] (timeout [dict get $opts ollama_timeout] ms)"
    if {[file isdirectory $tool_dir]} {
        log "Local tool dir: $tool_dir"
    } else {
        log "Warning: tool dir '$tool_dir' not found"
    }

    ensure_remote_dir $client $queue_path
    ensure_remote_dir $client $results_dir

    puts ""
    puts "To enqueue tasks for this agent from agfs-shell:"
    puts "  agfs:/> mkdir -p $queue_path"
    puts "  agfs:/> cat <<'EOF' > $queue_path/enqueue"
    puts "  {\"task\":\"summarize\",\"text\":\"Write a haiku about Tcl agents\"}"
    puts "  EOF"
    puts ""
    puts "Multi-step example:"
    puts "  agfs:/> cat <<'EOF' > $queue_path/enqueue"
    puts {  {
    "task": "research",
    "text": "Analyze why Tcl is useful for agents",
    "steps": [
      {"id": "outline", "prompt": "List the key angles you will cover."},
      {"id": "draft", "prompt": "Write the final summary using the previous outline."}
    ]
  }}
    puts "  EOF"
    puts ""

    set idle_cycles 0
    while {1} {
        set task_dict [fetch_task $client $queue_path]
        if {$task_dict eq ""} {
            if {$idle_cycles == 0} {
                log "Queue empty, waiting..."
            }
            incr idle_cycles
            after $interval_ms
            continue
        }

        set idle_cycles 0
        set task_id [dict_get_default $task_dict id "unknown"]
        log "Dequeued task $task_id"

        if {[catch {handle_task $client $opts $task_dict} err]} {
            log "✗ Failed to process $task_id: $err"
        }

        after 100
    }
}

if {[info exists argv0] && [string match "*agent_task_loop.tcl" $argv0]} {
    main
}
