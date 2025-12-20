#!/bin/sh
# lib/core/validate.sh - RSR Input Validation Framework
# POSIX-compliant validation utilities
#
# Usage: . "${RSR_LIB_DIR:-./lib}/core/validate.sh"
#
# Provides:
#   - Username/password validation
#   - Path validation
#   - Network validation (IP, hostname, port)
#   - Numeric validation
#   - Generic pattern validation

# =============================================================================
# Guard: Prevent double-sourcing
# =============================================================================

[ -n "${_RSR_CORE_VALIDATE_LOADED:-}" ] && return 0
_RSR_CORE_VALIDATE_LOADED=1

# Ensure core init is loaded
if [ -z "${_RSR_CORE_INIT_LOADED:-}" ]; then
    _script_dir="$(cd "$(dirname "$0")" 2> /dev/null && pwd)" || _script_dir="."
    . "${_script_dir}/init.sh" 2> /dev/null || . "./lib/core/init.sh" 2> /dev/null || {
        echo "ERROR: RSR core/init.sh must be sourced first" >&2
        return 1
    }
fi

# =============================================================================
# Username Validation
# =============================================================================

# Validate username format
# Usage: rsr_validate_username "john_doe"
# Returns: 0 if valid, 1 if invalid
rsr_validate_username() {
    _username="$1"

    # Check empty
    [ -z "$_username" ] && return 1

    # Check length (1-32 characters)
    _len=$(printf '%s' "$_username" | wc -c)
    [ "$_len" -lt 1 ] || [ "$_len" -gt 32 ] && return 1

    # Check format: starts with letter, contains only [a-z0-9_-]
    echo "$_username" | grep -qE '^[a-z][a-z0-9_-]*$'
}

# Validate username with detailed error message
# Usage: rsr_validate_username_or_die "john_doe"
rsr_validate_username_or_die() {
    _username="$1"

    if [ -z "$_username" ]; then
        rsr_die "Username cannot be empty" "$RSR_EXIT_USAGE"
    fi

    _len=$(printf '%s' "$_username" | wc -c)
    if [ "$_len" -gt 32 ]; then
        rsr_die "Username must be 32 characters or less" "$RSR_EXIT_USAGE"
    fi

    if ! echo "$_username" | grep -qE '^[a-z]'; then
        rsr_die "Username must start with a lowercase letter" "$RSR_EXIT_USAGE"
    fi

    if ! echo "$_username" | grep -qE '^[a-z][a-z0-9_-]*$'; then
        rsr_die "Username can only contain lowercase letters, numbers, underscore, and hyphen" "$RSR_EXIT_USAGE"
    fi
}

# =============================================================================
# Password Validation
# =============================================================================

# Validate password strength
# Usage: rsr_validate_password "MyP@ssw0rd" [min_length]
# Returns: 0 if meets requirements, 1 otherwise
rsr_validate_password() {
    _password="$1"
    _min_length="${2:-8}"

    # Check length
    _len=$(printf '%s' "$_password" | wc -c)
    [ "$_len" -lt "$_min_length" ] && return 1

    return 0
}

# Validate password with complexity requirements
# Usage: rsr_validate_password_complex "MyP@ssw0rd"
# Requirements: 8+ chars, uppercase, lowercase, number, special
rsr_validate_password_complex() {
    _password="$1"

    # Check length (8+)
    _len=$(printf '%s' "$_password" | wc -c)
    [ "$_len" -lt 8 ] && return 1

    # Check uppercase
    echo "$_password" | grep -q '[A-Z]' || return 1

    # Check lowercase
    echo "$_password" | grep -q '[a-z]' || return 1

    # Check number
    echo "$_password" | grep -q '[0-9]' || return 1

    # Check special character
    echo "$_password" | grep -q '[!@#$%^&*()_+=\-\[\]{};:,.<>?/\\|`~]' || return 1

    return 0
}

# =============================================================================
# Path Validation
# =============================================================================

# Validate path exists
# Usage: rsr_validate_path_exists "/etc/passwd"
rsr_validate_path_exists() {
    [ -e "$1" ]
}

# Validate path is a file
# Usage: rsr_validate_file "/etc/passwd"
rsr_validate_file() {
    [ -f "$1" ]
}

# Validate path is a directory
# Usage: rsr_validate_directory "/etc"
rsr_validate_directory() {
    [ -d "$1" ]
}

# Validate path is readable
# Usage: rsr_validate_readable "/etc/passwd"
rsr_validate_readable() {
    [ -r "$1" ]
}

# Validate path is writable
# Usage: rsr_validate_writable "/tmp/test"
rsr_validate_writable() {
    [ -w "$1" ]
}

# Validate path is executable
# Usage: rsr_validate_executable "/usr/bin/bash"
rsr_validate_executable() {
    [ -x "$1" ]
}

# Validate path format (no dangerous characters)
# Usage: rsr_validate_path_safe "/home/user/file.txt"
rsr_validate_path_safe() {
    _path="$1"

    # Reject empty
    [ -z "$_path" ] && return 1

    # Reject null bytes
    echo "$_path" | grep -q "$(printf '\0')" && return 1

    # Reject newlines
    echo "$_path" | grep -q "$(printf '\n')" && return 1

    # Allow path
    return 0
}

# =============================================================================
# Network Validation
# =============================================================================

# Validate IPv4 address
# Usage: rsr_validate_ipv4 "192.168.1.1"
rsr_validate_ipv4() {
    _ip="$1"

    # Check format
    echo "$_ip" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' || return 1

    # Check each octet is 0-255
    _IFS="$IFS"
    IFS='.'
    set -- $_ip
    IFS="$_IFS"

    for _octet in "$1" "$2" "$3" "$4"; do
        [ "$_octet" -ge 0 ] 2> /dev/null && [ "$_octet" -le 255 ] 2> /dev/null || return 1
    done

    return 0
}

# Validate IPv6 address (basic)
# Usage: rsr_validate_ipv6 "2001:db8::1"
rsr_validate_ipv6() {
    _ip="$1"
    echo "$_ip" | grep -qiE '^([0-9a-f]{0,4}:){2,7}[0-9a-f]{0,4}$'
}

# Validate hostname
# Usage: rsr_validate_hostname "server.example.com"
rsr_validate_hostname() {
    _hostname="$1"

    # Check length (1-253)
    _len=$(printf '%s' "$_hostname" | wc -c)
    [ "$_len" -lt 1 ] || [ "$_len" -gt 253 ] && return 1

    # Check format: letters, numbers, hyphens, dots
    echo "$_hostname" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*$'
}

# Validate port number
# Usage: rsr_validate_port 8080
rsr_validate_port() {
    _port="$1"

    # Check numeric
    echo "$_port" | grep -qE '^[0-9]+$' || return 1

    # Check range (1-65535)
    [ "$_port" -ge 1 ] 2> /dev/null && [ "$_port" -le 65535 ] 2> /dev/null
}

# Validate URL format (basic)
# Usage: rsr_validate_url "https://example.com/path"
rsr_validate_url() {
    _url="$1"
    echo "$_url" | grep -qE '^https?://[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?(/.*)?$'
}

# =============================================================================
# Numeric Validation
# =============================================================================

# Validate integer
# Usage: rsr_validate_integer "123"
rsr_validate_integer() {
    echo "$1" | grep -qE '^-?[0-9]+$'
}

# Validate positive integer
# Usage: rsr_validate_positive_integer "123"
rsr_validate_positive_integer() {
    echo "$1" | grep -qE '^[0-9]+$' && [ "$1" -gt 0 ] 2> /dev/null
}

# Validate integer in range
# Usage: rsr_validate_integer_range "50" 1 100
rsr_validate_integer_range() {
    _num="$1"
    _min="$2"
    _max="$3"

    rsr_validate_integer "$_num" || return 1
    [ "$_num" -ge "$_min" ] 2> /dev/null && [ "$_num" -le "$_max" ] 2> /dev/null
}

# =============================================================================
# Email Validation
# =============================================================================

# Validate email format (basic)
# Usage: rsr_validate_email "user@example.com"
rsr_validate_email() {
    _email="$1"
    echo "$_email" | grep -qE '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
}

# =============================================================================
# Generic Validation
# =============================================================================

# Validate against regex pattern
# Usage: rsr_validate_pattern "test123" '^[a-z]+[0-9]+$'
rsr_validate_pattern() {
    _value="$1"
    _pattern="$2"
    echo "$_value" | grep -qE "$_pattern"
}

# Validate value is in list
# Usage: rsr_validate_in_list "apple" "apple" "banana" "cherry"
rsr_validate_in_list() {
    _value="$1"
    shift

    for _item in "$@"; do
        [ "$_value" = "$_item" ] && return 0
    done

    return 1
}

# Validate non-empty
# Usage: rsr_validate_not_empty "$var"
rsr_validate_not_empty() {
    [ -n "$1" ]
}

# =============================================================================
# Network Share Validation
# =============================================================================

# Validate SMB/CIFS share path
# Usage: rsr_validate_smb_path "//server/share"
rsr_validate_smb_path() {
    _path="$1"
    [ -z "$_path" ] && return 1
    echo "$_path" | grep -qE '^(//|\\\\|smb://|cifs://)[^/\\:]+[/\\].+'
}

# Validate NFS export path
# Usage: rsr_validate_nfs_path "server:/export"
rsr_validate_nfs_path() {
    _path="$1"
    [ -z "$_path" ] && return 1
    echo "$_path" | grep -qE '^[^:]+:/.+'
}

# Validate SSHFS path
# Usage: rsr_validate_sshfs_path "user@server:/path"
rsr_validate_sshfs_path() {
    _path="$1"
    [ -z "$_path" ] && return 1
    echo "$_path" | grep -qE '^([^@]+@)?[^:]+:/.+|^s(ftp|sh)://'
}

# Validate WebDAV URL
# Usage: rsr_validate_webdav_path "https://server/dav"
rsr_validate_webdav_path() {
    _path="$1"
    [ -z "$_path" ] && return 1
    echo "$_path" | grep -qE '^(https?|davs?)://.+'
}

# Validate mount point path
# Usage: rsr_validate_mount_point "/mnt/share"
rsr_validate_mount_point() {
    _path="$1"
    [ -z "$_path" ] && return 1

    # Must be absolute path
    echo "$_path" | grep -qE '^/' || return 1

    # No double slashes or trailing slash (except root)
    [ "$_path" = "/" ] && return 0
    echo "$_path" | grep -qE '//|/$' && return 1

    return 0
}

# Validate share name (for saved configurations)
# Usage: rsr_validate_share_name "my-share"
rsr_validate_share_name() {
    _name="$1"
    [ -z "$_name" ] && return 1

    # Length check (1-64 chars)
    _len=$(printf '%s' "$_name" | wc -c)
    [ "$_len" -lt 1 ] || [ "$_len" -gt 64 ] && return 1

    # Format: starts with letter, contains only [a-zA-Z0-9_-]
    echo "$_name" | grep -qE '^[a-zA-Z][a-zA-Z0-9_-]*$'
}

# =============================================================================
# Initialization Complete
# =============================================================================

rsr_log_debug "RSR Validation Library loaded"
