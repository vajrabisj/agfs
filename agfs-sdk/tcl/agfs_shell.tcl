#!/usr/bin/env tclsh9.0
# AGFS Interactive Shell - Simple Tcl interface for AGFS

set auto_path [linsert $auto_path 0 /opt/homebrew/Cellar/tcl-tk/9.0.2/lib/tcllib2.0]
set auto_path [linsert $auto_path 0 /opt/homebrew/Cellar/tcl-tk/9.0.2/lib/tcllibc2.0]
set auto_path [linsert $auto_path 0 [file dirname [file dirname [file normalize [info script]]]]]

package require agfs

# Global state
set client ""
set current_dir "/"
set running true

# Initialize
proc init_shell {} {
    global client current_dir running

    puts ""
    puts "========================================"
    puts "  AGFS Tcl Shell v0.1.0"
    puts "========================================"
    puts ""

    # Create client
    set client [agfs::AGFSClient -api_base "http://localhost:8080"]

    # Test connection
    if {[catch {
        $client health
        puts "✓ Connected to AGFS server at [$client get_api_base]"
        puts ""
    } err]} {
        puts "⚠ Warning: Cannot connect to server"
        puts "  Error: $err"
        puts "  Some commands may fail"
        puts ""
    }
}

# Help command
proc cmd_help {} {
    puts "Available commands:"
    puts "  help          Show this help"
    puts "  exit, quit    Exit the shell"
    puts "  pwd           Print current directory"
    puts "  cd <dir>      Change directory"
    puts "  ls [dir]      List directory contents"
    puts "  cat <file>    View file contents"
    puts "  echo <text>   Echo text"
    puts "  mkdir <dir>   Create directory"
    puts "  touch <file>  Create empty file"
    puts "  rm <path>     Remove file or directory"
    puts "  mv <src> <dst> Rename/move file"
    puts "  stat <path>   Get file information"
    puts "  upload <local> <remote>  Upload file"
    puts "  download <remote> <local> Download file"
    puts "  cp <src> <dst> Copy file"
    puts ""
}

# Print working directory
proc cmd_pwd {} {
    global current_dir
    puts $current_dir
}

# Change directory
proc cmd_cd {args} {
    global current_dir client

    if {[llength $args] == 0} {
        set current_dir "/"
        return
    }

    set path [lindex $args 0]

    # Handle relative paths
    if {![string match "/*" $path]} {
        set path "[string trimright $current_dir /]/$path"
    }

    # Check if directory exists
    if {[catch {
        $client stat $path
        set current_dir $path
    } err]} {
        puts "Error: $err"
    }
}

# List directory
proc cmd_ls {args} {
    global current_dir client

    if {[llength $args] == 0} {
        set dir $current_dir
    } else {
        set dir [lindex $args 0]
        if {![string match "/*" $dir]} {
            set dir "[string trimright $current_dir /]/$dir"
        }
    }

    if {[catch {
        set files [$client ls $dir]
        foreach file $files {
            set name [dict get $file name]
            if {[dict get $file isDir]} {
                puts "[format {%-20s} \[$name\]]"
            } else {
                puts "[format {%-20s} $name]"
            }
        }
    } err]} {
        puts "Error: $err"
    }
}

# View file
proc cmd_cat {args} {
    global current_dir client

    if {[llength $args] == 0} {
        puts "Usage: cat <file>"
        return
    }

    set file [lindex $args 0]
    if {![string match "/*" $file]} {
        set file "[string trimright $current_dir /]/$file"
    }

    if {[catch {
        set content [$client cat $file]
        puts $content
    } err]} {
        puts "Error: $err"
    }
}

# Echo
proc cmd_echo {args} {
    puts [join $args " "]
}

# Make directory
proc cmd_mkdir {args} {
    global current_dir client

    if {[llength $args] == 0} {
        puts "Usage: mkdir <directory>"
        return
    }

    set dir [lindex $args 0]
    if {![string match "/*" $dir]} {
        set dir "[string trimright $current_dir /]/$dir"
    }

    if {[catch {
        $client mkdir $dir
        puts "Directory created: $dir"
    } err]} {
        puts "Error: $err"
    }
}

# Touch file
proc cmd_touch {args} {
    global current_dir client

    if {[llength $args] == 0} {
        puts "Usage: touch <file>"
        return
    }

    set file [lindex $args 0]
    if {![string match "/*" $file]} {
        set file "[string trimright $current_dir /]/$file"
    }

    if {[catch {
        $client touch $file
        puts "File created: $file"
    } err]} {
        puts "Error: $err"
    }
}

# Remove
proc cmd_rm {args} {
    global current_dir client

    if {[llength $args] == 0} {
        puts "Usage: rm [-r] <path>"
        return
    }

    set recursive false
    set path ""
    foreach arg $args {
        if {$arg == "-r"} {
            set recursive true
        } else {
            set path $arg
        }
    }

    if {![string match "/*" $path]} {
        set path "[string trimright $current_dir /]/$path"
    }

    if {[catch {
        $client rm $path -recursive $recursive
        puts "Removed: $path"
    } err]} {
        puts "Error: $err"
    }
}

# Move/rename
proc cmd_mv {args} {
    global current_dir client

    if {[llength $args] < 2} {
        puts "Usage: mv <source> <destination>"
        return
    }

    set src [lindex $args 0]
    set dst [lindex $args 1]

    if {![string match "/*" $src]} {
        set src "[string trimright $current_dir /]/$src"
    }
    if {![string match "/*" $dst]} {
        set dst "[string trimright $current_dir /]/$dst"
    }

    if {[catch {
        $client mv $src $dst
        puts "Moved: $src -> $dst"
    } err]} {
        puts "Error: $err"
    }
}

# Stat
proc cmd_stat {args} {
    global current_dir client

    if {[llength $args] == 0} {
        puts "Usage: stat <path>"
        return
    }

    set path [lindex $args 0]
    if {![string match "/*" $path]} {
        set path "[string trimright $current_dir /]/$path"
    }

    if {[catch {
        set info [$client stat $path]
        puts "Path: [dict get $info path]"
        puts "Size: [dict get $info size] bytes"
        puts "Mode: [dict get $info mode]"
        puts "Is Directory: [dict get $info isDir]"
    } err]} {
        puts "Error: $err"
    }
}

# Upload
proc cmd_upload {args} {
    global current_dir client

    if {[llength $args] < 2} {
        puts "Usage: upload <local_path> <remote_path>"
        return
    }

    set local [lindex $args 0]
    set remote [lindex $args 1]

    if {![string match "/*" $remote]} {
        set remote "[string trimright $current_dir /]/$remote"
    }

    if {[catch {
        agfs::upload $client $local $remote
        puts "Uploaded: $local -> $remote"
    } err]} {
        puts "Error: $err"
    }
}

# Download
proc cmd_download {args} {
    global current_dir client

    if {[llength $args] < 2} {
        puts "Usage: download <remote_path> <local_path>"
        return
    }

    set remote [lindex $args 0]
    set local [lindex $args 1]

    if {![string match "/*" $remote]} {
        set remote "[string trimright $current_dir /]/$remote"
    }

    if {[catch {
        agfs::download $client $remote $local
        puts "Downloaded: $remote -> $local"
    } err]} {
        puts "Error: $err"
    }
}

# Copy
proc cmd_cp {args} {
    global current_dir client

    if {[llength $args] < 2} {
        puts "Usage: cp <source> <destination>"
        return
    }

    set src [lindex $args 0]
    set dst [lindex $args 1]

    if {![string match "/*" $src]} {
        set src "[string trimright $current_dir /]/$src"
    }
    if {![string match "/*" $dst]} {
        set dst "[string trimright $current_dir /]/$dst"
    }

    if {[catch {
        agfs::cp $client $src $dst
        puts "Copied: $src -> $dst"
    } err]} {
        puts "Error: $err"
    }
}

# Main loop
proc run_shell {} {
    global current_dir running

    while {$running} {
        # Show prompt
        puts -nonewline "[string trimright $current_dir /]> "

        # Read input
        flush stdout
        gets stdin line

        # Skip empty lines
        if {[string trim $line] == ""} {
            continue
        }

        # Parse command
        set cmd_parts [split $line]
        set cmd [lindex $cmd_parts 0]
        set args [lrange $cmd_parts 1 end]

        # Execute command
        switch -exact $cmd {
            "exit" -
            "quit" {
                puts "Goodbye!"
                set running false
            }
            "help" {
                cmd_help
            }
            "pwd" {
                cmd_pwd
            }
            "cd" {
                eval cmd_cd $args
            }
            "ls" {
                eval cmd_ls $args
            }
            "cat" {
                eval cmd_cat $args
            }
            "echo" {
                eval cmd_echo $args
            }
            "mkdir" {
                eval cmd_mkdir $args
            }
            "touch" {
                eval cmd_touch $args
            }
            "rm" {
                eval cmd_rm $args
            }
            "mv" {
                eval cmd_mv $args
            }
            "stat" {
                eval cmd_stat $args
            }
            "upload" {
                eval cmd_upload $args
            }
            "download" {
                eval cmd_download $args
            }
            "cp" {
                eval cmd_cp $args
            }
            default {
                puts "Unknown command: $cmd"
                puts "Type 'help' for available commands"
            }
        }
    }
}

# Run the shell
if {[catch {
    init_shell
    run_shell
} err]} {
    puts "Error: $err"
    exit 1
}
