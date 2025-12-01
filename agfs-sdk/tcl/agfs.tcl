#!/usr/bin/env tclsh
# AGFS Tcl SDK - Main package file
package require Tcl 9.0

package provide agfs 0.1.0

# Load dependencies
package require http
package require uri
package require json

# Source modules
source [file join [file dirname [info script]] agfsclient.tcl]
source [file join [file dirname [info script]] exceptions.tcl]
source [file join [file dirname [info script]] helpers.tcl]

namespace eval agfs {
    namespace export AGFSClient AGFSClientError AGFSConnectionError
    namespace export AGFSTimeoutError AGFSHTTPError
    namespace export cp upload download
}

# Package version
set ::agfs::version "0.1.0"

# Convenience proc for quick testing
proc agfs::version {} {
    return $::agfs::version
}
