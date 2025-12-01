#!/usr/bin/env tclsh
package require Tcl 9.0

namespace eval agfs {
    namespace export AGFSClientError
    namespace export AGFSConnectionError
    namespace export AGFSTimeoutError
    namespace export AGFSHTTPError
}

# Base exception for AGFS client errors
interp alias {} agfs::AGFSClientError {} agfs::RaiseError "AGFSClientError"

# Connection related errors
interp alias {} agfs::AGFSConnectionError {} agfs::RaiseError "AGFSConnectionError"

# Timeout errors
interp alias {} agfs::AGFSTimeoutError {} agfs::RaiseError "AGFSTimeoutError"

# HTTP related errors
interp alias {} agfs::AGFSHTTPError {} agfs::RaiseHTTPError

proc agfs::RaiseError {type message} {
    error "$type: $message"
}

proc agfs::RaiseHTTPError {message {status_code ""}} {
    if {$status_code != ""} {
        error "AGFSHTTPError ($status_code): $message"
    } else {
        error "AGFSHTTPError: $message"
    }
}

# Helper to handle request errors
proc agfs::HandleRequestError {error_msg status_code} {
    # Try to extract useful error information
    if {$status_code != ""} {
        switch -exact $status_code {
            404 {
                error "No such file or directory"
            }
            403 {
                error "Permission denied"
            }
            409 {
                error "Resource already exists"
            }
            500 {
                error "Internal server error"
            }
            502 {
                error "Bad Gateway - backend service unavailable"
            }
            default {
                error "HTTP error $status_code"
            }
        }
    }

    # Check for connection errors
    if {[string match -nocase "*connection refused*" $error_msg] ||
        [string match -nocase "*couldn't connect*" $error_msg]} {
        error "Connection refused - server not running"
    }

    if {[string match -nocase "*timeout*" $error_msg]} {
        error "Request timeout"
    }

    # Default error
    error $error_msg
}
