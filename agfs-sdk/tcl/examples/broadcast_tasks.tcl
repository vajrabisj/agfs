#!/usr/bin/env tclsh
# Broadcast a research/analysis task to multiple agent queues (similar to
# agfs-mcp/demos/parallel_research.py but implemented in Tcl).

package require Tcl 9.0

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file dirname [file dirname $script_dir]]
set auto_path [linsert $auto_path 0 $repo_root]
if {[info exists ::tcllibpath]} {
    set ::tcllibpath [linsert $::tcllibpath 0 $repo_root]
} else {
    set ::tcllibpath [list $repo_root]
}

package require agfs
package require json

proc usage {} {
    puts "Usage: tclsh examples/broadcast_tasks.tcl ?options?"
    puts "Options:"
    puts "  -api_base URL          AGFS API base (default: http://localhost:8080)"
    puts "  -queue_prefix PATH     QueueFS prefix (default: /queuefs/agent)"
    puts "  -agents name1,name2    Comma-separated agent names (required)"
    puts "  -task TEXT             Task description (mutually exclusive with -task_file)"
    puts "  -task_file PATH        File containing the task description"
    puts "  -results_root PATH     Where agents should store results (hint for payload)"
    puts "  -help                  Show this help"
    exit 1
}

proc parse_args {argv} {
    array set opts {
        -api_base "http://localhost:8080"
        -queue_prefix "/queuefs/agent"
        -agents ""
        -task ""
        -task_file ""
        -results_root "/local/broadcast"
    }
    for {set i 0} {$i < [llength $argv]} {incr i} {
        set key [lindex $argv $i]
        switch -- $key {
            -api_base - -queue_prefix - -agents - -task - -task_file - -results_root {
                if {$i == [expr {[llength $argv]-1}]} {
                    error "Missing value for $key"
                }
                set opts($key) [lindex $argv [incr i]]
            }
            -help { usage }
            default { error "Unknown option: $key (use -help)" }
        }
    }
    if {$opts(-agents) eq ""} {
        error "No agents specified. Use -agents name1,name2"
    }
    if {$opts(-task) eq "" && $opts(-task_file) eq ""} {
        error "Provide -task or -task_file"
    }
    if {$opts(-task) ne "" && $opts(-task_file) ne ""} {
        error "-task and -task_file cannot be used together"
    }
    set task_text $opts(-task)
    if {$task_text eq ""} {
        set path [file normalize $opts(-task_file)]
        if {![file exists $path]} {
            error "Task file not found: $path"
        }
        set fh [open $path r]
        set task_text [read $fh]
        close $fh
    }
    dict set result api_base $opts(-api_base)
    dict set result queue_prefix $opts(-queue_prefix)
    dict set result agents [split $opts(-agents) ","]
    dict set result task_text [string trim $task_text]
    dict set result results_root $opts(-results_root)
    return $result
}

proc generate_task_id {} {
    set seconds [clock seconds]
    set clicks [clock clicks]
    return [format "task-%d-%x" $seconds $clicks]
}

proc ensure_queue {client queue_path} {
    if {[catch {$client mkdir $queue_path} err]} {
        if {![string match -nocase "*exists*" $err]} {
            puts "Warning: unable to mkdir $queue_path: $err"
        }
    }
}

proc main {} {
    if {[catch {set opts [parse_args $::argv]} err]} {
        puts "Error: $err"
        usage
    }

    set api [dict get $opts api_base]
    set queue_prefix [string trimright [dict get $opts queue_prefix] "/"]
    set agents [dict get $opts agents]
    set task_text [dict get $opts task_text]
    set results_root [dict get $opts results_root]

    set client [agfs::AGFSClient -api_base $api]

    set root_task_id [generate_task_id]
    puts "Broadcasting task $root_task_id to [llength $agents] agents..."

    set payloads {}
    foreach agent_raw $agents {
        set agent [string trim $agent_raw]
        if {$agent eq ""} continue
        set queue_path "$queue_prefix/$agent"
        ensure_queue $client $queue_path

        set agent_task_id "${root_task_id}-$agent"
        set result_dir "$results_root/$root_task_id/$agent"

        set payload [json::write object \
            task_id [json::write string $agent_task_id] \
            parent_task [json::write string $root_task_id] \
            agent [json::write string $agent] \
            description [json::write string $task_text] \
            result_dir [json::write string $result_dir]]

        if {[catch {
            $client write "$queue_path/enqueue" $payload
        } err]} {
            puts "✗ Failed to enqueue for $agent: $err"
        } else {
            puts "✓ Queued task for $agent at $queue_path"
            lappend payloads [list agent $agent queue $queue_path payload $payload]
        }
    }

    puts ""
    puts "Summary:"
    foreach item $payloads {
        set agent [dict get $item agent]
        set queue [dict get $item queue]
        puts "  - $agent <- $queue"
    }
    puts "Task description:"
    puts "-----------------"
    puts $task_text
    puts "-----------------"
}

main
