#!/usr/bin/env tclsh
# Basic usage example for AGFS Tcl SDK

# Add SDK to path
set auto_path [linsert $auto_path 0 [file dirname [file dirname [file normalize [info script]]]]]

package require agfs

puts "AGFS Tcl SDK - Basic Usage Example"
puts [string repeat "=" 60]

# Initialize the client
set client [agfs::AGFSClient -api_base "http://localhost:8080"]

# Example 1: Check server health
puts "\n1. Check server health:"
set health [$client health]
puts "   Server version: [dict get $health version]"

# Example 2: List directory contents
puts "\n2. List root directory:"
set files [$client ls /]
foreach file $files {
    set type [expr {[dict get $file isDir] ? "DIR" : "FILE"}]
    puts "   \[$type\] [dict get $file name]"
}

# Example 3: Create a directory
puts "\n3. Create a directory:"
set test_dir "/my_project"
$client mkdir $test_dir
puts "   Created: $test_dir"

# Example 4: Write a file
puts "\n4. Write a file:"
set test_file "$test_dir/README.txt"
set content "# My Project\n\nThis project uses AGFS Tcl SDK.\n"
$client write $test_file $content
puts "   Written: $test_file"

# Example 5: Read a file
puts "\n5. Read a file:"
set data [$client cat $test_file]
puts "   Content:"
puts "   ---"
puts $data
puts "   ---"

# Example 6: Get file information
puts "\n6. Get file information:"
set info [$client stat $test_file]
puts "   Path: [dict get $info path]"
puts "   Size: [dict get $info size] bytes"
puts "   Modified: [dict get $info modified]"

# Example 7: Upload a local file
puts "\n7. Upload local file:"
set local_file "/tmp/local_data.txt"
set fp [open $local_file w]
puts $fp "Local file content"
close $fp

set remote_file "$test_dir/uploaded.txt"
agfs::upload $client $local_file $remote_file
puts "   Uploaded: $local_file -> $remote_file"

# Example 8: Download a remote file
puts "\n8. Download remote file:"
set downloaded_file "/tmp/downloaded.txt"
agfs::download $client $remote_file $downloaded_file
puts "   Downloaded: $remote_file -> $downloaded_file"

# Example 9: Copy files within AGFS
puts "\n9. Copy file within AGFS:"
set copied_file "$test_dir/README_copy.txt"
agfs::cp $client $test_file $copied_file
puts "   Copied: $test_file -> $copied_file"

# Example 10: List mounts
puts "\n10. List mounted filesystems:"
set mounts [$client mounts]
foreach mount $mounts {
    puts "   Mount: [dict get $mount name]"
    puts "     Path: [dict get $mount path]"
    puts "     Type: [dict get $mount type]"
}

# Example 11: Use in a script
puts "\n11. Using in a Tcl script:"
puts "   Processing data..."

set data_file "$test_dir/data.txt"
$client write $data_file "Line 1\nLine 2\nLine 3\n"

set content [$client cat $data_file]
set lines [split $content "\n"]
puts "   Found [expr {[llength $lines] - 1}] lines"

# Clean up
puts "\n12. Cleanup:"
$client rm $test_dir -recursive true
puts "   Removed: $test_dir"

file delete $local_file
file delete $downloaded_file

puts "\n" [string repeat = 60]
puts "Example completed successfully!"
