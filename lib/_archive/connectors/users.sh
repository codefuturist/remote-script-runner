#!/bin/bash
# lib/users.sh - Cross-platform user management utilities for RSR
# Bash-compatible with platform-specific implementations
#
# Source this in user-related scripts:
#   . "${0%/*}/../lib/users.sh"
#
# Provides: user creation, password management, groups, permissions, sessions

# =============================================================================
# OS Detection & Setup
# =============================================================================

# Get OS type (cached for performance)
_users_get_os() {
    if [ -z "${_USERS_OS:-}" ]; then
        case "$(uname -s 2>/dev/null || echo unknown)" in
            Darwin*) _USERS_OS="darwin" ;;
            Linux*) _USERS_OS="linux" ;;
            FreeBSD*) _USERS_OS="freebsd" ;;
            *) _USERS_OS="unknown" ;;
        esac
    fi
    echo "$_USERS_OS"
}

# Check if command exists
_users_has_command() {
    command -v "$1" >/dev/null 2>&1
}

# =============================================================================
# User Existence & Info
# =============================================================================

# Check if user exists (cross-platform)
# Usage: user_exists "username"
# Returns: 0 if exists, 1 if not
user_exists() {
    local username="$1"
    case "$(_users_get_os)" in
        darwin)
            dscl . -list /Users | grep -q "^${username}$" 2>/dev/null
            ;;
        linux|freebsd)
            id "$username" >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

# Get user info (cross-platform)
# Usage: user_get_info "username"
# Returns: uid:gid:home:shell or empty if not exists
user_get_info() {
    local username="$1"
    case "$(_users_get_os)" in
        darwin)
            if user_exists "$username"; then
                local uid=$(dscl . -read "/Users/$username" UniqueID 2>/dev/null | awk '{print $2}')
                local gid=$(dscl . -read "/Users/$username" PrimaryGroupID 2>/dev/null | awk '{print $2}')
                local home=$(dscl . -read "/Users/$username" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
                local shell=$(dscl . -read "/Users/$username" UserShell 2>/dev/null | awk '{print $2}')
                echo "${uid}:${gid}:${home}:${shell}"
            fi
            ;;
        linux|freebsd)
            getent passwd "$username" 2>/dev/null | awk -F: '{print $3":"$4":"$6":"$7}'
            ;;
    esac
}

# Get all human users (UID >= 1000 or UID 0)
# Usage: user_list_humans
user_list_humans() {
    case "$(_users_get_os)" in
        darwin)
            dscl . -list /Users UniqueID | awk '$2 >= 500 || $2 == 0 { print $1 }' | \
                grep -v "^_" | grep -v "nobody"
            ;;
        linux|freebsd)
            awk -F: '$3 >= 1000 || $3 == 0 { print $1 }' /etc/passwd
            ;;
    esac
}

# Get all users
# Usage: user_list_all
user_list_all() {
    case "$(_users_get_os)" in
        darwin)
            dscl . -list /Users | grep -v "^_" | sort
            ;;
        linux|freebsd)
            awk -F: '{ print $1 }' /etc/passwd | sort
            ;;
    esac
}

# =============================================================================
# User Creation
# =============================================================================

# Create user (cross-platform)
# Usage: user_create "username" [options]
# Options: --uid UID --gid GID --home PATH --shell SHELL --comment "Full Name"
user_create() {
    local username="$1"
    shift

    if user_exists "$username"; then
        log_error "User '$username' already exists"
        return 1
    fi

    case "$(_users_get_os)" in
        darwin)
            _user_create_darwin "$username" "$@"
            ;;
        linux)
            _user_create_linux "$username" "$@"
            ;;
        *)
            log_error "Unsupported OS: $(_users_get_os)"
            return 1
            ;;
    esac
}

# Create user on Linux
_user_create_linux() {
    local username="$1"
    shift

    local uid="" gid="" home="" shell="/bin/bash" comment="" create_home=true

    # Parse options
    while [ $# -gt 0 ]; do
        case "$1" in
            --uid) uid="$2"; shift 2 ;;
            --gid) gid="$2"; shift 2 ;;
            --home) home="$2"; shift 2 ;;
            --shell) shell="$2"; shift 2 ;;
            --comment) comment="$2"; shift 2 ;;
            --no-create-home) create_home=false; shift ;;
            *) shift ;;
        esac
    done

    # Build useradd command
    local cmd="useradd"
    [ -n "$uid" ] && cmd="$cmd -u $uid"
    [ -n "$gid" ] && cmd="$cmd -g $gid"
    [ -n "$home" ] && cmd="$cmd -d $home"
    [ -n "$shell" ] && cmd="$cmd -s $shell"
    [ -n "$comment" ] && cmd="$cmd -c \"$comment\""
    [ "$create_home" = "true" ] && cmd="$cmd -m"
    cmd="$cmd $username"

    eval "$cmd"
}

# Create user on macOS
_user_create_darwin() {
    local username="$1"
    shift

    local uid="" gid="20" home="" shell="/bin/bash" comment="" create_home=true

    # Parse options
    while [ $# -gt 0 ]; do
        case "$1" in
            --uid) uid="$2"; shift 2 ;;
            --gid) gid="$2"; shift 2 ;;
            --home) home="$2"; shift 2 ;;
            --shell) shell="$2"; shift 2 ;;
            --comment) comment="$2"; shift 2 ;;
            --no-create-home) create_home=false; shift ;;
            *) shift ;;
        esac
    done

    # Get next available UID if not specified
    if [ -z "$uid" ]; then
        uid=$(dscl . -list /Users UniqueID | awk '$2 >= 500 {print $2}' | sort -n | tail -1)
        uid=$((uid + 1))
    fi

    # Set home directory
    [ -z "$home" ] && home="/Users/$username"

    # Create user with sysadminctl (macOS 10.10+)
    if _users_has_command sysadminctl; then
        local cmd="sysadminctl -addUser $username"
        [ -n "$uid" ] && cmd="$cmd -UID $uid"
        [ -n "$gid" ] && cmd="$cmd -GID $gid"
        [ -n "$shell" ] && cmd="$cmd -shell $shell"
        [ -n "$comment" ] && cmd="$cmd -fullName \"$comment\""
        [ "$create_home" = "true" ] && cmd="$cmd -home $home"

        eval "$cmd"
    else
        # Fallback to dscl
        dscl . -create "/Users/$username"
        dscl . -create "/Users/$username" UserShell "$shell"
        dscl . -create "/Users/$username" UniqueID "$uid"
        dscl . -create "/Users/$username" PrimaryGroupID "$gid"
        dscl . -create "/Users/$username" NFSHomeDirectory "$home"
        [ -n "$comment" ] && dscl . -create "/Users/$username" RealName "$comment"

        # Create home directory
        if [ "$create_home" = "true" ] && [ ! -d "$home" ]; then
            mkdir -p "$home"
            chown "$username:$gid" "$home"
            chmod 755 "$home"
        fi
    fi
}

# =============================================================================
# User Deletion
# =============================================================================

# Delete user (cross-platform)
# Usage: user_delete "username" [--remove-home]
user_delete() {
    local username="$1"
    local remove_home=false

    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            --remove-home) remove_home=true; shift ;;
            *) shift ;;
        esac
    done

    if ! user_exists "$username"; then
        log_error "User '$username' does not exist"
        return 1
    fi

    case "$(_users_get_os)" in
        darwin)
            _user_delete_darwin "$username" "$remove_home"
            ;;
        linux)
            _user_delete_linux "$username" "$remove_home"
            ;;
        *)
            log_error "Unsupported OS: $(_users_get_os)"
            return 1
            ;;
    esac
}

# Delete user on Linux
_user_delete_linux() {
    local username="$1"
    local remove_home="$2"

    if [ "$remove_home" = "true" ]; then
        userdel -r "$username"
    else
        userdel "$username"
    fi
}

# Delete user on macOS
_user_delete_darwin() {
    local username="$1"
    local remove_home="$2"

    if _users_has_command sysadminctl; then
        sysadminctl -deleteUser "$username"
    else
        dscl . -delete "/Users/$username"
    fi

    # Remove home directory if requested
    if [ "$remove_home" = "true" ]; then
        local home=$(dscl . -read "/Users/$username" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
        [ -n "$home" ] && [ -d "$home" ] && rm -rf "$home"
    fi
}

# =============================================================================
# User Modification
# =============================================================================

# Lock user account (disable login)
# Usage: user_lock "username"
user_lock() {
    local username="$1"

    if ! user_exists "$username"; then
        log_error "User '$username' does not exist"
        return 1
    fi

    case "$(_users_get_os)" in
        darwin)
            dscl . -create "/Users/$username" AuthenticationAuthority ";DisabledUser;"
            ;;
        linux)
            if _users_has_command usermod; then
                usermod -L "$username"
            else
                passwd -l "$username"
            fi
            ;;
        *)
            log_error "Unsupported OS: $(_users_get_os)"
            return 1
            ;;
    esac
}

# Unlock user account
# Usage: user_unlock "username"
user_unlock() {
    local username="$1"

    if ! user_exists "$username"; then
        log_error "User '$username' does not exist"
        return 1
    fi

    case "$(_users_get_os)" in
        darwin)
            dscl . -delete "/Users/$username" AuthenticationAuthority
            ;;
        linux)
            if _users_has_command usermod; then
                usermod -U "$username"
            else
                passwd -u "$username"
            fi
            ;;
        *)
            log_error "Unsupported OS: $(_users_get_os)"
            return 1
            ;;
    esac
}

# Change user shell
# Usage: user_set_shell "username" "/bin/zsh"
user_set_shell() {
    local username="$1"
    local shell="$2"

    if ! user_exists "$username"; then
        log_error "User '$username' does not exist"
        return 1
    fi

    case "$(_users_get_os)" in
        darwin)
            dscl . -create "/Users/$username" UserShell "$shell"
            ;;
        linux)
            usermod -s "$shell" "$username"
            ;;
        *)
            log_error "Unsupported OS: $(_users_get_os)"
            return 1
            ;;
    esac
}

# =============================================================================
# Password Management
# =============================================================================

# Set user password (interactive)
# Usage: password_set "username"
password_set() {
    local username="$1"

    if ! user_exists "$username"; then
        log_error "User '$username' does not exist"
        return 1
    fi

    case "$(_users_get_os)" in
        darwin)
            if _users_has_command sysadminctl; then
                sysadminctl -resetPasswordFor "$username" -newPassword -
            else
                passwd "$username"
            fi
            ;;
        linux)
            passwd "$username"
            ;;
        *)
            log_error "Unsupported OS: $(_users_get_os)"
            return 1
            ;;
    esac
}

# Set password from string (non-interactive)
# Usage: password_set_string "username" "password"
password_set_string() {
    local username="$1"
    local password="$2"

    if ! user_exists "$username"; then
        log_error "User '$username' does not exist"
        return 1
    fi

    case "$(_users_get_os)" in
        darwin)
            if _users_has_command sysadminctl; then
                echo "$password" | sysadminctl -resetPasswordFor "$username" -newPassword -
            else
                dscl . -passwd "/Users/$username" "$password"
            fi
            ;;
        linux)
            echo "$username:$password" | chpasswd
            ;;
        *)
            log_error "Unsupported OS: $(_users_get_os)"
            return 1
            ;;
    esac
}

# Generate random password
# Usage: password_generate [length]
password_generate() {
    local length="${1:-16}"

    if _users_has_command openssl; then
        openssl rand -base64 "$((length * 3 / 4))" | tr -dc 'A-Za-z0-9!@#$%^&*' | head -c "$length"
    elif [ -f /dev/urandom ]; then
        tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c "$length"
    else
        # Fallback to basic random
        date +%s | sha256sum | base64 | head -c "$length"
    fi
    echo
}

# Force password change on next login
# Usage: password_expire_now "username"
password_expire_now() {
    local username="$1"

    if ! user_exists "$username"; then
        log_error "User '$username' does not exist"
        return 1
    fi

    case "$(_users_get_os)" in
        darwin)
            pwpolicy -u "$username" -setpolicy "newPasswordRequired=1"
            ;;
        linux)
            if _users_has_command chage; then
                chage -d 0 "$username"
            else
                passwd -e "$username"
            fi
            ;;
        *)
            log_error "Unsupported OS: $(_users_get_os)"
            return 1
            ;;
    esac
}

# Get password expiry info (Linux only - chage required)
# Usage: password_get_expiry "username"
password_get_expiry() {
    local username="$1"

    if ! user_exists "$username"; then
        log_error "User '$username' does not exist"
        return 1
    fi

    case "$(_users_get_os)" in
        linux)
            if _users_has_command chage; then
                chage -l "$username"
            else
                log_warn "chage command not available"
                return 1
            fi
            ;;
        darwin)
            pwpolicy -u "$username" -getpolicy 2>/dev/null || \
                log_warn "Password policy not available on macOS"
            ;;
        *)
            log_error "Unsupported OS: $(_users_get_os)"
            return 1
            ;;
    esac
}

# =============================================================================
# Group Management
# =============================================================================

# Check if group exists
# Usage: group_exists "groupname"
group_exists() {
    local groupname="$1"
    case "$(_users_get_os)" in
        darwin)
            dscl . -list /Groups | grep -q "^${groupname}$" 2>/dev/null
            ;;
        linux|freebsd)
            getent group "$groupname" >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

# Create group
# Usage: group_create "groupname" [--gid GID]
group_create() {
    local groupname="$1"
    shift

    local gid=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --gid) gid="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if group_exists "$groupname"; then
        log_error "Group '$groupname' already exists"
        return 1
    fi

    case "$(_users_get_os)" in
        darwin)
            if [ -z "$gid" ]; then
                gid=$(dscl . -list /Groups PrimaryGroupID | awk '$2 >= 500 {print $2}' | sort -n | tail -1)
                gid=$((gid + 1))
            fi
            dscl . -create "/Groups/$groupname"
            dscl . -create "/Groups/$groupname" PrimaryGroupID "$gid"
            ;;
        linux)
            if [ -n "$gid" ]; then
                groupadd -g "$gid" "$groupname"
            else
                groupadd "$groupname"
            fi
            ;;
        *)
            log_error "Unsupported OS: $(_users_get_os)"
            return 1
            ;;
    esac
}

# Add user to group
# Usage: group_add_member "groupname" "username"
group_add_member() {
    local groupname="$1"
    local username="$2"

    if ! group_exists "$groupname"; then
        log_error "Group '$groupname' does not exist"
        return 1
    fi

    if ! user_exists "$username"; then
        log_error "User '$username' does not exist"
        return 1
    fi

    case "$(_users_get_os)" in
        darwin)
            dscl . -append "/Groups/$groupname" GroupMembership "$username"
            ;;
        linux)
            usermod -aG "$groupname" "$username"
            ;;
        *)
            log_error "Unsupported OS: $(_users_get_os)"
            return 1
            ;;
    esac
}

# Remove user from group
# Usage: group_remove_member "groupname" "username"
group_remove_member() {
    local groupname="$1"
    local username="$2"

    if ! group_exists "$groupname"; then
        log_error "Group '$groupname' does not exist"
        return 1
    fi

    case "$(_users_get_os)" in
        darwin)
            dscl . -delete "/Groups/$groupname" GroupMembership "$username"
            ;;
        linux)
            gpasswd -d "$username" "$groupname"
            ;;
        *)
            log_error "Unsupported OS: $(_users_get_os)"
            return 1
            ;;
    esac
}

# List group members
# Usage: group_list_members "groupname"
group_list_members() {
    local groupname="$1"

    if ! group_exists "$groupname"; then
        log_error "Group '$groupname' does not exist"
        return 1
    fi

    case "$(_users_get_os)" in
        darwin)
            dscl . -read "/Groups/$groupname" GroupMembership 2>/dev/null | \
                sed 's/GroupMembership: //' | tr ' ' '\n' | grep -v '^$'
            ;;
        linux|freebsd)
            getent group "$groupname" | cut -d: -f4 | tr ',' '\n'
            ;;
    esac
}

# Check if user has sudo access
# Usage: user_has_sudo "username"
user_has_sudo() {
    local username="$1"

    if ! user_exists "$username"; then
        return 1
    fi

    # Check sudo/wheel/admin groups
    case "$(_users_get_os)" in
        darwin)
            dscl . -read "/Groups/admin" GroupMembership 2>/dev/null | grep -q "\b${username}\b"
            ;;
        linux)
            groups "$username" 2>/dev/null | grep -qE '\b(sudo|wheel|admin)\b'
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# Permission Management
# =============================================================================

# Set file/directory permissions
# Usage: permission_set "path" "mode" ["owner:group"]
permission_set() {
    local path="$1"
    local mode="$2"
    local owner="${3:-}"

    if [ ! -e "$path" ]; then
        log_error "Path '$path' does not exist"
        return 1
    fi

    chmod "$mode" "$path" || return 1

    if [ -n "$owner" ]; then
        chown "$owner" "$path" || return 1
    fi
}

# Set permissions recursively
# Usage: permission_set_recursive "path" "mode" ["owner:group"]
permission_set_recursive() {
    local path="$1"
    local mode="$2"
    local owner="${3:-}"

    if [ ! -e "$path" ]; then
        log_error "Path '$path' does not exist"
        return 1
    fi

    chmod -R "$mode" "$path" || return 1

    if [ -n "$owner" ]; then
        chown -R "$owner" "$path" || return 1
    fi
}

# =============================================================================
# Session Management
# =============================================================================

# List active sessions
# Usage: session_list
session_list() {
    if _users_has_command who; then
        who
    elif _users_has_command w; then
        w
    else
        log_error "Neither 'who' nor 'w' command available"
        return 1
    fi
}

# List active sessions with details
# Usage: session_list_detailed
session_list_detailed() {
    if _users_has_command w; then
        w
    else
        session_list
    fi
}

# Get login history
# Usage: login_history ["username"] [lines]
login_history() {
    local username="${1:-}"
    local lines="${2:-20}"

    if _users_has_command last; then
        if [ -n "$username" ]; then
            last "$username" -n "$lines"
        else
            last -n "$lines"
        fi
    else
        log_error "last command not available"
        return 1
    fi
}

# Get failed login attempts
# Usage: login_failures [lines]
login_failures() {
    local lines="${1:-20}"

    case "$(_users_get_os)" in
        darwin)
            if [ -f /var/log/system.log ]; then
                grep -i "failed" /var/log/system.log | tail -n "$lines"
            else
                log_warn "System log not accessible"
                return 1
            fi
            ;;
        linux)
            if _users_has_command lastb && [ "$(id -u)" -eq 0 ]; then
                lastb -n "$lines"
            elif [ -f /var/log/auth.log ]; then
                grep "Failed password" /var/log/auth.log | tail -n "$lines"
            elif [ -f /var/log/secure ]; then
                grep "Failed password" /var/log/secure | tail -n "$lines"
            else
                log_warn "No failed login log accessible"
                return 1
            fi
            ;;
    esac
}

# =============================================================================
# SSH Key Management
# =============================================================================

# Get SSH directory for user
# Usage: ssh_get_dir "username"
ssh_get_dir() {
    local username="$1"

    if ! user_exists "$username"; then
        log_error "User '$username' does not exist"
        return 1
    fi

    local info home
    info=$(user_get_info "$username")
    home=$(echo "$info" | cut -d: -f3)

    echo "${home}/.ssh"
}

# Ensure SSH directory exists with proper permissions
# Usage: ssh_ensure_dir "username"
ssh_ensure_dir() {
    local username="$1"
    local ssh_dir

    ssh_dir=$(ssh_get_dir "$username") || return 1

    # Create directory if it doesn't exist
    if [ ! -d "$ssh_dir" ]; then
        mkdir -p "$ssh_dir"
    fi

    # Set proper ownership and permissions
    chown "$username:$(id -g "$username")" "$ssh_dir"
    chmod 700 "$ssh_dir"
}

# Generate SSH key pair for user with best practices
# Usage: ssh_generate_key "username" [OPTIONS]
#
# Generates SSH keys with security best practices:
# - Ed25519 (default) with 100 KDF rounds for stronger key derivation
# - Purpose-based naming: id_ed25519_purpose (e.g., id_ed25519_github)
# - Descriptive comment: user@hostname purpose (hostname)
# - Optional passphrase generation and SOPS encryption
#
# Options:
#   --type TYPE             Key type: ed25519 (default), ecdsa, rsa, dsa
#   --purpose PURPOSE       Purpose/label for the key (default: 'default')
#   --bits NUM              Bit size for RSA keys (default: 4096)
#   --rounds NUM            KDF rounds for ed25519/ecdsa (default: 100)
#   --comment TEXT          Custom comment (auto-generated if not provided)
#   --passphrase TEXT       Manual passphrase
#   --generate-passphrase   Auto-generate random passphrase
#   --passphrase-length NUM Length of generated passphrase (default: 24)
#   --sops                  Encrypt passphrase with SOPS
#   --sops-age KEY          Age public key for SOPS encryption
#   --output-passphrase     Display generated passphrase
#   --file PATH             Override key file path
#   --hostname NAME         Override hostname in comment
#
# Example:
#   ssh_generate_key "john" --purpose "github"
#   ssh_generate_key "john" --purpose "prod" --generate-passphrase --sops
#   Creates: ~/.ssh/id_ed25519_github with comment "john@hostname github (hostname)"
ssh_generate_key() {
    local username="$1"
    shift

    if ! user_exists "$username"; then
        log_error "User '$username' does not exist"
        return 1
    fi

    local key_type="ed25519"         # Default to ed25519 (recommended)
    local purpose="default"          # Default purpose
    local key_bits="4096"            # Only used for RSA keys
    local rounds="100"               # KDF rounds for ed25519/ecdsa
    local comment=""
    local passphrase=""
    local generate_passphrase=false
    local passphrase_length="24"
    local encrypt_with_sops=false
    local sops_age=""
    local output_passphrase=false
    local key_file_override=""
    local hostname_override=""

    # Parse options
    while [ $# -gt 0 ]; do
        case "$1" in
            --type) key_type="$2"; shift 2 ;;
            --purpose) purpose="$2"; shift 2 ;;
            --bits) key_bits="$2"; shift 2 ;;
            --rounds) rounds="$2"; shift 2 ;;
            --comment) comment="$2"; shift 2 ;;
            --passphrase) passphrase="$2"; shift 2 ;;
            --generate-passphrase) generate_passphrase=true; shift ;;
            --passphrase-length) passphrase_length="$2"; shift 2 ;;
            --sops) encrypt_with_sops=true; shift ;;
            --sops-age) sops_age="$2"; shift 2 ;;
            --output-passphrase) output_passphrase=true; shift ;;
            --file) key_file_override="$2"; shift 2 ;;
            --hostname) hostname_override="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local ssh_dir
    ssh_dir=$(ssh_get_dir "$username") || return 1
    ssh_ensure_dir "$username"

    # Sanitize purpose for filename (lowercase, alphanumeric and hyphens only)
    local safe_purpose
    safe_purpose=$(echo "$purpose" | tr '[:upper:]' '[:lower:]' | tr -c '[:alnum:]-' '-')

    # Build key filename with purpose: id_<type>_<purpose>
    local key_file
    if [ -n "$key_file_override" ]; then
        key_file="$key_file_override"
    else
        key_file="${ssh_dir}/id_${key_type}_${safe_purpose}"
    fi

    # Check if key already exists
    if [ -f "$key_file" ]; then
        log_error "Key already exists: $key_file. Use a different purpose or remove existing key."
        return 1
    fi

    # Get hostname for comment
    local hostname_short
    if [ -n "$hostname_override" ]; then
        hostname_short="$hostname_override"
    else
        hostname_short=$(hostname -s 2>/dev/null || hostname | cut -d. -f1)
    fi

    # Build descriptive comment: "user@hostname purpose (hostname)"
    if [ -z "$comment" ]; then
        comment="${username}@${hostname_short} ${purpose} (${hostname_short})"
    fi

    # Handle passphrase generation
    local actual_passphrase=""
    local passphrase_file="${key_file}.passphrase"
    local passphrase_enc_file="${key_file}.passphrase.enc"

    if [ "$generate_passphrase" = true ]; then
        # Generate strong random passphrase
        # Use openssl for cross-platform compatibility
        if _users_has_command openssl; then
            actual_passphrase=$(openssl rand -base64 "$passphrase_length" | tr -d '\n' | head -c "$passphrase_length")
            log_ok "Generated random passphrase ($passphrase_length characters)"
        else
            log_error "openssl not found. Cannot generate passphrase."
            return 1
        fi
    elif [ -n "$passphrase" ]; then
        actual_passphrase="$passphrase"
    fi

    # Handle SOPS encryption if requested
    if [ -n "$actual_passphrase" ] && [ "$encrypt_with_sops" = true ]; then
        # Check if sops is available
        if ! _users_has_command sops; then
            log_warning "SOPS not found. Install from: https://github.com/mozilla/sops"
            log_warning "Saving passphrase to: $passphrase_file"
            echo -n "$actual_passphrase" > "$passphrase_file"
            chmod 600 "$passphrase_file"
        else
            # Create temp file for passphrase
            local temp_pass_file
            temp_pass_file=$(mktemp)
            echo -n "$actual_passphrase" > "$temp_pass_file"

            # Encrypt with SOPS
            local sops_cmd="sops --encrypt"
            [ -n "$sops_age" ] && sops_cmd="$sops_cmd --age $sops_age"
            sops_cmd="$sops_cmd --output $passphrase_enc_file $temp_pass_file"

            if eval "$sops_cmd" 2>/dev/null; then
                log_ok "Passphrase encrypted with SOPS: $passphrase_enc_file"
                rm -f "$temp_pass_file"
            else
                log_error "SOPS encryption failed"
                log_warning "Saving unencrypted passphrase to: $passphrase_file"
                echo -n "$actual_passphrase" > "$passphrase_file"
                chmod 600 "$passphrase_file"
                rm -f "$temp_pass_file"
            fi
        fi
    elif [ -n "$actual_passphrase" ] && [ "$encrypt_with_sops" != true ]; then
        # Save passphrase unencrypted if not using SOPS
        log_info "Saving passphrase to: $passphrase_file"
        echo -n "$actual_passphrase" > "$passphrase_file"
        chmod 600 "$passphrase_file"
        log_warning "WARNING: Passphrase saved unencrypted. Use --sops for better security."
    fi

    # Build ssh-keygen command with best practices
    local ssh_keygen_cmd

    case "$key_type" in
        ed25519)
            # Ed25519 with KDF rounds for stronger key derivation
            # -a: KDF rounds (higher = more secure, slower to crack)
            ssh_keygen_cmd="ssh-keygen -t ed25519 -a $rounds -C \"$comment\" -f \"$key_file\" -N \"$actual_passphrase\""
            ;;
        ecdsa)
            # ECDSA with KDF rounds
            ssh_keygen_cmd="ssh-keygen -t ecdsa -a $rounds -C \"$comment\" -f \"$key_file\" -N \"$actual_passphrase\""
            ;;
        rsa)
            # RSA with specified bit size
            ssh_keygen_cmd="ssh-keygen -t rsa -b $key_bits -C \"$comment\" -f \"$key_file\" -N \"$actual_passphrase\""
            ;;
        dsa)
            # DSA (deprecated but supported)
            ssh_keygen_cmd="ssh-keygen -t dsa -b $key_bits -C \"$comment\" -f \"$key_file\" -N \"$actual_passphrase\""
            ;;
        *)
            log_error "Unsupported key type: $key_type (supported: ed25519, ecdsa, rsa, dsa)"
            return 1
            ;;
    esac

    # Execute as user if possible
    if _users_has_command sudo && [ "$(id -u)" -eq 0 ]; then
        sudo -u "$username" sh -c "$ssh_keygen_cmd"
    else
        eval "$ssh_keygen_cmd"
    fi

    # Verify key was created
    if [ ! -f "$key_file" ]; then
        log_error "Failed to generate SSH key"
        return 1
    fi

    # Set proper permissions
    chmod 600 "$key_file"
    chmod 644 "${key_file}.pub"
    chown "$username:$(id -g "$username")" "$key_file" "${key_file}.pub" 2>/dev/null || true

    # Set permissions on passphrase files if they exist
    [ -f "$passphrase_file" ] && chmod 600 "$passphrase_file" && chown "$username:$(id -g "$username")" "$passphrase_file" 2>/dev/null || true
    [ -f "$passphrase_enc_file" ] && chmod 600 "$passphrase_enc_file" && chown "$username:$(id -g "$username")" "$passphrase_enc_file" 2>/dev/null || true

    # Output passphrase if requested
    if [ "$output_passphrase" = true ] && [ -n "$actual_passphrase" ]; then
        echo ""
        log_warning "Generated Passphrase:"
        echo "$actual_passphrase"
        echo ""
        log_error "⚠ WARNING: Store this passphrase securely!"
        echo ""
    fi

    echo "$key_file"
}

# Add SSH public key to authorized_keys
# Usage: ssh_add_key "username" "public_key_content"
ssh_add_key() {
    local username="$1"
    local key_content="$2"

    if ! user_exists "$username"; then
        log_error "User '$username' does not exist"
        return 1
    fi

    if [ -z "$key_content" ]; then
        log_error "Key content is required"
        return 1
    fi

    # Validate key format (basic check)
    if ! echo "$key_content" | grep -qE '^(ssh-rsa|ssh-ed25519|ssh-dss|ecdsa-sha2-)'; then
        log_error "Invalid SSH public key format"
        return 1
    fi

    local ssh_dir auth_keys
    ssh_dir=$(ssh_get_dir "$username") || return 1
    ssh_ensure_dir "$username"

    auth_keys="${ssh_dir}/authorized_keys"

    # Check if key already exists
    if [ -f "$auth_keys" ]; then
        local key_fingerprint
        key_fingerprint=$(echo "$key_content" | awk '{print $2}')
        if grep -q "$key_fingerprint" "$auth_keys"; then
            log_error "Key already exists in authorized_keys"
            return 1
        fi
    fi

    # Add key
    echo "$key_content" >> "$auth_keys"

    # Set proper permissions
    chmod 600 "$auth_keys"
    chown "$username:$(id -g "$username")" "$auth_keys"
}

# Add SSH public key from file
# Usage: ssh_add_key_file "username" "/path/to/key.pub"
ssh_add_key_file() {
    local username="$1"
    local key_file="$2"

    if [ ! -f "$key_file" ]; then
        log_error "Key file not found: $key_file"
        return 1
    fi

    local key_content
    key_content=$(cat "$key_file")

    ssh_add_key "$username" "$key_content"
}

# Remove SSH public key from authorized_keys
# Usage: ssh_remove_key "username" "key_identifier"
# Key identifier can be: fingerprint, comment, or part of the key
ssh_remove_key() {
    local username="$1"
    local identifier="$2"

    if ! user_exists "$username"; then
        log_error "User '$username' does not exist"
        return 1
    fi

    if [ -z "$identifier" ]; then
        log_error "Key identifier is required"
        return 1
    fi

    local ssh_dir auth_keys
    ssh_dir=$(ssh_get_dir "$username") || return 1
    auth_keys="${ssh_dir}/authorized_keys"

    if [ ! -f "$auth_keys" ]; then
        log_error "No authorized_keys file found"
        return 1
    fi

    # Create backup
    cp "$auth_keys" "${auth_keys}.backup"

    # Remove matching lines
    grep -v "$identifier" "$auth_keys" > "${auth_keys}.tmp"

    # Check if anything was removed
    if cmp -s "$auth_keys" "${auth_keys}.tmp"; then
        log_error "No matching key found"
        rm "${auth_keys}.tmp"
        return 1
    fi

    # Replace file
    mv "${auth_keys}.tmp" "$auth_keys"
    chmod 600 "$auth_keys"
    chown "$username:$(id -g "$username")" "$auth_keys"
}

# List SSH authorized keys
# Usage: ssh_list_keys "username"
ssh_list_keys() {
    local username="$1"

    if ! user_exists "$username"; then
        log_error "User '$username' does not exist"
        return 1
    fi

    local ssh_dir auth_keys
    ssh_dir=$(ssh_get_dir "$username") || return 1
    auth_keys="${ssh_dir}/authorized_keys"

    if [ ! -f "$auth_keys" ]; then
        return 0
    fi

    cat "$auth_keys"
}

# Get SSH key fingerprints
# Usage: ssh_get_fingerprints "username"
ssh_get_fingerprints() {
    local username="$1"

    if ! user_exists "$username"; then
        log_error "User '$username' does not exist"
        return 1
    fi

    local ssh_dir auth_keys
    ssh_dir=$(ssh_get_dir "$username") || return 1
    auth_keys="${ssh_dir}/authorized_keys"

    if [ ! -f "$auth_keys" ]; then
        return 0
    fi

    if _users_has_command ssh-keygen; then
        ssh-keygen -lf "$auth_keys" 2>/dev/null || true
    else
        # Fallback: just show key types and comments
        awk '{print $1, $NF}' "$auth_keys"
    fi
}

# Copy SSH keys from one user to another
# Usage: ssh_copy_keys "source_user" "dest_user"
ssh_copy_keys() {
    local source_user="$1"
    local dest_user="$2"

    if ! user_exists "$source_user"; then
        log_error "Source user '$source_user' does not exist"
        return 1
    fi

    if ! user_exists "$dest_user"; then
        log_error "Destination user '$dest_user' does not exist"
        return 1
    fi

    local source_auth dest_ssh_dir
    source_auth="$(ssh_get_dir "$source_user")/authorized_keys"
    dest_ssh_dir=$(ssh_get_dir "$dest_user")

    if [ ! -f "$source_auth" ]; then
        log_error "No authorized_keys found for user '$source_user'"
        return 1
    fi

    ssh_ensure_dir "$dest_user"

    # Copy each key
    while IFS= read -r key; do
        [ -z "$key" ] && continue
        [[ "$key" =~ ^# ]] && continue  # Skip comments
        ssh_add_key "$dest_user" "$key" 2>/dev/null || true
    done < "$source_auth"
}

# Set SSH directory permissions (fix permissions)
# Usage: ssh_fix_permissions "username"
ssh_fix_permissions() {
    local username="$1"

    if ! user_exists "$username"; then
        log_error "User '$username' does not exist"
        return 1
    fi

    local ssh_dir
    ssh_dir=$(ssh_get_dir "$username") || return 1

    if [ ! -d "$ssh_dir" ]; then
        return 0
    fi

    # Fix .ssh directory
    chmod 700 "$ssh_dir"
    chown "$username:$(id -g "$username")" "$ssh_dir"

    # Fix authorized_keys
    if [ -f "${ssh_dir}/authorized_keys" ]; then
        chmod 600 "${ssh_dir}/authorized_keys"
        chown "$username:$(id -g "$username")" "${ssh_dir}/authorized_keys"
    fi

    # Fix private keys
    for key in "${ssh_dir}"/id_*; do
        [ -f "$key" ] || continue
        [[ "$key" == *.pub ]] && continue
        chmod 600 "$key"
        chown "$username:$(id -g "$username")" "$key"
    done

    # Fix public keys
    for key in "${ssh_dir}"/*.pub; do
        [ -f "$key" ] || continue
        chmod 644 "$key"
        chown "$username:$(id -g "$username")" "$key"
    done

    # Fix config if exists
    if [ -f "${ssh_dir}/config" ]; then
        chmod 600 "${ssh_dir}/config"
        chown "$username:$(id -g "$username")" "${ssh_dir}/config"
    fi

    # Fix known_hosts if exists
    if [ -f "${ssh_dir}/known_hosts" ]; then
        chmod 644 "${ssh_dir}/known_hosts"
        chown "$username:$(id -g "$username")" "${ssh_dir}/known_hosts"
    fi
}

# Get public key content from private key file
# Usage: ssh_get_public_key "username" [key_file]
ssh_get_public_key() {
    local username="$1"
    local key_file="${2:-}"

    if ! user_exists "$username"; then
        log_error "User '$username' does not exist"
        return 1
    fi

    local ssh_dir
    ssh_dir=$(ssh_get_dir "$username") || return 1

    # If no key file specified, try to find default
    if [ -z "$key_file" ]; then
        for default_key in id_rsa id_ed25519 id_ecdsa; do
            if [ -f "${ssh_dir}/${default_key}.pub" ]; then
                key_file="${ssh_dir}/${default_key}.pub"
                break
            fi
        done
    fi

    if [ -z "$key_file" ] || [ ! -f "$key_file" ]; then
        log_error "No public key found"
        return 1
    fi

    cat "$key_file"
}

# Validate SSH authorized_keys file
# Usage: ssh_validate_keys "username"
ssh_validate_keys() {
    local username="$1"

    if ! user_exists "$username"; then
        log_error "User '$username' does not exist"
        return 1
    fi

    local ssh_dir auth_keys
    ssh_dir=$(ssh_get_dir "$username") || return 1
    auth_keys="${ssh_dir}/authorized_keys"

    if [ ! -f "$auth_keys" ]; then
        return 0
    fi

    local valid_count=0
    local invalid_count=0
    local line_num=0

    while IFS= read -r line; do
        ((line_num++)) || true

        # Skip empty lines and comments
        [ -z "$line" ] && continue
        [[ "$line" =~ ^# ]] && continue

        # Validate key format
        if echo "$line" | grep -qE '^(ssh-rsa|ssh-ed25519|ssh-dss|ecdsa-sha2-)'; then
            ((valid_count++)) || true
        else
            echo "Line $line_num: Invalid key format"
            ((invalid_count++)) || true
        fi
    done < "$auth_keys"

    echo "Valid keys: $valid_count"
    echo "Invalid keys: $invalid_count"

    [ "$invalid_count" -eq 0 ]
}

# =============================================================================
# Secret Generation Functions
# =============================================================================

# Generate secure random secrets (passwords, API keys, tokens, etc.)
# Usage: secret_generate [OPTIONS]
#
# Options:
#   --type TYPE             Secret type: password (default), apikey, hex, base64, alphanumeric, numeric, custom
#   --length NUM            Length of the secret (default: 32)
#   --include-symbols       Include symbols in password/apikey (default: true)
#   --exclude-ambiguous     Exclude ambiguous characters like 0/O, 1/l/I
#   --custom-charset CHARS  Custom character set for type 'custom'
#   --prefix TEXT           Add a prefix to the secret (useful for API keys)
#   --separator             Add separators every N characters
#   --separator-char CHAR   Character to use as separator (default: "-")
#   --separator-interval N  Interval for separators (default: 4)
#   --sops                  Encrypt the secret with SOPS
#   --sops-age KEY          Age public key for SOPS encryption
#   --output-file PATH      Save secret to file
#
# Examples:
#   secret_generate --type password --length 24
#   secret_generate --type apikey --prefix "sk_live_" --length 32
#   secret_generate --type hex --length 64
#   secret_generate --type apikey --length 32 --separator
secret_generate() {
    local type="password"
    local length="32"
    local include_symbols=true
    local exclude_ambiguous=false
    local custom_charset=""
    local prefix=""
    local separator=false
    local separator_char="-"
    local separator_interval="4"
    local encrypt_with_sops=false
    local sops_age=""
    local output_file=""

    # Parse options
    while [ $# -gt 0 ]; do
        case "$1" in
            --type) type="$2"; shift 2 ;;
            --length) length="$2"; shift 2 ;;
            --include-symbols) include_symbols=true; shift ;;
            --no-symbols) include_symbols=false; shift ;;
            --exclude-ambiguous) exclude_ambiguous=true; shift ;;
            --custom-charset) custom_charset="$2"; shift 2 ;;
            --prefix) prefix="$2"; shift 2 ;;
            --separator) separator=true; shift ;;
            --separator-char) separator_char="$2"; shift 2 ;;
            --separator-interval) separator_interval="$2"; shift 2 ;;
            --sops) encrypt_with_sops=true; shift ;;
            --sops-age) sops_age="$2"; shift 2 ;;
            --output-file) output_file="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # Define character sets
    local lowercase='abcdefghijklmnopqrstuvwxyz'
    local uppercase='ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    local numbers='0123456789'
    local symbols='!@#$%^&*()-_=+[]{}|;:,.<>?'
    local hex_chars='0123456789abcdef'
    local alphanumeric="${uppercase}${lowercase}${numbers}"
    local ambiguous='0O1lI'

    # Build character set based on type
    local charset=""
    case "$type" in
        password)
            charset="${lowercase}${uppercase}${numbers}"
            [ "$include_symbols" = true ] && charset="${charset}${symbols}"
            ;;
        apikey)
            charset="$alphanumeric"
            ;;
        hex)
            charset="$hex_chars"
            ;;
        base64)
            # For base64, generate random bytes and encode
            if _users_has_command openssl; then
                local secret
                secret=$(openssl rand -base64 "$length" | tr -d '\n' | head -c "$length")
                [ -n "$prefix" ] && secret="${prefix}${secret}"
                echo "$secret"
                return 0
            else
                log_error "openssl required for base64 generation"
                return 1
            fi
            ;;
        alphanumeric)
            charset="$alphanumeric"
            ;;
        numeric)
            charset="$numbers"
            ;;
        custom)
            if [ -z "$custom_charset" ]; then
                log_error "CustomCharset is required when type is 'custom'"
                return 1
            fi
            charset="$custom_charset"
            ;;
        *)
            log_error "Unsupported secret type: $type"
            return 1
            ;;
    esac

    # Remove ambiguous characters if requested
    if [ "$exclude_ambiguous" = true ]; then
        for char in $(echo "$ambiguous" | fold -w1); do
            charset=$(echo "$charset" | tr -d "$char")
        done
    fi

    # Generate cryptographically secure random secret
    local secret=""
    local charset_len=${#charset}

    if _users_has_command openssl; then
        # Use openssl for cryptographically secure random
        for ((i=0; i<length; i++)); do
            local random_byte
            random_byte=$(openssl rand -hex 1)
            local random_num=$((16#$random_byte))
            local index=$((random_num % charset_len))
            secret="${secret}${charset:$index:1}"
        done
    elif _users_has_command /dev/urandom; then
        # Fallback to /dev/urandom
        for ((i=0; i<length; i++)); do
            local random_byte
            random_byte=$(od -An -N1 -tu1 /dev/urandom | tr -d ' ')
            local index=$((random_byte % charset_len))
            secret="${secret}${charset:$index:1}"
        done
    else
        log_error "No secure random source available (openssl or /dev/urandom required)"
        return 1
    fi

    # Add prefix if specified
    [ -n "$prefix" ] && secret="${prefix}${secret}"

    # Add separators if requested
    if [ "$separator" = true ]; then
        local separated=""
        local secret_len=${#secret}
        for ((i=0; i<secret_len; i+=separator_interval)); do
            if [ $i -gt 0 ]; then
                separated="${separated}${separator_char}"
            fi
            local end=$((i + separator_interval))
            [ $end -gt $secret_len ] && end=$secret_len
            separated="${separated}${secret:$i:$separator_interval}"
        done
        secret="$separated"
    fi

    # Handle SOPS encryption if requested
    if [ "$encrypt_with_sops" = true ]; then
        if ! _users_has_command sops; then
            log_warning "SOPS not found. Install from: https://github.com/mozilla/sops"

            if [ -n "$output_file" ]; then
                echo -n "$secret" > "$output_file"
                chmod 600 "$output_file"
                log_warning "Secret saved unencrypted to: $output_file"
            fi
        else
            # Create temp file
            local temp_file
            temp_file=$(mktemp)
            echo -n "$secret" > "$temp_file"

            local output
            if [ -n "$output_file" ]; then
                output="$output_file"
            else
                output="${temp_file}.enc"
            fi

            # Encrypt with SOPS
            local sops_cmd="sops --encrypt"
            [ -n "$sops_age" ] && sops_cmd="$sops_cmd --age $sops_age"
            sops_cmd="$sops_cmd --output $output $temp_file"

            if eval "$sops_cmd" 2>/dev/null; then
                log_ok "Secret encrypted with SOPS: $output"
                rm -f "$temp_file"
                echo "[ENCRYPTED: $output]"
                return 0
            else
                log_error "SOPS encryption failed"
                rm -f "$temp_file"

                if [ -n "$output_file" ]; then
                    echo -n "$secret" > "$output_file"
                    chmod 600 "$output_file"
                    log_warning "Secret saved unencrypted to: $output_file"
                fi
            fi
        fi
    elif [ -n "$output_file" ]; then
        # Save to file without encryption
        echo -n "$secret" > "$output_file"
        chmod 600 "$output_file"
        log_info "Secret saved to: $output_file"
        log_warning "WARNING: Secret file is unencrypted!"
    fi

    echo "$secret"
}

# Generate a secure password (convenience wrapper)
# Usage: password_generate [--length NUM] [--exclude-ambiguous] [--no-symbols]
password_generate() {
    local length="16"
    local exclude_ambiguous=false
    local include_symbols=true

    while [ $# -gt 0 ]; do
        case "$1" in
            --length) length="$2"; shift 2 ;;
            --exclude-ambiguous) exclude_ambiguous=true; shift ;;
            --no-symbols) include_symbols=false; shift ;;
            *) shift ;;
        esac
    done

    local opts=("--type" "password" "--length" "$length")
    [ "$include_symbols" = false ] && opts+=("--no-symbols")
    [ "$exclude_ambiguous" = true ] && opts+=("--exclude-ambiguous")

    secret_generate "${opts[@]}"
}

# Generate an API key (convenience wrapper)
# Usage: apikey_generate [--prefix TEXT] [--length NUM] [--separator]
apikey_generate() {
    local prefix=""
    local length="32"
    local separator=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --prefix) prefix="$2"; shift 2 ;;
            --length) length="$2"; shift 2 ;;
            --separator) separator=true; shift ;;
            *) shift ;;
        esac
    done

    local opts=("--type" "apikey" "--length" "$length")
    [ -n "$prefix" ] && opts+=("--prefix" "$prefix")
    [ "$separator" = true ] && opts+=("--separator")

    secret_generate "${opts[@]}"
}

# Generate a hex or base64 token (convenience wrapper)
# Usage: token_generate [--type hex|base64] [--length NUM]
token_generate() {
    local type="hex"
    local length="32"

    while [ $# -gt 0 ]; do
        case "$1" in
            --type) type="$2"; shift 2 ;;
            --length) length="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    secret_generate --type "$type" --length "$length"
}

# =============================================================================
# End Secret Generation Functions
# =============================================================================

# =============================================================================
# Initialization
# =============================================================================

# Detect OS on source
_users_get_os >/dev/null

