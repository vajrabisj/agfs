#!/usr/bin/env tclsh
#
# Tcl implementation of the simpcurlfs ➜ summaryfs pipeline.

package require http

namespace eval ::agfs {
    variable default_api_base "http://localhost:8080/api/v1"
}

proc ::agfs::env_or_default {name default} {
    if {[info exists ::env($name)] && [string length [string trim $::env($name)]]} {
        return $::env($name)
    }
    return $default
}

proc ::agfs::env_int {name default} {
    set val [env_or_default $name ""]
    if {$val eq ""} { return $default }
    if {![regexp {^-?\d+$} $val]} {
        return $default
    }
    return $val
}

proc ::agfs::env_bool {name default} {
    set val [env_or_default $name ""]
    if {$val eq ""} { return $default }
    set lowered [string tolower [string trim $val]]
    return [expr {$lowered in {"1" "true" "yes" "on"}}]
}

proc ::agfs::json_escape {text} {
    set result ""
    set utf [encoding convertto utf-8 $text]
    binary scan $utf cu* codes
    foreach code $codes {
        if {$code < 0} { set code [expr {$code + 256}] }
        switch -- $code {
            8 { append result "\\b" }
            9 { append result "\\t" }
            10 { append result "\\n" }
            12 { append result "\\f" }
            13 { append result "\\r" }
            34 { append result "\\\"" }
            47 { append result "/" }
            92 { append result "\\\\" }
            default {
                if {$code < 32} {
                    append result [format "\\u%04x" $code]
                } else {
                    append result [format "%c" $code]
                }
            }
        }
    }
    return $result
}

proc ::agfs::url_encode {text} {
    set bytes [encoding convertto utf-8 $text]
    binary scan $bytes cu* codes
    set result ""
    foreach code $codes {
        if {$code < 0} { set code [expr {$code + 256}] }
        if {($code >= 48 && $code <= 57) || ($code >= 65 && $code <= 90) || ($code >= 97 && $code <= 122) || $code in {45 95 46 126} || $code == 47} {
            append result [format "%c" $code]
        } else {
            append result %[string toupper [format "%02x" $code]]
        }
    }
    return $result
}

proc ::agfs::http_request {method url {content_type ""} {body ""}} {
    set opts [list -method $method -timeout 120000]
    if {$body ne ""} {
        lappend opts -query $body
    }
    if {$content_type ne ""} {
        lappend opts -headers [list Content-Type $content_type]
        lappend opts -type $content_type
    }
    set token [eval [list ::http::geturl $url] $opts]
    set code [::http::ncode $token]
    set status [::http::status $token]
    set data [::http::data $token]
    set err ""
    if {$status ne "ok"} {
        set err [::http::error $token]
    }
    ::http::cleanup $token
    return [list $code $data $err]
}

proc ::agfs::put_file {api_base path body content_type} {
    set url "${api_base}/files?path=[url_encode $path]"
    lassign [http_request "PUT" $url $content_type $body] code _ err
    if {$code < 200 || $code >= 300} {
        error "PUT $path failed (HTTP $code): $err"
    }
}

proc ::agfs::get_file {api_base path} {
    set url "${api_base}/files?path=[url_encode $path]"
    lassign [http_request "GET" $url "" ""] code data err
    if {$code >= 200 && $code < 300} {
        return [list true $data]
    }
    return [list false $err]
}

proc ::agfs::poll_file {api_base path attempts delay_seconds} {
    for {set i 1} {$i <= $attempts} {incr i} {
        lassign [get_file $api_base $path] ok payload
        if {$ok && [string length $payload]} {
            return $payload
        }
        after [expr {int($delay_seconds * 1000)}]
    }
    error "Timed out waiting for $path after $attempts attempts"
}

proc ::agfs::build_search_payload {query max_results} {
    set q [json_escape $query]
    return [format "{\"query\":\"%s\",\"max_results\":%d}" $q $max_results]
}

proc ::agfs::build_summary_payload {text format} {
    set escaped_text [json_escape $text]
    set escaped_format [json_escape $format]
    return [format "{\"text\":\"%s\",\"format\":\"%s\"}" $escaped_text $escaped_format]
}

proc ::agfs::main {} {
    variable default_api_base

    ::http::config -useragent "agfs-tcl-client/0.1"

    set api_base [env_or_default "AGFS_API_BASE" $default_api_base]
    set max_results [env_int "AGFS_MAX_RESULTS" 2]
    set summary_format [env_or_default "AGFS_SUMMARY_FORMAT" "bullet list"]
    set poll_attempts [env_int "AGFS_POLL_ATTEMPTS" 30]
    set poll_delay [env_int "AGFS_POLL_DELAY" 2]
    set print_search [env_bool "AGFS_PRINT_SEARCH" 1]

    if {[llength $::argv] > 0} {
        set query [join $::argv " "]
    } else {
        set query "llm agents in 2025"
    }

    puts {[1/4] Sending query to simpcurlfs...}
    set search_payload [build_search_payload $query $max_results]
    put_file $api_base "/web/request" $search_payload "application/json"

    puts {[2/4] Waiting for /web/response.txt...}
    set web_response [poll_file $api_base "/web/response.txt" $poll_attempts $poll_delay]

    puts {[3/4] Sending text to summaryfs...}
    set summary_payload [build_summary_payload $web_response $summary_format]
    put_file $api_base "/summary/request" $summary_payload "application/json"

    puts {[4/4] Waiting for /summary/response.txt...}
    set summary_response [poll_file $api_base "/summary/response.txt" $poll_attempts $poll_delay]

    if {$print_search} {
        puts ""
        puts "====== SimpcurlFS Result ======"
        puts $web_response
    }

    puts ""
    puts "====== SummaryFS Result ======"
    puts $summary_response
}

if {[info exists argv0] && [string match "*run_search_and_summary.tcl" $argv0]} {
    if {[catch {::agfs::main} err opts]} {
        puts stderr "Error: $err"
        if {[dict exists $opts -errorinfo]} {
            puts stderr [dict get $opts -errorinfo]
        }
        exit 1
    }
} else {
    ::agfs::main
}
