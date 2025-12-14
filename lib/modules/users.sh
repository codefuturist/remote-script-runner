#!/bin/sh
# lib/modules/users.sh - RSR User Management Module
# Cross-platform user/group management for Linux, macOS, and FreeBSD
#
# Usage: . "${RSR_LIB_DIR:-./lib}/modules/users.sh"
#
# Provides:
#   - User CRUD operations
#   - Group management
#   - Password management
#   - Session/login info

# =============================================================================
# Guard: Prevent double-sourcing
# =============================================================================

[ -n "${_RSR_MODULE_USERS_LOADED:-}" ] && return 0
_RSR_MODULE_USERS_LOADED=1

# Ensure core is loaded
if [ -z "${_RSR_CORE_INIT_LOADED:-}" ]; then
    _script_dir="$(cd "$(dirname "$0")" 2> /dev/null && pwd)" || _script_dir="."
    . "${_script_dir}/../core/init.sh" 2> /dev/null || . "./lib/core/init.sh" 2> /dev/null || {
        echo "ERROR: RSR core/init.sh must be sourced first" >&2
        return 1
    }
fi

# =============================================================================
# Module Metadata
# =============================================================================

_RSR_USERS_VERSION="2.0.0"

# =============================================================================
# Internal Helpers
# =============================================================================

# Get OS for user operations (cached)
_rsr_users_os() {
    rsr_detect_os
}

# =============================================================================
# User Existence & Info
# =============================================================================

# Check if user exists
# Usage: rsr_user_exists "username"
# Returns: 0 if exists, 1 if not
rsr_user_exists() {
    _username="$1"
    [ -z "$_username" ] && return 1

    case "$(_rsr_users_os)" in
        darwin)
            dscl . -list /Users 2> /dev/null | grep -q "^${_username}$"
            ;;
        linux | freebsd)
            id "$_username" > /dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

# Get user info
# Usage: rsr_user_info "username"
# Output: uid:gid:home:shell (colon-separated)
rsr_user_info() {
    _username="$1"

    case "$(_rsr_users_os)" in
        darwin)
            if rsr_user_exists "$_username"; then
                _uid=$(dscl . -read "/Users/$_username" UniqueID 2> /dev/null | awk '{print $2}')
                _gid=$(dscl . -read "/Users/$_username" PrimaryGroupID 2> /dev/null | awk '{print $2}')
                _home=$(dscl . -read "/Users/$_username" NFSHomeDirectory 2> /dev/null | awk '{print $2}')
                _shell=$(dscl . -read "/Users/$_username" UserShell 2> /dev/null | awk '{print $2}')
                echo "${_uid}:${_gid}:${_home}:${_shell}"
            fi
            ;;
        linux | freebsd)
            getent passwd "$_username" 2> /dev/null | awk -F: '{print $3":"$4":"$6":"$7}'
            ;;
    esac
}

# Get user UID
# Usage: uid=$(rsr_user_uid "username")
rsr_user_uid() {
    _username="$1"

    case "$(_rsr_users_os)" in
        darwin)
            dscl . -read "/Users/$_username" UniqueID 2> /dev/null | awk '{print $2}'
            ;;
        linux | freebsd)
            id -u "$_username" 2> /dev/null
            ;;
    esac
}

# Get user home directory
# Usage: home=$(rsr_user_home "username")
rsr_user_home() {
    _username="$1"

    case "$(_rsr_users_os)" in
        darwin)
            dscl . -read "/Users/$_username" NFSHomeDirectory 2> /dev/null | awk '{print $2}'
            ;;
        linux | freebsd)
            getent passwd "$_username" 2> /dev/null | cut -d: -f6
            ;;
    esac
}

# Get user shell
# Usage: shell=$(rsr_user_shell "username")
rsr_user_shell() {
    _username="$1"

    case "$(_rsr_users_os)" in
        darwin)
            dscl . -read "/Users/$_username" UserShell 2> /dev/null | awk '{print $2}'
            ;;
        linux | freebsd)
            getent passwd "$_username" 2> /dev/null | cut -d: -f7
            ;;
    esac
}

# =============================================================================
# User Listing
# =============================================================================

# List all users
# Usage: rsr_user_list_all
rsr_user_list_all() {
    case "$(_rsr_users_os)" in
        darwin)
            dscl . -list /Users 2> /dev/null | grep -v "^_" | sort
            ;;
        linux | freebsd)
            awk -F: '{print $1}' /etc/passwd | sort
            ;;
    esac
}

# List human users (non-system)
# Usage: rsr_user_list_humans
rsr_user_list_humans() {
    case "$(_rsr_users_os)" in
        darwin)
            dscl . -list /Users UniqueID 2> /dev/null | awk '$2 >= 500 || $2 == 0 {print $1}' \
                | grep -v "^_" | grep -v "^nobody$" | grep -v "^Guest$" | sort
            ;;
        linux | freebsd)
            awk -F: '($3 >= 1000 || $3 == 0) && $1 != "nobody" {print $1}' /etc/passwd | sort
            ;;
    esac
}

# List system users
# Usage: rsr_user_list_system
rsr_user_list_system() {
    case "$(_rsr_users_os)" in
        darwin)
            dscl . -list /Users UniqueID 2> /dev/null | awk '$2 > 0 && $2 < 500 {print $1}' | sort
            ;;
        linux | freebsd)
            awk -F: '$3 > 0 && $3 < 1000 {print $1}' /etc/passwd | sort
            ;;
    esac
}

# =============================================================================
# User Creation
# =============================================================================

# Create a new user
# Usage: rsr_user_create "username" [--uid UID] [--gid GID] [--home PATH] [--shell SHELL] [--comment "Full Name"] [--no-create-home]
# Returns: 0 on success, non-zero on failure
rsr_user_create() {
    _username="$1"
    shift

    # Check if user exists
    if rsr_user_exists "$_username"; then
        rsr_log_error "User '$_username' already exists"
        return "$RSR_EXIT_ALREADY_EXISTS"
    fi

    # Parse options
    _uid="" _gid="" _home="" _shell="" _comment="" _create_home=1

    while [ $# -gt 0 ]; do
        case "$1" in
            --uid)
                _uid="$2"
                shift 2
                ;;
            --gid)
                _gid="$2"
                shift 2
                ;;
            --home)
                _home="$2"
                shift 2
                ;;
            --shell)
                _shell="$2"
                shift 2
                ;;
            --comment)
                _comment="$2"
                shift 2
                ;;
            --no-create-home)
                _create_home=0
                shift
                ;;
            *) shift ;;
        esac
    done

    case "$(_rsr_users_os)" in
        darwin)
            _rsr_user_create_darwin "$_username" "$_uid" "$_gid" "$_home" "$_shell" "$_comment" "$_create_home"
            ;;
        linux)
            _rsr_user_create_linux "$_username" "$_uid" "$_gid" "$_home" "$_shell" "$_comment" "$_create_home"
            ;;
        freebsd)
            _rsr_user_create_freebsd "$_username" "$_uid" "$_gid" "$_home" "$_shell" "$_comment" "$_create_home"
            ;;
        *)
            rsr_log_error "Unsupported OS: $(_rsr_users_os)"
            return "$RSR_EXIT_ERROR"
            ;;
    esac
}

# Create user on Linux
_rsr_user_create_linux() {
    _username="$1" _uid="$2" _gid="$3" _home="$4" _shell="$5" _comment="$6" _create_home="$7"

    _cmd="useradd"
    [ -n "$_uid" ] && _cmd="$_cmd -u $_uid"
    [ -n "$_gid" ] && _cmd="$_cmd -g $_gid"
    [ -n "$_home" ] && _cmd="$_cmd -d $_home"
    [ -n "$_shell" ] && _cmd="$_cmd -s $_shell" || _cmd="$_cmd -s /bin/bash"
    [ -n "$_comment" ] && _cmd="$_cmd -c \"$_comment\""
    [ "$_create_home" = "1" ] && _cmd="$_cmd -m"
    _cmd="$_cmd $_username"

    eval "$_cmd"
}

# Create user on macOS
_rsr_user_create_darwin() {
    _username="$1" _uid="$2" _gid="$3" _home="$4" _shell="$5" _comment="$6" _create_home="$7"

    # Get next available UID if not specified
    if [ -z "$_uid" ]; then
        _uid=$(dscl . -list /Users UniqueID 2> /dev/null | awk '$2 >= 500 {print $2}' | sort -n | tail -1)
        _uid=$((_uid + 1))
    fi

    # Default GID (staff = 20)
    [ -z "$_gid" ] && _gid="20"

    # Default home
    [ -z "$_home" ] && _home="/Users/$_username"

    # Default shell
    [ -z "$_shell" ] && _shell="/bin/zsh"

    # Use sysadminctl on macOS 10.10+
    if rsr_has_command sysadminctl; then
        _cmd="sysadminctl -addUser $_username -UID $_uid -GID $_gid -shell $_shell"
        [ -n "$_comment" ] && _cmd="$_cmd -fullName \"$_comment\""
        [ "$_create_home" = "1" ] && _cmd="$_cmd -home $_home"
        eval "$_cmd"
    else
        # Fallback to dscl
        dscl . -create "/Users/$_username"
        dscl . -create "/Users/$_username" UniqueID "$_uid"
        dscl . -create "/Users/$_username" PrimaryGroupID "$_gid"
        dscl . -create "/Users/$_username" UserShell "$_shell"
        dscl . -create "/Users/$_username" NFSHomeDirectory "$_home"
        [ -n "$_comment" ] && dscl . -create "/Users/$_username" RealName "$_comment"

        if [ "$_create_home" = "1" ]; then
            mkdir -p "$_home"
            chown "$_username:$_gid" "$_home"
        fi
    fi
}

# Create user on FreeBSD
_rsr_user_create_freebsd() {
    _username="$1" _uid="$2" _gid="$3" _home="$4" _shell="$5" _comment="$6" _create_home="$7"

    _cmd="pw useradd $_username"
    [ -n "$_uid" ] && _cmd="$_cmd -u $_uid"
    [ -n "$_gid" ] && _cmd="$_cmd -g $_gid"
    [ -n "$_home" ] && _cmd="$_cmd -d $_home"
    [ -n "$_shell" ] && _cmd="$_cmd -s $_shell" || _cmd="$_cmd -s /bin/sh"
    [ -n "$_comment" ] && _cmd="$_cmd -c \"$_comment\""
    [ "$_create_home" = "1" ] && _cmd="$_cmd -m"

    eval "$_cmd"
}

# =============================================================================
# User Deletion
# =============================================================================

# Delete a user
# Usage: rsr_user_delete "username" [--remove-home]
rsr_user_delete() {
    _username="$1"
    shift
    _remove_home=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --remove-home)
                _remove_home=1
                shift
                ;;
            *) shift ;;
        esac
    done

    if ! rsr_user_exists "$_username"; then
        rsr_log_error "User '$_username' does not exist"
        return "$RSR_EXIT_NOT_FOUND"
    fi

    # Safety check
    case "$_username" in
        root | Administrator)
            rsr_log_error "Cannot delete system user '$_username'"
            return "$RSR_EXIT_PERMISSION"
            ;;
    esac

    # Get home before deletion
    _home=$(rsr_user_home "$_username")

    case "$(_rsr_users_os)" in
        darwin)
            if rsr_has_command sysadminctl; then
                sysadminctl -deleteUser "$_username"
            else
                dscl . -delete "/Users/$_username"
            fi
            ;;
        linux)
            userdel "$_username"
            ;;
        freebsd)
            pw userdel "$_username"
            ;;
    esac

    # Remove home directory if requested
    if [ "$_remove_home" = "1" ] && [ -n "$_home" ] && [ -d "$_home" ]; then
        rm -rf "$_home"
    fi
}

# =============================================================================
# User Modification
# =============================================================================

# Lock/disable user account
# Usage: rsr_user_lock "username"
rsr_user_lock() {
    _username="$1"

    if ! rsr_user_exists "$_username"; then
        rsr_log_error "User '$_username' does not exist"
        return "$RSR_EXIT_NOT_FOUND"
    fi

    case "$(_rsr_users_os)" in
        darwin)
            # Disable login by setting shell to /usr/bin/false
            dscl . -create "/Users/$_username" UserShell /usr/bin/false
            ;;
        linux)
            usermod -L "$_username"
            ;;
        freebsd)
            pw lock "$_username"
            ;;
    esac
}

# Unlock/enable user account
# Usage: rsr_user_unlock "username"
rsr_user_unlock() {
    _username="$1"

    if ! rsr_user_exists "$_username"; then
        rsr_log_error "User '$_username' does not exist"
        return "$RSR_EXIT_NOT_FOUND"
    fi

    case "$(_rsr_users_os)" in
        darwin)
            # Restore shell (default to zsh)
            dscl . -create "/Users/$_username" UserShell /bin/zsh
            ;;
        linux)
            usermod -U "$_username"
            ;;
        freebsd)
            pw unlock "$_username"
            ;;
    esac
}

# Set user shell
# Usage: rsr_user_set_shell "username" "/bin/zsh"
rsr_user_set_shell() {
    _username="$1"
    _shell="$2"

    if ! rsr_user_exists "$_username"; then
        rsr_log_error "User '$_username' does not exist"
        return "$RSR_EXIT_NOT_FOUND"
    fi

    case "$(_rsr_users_os)" in
        darwin)
            dscl . -create "/Users/$_username" UserShell "$_shell"
            ;;
        linux)
            usermod -s "$_shell" "$_username"
            ;;
        freebsd)
            pw usermod "$_username" -s "$_shell"
            ;;
    esac
}

# =============================================================================
# Password Management
# =============================================================================

# Set user password
# Usage: echo "password" | rsr_user_set_password "username"
# Note: Password is read from stdin for security
rsr_user_set_password() {
    _username="$1"

    if ! rsr_user_exists "$_username"; then
        rsr_log_error "User '$_username' does not exist"
        return "$RSR_EXIT_NOT_FOUND"
    fi

    case "$(_rsr_users_os)" in
        darwin)
            # Read password from stdin
            read -r _password
            dscl . -passwd "/Users/$_username" "$_password"
            ;;
        linux | freebsd)
            chpasswd
            ;;
    esac
}

# Generate random password
# Usage: password=$(rsr_password_generate [length])
rsr_password_generate() {
    _length="${1:-16}"

    if rsr_has_command openssl; then
        openssl rand -base64 48 | tr -dc 'a-zA-Z0-9!@#$%^&*' | head -c "$_length"
    else
        # Fallback using /dev/urandom
        tr -dc 'a-zA-Z0-9!@#$%^&*' < /dev/urandom | head -c "$_length"
    fi
    echo
}

# Force password change on next login
# Usage: rsr_user_expire_password "username"
rsr_user_expire_password() {
    _username="$1"

    if ! rsr_user_exists "$_username"; then
        rsr_log_error "User '$_username' does not exist"
        return "$RSR_EXIT_NOT_FOUND"
    fi

    case "$(_rsr_users_os)" in
        darwin)
            # macOS doesn't have chage, use pwpolicy
            pwpolicy -u "$_username" -setpolicy "newPasswordRequired=1" 2> /dev/null \
                || rsr_log_warn "Password expiry may not be supported"
            ;;
        linux)
            chage -d 0 "$_username"
            ;;
        freebsd)
            pw usermod "$_username" -p "01-Jan-1970"
            ;;
    esac
}

# =============================================================================
# Group Operations
# =============================================================================

# Check if group exists
# Usage: rsr_group_exists "groupname"
rsr_group_exists() {
    _groupname="$1"
    [ -z "$_groupname" ] && return 1

    case "$(_rsr_users_os)" in
        darwin)
            dscl . -list /Groups 2> /dev/null | grep -q "^${_groupname}$"
            ;;
        linux | freebsd)
            getent group "$_groupname" > /dev/null 2>&1
            ;;
    esac
}

# Create a group
# Usage: rsr_group_create "groupname" [--gid GID]
rsr_group_create() {
    _groupname="$1"
    shift
    _gid=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --gid)
                _gid="$2"
                shift 2
                ;;
            *) shift ;;
        esac
    done

    if rsr_group_exists "$_groupname"; then
        rsr_log_error "Group '$_groupname' already exists"
        return "$RSR_EXIT_ALREADY_EXISTS"
    fi

    case "$(_rsr_users_os)" in
        darwin)
            if [ -z "$_gid" ]; then
                _gid=$(dscl . -list /Groups PrimaryGroupID 2> /dev/null | awk '{print $2}' | sort -n | tail -1)
                _gid=$((_gid + 1))
            fi
            dscl . -create "/Groups/$_groupname"
            dscl . -create "/Groups/$_groupname" PrimaryGroupID "$_gid"
            ;;
        linux)
            if [ -n "$_gid" ]; then
                groupadd -g "$_gid" "$_groupname"
            else
                groupadd "$_groupname"
            fi
            ;;
        freebsd)
            if [ -n "$_gid" ]; then
                pw groupadd "$_groupname" -g "$_gid"
            else
                pw groupadd "$_groupname"
            fi
            ;;
    esac
}

# Delete a group
# Usage: rsr_group_delete "groupname"
rsr_group_delete() {
    _groupname="$1"

    if ! rsr_group_exists "$_groupname"; then
        rsr_log_error "Group '$_groupname' does not exist"
        return "$RSR_EXIT_NOT_FOUND"
    fi

    case "$(_rsr_users_os)" in
        darwin)
            dscl . -delete "/Groups/$_groupname"
            ;;
        linux)
            groupdel "$_groupname"
            ;;
        freebsd)
            pw groupdel "$_groupname"
            ;;
    esac
}

# Add user to group
# Usage: rsr_group_add_member "groupname" "username"
rsr_group_add_member() {
    _groupname="$1"
    _username="$2"

    if ! rsr_group_exists "$_groupname"; then
        rsr_log_error "Group '$_groupname' does not exist"
        return "$RSR_EXIT_NOT_FOUND"
    fi

    if ! rsr_user_exists "$_username"; then
        rsr_log_error "User '$_username' does not exist"
        return "$RSR_EXIT_NOT_FOUND"
    fi

    case "$(_rsr_users_os)" in
        darwin)
            dscl . -append "/Groups/$_groupname" GroupMembership "$_username"
            ;;
        linux)
            usermod -aG "$_groupname" "$_username"
            ;;
        freebsd)
            pw groupmod "$_groupname" -m "$_username"
            ;;
    esac
}

# Remove user from group
# Usage: rsr_group_remove_member "groupname" "username"
rsr_group_remove_member() {
    _groupname="$1"
    _username="$2"

    if ! rsr_group_exists "$_groupname"; then
        rsr_log_error "Group '$_groupname' does not exist"
        return "$RSR_EXIT_NOT_FOUND"
    fi

    case "$(_rsr_users_os)" in
        darwin)
            dscl . -delete "/Groups/$_groupname" GroupMembership "$_username"
            ;;
        linux)
            gpasswd -d "$_username" "$_groupname"
            ;;
        freebsd)
            pw groupmod "$_groupname" -d "$_username"
            ;;
    esac
}

# List groups for user
# Usage: rsr_user_groups "username"
rsr_user_groups() {
    _username="$1"

    if ! rsr_user_exists "$_username"; then
        rsr_log_error "User '$_username' does not exist"
        return "$RSR_EXIT_NOT_FOUND"
    fi

    case "$(_rsr_users_os)" in
        darwin)
            id -Gn "$_username" 2> /dev/null | tr ' ' '\n' | sort
            ;;
        linux | freebsd)
            id -Gn "$_username" 2> /dev/null | tr ' ' '\n' | sort
            ;;
    esac
}

# List all groups
# Usage: rsr_group_list_all
rsr_group_list_all() {
    case "$(_rsr_users_os)" in
        darwin)
            dscl . -list /Groups 2> /dev/null | grep -v "^_" | sort
            ;;
        linux | freebsd)
            awk -F: '{print $1}' /etc/group | sort
            ;;
    esac
}

# =============================================================================
# Session Information
# =============================================================================

# Get currently logged in users
# Usage: rsr_users_logged_in
rsr_users_logged_in() {
    who | awk '{print $1}' | sort -u
}

# Get user's last login
# Usage: rsr_user_last_login "username"
rsr_user_last_login() {
    _username="$1"

    if rsr_has_command lastlog; then
        lastlog -u "$_username" 2> /dev/null | tail -1
    elif rsr_has_command last; then
        last -1 "$_username" 2> /dev/null | head -1
    else
        echo "unknown"
    fi
}

# =============================================================================
# Sudo Operations
# =============================================================================

# Check if user has sudo access
# Usage: rsr_user_has_sudo "username"
rsr_user_has_sudo() {
    _username="$1"

    case "$(_rsr_users_os)" in
        darwin)
            # Check admin group
            dscl . -read "/Groups/admin" GroupMembership 2> /dev/null | grep -q "$_username"
            ;;
        linux)
            # Check sudo or wheel group
            id -nG "$_username" 2> /dev/null | grep -qE '\b(sudo|wheel)\b'
            ;;
        freebsd)
            id -nG "$_username" 2> /dev/null | grep -q '\bwheel\b'
            ;;
    esac
}

# Grant sudo access to user
# Usage: rsr_user_grant_sudo "username"
rsr_user_grant_sudo() {
    _username="$1"

    if ! rsr_user_exists "$_username"; then
        rsr_log_error "User '$_username' does not exist"
        return "$RSR_EXIT_NOT_FOUND"
    fi

    case "$(_rsr_users_os)" in
        darwin)
            dscl . -append /Groups/admin GroupMembership "$_username"
            ;;
        linux)
            if rsr_group_exists "sudo"; then
                usermod -aG sudo "$_username"
            elif rsr_group_exists "wheel"; then
                usermod -aG wheel "$_username"
            else
                rsr_log_error "Neither sudo nor wheel group exists"
                return "$RSR_EXIT_ERROR"
            fi
            ;;
        freebsd)
            pw groupmod wheel -m "$_username"
            ;;
    esac
}

# Revoke sudo access from user
# Usage: rsr_user_revoke_sudo "username"
rsr_user_revoke_sudo() {
    _username="$1"

    if ! rsr_user_exists "$_username"; then
        rsr_log_error "User '$_username' does not exist"
        return "$RSR_EXIT_NOT_FOUND"
    fi

    case "$(_rsr_users_os)" in
        darwin)
            dscl . -delete /Groups/admin GroupMembership "$_username" 2> /dev/null
            ;;
        linux)
            gpasswd -d "$_username" sudo 2> /dev/null
            gpasswd -d "$_username" wheel 2> /dev/null
            ;;
        freebsd)
            pw groupmod wheel -d "$_username"
            ;;
    esac
}

# =============================================================================
# Initialization Complete
# =============================================================================

rsr_log_debug "RSR Users Module v${_RSR_USERS_VERSION} loaded"
