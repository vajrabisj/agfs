#!/usr/bin/env tclsh
package require Tcl 9.0

namespace eval agfs {
    namespace export cp
    namespace export upload
    namespace export download
}

proc agfs::_cat_binary {client path {offset 0} {size -1}} {
    set api_base [$client get_api_base]
    set timeout [$client get_timeout]
    return [agfs::CatBytes $api_base $timeout $path $offset $size]
}

# Copy files within AGFS
proc agfs::cp {client src dst args} {
    set recursive false
    set stream false

    foreach {key value} $args {
        switch -exact -- $key {
            -recursive { set recursive true }
            -stream { set stream true }
        }
    }

    # Check if source exists and get its type
    set src_info [$client stat $src]
    set is_dir [dict get $src_info isDir]

    if {$is_dir} {
        if {!$recursive} {
            error "Cannot copy directory '$src' without -recursive flag"
        }
        _copy_directory $client $src $dst $stream
    } else {
        _copy_file $client $src $dst $stream
    }
}

# Upload from local to AGFS
proc agfs::upload {client local_path remote_path args} {
    set recursive false
    set stream false

    foreach {key value} $args {
        switch -exact -- $key {
            -recursive { set recursive true }
            -stream { set stream true }
        }
    }

    if {![file exists $local_path]} {
        error "Local path does not exist: $local_path"
    }

    if {[file isdirectory $local_path]} {
        if {!$recursive} {
            error "Cannot upload directory '$local_path' without -recursive flag"
        }
        _upload_directory $client $local_path $remote_path $stream
    } else {
        _upload_file $client $local_path $remote_path $stream
    }
}

# Download from AGFS to local
proc agfs::download {client remote_path local_path args} {
    set recursive false
    set stream false

    foreach {key value} $args {
        switch -exact -- $key {
            -recursive { set recursive true }
            -stream { set stream true }
        }
    }

    # Check if remote path exists and get its type
    set remote_info [$client stat $remote_path]
    set is_dir [dict get $remote_info isDir]

    if {$is_dir} {
        if {!$recursive} {
            error "Cannot download directory '$remote_path' without -recursive flag"
        }
        _download_directory $client $remote_path $local_path $stream
    } else {
        _download_file $client $remote_path $local_path $stream
    }
}

# Internal: Copy single file
proc agfs::_copy_file {client src dst stream} {
    # Ensure parent directory exists
    _ensure_remote_parent_dir $client $dst

    if {$stream} {
        # Stream the file content
        set response [agfs::_cat_binary $client $src]
        _write_stream $client $dst $response
    } else {
        # Read entire file and write
        set data [agfs::_cat_binary $client $src]
        $client write $dst $data
    }
}

# Internal: Copy directory recursively
proc agfs::_copy_directory {client src dst stream} {
    # Create destination directory
    catch {
        $client mkdir $dst
    }

    # List source directory contents
    set items [$client ls $src]

    foreach item $items {
        set item_name [dict get $item name]
        set src_path [string trimright $src "/"]/$item_name
        set dst_path [string trimright $dst "/"]/$item_name

        if {[dict get $item isDir]} {
            _copy_directory $client $src_path $dst_path $stream
        } else {
            _copy_file $client $src_path $dst_path $stream
        }
    }
}

# Internal: Upload single file
proc agfs::_upload_file {client local_file remote_path stream} {
    # Ensure parent directory exists
    _ensure_remote_parent_dir $client $remote_path

    if {$stream} {
        # Read file in chunks
        set chunk_size 8192
        set data [_read_file_stream $local_file $chunk_size]
        $client write $remote_path $data
    } else {
        # Read entire file
        set fp [open $local_file rb]
        fconfigure $fp -translation binary -encoding iso8859-1
        set data [read $fp]
        close $fp
        $client write $remote_path $data
    }
}

# Internal: Upload directory recursively
proc agfs::_upload_directory {client local_dir remote_path stream} {
    # Create remote directory
    catch {
        $client mkdir $remote_path
    }

    # Walk through local directory
    foreach item [glob -nocomplain -directory $local_dir *] {
        set item_name [file tail $item]
        set remote_item_path [string trimright $remote_path "/"]/$item_name

        if {[file isdirectory $item]} {
            _upload_directory $client $item $remote_item_path $stream
        } else {
            _upload_file $client $item $remote_item_path $stream
        }
    }
}

# Internal: Download single file
proc agfs::_download_file {client remote_path local_file stream} {
    # Ensure parent directory exists
    set parent_dir [file dirname $local_file]
    file mkdir $parent_dir

    if {$stream} {
        # Stream the file content
        set data [agfs::_cat_binary $client $remote_path]
        _write_local_file $local_file $data
    } else {
        # Read entire file
        set data [agfs::_cat_binary $client $remote_path]
        _write_local_file $local_file $data
    }
}

# Internal: Download directory recursively
proc agfs::_download_directory {client remote_path local_dir stream} {
    # Create local directory
    file mkdir $local_dir

    # List remote directory contents
    set items [$client ls $remote_path]

    foreach item $items {
        set item_name [dict get $item name]
        set remote_item_path [string trimright $remote_path "/"]/$item_name
        set local_item_path [file join $local_dir $item_name]

        if {[dict get $item isDir]} {
            _download_directory $client $remote_item_path $local_item_path $stream
        } else {
            _download_file $client $remote_item_path $local_item_path $stream
        }
    }
}

# Internal: Ensure parent directory exists
proc agfs::_ensure_remote_parent_dir {client path} {
    set parts [split [string trimright $path "/"] "/"]
    set parent_parts [lrange $parts 0 end-1]

    if {[llength $parent_parts] > 0} {
        set parent [join $parent_parts "/"]
        if {$parent != "" && $parent != "/"} {
            _ensure_remote_dir_recursive $client $parent
        }
    }
}

# Internal: Recursively ensure directory exists
proc agfs::_ensure_remote_dir_recursive {client path} {
    if {$path == "" || $path == "/"} {
        return
    }

    # Check if directory exists
    catch {
        set info [$client stat $path]
        if {[dict get $info isDir]} {
            return
        }
    }

    # Ensure parent exists first
    set parts [split [string trimright $path "/"] "/"]
    set parent_parts [lrange $parts 0 end-1]

    if {[llength $parent_parts] > 0} {
        set parent [join $parent_parts "/"]
        if {$parent != "" && $parent != "/"} {
            _ensure_remote_dir_recursive $client $parent
        }
    }

    # Create this directory
    catch {
        $client mkdir $path
    }
}

# Helper: Read file in streaming mode
proc agfs::_read_file_stream {filepath chunk_size} {
    set fp [open $filepath rb]
    fconfigure $fp -translation binary -encoding iso8859-1
    set data [read $fp]
    close $fp
    return $data
}

# Helper: Write to local file
proc agfs::_write_local_file {filepath data} {
    set fp [open $filepath wb]
    fconfigure $fp -translation binary -encoding iso8859-1
    puts -nonewline $fp $data
    close $fp
}

# Helper: Write stream
proc agfs::_write_stream {client path data} {
    $client write $path $data
}
