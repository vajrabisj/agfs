#!/usr/bin/env tclsh9.0
set auto_path [linsert $auto_path 0 /opt/homebrew/Cellar/tcl-tk/9.0.2/lib/tcllib2.0]
set auto_path [linsert $auto_path 0 /opt/homebrew/Cellar/tcl-tk/9.0.2/lib/tcllibc2.0]
set auto_path [linsert $auto_path 0 [file dirname [file normalize [info script]]]]

package require agfs

puts "Testing AGFS Shell..."

set client [agfs::AGFSClient -api_base "http://localhost:8080"]
puts "✓ Client created"

# Test basic commands
puts "\n1. Testing help command:"
cmd_help

puts "\n2. Testing pwd command:"
cmd_pwd

puts "\n3. Testing ls command:"
cmd_ls

puts "\n4. Testing mkdir:"
cmd_mkdir test_dir

puts "\n5. Testing ls test_dir:"
cmd_ls test_dir

puts "\n6. Testing write file:"
cmd_echo Hello World > test_dir/file.txt

puts "\n7. Testing cat:"
cmd_cat test_dir/file.txt

puts "\n8. Testing cleanup:"
cmd_rm -r test_dir

puts "\n=== All tests passed! ==="
