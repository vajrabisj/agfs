#!/usr/bin/env tclsh
package require Tcl 9.0

# Ensure json::write is available (fallback implementation if Tcllib json is missing)
catch {package require json}
if {[catch {package require json::write}] || ![llength [info commands ::json::write]]} {
    namespace eval ::json {
        proc _escape_string {text} {
            set result ""
            foreach char [split $text ""] {
                scan $char %c code
                switch -- $char {
                    "\"" { append result "\\\"" }
                    "\\" { append result "\\\\" }
                    "\b" { append result "\\b" }
                    "\f" { append result "\\f" }
                    "\n" { append result "\\n" }
                    "\r" { append result "\\r" }
                    "\t" { append result "\\t" }
                    default {
                        if {$code < 32} {
                            append result [format "\\u%04X" $code]
                        } else {
                            append result $char
                        }
                    }
                }
            }
            return $result
        }
        proc write {type args} {
            switch -exact -- $type {
                string {
                    set value [lindex $args 0]
                    return "\"[::json::_escape_string $value]\""
                }
                number {
                    return [lindex $args 0]
                }
                boolean {
                    set value [string tolower [lindex $args 0]]
                    if {$value in {1 true yes}} {
                        return "true"
                    }
                    return "false"
                }
                object {
                    set pairs {}
                    foreach {key value} $args {
                        set enc_key "\"[::json::_escape_string $key]\""
                        lappend pairs "$enc_key:$value"
                    }
                    return "\{[join $pairs ,]\}"
                }
                default {
                    error "Unsupported json::write type: $type"
                }
            }
        }
    }
}

namespace eval agfs {
    namespace export AGFSClient
}

proc agfs::AGFSClient {args} {
    variable api_base
    variable session_id
    variable timeout

    # Default values
    set api_base "http://localhost:8080"
    set timeout 10
    set session_id "agfs-[pid]-[clock clicks]"

    # Parse arguments
    foreach {key value} $args {
        switch -exact -- $key {
            -api_base { set api_base $value }
            -timeout { set timeout $value }
        }
    }

    # Ensure API base URL ends with /api/v1
    set api_base [string trimright $api_base "/"]
    if {![string match "*/api/v1" $api_base]} {
        set api_base "$api_base/api/v1"
    }

    # Create the client object
    set client [namespace current]::client_$session_id
    interp alias {} $client {} agfs::ClientProc $session_id
    namespace eval $client {
        variable api_base
        variable timeout
        variable session_id
    }

    # Set variables
    set ${client}::api_base $api_base
    set ${client}::timeout $timeout
    set ${client}::session_id $session_id

    return $client
}

proc agfs::ClientProc {session_id method args} {
    # Get variables from the client namespace
    set client_ns "::agfs::client_$session_id"
    set api_base [set ${client_ns}::api_base]
    set timeout [set ${client_ns}::timeout]

    switch -exact -- $method {
        health { return [agfs::Health $api_base $timeout {*}$args] }
        ls { return [agfs::Ls $api_base $timeout {*}$args] }
        cat { return [agfs::Cat $api_base $timeout {*}$args] }
        read { return [agfs::Cat $api_base $timeout {*}$args] }
        write { return [agfs::Write $api_base {*}$args] }
        create { return [agfs::Create $api_base $timeout {*}$args] }
        mkdir { return [agfs::Mkdir $api_base $timeout {*}$args] }
        rm {
            set path [lindex $args 0]
            set recursive [expr {[lsearch -exact $args "-recursive"] >= 0}]
            return [agfs::Rm $api_base $timeout $path $recursive]
        }
        stat { return [agfs::Stat $api_base $timeout {*}$args] }
        mv { return [agfs::Mv $api_base $timeout {*}$args] }
        chmod { return [agfs::Chmod $api_base $timeout {*}$args] }
        touch { return [agfs::Touch $api_base $timeout {*}$args] }
        mounts { return [agfs::Mounts $api_base $timeout {*}$args] }
        mount { return [agfs::MountPlugin $api_base $timeout {*}$args] }
        unmount { return [agfs::Unmount $api_base $timeout {*}$args] }
        list_plugins { return [agfs::ListPlugins $api_base $timeout {*}$args] }
        load_plugin { return [agfs::LoadPlugin $api_base $timeout {*}$args] }
        unload_plugin { return [agfs::UnloadPlugin $api_base $timeout {*}$args] }
        grep { return [agfs::Grep $api_base {*}$args] }
        digest { return [agfs::Digest $api_base $timeout {*}$args] }
        get_api_base { return [set ${client_ns}::api_base] }
        get_timeout { return [set ${client_ns}::timeout] }
        default {
            error "Unknown method: $method"
        }
    }
}

# Health check
proc agfs::Health {api_base timeout} {
    set url "$api_base/health"
    set response [agfs::HttpRequest GET $url "" "" $timeout]
    # Debug output
    # puts "DEBUG Health - raw response: $response"
    return [agfs::ParseJson $response]
}

# List directory
proc agfs::Ls {api_base timeout {path "/"}} {
    if {$path == ""} { set path "/" }

    set url "$api_base/directories"
    set params [dict create path $path]
    set response [agfs::HttpRequest GET $url $params "" $timeout]

    set data [agfs::ParseJson $response]
    set files [dict get $data files]
    if {$files == ""} {
        return {}
    }
    return $files
}

# Read file
proc agfs::CatBytes {api_base timeout path {offset 0} {size -1}} {
    if {$path == ""} {
        error "Path is required"
    }

    set url "$api_base/files"
    set params [dict create path $path]

    if {$offset > 0} {
        dict set params offset $offset
    }
    if {$size >= 0} {
        dict set params size $size
    }

    return [agfs::HttpRequest GET $url $params "" $timeout [dict create binary_response 1 accept "*/*"]]
}

proc agfs::Cat {api_base timeout path {offset 0} {size -1}} {
    set raw_data [agfs::CatBytes $api_base $timeout $path $offset $size]
    if {[catch {encoding convertfrom utf-8 $raw_data} decoded]} {
        return $raw_data
    }
    return $decoded
}

# Write file
proc agfs::Write {api_base path data} {
    if {$path == ""} {
        error "Path is required"
    }
    if {$data == ""} {
        error "Data is required"
    }

    set url "$api_base/files"
    set params [dict create path $path]

    set response [agfs::HttpRequest PUT $url $params $data "" [dict create content_type "application/octet-stream" accept "application/json"]]
    set result [agfs::ParseJson $response]
    return [dict get $result message]
}

# Create file
proc agfs::Create {api_base timeout path} {
    if {$path == ""} {
        error "Path is required"
    }

    set url "$api_base/files"
    set params [dict create path $path]
    set response [agfs::HttpRequest POST $url $params "" $timeout]

    return [agfs::ParseJson $response]
}

# Create directory
proc agfs::Mkdir {api_base timeout path {mode "755"}} {
    if {$path == ""} {
        error "Path is required"
    }

    set url "$api_base/directories"
    set params [dict create path $path mode $mode]
    set response [agfs::HttpRequest POST $url $params "" $timeout]

    return [agfs::ParseJson $response]
}

# Remove file or directory
proc agfs::Rm {api_base timeout path {recursive false}} {
    if {$path == ""} {
        error "Path is required"
    }

    set url "$api_base/files"
    set params [dict create path $path]
    if {$recursive} {
        dict set params recursive true
    }

    set response [agfs::HttpRequest DELETE $url $params "" $timeout]
    return [agfs::ParseJson $response]
}

# Get file stats
proc agfs::Stat {api_base timeout path} {
    if {$path == ""} {
        error "Path is required"
    }

    set url "$api_base/stat"
    set params [dict create path $path]
    set response [agfs::HttpRequest GET $url $params "" $timeout]

    return [agfs::ParseJson $response]
}

# Move/rename file
proc agfs::Mv {api_base timeout old_path new_path} {
    if {$old_path == "" || $new_path == ""} {
        error "Both old_path and new_path are required"
    }

    set url "$api_base/rename"
    set params [dict create path $old_path]
    set json_data [json::write object newPath [json::write string $new_path]]

    set response [agfs::HttpRequest POST $url $params $json_data $timeout]
    return [agfs::ParseJson $response]
}

# Change permissions
proc agfs::Chmod {api_base timeout path mode} {
    if {$path == "" || $mode == ""} {
        error "Path and mode are required"
    }

    set url "$api_base/chmod"
    set params [dict create path $path]
    set json_data [json::write object mode [json::write number $mode]]

    set response [agfs::HttpRequest POST $url $params $json_data $timeout]
    return [agfs::ParseJson $response]
}

# Touch file
proc agfs::Touch {api_base timeout path} {
    if {$path == ""} {
        error "Path is required"
    }

    set url "$api_base/touch"
    set params [dict create path $path]
    set response [agfs::HttpRequest POST $url $params "" $timeout]

    return [agfs::ParseJson $response]
}

# List mounts
proc agfs::Mounts {api_base timeout} {
    set url "$api_base/mounts"
    set response [agfs::HttpRequest GET $url "" "" $timeout]

    set data [agfs::ParseJson $response]
    return [dict get $data mounts]
}

# Mount plugin
proc agfs::MountPlugin {api_base timeout fstype path config} {
    if {$fstype == "" || $path == "" || $config == ""} {
        error "fstype, path, and config are required"
    }

    set url "$api_base/mount"
    set json_data [agfs::CreateMountJson $fstype $path $config]
    set response [agfs::HttpRequest POST $url "" $json_data $timeout]

    return [agfs::ParseJson $response]
}

# Unmount plugin
proc agfs::Unmount {api_base timeout path} {
    if {$path == ""} {
        error "Path is required"
    }

    set url "$api_base/unmount"
    set json_data [json::write object path [json::write string $path]]
    set response [agfs::HttpRequest POST $url "" $json_data $timeout]

    return [agfs::ParseJson $response]
}

# List loaded plugins
proc agfs::ListPlugins {api_base timeout} {
    set url "$api_base/plugins"
    set response [agfs::HttpRequest GET $url "" "" $timeout]

    set data [agfs::ParseJson $response]
    return [dict get $data loaded_plugins]
}

# Load plugin
proc agfs::LoadPlugin {api_base timeout library_path} {
    if {$library_path == ""} {
        error "library_path is required"
    }

    set url "$api_base/plugins/load"
    set json_data [json::write object library_path [json::write string $library_path]]
    set response [agfs::HttpRequest POST $url "" $json_data $timeout]

    return [agfs::ParseJson $response]
}

# Unload plugin
proc agfs::UnloadPlugin {api_base timeout library_path} {
    if {$library_path == ""} {
        error "library_path is required"
    }

    set url "$api_base/plugins/unload"
    set json_data [json::write object library_path [json::write string $library_path]]
    set response [agfs::HttpRequest POST $url "" $json_data $timeout]

    return [agfs::ParseJson $response]
}

# Grep search
proc agfs::Grep {api_base path pattern {recursive false} {case_insensitive false}} {
    if {$path == "" || $pattern == ""} {
        error "path and pattern are required"
    }

    set url "$api_base/grep"
    set json_data [agfs::CreateGrepJson $path $pattern $recursive $case_insensitive]
    set response [agfs::HttpRequest POST $url "" $json_data ""]

    return [agfs::ParseJson $response]
}

# Calculate digest
proc agfs::Digest {api_base timeout path {algorithm "xxh3"}} {
    if {$path == ""} {
        error "Path is required"
    }

    set url "$api_base/digest"
    set json_data [json::write object path [json::write string $path] algorithm [json::write string $algorithm]]
    set response [agfs::HttpRequest POST $url "" $json_data $timeout]

    return [agfs::ParseJson $response]
}

# Simple URL encoding
proc agfs::UrlEncode {text} {
    set encoded ""
    foreach char [split $text ""] {
        scan $char %c ascii
        if {($ascii >= 65 && $ascii <= 90) || \
            ($ascii >= 97 && $ascii <= 122) || \
            ($ascii >= 48 && $ascii <= 57) || \
            $char eq "-" || $char eq "_" || $char eq "." || $char eq "~"} {
            append encoded $char
        } else {
            append encoded [format "%%%02X" $ascii]
        }
    }
    return $encoded
}

# HTTP request helper
proc agfs::HttpRequest {method url params data timeout {options ""}} {
    # Build full URL
    if {$params != ""} {
        append url "?"
        set query_parts {}
        dict for {key value} $params {
            lappend query_parts "[agfs::UrlEncode $key]=[agfs::UrlEncode $value]"
        }
        append url [join $query_parts "&"]
    }

    # Parse options
    set binary_response 0
    set accept_header "application/json"
    set content_type ""
    if {$options ne ""} {
        dict for {key value} $options {
            switch -exact -- $key {
                binary_response { set binary_response $value }
                accept { set accept_header $value }
                content_type { set content_type $value }
            }
        }
    }
    if {$accept_header eq ""} {
        set accept_header "*/*"
    }

    # Prepare headers
    set headers [list Accept $accept_header]
    if {$data ne "" || $content_type ne ""} {
        if {$content_type eq ""} {
            set content_type "application/json"
        }
        lappend headers Content-Type $content_type
    }

    set request_type "application/json"
    if {$content_type ne ""} {
        set request_type $content_type
    }

    # Execute HTTP request, only set timeout when provided
    set http_args [list \
        -method $method \
        -headers $headers \
        -type $request_type]
    if {$timeout ne ""} {
        lappend http_args -timeout $timeout
    }
    if {$data ne ""} {
        lappend http_args -query $data
    }
    if {$binary_response} {
        lappend http_args -binary true
    }
    set token [::http::geturl $url {*}$http_args]

    # Get status and response body
    set status [::http::status $token]
    set ncode [::http::ncode $token]
    set response [::http::data $token]
    if {!$binary_response && [string is list $response] && [llength $response] == 2} {
        # It's a binary encoding list: {encoding data}
        set response [encoding convertfrom utf-8 [lindex $response 1]]
    }

    if {$status == "ok" && $ncode >= 200 && $ncode < 300} {
        ::http::cleanup $token
        return $response
    } else {
        set extra_msg ""
        set response_text $response
        if {$binary_response} {
            if {[catch {set response_text [encoding convertfrom utf-8 $response]}]} {
                set response_text ""
            }
        }
        set trimmed_response [string trim $response_text]
        if {$trimmed_response ne ""} {
            # Try to parse JSON error payloads for friendly messages
            catch { package require json }
            if {[catch {set error_data [::json::json2dict $trimmed_response]}]} {
                set extra_msg $trimmed_response
            } else {
                set error_dict [dict create {*}$error_data]
                if {[dict exists $error_dict error]} {
                    set extra_msg [dict get $error_dict error]
                } elseif {[dict exists $error_dict message]} {
                    set extra_msg [dict get $error_dict message]
                } else {
                    set extra_msg $trimmed_response
                }
            }
        } elseif {$status != "ok"} {
            set extra_msg $status
        }

        if {$extra_msg ne ""} {
            set error_msg "HTTP Error $ncode: $extra_msg"
        } else {
            set error_msg "HTTP Error $ncode"
        }

        ::http::cleanup $token
        error $error_msg
    }
}

# JSON parsing
proc agfs::ParseJson {json_text} {
    # Ensure we have a string
    set json_str $json_text
    if {[string is list $json_str] && [llength $json_str] == 2} {
        set json_str [encoding convertfrom utf-8 [lindex $json_str 1]]
    }

    # Ensure json package is loaded
    catch { package require json }

    # Try to parse
    set kv_list [::json::json2dict $json_str]
    # Convert key-value list to proper Tcl dictionary
    set dict_result [dict create {*}$kv_list]
    return $dict_result
}

# Create mount JSON
proc agfs::CreateMountJson {fstype path config} {
    set config_parts {}
    dict for {key value} $config {
        lappend config_parts [json::write string $key] [json::write string $value]
    }
    set config_obj [json::write object {*}$config_parts]

    return [json::write object \
        fstype [json::write string $fstype] \
        path [json::write string $path] \
        config $config_obj]
}

# Create grep JSON
proc agfs::CreateGrepJson {path pattern recursive case_insensitive} {
    set recursive_val [expr {$recursive ? "true" : "false"}]
    set case_insensitive_val [expr {$case_insensitive ? "true" : "false"}]

    return [json::write object \
        path [json::write string $path] \
        pattern [json::write string $pattern] \
        recursive [json::write boolean $recursive_val] \
        case_insensitive [json::write boolean $case_insensitive_val]]
}
