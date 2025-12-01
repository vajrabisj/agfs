#!/usr/bin/env tclsh
# Basic test script for AGFS Tcl SDK

# Add the current directory to the auto path
set auto_path [linsert $auto_path 0 [file dirname [file normalize [info script]]]]

package require agfs
package require json

proc dict_get_default {dict_value key default} {
    if {[dict exists $dict_value $key]} {
        return [dict get $dict_value $key]
    }
    return $default
}

proc normalize_test_base {value} {
    set base $value
    if {$base eq ""} {
        set base "/memfs"
    }
    if {[string index $base 0] ne "/"} {
        set base "/$base"
    }
    return [string trimright $base "/"]
}

proc find_writable_base {client preferred_base} {
    set candidates {}
    if {$preferred_base ne ""} {
        lappend candidates $preferred_base
    }
    foreach fallback {/memfs /local/tmp /local /tmp /} {
        if {[lsearch -exact $candidates $fallback] < 0} {
            lappend candidates $fallback
        }
    }
    # Add dynamic mounts from root listing
    if {![catch {set root_entries [$client ls "/"]} root_err]} {
        foreach entry $root_entries {
            if {[dict exists $entry name]} {
                set candidate "/[dict get $entry name]"
                if {[lsearch -exact $candidates $candidate] < 0} {
                    lappend candidates $candidate
                }
            }
        }
    }

    set probe_id [clock clicks]
    set last_error ""
    foreach base $candidates {
        set candidate [string trimright $base "/"]
        if {$candidate eq ""} {
            continue
        }
        set probe "$candidate/.tcl_sdk_probe_$probe_id"
        if {[catch {$client mkdir $probe} errMsg]} {
            if {[string match -nocase "*already exists*" $errMsg]} {
                return $candidate
            }
            if {[string match -nocase "*not found*" $errMsg]} {
                continue
            }
            set last_error $errMsg
            continue
        }
        catch {$client rm $probe -recursive true}
        return $candidate
    }
    if {$last_error ne ""} {
        error "Unable to find writable base. Last error: $last_error"
    }
    error "Unable to find writable base. Tried: [join $candidates {, }]"
}

puts "AGFS Tcl SDK Test - Version: [agfs::version]"
puts [string repeat "=" 60]

# Configuration
set api_url "http://localhost:8080"
set preferred_base ""
if {[info exists ::env(AGFS_TEST_BASE)]} {
    set preferred_base $::env(AGFS_TEST_BASE)
}
set preferred_base [normalize_test_base $preferred_base]
set test_base ""
set test_dir ""
set test_file ""

puts "\nConfiguration:"
puts "  API URL: $api_url"
puts "  Preferred base: $preferred_base"
puts ""

# Initialize client
puts "1. Creating AGFS client..."
if {[catch {
    set client [agfs::AGFSClient -api_base $api_url -timeout 10]
    puts "   ✓ Client created successfully"
    puts "   API Base: [$client get_api_base]"
    puts "   Timeout: [$client get_timeout]s"
} err]} {
    puts "   ✗ Failed to create client: $err"
    puts "   Make sure AGFS server is running at $api_url"
    exit 1
}


# Test server health
puts "\n2. Checking server health..."
if {[catch {
    set health [$client health]
    puts "   ✓ Server is running"
    puts "   Version: [dict get $health version]"
} err]} {
    puts "   ✗ Health check failed: $err"
    exit 1
}

if {[catch {
    set test_base [find_writable_base $client $preferred_base]
} err]} {
    puts "   ✗ Failed to determine writable base: $err"
    puts "   请设置 AGFS_TEST_BASE 为可写挂载点 (例如 /local)"
    exit 1
}
set test_dir "$test_base/test_tcl_agfs"
set test_file "$test_dir/test.txt"
puts "\nResolved Test Paths:"
puts "  Test base: $test_base"
puts "  Test directory: $test_dir"
puts ""

# List root directory
puts "\n3. Listing root directory..."
if {[catch {
    set files [$client ls /]
    puts "   Found [llength $files] items:"
    foreach file $files {
        if {![dict exists $file name]} {
            continue
        }
        set name [dict get $file name]
        set is_dir [expr {[dict exists $file isDir] ? [dict get $file isDir] : 0}]
        set type [expr {$is_dir ? "DIR" : "FILE"}]
        puts "     \[$type\] $name"
    }
} err]} {
    puts "   ✗ Failed to list directory: $err"
}

# Create test directory
puts "\n4. Creating test directory..."
if {[catch {
    $client mkdir $test_dir
    puts "   ✓ Directory created: $test_dir"
} err]} {
    puts "   ✗ Failed to create directory: $err"
}

# Write test file
puts "\n5. Writing test file..."
if {[catch {
    set content "Hello from AGFS Tcl SDK!\nTest at [clock format [clock seconds]]\n"
    $client write $test_file $content
    puts "   ✓ File written: $test_file"
    puts "   Content length: [string length $content] bytes"
} err]} {
    puts "   ✗ Failed to write file: $err"
}

# Read test file
puts "\n6. Reading test file..."
if {[catch {
    set data [$client cat $test_file]
    puts "   ✓ File read successfully"
    puts "   Content:"
    foreach line [split $data "\n"] {
        if {$line != ""} {
            puts "     $line"
        }
    }
} err]} {
    puts "   ✗ Failed to read file: $err"
}

# Get file stats
puts "\n7. Getting file stats..."
if {[catch {
    set info [$client stat $test_file]
    puts "   ✓ File information:"
    set info_path [dict_get_default $info path $test_file]
    set info_size [dict_get_default $info size "unknown"]
    set info_mode [dict_get_default $info mode "unknown"]
    set info_isdir [dict_get_default $info isDir 0]
    puts "     Path: $info_path"
    puts "     Size: $info_size bytes"
    puts "     Mode: $info_mode"
    puts "     Is Directory: $info_isdir"
} err]} {
    puts "   ✗ Failed to get stats: $err"
}

# List test directory
puts "\n8. Listing test directory..."
if {[catch {
    set files [$client ls $test_dir]
    puts "   Found [llength $files] items:"
    foreach file $files {
        if {![dict exists $file name]} {
            continue
        }
        set name [dict get $file name]
        set size "?"
        if {[dict exists $file size]} {
            set size [dict get $file size]
        }
        puts "     FILE $name ($size bytes)"
    }
} err]} {
    puts "   ✗ Failed to list directory: $err"
}

# Rename file
puts "\n9. Renaming file..."
set rename_success 0
if {[catch {
    set new_file "$test_dir/renamed.txt"
    $client mv $test_file $new_file
    puts "   ✓ File renamed to: $new_file"
    set test_file $new_file
    set rename_success 1
} err]} {
    puts "   ✗ Failed to rename: $err"
}

# Test helper functions
puts "\n10. Testing helper functions..."
if {[catch {
    # Upload test (local file upload)
    set local_test "/tmp/test_local_$$.txt"
    set fp [open $local_test wb]
    fconfigure $fp -translation binary -encoding iso8859-1
    puts $fp "This is a local test file"
    close $fp

    puts "   Uploading local file..."
    agfs::upload $client $local_test "$test_dir/uploaded.txt"
    puts "   ✓ File uploaded to: $test_dir/uploaded.txt"

    # Download test
    puts "   Downloading file back..."
    set downloaded "/tmp/downloaded_$$.txt"
    agfs::download $client "$test_dir/uploaded.txt" $downloaded

    if {[file exists $downloaded]} {
        set fp [open $downloaded rb]
        fconfigure $fp -translation binary -encoding iso8859-1
        set content [read $fp]
        close $fp
        puts "   ✓ File downloaded successfully"
        puts "     Content: [string trim $content]"
        file delete $downloaded
    }

    # Clean up
    file delete $local_test
} err]} {
    puts "   ✗ Helper function test failed: $err"
}

# Test cp function
puts "\n11. Testing cp function..."
if {$rename_success} {
    if {[catch {
        agfs::cp $client "$test_dir/renamed.txt" "$test_dir/copied.txt"
        puts "   ✓ File copied to: $test_dir/copied.txt"
    } err]} {
        puts "   ✗ cp function failed: $err"
    }
} else {
    puts "   - Skipping cp test because rename failed"
}

# List mounts
puts "\n12. Listing mounted filesystems..."
if {[catch {
    set mounts [$client mounts]
    puts "   Found [llength $mounts] mounted filesystems:"
    foreach mount $mounts {
        set mount_name "<unknown>"
        if {[dict exists $mount name]} {
            set mount_name [dict get $mount name]
        }
        set mount_path "<unknown>"
        if {[dict exists $mount path]} {
            set mount_path [dict get $mount path]
        }
        if {$mount_name eq "<unknown>" && $mount_path ne "<unknown>"} {
            set mount_name [file tail $mount_path]
        }
        puts "     $mount_name at $mount_path"
    }
} err]} {
    puts "   ✗ Failed to list mounts: $err"
}

# Clean up
puts "\n13. Cleaning up..."
if {[catch {
    $client rm $test_dir -recursive true
    puts "   ✓ Test directory removed"
} err]} {
    puts "   ✗ Failed to clean up: $err"
}

puts ""
puts [string repeat "=" 60]
puts "All tests completed!"
