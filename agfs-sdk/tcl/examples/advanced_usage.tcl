#!/usr/bin/env tclsh
# Advanced usage examples for AGFS Tcl SDK

set auto_path [linsert $auto_path 0 [file dirname [file dirname [file normalize [info script]]]]]

package require agfs

puts "AGFS Tcl SDK - Advanced Usage Examples"
puts [string repeat "=" 60]

# Initialize client
set client [agfs::AGFSClient -api_base "http://localhost:8080" -timeout 30]

# Example 1: Batch file processing
puts "\n1. Batch File Processing:"
puts "   Creating test files..."

set test_dir "/batch_processing"
$client mkdir $test_dir

# Create multiple test files
for {set i 1} {$i <= 5} {incr i} {
    set file "$test_dir/data_$i.txt"
    set content "Data file $i\nLine 1\nLine 2\nLine 3\n"
    $client write $file $content
}

# Process all files
set files [$client ls $test_dir]
set total_lines 0

foreach file $files {
    if {![dict get $file isDir]} {
        set path "[dict get $file path]/[dict get $file name]"
        set content [$client cat $path]
        set num_lines [llength [split $content "\n"]]
        incr total_lines $num_lines
    }
}

puts "   Processed [llength $files] files"
puts "   Total lines: $total_lines"

# Example 2: Error handling
puts "\n2. Error Handling Example:"

set safe_file "$test_dir/safe_file.txt"
$client write $safe_file "Safe content"

# Try to read non-existent file
if {[catch {
    $client cat "/nonexistent.txt"
    puts "   ✗ Should have failed"
} err]} {
    puts "   ✓ Caught expected error: $err"
}

# Example 3: Working with directory trees
puts "\n3. Directory Tree Operations:"

set project_dir "/my_project"
$client mkdir $project_dir

set src_dir "$project_dir/src"
set tests_dir "$project_dir/tests"
$client mkdir $src_dir
$client mkdir $tests_dir

# Create source files
$client write "$src_dir/main.tcl" "# Main application\nputs 'Hello World'"
$client write "$src_dir/utils.tcl" "# Utilities\nproc util_func {} { return 42 }"

# Create test files
$client write "$tests_dir/test_main.tcl" "# Tests\npackage require tcltest\ntest main-exists {Main should exist} {} {"

puts "   Created project structure"
puts "   Source files: [$client ls $src_dir | llength]"
puts "   Test files: [$client ls $tests_dir | llength]"

# Example 4: Streaming and large file handling
puts "\n4. Large File Operations:"

set large_file "$project_dir/large_data.txt"
set chunk_size 1000
set total_size [expr {$chunk_size * 100}]

puts "   Creating [format %.1f [expr {$total_size / 1024.0}]]KB test file..."

# Create a large file
set large_content ""
for {set i 0} {$i < 100} {incr i} {
    append large_content "Line $i: [string repeat X $chunk_size]\n"
}

$client write $large_file $large_content

# Verify file size
set info [$client stat $large_file]
puts "   ✓ File created: [dict get $info size] bytes"

# Example 5: Working with configuration
puts "\n5. Configuration Management:"

set config_dir "$project_dir/config"
$client mkdir $config_dir

# Create config file
set config_file "$config_dir/app.conf"
set config_content {
# Application Configuration
app_name = "MyApp"
version = "1.0.0"
debug = true
port = 8080
}

$client write $config_file $config_content

# Parse config (simple parsing)
set config_data [$client cat $config_file]
puts "   Configuration loaded:"
foreach line [split $config_data "\n"] {
    set line [string trim $line]
    if {$line != "" && ![string match "#*" $line]} {
        puts "     $line"
    }
}

# Example 6: Backup and restore
puts "\n6. Backup Operations:"

set backup_dir "/backups/[clock format [clock seconds] -format %Y%m%d_%H%M%S]"
$client mkdir $backup_dir

# Copy important files to backup
foreach file_path {"$config_file" "$src_dir"} {
    set filename [file tail $file_path]
    agfs::cp $client $file_path "$backup_dir/$filename"
    puts "   Backed up: $filename"
}

# Example 7: Searching with grep
puts "\n7. File Search:"

set log_dir "$project_dir/logs"
$client mkdir $log_dir

# Create log files with different messages
$client write "$log_dir/app.log" "2024-01-01 INFO: Starting application\n2024-01-01 ERROR: Database connection failed\n2024-01-01 INFO: Retrying..."
$client write "$log_dir/debug.log" "2024-01-01 DEBUG: Memory usage: 50MB\n2024-01-01 ERROR: Invalid configuration\n2024-01-01 DEBUG: Cache cleared"

# Search for errors (requires grep support on server)
if {[catch {
    set results [$client grep $log_dir "ERROR" -recursive true]
    puts "   Found errors:"
    foreach result $results {
        puts "     [dict get $result file]: [dict get $result content]"
    }
} err]} {
    puts "   Grep not available or no matches: $err"
}

# Example 8: Calculate checksums
puts "\n8. File Integrity:"

set checksum_file "$project_dir/important.txt"
$client write $checksum_file "Important data that needs verification"

if {[catch {
    set digest [$client digest $checksum_file "md5"]
    puts "   File: $checksum_file"
    puts "   MD5: [dict get $digest digest]"
} err]} {
    puts "   Digest calculation not available: $err"
}

# Example 9: Memory-efficient processing
puts "\n9. Memory-Efficient Processing:"

set data_file "$project_dir/big_data.txt"
set fp [open "/tmp/big_input.txt" w]
for {set i 0} {$i < 1000} {incr i} {
    puts $fp "Record $i: Some data here"
}
close $fp

agfs::upload $client "/tmp/big_input.txt" $data_file -stream true
puts "   Uploaded large file with streaming"

# Process line by line (simulated)
set content [$client cat $data_file]
set record_count [llength [split $content "\n"]]
puts "   Processed $record_count records"

# Example 10: Plugin management
puts "\n10. Plugin Management:"

if {[catch {
    set plugins [$client list_plugins]
    puts "   Loaded plugins: $plugins"
} err]} {
    puts "   Plugin management not available: $err"
}

# Summary
puts "\n" [string repeat = 60]
puts "Advanced Examples Completed!"

# Cleanup
puts "\nCleanup:"
$client rm $project_dir -recursive true
catch { file delete "/tmp/big_input.txt" }
puts "   Test data cleaned up"
