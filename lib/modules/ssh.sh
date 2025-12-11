#!/bin/sh
# lib/modules/ssh.sh - RSR SSH Management Module
# Cross-platform SSH server/client management
#
# Usage: . "${RSR_LIB_DIR:-./lib}/modules/ssh.sh"
#
# Provides:
#   - SSH server installation and configuration
#   - SSH service management
#   - SSH key management
#   - SSH hardening

# =============================================================================
# Guard: Prevent double-sourcing
# =============================================================================

[ -n "${_RSR_MODULE_SSH_LOADED:-}" ] && return 0
_RSR_MODULE_SSH_LOADED=1

# Ensure core is loaded
if [ -z "${_RSR_CORE_INIT_LOADED:-}" ]; then
    _script_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || _script_dir="."
    . "${_script_dir}/../core/init.sh" 2>/dev/null || . "./lib/core/init.sh" 2>/dev/null || {
        echo "ERROR: RSR core/init.sh must be sourced first" >&2
        return 1
    }
fi

# =============================================================================
# Module Metadata
# =============================================================================

_RSR_SSH_VERSION="2.0.0"

# =============================================================================
# Configuration Paths
# =============================================================================

# Get SSH config path
_rsr_ssh_config_path() {
    case "$(rsr_detect_os)" in
        darwin|linux|freebsd) echo "/etc/ssh/sshd_config" ;;
        *) echo "" ;;
    esac
}

# Get SSH service name
_rsr_ssh_service_name() {
    case "$(rsr_detect_os)" in
        darwin) echo "com.openssh.sshd" ;;
        linux)
            if rsr_has_command systemctl; then
                if systemctl list-unit-files 2>/dev/null | grep -q "^sshd.service"; then
                    echo "sshd"
                else
                    echo "ssh"
                fi
            else
                echo "ssh"
            fi
            ;;
        freebsd) echo "sshd" ;;
        *) echo "sshd" ;;
    esac
}

# =============================================================================
# SSH Server Detection
# =============================================================================

# Check if SSH server is installed
# Usage: if rsr_ssh_server_is_installed; then ...
rsr_ssh_server_is_installed() {
    case "$(rsr_detect_os)" in
        darwin)
            # macOS has sshd built-in
            [ -f /usr/sbin/sshd ]
            ;;
        linux|freebsd)
            rsr_has_command sshd
            ;;
        *)
            return 1
            ;;
    esac
}

# Check if SSH server is running
# Usage: if rsr_ssh_server_is_running; then ...
rsr_ssh_server_is_running() {
    case "$(rsr_detect_os)" in
        darwin)
            launchctl list 2>/dev/null | grep -q "com.openssh.sshd"
            ;;
        linux)
            if rsr_has_command systemctl; then
                systemctl is-active "$(_rsr_ssh_service_name)" >/dev/null 2>&1
            else
                service "$(_rsr_ssh_service_name)" status >/dev/null 2>&1
            fi
            ;;
        freebsd)
            service sshd status >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

# Check if SSH server is enabled at boot
# Usage: if rsr_ssh_server_is_enabled; then ...
rsr_ssh_server_is_enabled() {
    case "$(rsr_detect_os)" in
        darwin)
            systemsetup -getremotelogin 2>/dev/null | grep -qi "on"
            ;;
        linux)
            if rsr_has_command systemctl; then
                systemctl is-enabled "$(_rsr_ssh_service_name)" >/dev/null 2>&1
            else
                return 0  # Assume enabled if using SysV
            fi
            ;;
        freebsd)
            grep -q 'sshd_enable="YES"' /etc/rc.conf 2>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Get SSH server status
# Usage: rsr_ssh_server_status
rsr_ssh_server_status() {
    _installed="no"
    _running="no"
    _enabled="no"

    rsr_ssh_server_is_installed && _installed="yes"
    rsr_ssh_server_is_running && _running="yes"
    rsr_ssh_server_is_enabled && _enabled="yes"

    echo "installed: $_installed"
    echo "running: $_running"
    echo "enabled: $_enabled"
}

# =============================================================================
# SSH Server Installation
# =============================================================================

# Install SSH server
# Usage: rsr_ssh_server_install
rsr_ssh_server_install() {
    if rsr_ssh_server_is_installed; then
        rsr_log_ok "SSH server is already installed"
        return 0
    fi

    case "$(rsr_detect_os)" in
        darwin)
            rsr_log_ok "SSH server is built-in on macOS"
            return 0
            ;;
        linux)
            case "$(rsr_detect_package_manager)" in
                apt)
                    apt-get update && apt-get install -y openssh-server
                    ;;
                dnf|yum)
                    dnf install -y openssh-server || yum install -y openssh-server
                    ;;
                pacman)
                    pacman -S --noconfirm openssh
                    ;;
                zypper)
                    zypper install -y openssh
                    ;;
                apk)
                    apk add openssh
                    ;;
                *)
                    rsr_log_error "Unknown package manager"
                    return "$RSR_EXIT_ERROR"
                    ;;
            esac
            ;;
        freebsd)
            rsr_log_ok "SSH server is built-in on FreeBSD"
            return 0
            ;;
        *)
            rsr_log_error "Unsupported OS: $(rsr_detect_os)"
            return "$RSR_EXIT_ERROR"
            ;;
    esac
}

# =============================================================================
# SSH Server Control
# =============================================================================

# Start SSH server
# Usage: rsr_ssh_server_start
rsr_ssh_server_start() {
    if rsr_ssh_server_is_running; then
        rsr_log_ok "SSH server is already running"
        return 0
    fi

    case "$(rsr_detect_os)" in
        darwin)
            launchctl load -w /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || \
                systemsetup -setremotelogin on
            ;;
        linux)
            if rsr_has_command systemctl; then
                systemctl start "$(_rsr_ssh_service_name)"
            else
                service "$(_rsr_ssh_service_name)" start
            fi
            ;;
        freebsd)
            service sshd start
            ;;
        *)
            rsr_log_error "Unsupported OS"
            return "$RSR_EXIT_ERROR"
            ;;
    esac
}

# Stop SSH server
# Usage: rsr_ssh_server_stop
rsr_ssh_server_stop() {
    if ! rsr_ssh_server_is_running; then
        rsr_log_ok "SSH server is not running"
        return 0
    fi

    case "$(rsr_detect_os)" in
        darwin)
            launchctl unload -w /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || \
                systemsetup -setremotelogin off
            ;;
        linux)
            if rsr_has_command systemctl; then
                systemctl stop "$(_rsr_ssh_service_name)"
            else
                service "$(_rsr_ssh_service_name)" stop
            fi
            ;;
        freebsd)
            service sshd stop
            ;;
    esac
}

# Restart SSH server
# Usage: rsr_ssh_server_restart
rsr_ssh_server_restart() {
    case "$(rsr_detect_os)" in
        darwin)
            rsr_ssh_server_stop
            sleep 1
            rsr_ssh_server_start
            ;;
        linux)
            if rsr_has_command systemctl; then
                systemctl restart "$(_rsr_ssh_service_name)"
            else
                service "$(_rsr_ssh_service_name)" restart
            fi
            ;;
        freebsd)
            service sshd restart
            ;;
    esac
}

# Enable SSH server at boot
# Usage: rsr_ssh_server_enable
rsr_ssh_server_enable() {
    case "$(rsr_detect_os)" in
        darwin)
            systemsetup -setremotelogin on
            ;;
        linux)
            if rsr_has_command systemctl; then
                systemctl enable "$(_rsr_ssh_service_name)"
            fi
            ;;
        freebsd)
            sysrc sshd_enable="YES"
            ;;
    esac
}

# Disable SSH server at boot
# Usage: rsr_ssh_server_disable
rsr_ssh_server_disable() {
    case "$(rsr_detect_os)" in
        darwin)
            systemsetup -setremotelogin off
            ;;
        linux)
            if rsr_has_command systemctl; then
                systemctl disable "$(_rsr_ssh_service_name)"
            fi
            ;;
        freebsd)
            sysrc sshd_enable="NO"
            ;;
    esac
}

# =============================================================================
# SSH Configuration
# =============================================================================

# Get SSH config value
# Usage: value=$(rsr_ssh_config_get "PermitRootLogin")
rsr_ssh_config_get() {
    _key="$1"
    _config="$(_rsr_ssh_config_path)"

    [ -f "$_config" ] || return 1

    grep -E "^[[:space:]]*${_key}[[:space:]]" "$_config" 2>/dev/null | awk '{print $2}'
}

# Set SSH config value
# Usage: rsr_ssh_config_set "PermitRootLogin" "no"
rsr_ssh_config_set() {
    _key="$1"
    _value="$2"
    _config="$(_rsr_ssh_config_path)"

    [ -f "$_config" ] || {
        rsr_log_error "SSH config not found: $_config"
        return "$RSR_EXIT_NOT_FOUND"
    }

    # Backup config
    cp "$_config" "${_config}.bak.$(date +%Y%m%d%H%M%S)"

    # Check if key exists
    if grep -qE "^[[:space:]]*#?[[:space:]]*${_key}[[:space:]]" "$_config"; then
        # Update existing (commented or not)
        sed -i.tmp "s/^[[:space:]]*#*[[:space:]]*${_key}[[:space:]].*/${_key} ${_value}/" "$_config"
        rm -f "${_config}.tmp"
    else
        # Append new
        echo "${_key} ${_value}" >> "$_config"
    fi
}

# Validate SSH config
# Usage: if rsr_ssh_config_test; then ...
rsr_ssh_config_test() {
    sshd -t 2>/dev/null
}

# =============================================================================
# SSH Key Management
# =============================================================================

# Generate SSH key pair
# Usage: rsr_ssh_key_generate "email@example.com" [keyfile] [type]
rsr_ssh_key_generate() {
    _email="$1"
    _keyfile="${2:-$HOME/.ssh/id_ed25519}"
    _type="${3:-ed25519}"

    # Create .ssh directory if needed
    mkdir -p "$(dirname "$_keyfile")"
    chmod 700 "$(dirname "$_keyfile")"

    # Generate key
    ssh-keygen -t "$_type" -C "$_email" -f "$_keyfile" -N ""

    chmod 600 "$_keyfile"
    chmod 644 "${_keyfile}.pub"

    rsr_log_ok "SSH key generated: $_keyfile"
}

# Get SSH public key
# Usage: pubkey=$(rsr_ssh_key_get_public [keyfile])
rsr_ssh_key_get_public() {
    _keyfile="${1:-$HOME/.ssh/id_ed25519.pub}"

    # Try common key files
    for _f in "$_keyfile" "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub"; do
        if [ -f "$_f" ]; then
            cat "$_f"
            return 0
        fi
    done

    rsr_log_error "No SSH public key found"
    return "$RSR_EXIT_NOT_FOUND"
}

# Add public key to authorized_keys
# Usage: echo "ssh-ed25519 AAAA..." | rsr_ssh_authorized_keys_add [user]
rsr_ssh_authorized_keys_add() {
    _user="${1:-$(whoami)}"

    # Get home directory
    if [ -n "${_RSR_MODULE_USERS_LOADED:-}" ]; then
        _home=$(rsr_user_home "$_user" 2>/dev/null)
    fi
    [ -z "$_home" ] && _home="$HOME"

    _auth_keys="$_home/.ssh/authorized_keys"

    # Create .ssh directory
    mkdir -p "$_home/.ssh"
    chmod 700 "$_home/.ssh"

    # Read public key from stdin
    read -r _pubkey

    # Check if key already exists
    if [ -f "$_auth_keys" ] && grep -qF "$_pubkey" "$_auth_keys"; then
        rsr_log_warn "Key already exists in authorized_keys"
        return 0
    fi

    # Append key
    echo "$_pubkey" >> "$_auth_keys"
    chmod 600 "$_auth_keys"

    # Fix ownership if running as root
    if rsr_is_root && [ "$_user" != "root" ]; then
        chown -R "$_user" "$_home/.ssh"
    fi

    rsr_log_ok "Key added to authorized_keys"
}

# Remove public key from authorized_keys
# Usage: rsr_ssh_authorized_keys_remove "key-comment-or-pattern" [user]
rsr_ssh_authorized_keys_remove() {
    _pattern="$1"
    _user="${2:-$(whoami)}"

    # Get home directory
    if [ -n "${_RSR_MODULE_USERS_LOADED:-}" ]; then
        _home=$(rsr_user_home "$_user" 2>/dev/null)
    fi
    [ -z "$_home" ] && _home="$HOME"

    _auth_keys="$_home/.ssh/authorized_keys"

    [ -f "$_auth_keys" ] || {
        rsr_log_warn "No authorized_keys file"
        return 0
    }

    # Backup
    cp "$_auth_keys" "${_auth_keys}.bak"

    # Remove matching lines
    grep -v "$_pattern" "$_auth_keys" > "${_auth_keys}.tmp"
    mv "${_auth_keys}.tmp" "$_auth_keys"
    chmod 600 "$_auth_keys"

    rsr_log_ok "Removed keys matching: $_pattern"
}

# List authorized keys
# Usage: rsr_ssh_authorized_keys_list [user]
rsr_ssh_authorized_keys_list() {
    _user="${1:-$(whoami)}"

    # Get home directory
    if [ -n "${_RSR_MODULE_USERS_LOADED:-}" ]; then
        _home=$(rsr_user_home "$_user" 2>/dev/null)
    fi
    [ -z "$_home" ] && _home="$HOME"

    _auth_keys="$_home/.ssh/authorized_keys"

    [ -f "$_auth_keys" ] || {
        echo "No authorized_keys file"
        return 0
    }

    cat "$_auth_keys"
}

# =============================================================================
# SSH Hardening
# =============================================================================

# Apply SSH hardening settings
# Usage: rsr_ssh_harden [--disable-root] [--disable-password] [--change-port PORT]
rsr_ssh_harden() {
    _disable_root=0
    _disable_password=0
    _port=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --disable-root) _disable_root=1; shift ;;
            --disable-password) _disable_password=1; shift ;;
            --change-port) _port="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    rsr_log_info "Applying SSH hardening..."

    # Backup config
    _config="$(_rsr_ssh_config_path)"
    cp "$_config" "${_config}.backup.$(date +%Y%m%d%H%M%S)"

    # Apply settings
    if [ "$_disable_root" = "1" ]; then
        rsr_ssh_config_set "PermitRootLogin" "no"
        rsr_log_ok "Disabled root login"
    fi

    if [ "$_disable_password" = "1" ]; then
        rsr_ssh_config_set "PasswordAuthentication" "no"
        rsr_ssh_config_set "ChallengeResponseAuthentication" "no"
        rsr_log_ok "Disabled password authentication"
    fi

    if [ -n "$_port" ]; then
        rsr_ssh_config_set "Port" "$_port"
        rsr_log_ok "Changed port to $_port"
    fi

    # Always apply these security settings
    rsr_ssh_config_set "Protocol" "2"
    rsr_ssh_config_set "X11Forwarding" "no"
    rsr_ssh_config_set "MaxAuthTries" "3"
    rsr_ssh_config_set "ClientAliveInterval" "300"
    rsr_ssh_config_set "ClientAliveCountMax" "2"

    # Test config
    if rsr_ssh_config_test; then
        rsr_log_ok "SSH configuration is valid"
        rsr_log_info "Restart SSH to apply: rsr_ssh_server_restart"
    else
        rsr_log_error "SSH configuration is invalid!"
        rsr_log_info "Restoring backup..."
        cp "${_config}.backup."* "$_config" 2>/dev/null
        return "$RSR_EXIT_ERROR"
    fi
}

# =============================================================================
# SSH Connection Testing
# =============================================================================

# Test SSH connection
# Usage: if rsr_ssh_test_connection "user@host" [port]; then ...
rsr_ssh_test_connection() {
    _target="$1"
    _port="${2:-22}"

    ssh -o BatchMode=yes -o ConnectTimeout=5 -p "$_port" "$_target" exit 2>/dev/null
}

# =============================================================================
# SSH Key Distribution
# =============================================================================

# List local SSH keys
# Usage: rsr_ssh_list_local_keys
rsr_ssh_list_local_keys() {
    _ssh_dir="$HOME/.ssh"
    [ -d "$_ssh_dir" ] || return 0

    find "$_ssh_dir" -type f \( -name "id_*.pub" -o -name "*.pub" \) 2>/dev/null | sort
}

# Get SSH key fingerprint
# Usage: rsr_ssh_get_key_fingerprint "path/to/key.pub"
rsr_ssh_get_key_fingerprint() {
    _keyfile="$1"
    [ -f "$_keyfile" ] || return 1

    ssh-keygen -lf "$_keyfile" 2>/dev/null | awk '{print $2}'
}

# Check if SSH key file exists
# Usage: if rsr_ssh_key_file_exists "~/.ssh/id_ed25519"; then ...
rsr_ssh_key_file_exists() {
    _keyfile="$1"
    # Expand tilde
    _keyfile="${_keyfile/#\~/$HOME}"
    [ -f "$_keyfile" ]
}

# Copy SSH key to remote host
# Usage: rsr_ssh_copy_key_to_host "user@host" [keyfile] [port]
rsr_ssh_copy_key_to_host() {
    _target="$1"
    _keyfile="${2:-}"
    _port="${3:-22}"

    # Auto-detect key if not specified
    if [ -z "$_keyfile" ]; then
        for _f in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub" "$HOME/.ssh/id_ecdsa.pub"; do
            if [ -f "$_f" ]; then
                _keyfile="$_f"
                break
            fi
        done
    fi

    [ -f "$_keyfile" ] || {
        rsr_log_error "No public key found: $_keyfile"
        return "$RSR_EXIT_NOT_FOUND"
    }

    _pubkey=$(cat "$_keyfile")

    # Copy key using ssh
    ssh -p "$_port" "$_target" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$_pubkey' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" 2>/dev/null
}

# Test SSH key authentication
# Usage: if rsr_ssh_test_key_auth "user@host" [keyfile] [port]; then ...
rsr_ssh_test_key_auth() {
    _target="$1"
    _keyfile="${2:-}"
    _port="${3:-22}"

    _ssh_opts="-o BatchMode=yes -o ConnectTimeout=5 -o PreferredAuthentications=publickey"
    [ -n "$_keyfile" ] && _ssh_opts="$_ssh_opts -i $_keyfile"

    ssh $_ssh_opts -p "$_port" "$_target" exit 2>/dev/null
}

# Remove SSH key from remote host
# Usage: rsr_ssh_revoke_key_from_host "user@host" "pattern" [port]
rsr_ssh_revoke_key_from_host() {
    _target="$1"
    _pattern="$2"
    _port="${3:-22}"

    ssh -p "$_port" "$_target" "[ -f ~/.ssh/authorized_keys ] && grep -v '$_pattern' ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.tmp && mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys" 2>/dev/null
}

# =============================================================================
# Initialization Complete
# =============================================================================

rsr_log_debug "RSR SSH Module v${_RSR_SSH_VERSION} loaded"

