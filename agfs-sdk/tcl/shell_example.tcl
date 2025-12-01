#!/usr/bin/env tclsh9.0
# AGFS Shell - Interactive shell for AGFS using Tcl

set auto_path [linsert $auto_path 0 /opt/homebrew/Cellar/tcl-tk/9.0.2/lib/tcllib2.0]
set auto_path [linsert $auto_path 0 /opt/homebrew/Cellar/tcl-tk/9.0.2/lib/tcllibc2.0]
set auto_path [linsert $auto_path 0 [file dirname [file dirname [file normalize [info script]]]]]

package require agfs

# Create namespace first
namespace eval agfs_shell {
    variable prompt "agfs> "
    variable client ""
    variable current_dir "/"
    variable running true
}

# Initialize
proc agfs_shell::init {} {
    puts "AGFS Tcl Shell v0.1.0"
    puts "Type 'help' for commands, 'exit' or 'quit' to leave"
    puts ""

    # Create client
    set ::agfs_shell::client [agfs::AGFSClient -api_base "http://localhost:8080"]

    # Test connection
    if {[catch {
        $::agfs_shell::client health
        puts "Connected to AGFS server at [$::agfs_shell::client get_api_base]"
    } err]} {
        puts "Warning: Cannot connect to server - $err"
        puts "Some commands may fail"
    }

    puts ""
}

# Command handlers
proc agfs_shell::cmd_help {args} {
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
}

proc agfs_shell::cmd_pwd {args} {
    puts $::agfs_shell::current_dir
}

proc agfs_shell::cmd_cd {args} {
    if {[llength $args] == 0} {
        set ::agfs_shell::current_dir "/"
        return
    }

    set path [lindex $args 0]

    # Handle relative paths
    if {![string match "/*" $path]} {
        set path "[string trimright $::agfs_shell::current_dir /]/$path"
    }

    # Check if directory exists
    if {[catch {
        $::agfs_shell::client stat $path
        set ::agfs_shell::current_dir $path
    } err]} {
        puts "Error: $err"
    }
}

proc agfs_shell::cmd_ls {args} {
    if {[llength $args] == 0} {
        set dir $::agfs_shell::current_dir
    } else {
        set dir [lindex $args 0]
        if {![string match "/*" $dir]} {
            set dir "[string trimright $::agfs_shell::current_dir /]/$dir"
        }
    }

    if {[catch {
        set files [$::agfs_shell::client ls $dir]
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

proc agfs_shell::cmd_cat {args} {
    if {[llength $args] == 0} {
        puts "Usage: cat <file>"
        return
    }

    set file [lindex $args 0]
    if {![string match "/*" $file]} {
        set file "[string trimright $::agfs_shell::current_dir /]/$file"
    }

    if {[catch {
        set content [$::agfs_shell::client cat $file]
        puts $content
    } err]} {
        puts "Error: $err"
    }
}

proc agfs_shell::cmd_echo {args} {
    puts [join $args " "]
}

proc agfs_shell::cmd_mkdir {args} {
    if {[llength $args] == 0} {
        puts "Usage: mkdir <directory>"
        return
    }

    set dir [lindex $args 0]
    if {![string match "/*" $dir]} {
        set dir "[string trimright $::agfs_shell::current_dir /]/$dir"
    }

    if {[catch {
        $::agfs_shell::client mkdir $dir
        puts "Directory created: $dir"
    } err]} {
        puts "Error: $err"
    }
}

proc agfs_shell::cmd_touch {args} {
    if {[llength $args] == 0} {
        puts "Usage: touch <file>"
        return
    }

    set file [lindex $args 0]
    if {![string match "/*" $file]} {
        set file "[string trimright $::agfs_shell::current_dir /]/$file"
    }

    if {[catch {
        $::agfs_shell::client touch $file
        puts "File created: $file"
    } err]} {
        puts "Error: $err"
    }
}

proc agfs_shell::cmd_rm {args} {
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
        set path "[string trimright $::agfs_shell::current_dir /]/$path"
    }

    if {[catch {
        $::agfs_shell::client rm $path -recursive $recursive
        puts "Removed: $path"
    } err]} {
        puts "Error: $err"
    }
}

proc agfs_shell::cmd_mv {args} {
    if {[llength $args] < 2} {
        puts "Usage: mv <source> <destination>"
        return
    }

    set src [lindex $args 0]
    set dst [lindex $args 1]

    if {![string match "/*" $src]} {
        set src "[string trimright $::agfs_shell::current_dir /]/$src"
    }
    if {![string match "/*" $dst]} {
        set dst "[string trimright $::agfs_shell::current_dir /]/$dst"
    }

    if {[catch {
        $::agfs_shell::client mv $src $dst
        puts "Moved: $src -> $dst"
    } err]} {
        puts "Error: $err"
    }
}

proc agfs_shell::cmd_stat {args} {
    if {[llength $args] == 0} {
        puts "Usage: stat <path>"
        return
    }

    set path [lindex $args 0]
    if {![string match "/*" $path]} {
        set path "[string trimright $::agfs_shell::current_dir /]/$path"
    }

    if {[catch {
        set info [$::agfs_shell::client stat $path]
        puts "Path: [dict get $info path]"
        puts "Size: [dict get $info size] bytes"
        puts "Mode: [dict get $info mode]"
        puts "Is Directory: [dict get $info isDir]"
    } err]} {
        puts "Error: $err"
    }
}

proc agfs_shell::cmd_upload {args} {
    if {[llength $args] < 2} {
        puts "Usage: upload <local_path> <remote_path>"
        return
    }

    set local [lindex $args 0]
    set remote [lindex $args 1]

    if {![string match "/*" $remote]} {
        set remote "[string trimright $::agfs_shell::current_dir /]/$remote"
    }

    if {[catch {
        agfs::upload $::agfs_shell::client $local $remote
        puts "Uploaded: $local -> $remote"
    } err]} {
        puts "Error: $err"
    }
}

proc agfs_shell::cmd_download {args} {
    if {[llength $args] < 2} {
        puts "Usage: download <remote_path> <local_path>"
        return
    }

    set remote [lindex $args 0]
    set local [lindex $args 1]

    if {![string match "/*" $remote]} {
        set remote "[string trimright $::agfs_shell::current_dir /]/$remote"
    }

    if {[catch {
        agfs::download $::agfs_shell::client $remote $local
        puts "Downloaded: $remote -> $local"
    } err]} {
        puts "Error: $err"
    }
}

proc agfs_shell::cmd_cp {args} {
    if {[llength $args] < 2} {
        puts "Usage: cp <source> <destination>"
        return
    }

    set src [lindex $args 0]
    set dst [lindex $args 1]

    if {![string match "/*" $src]} {
        set src "[string trimright $::agfs_shell::current_dir /]/$src"
    }
    if {![string match "/*" $dst]} {
        set dst "[string trimright $::agfs_shell::current_dir /]/$dst"
    }

    if {[catch {
        agfs::cp $::agfs_shell::client $src $dst
        puts "Copied: $src -> $dst"
    } err]} {
        puts "Error: $err"
    }
}

# Main loop
proc agfs_shell::run {} {
    while {$::agfs_shell::running} {
        # Show prompt
        puts -nonewline "[string trimright $::agfs_shell::current_dir /]> "

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
                set ::agfs_shell::running false
            }
            "help" {
                cmd_help {*}$args
            }
            "pwd" {
                cmd_pwd {*}$args
            }
            "cd" {
                cmd_cd {*}$args
            }
            "ls" {
                cmd_ls {*}$args
            }
            "cat" {
                cmd_cat {*}$args
            }
            "echo" {
                cmd_echo {*}$args
            }
            "mkdir" {
                cmd_mkdir {*}$args
            }
            "touch" {
                cmd_touch {*}$args
            }
            "rm" {
                cmd_rm {*}$args
            }
            "mv" {
                cmd_mv {*}$args
            }
            "stat" {
                cmd_stat {*}$args
            }
            "upload" {
                cmd_upload {*}$args
            }
            "download" {
                cmd_download {*}$args
            }
            "cp" {
                cmd_cp {*}$args
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
    agfs_shell::init
    agfs_shell::run
} err]} {
    puts "Error: $err"
    exit 1
}
