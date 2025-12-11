#!/bin/bash
# lib/ssh.sh - Cross-platform SSH server management library for RSR
# Provides unified API for SSH installation, configuration, and management
#
# Usage: source lib/ssh.sh

#Requires bash 4.0+

# =============================================================================
# Module Metadata
# =============================================================================

_SSH_LIB_VERSION="1.0.0"
_SSH_LIB_LOADED=true

# =============================================================================
# Configuration Paths
# =============================================================================

_ssh_get_config_path() {
    case "$(_ssh_get_os)" in
        darwin) echo "/etc/ssh/sshd_config" ;;
        linux) echo "/etc/ssh/sshd_config" ;;
        freebsd) echo "/etc/ssh/sshd_config" ;;
        *) echo "" ;;
    esac
}

_ssh_get_service_name() {
    case "$(_ssh_get_os)" in
        darwin) echo "com.openssh.sshd" ;;
        linux)
            if systemctl list-unit-files | grep -q "^sshd.service"; then
                echo "sshd"
            else
                echo "ssh"
            fi
            ;;
        freebsd) echo "sshd" ;;
        *) echo "sshd" ;;
    esac
}

# =============================================================================
# OS Detection
# =============================================================================

_ssh_get_os() {
    if [ -z "${_SSH_OS:-}" ]; then
        case "$(uname -s 2>/dev/null || echo unknown)" in
            Darwin*) _SSH_OS="darwin" ;;
            Linux*) _SSH_OS="linux" ;;
            FreeBSD*) _SSH_OS="freebsd" ;;
            *) _SSH_OS="unknown" ;;
        esac
    fi
    echo "$_SSH_OS"
}

_ssh_has_command() {
    command -v "$1" >/dev/null 2>&1
}

_ssh_get_package_manager() {
    if _ssh_has_command apt-get; then
        echo "apt"
    elif _ssh_has_command yum; then
        echo "yum"
    elif _ssh_has_command dnf; then
        echo "dnf"
    elif _ssh_has_command pacman; then
        echo "pacman"
    elif _ssh_has_command zypper; then
        echo "zypper"
    elif _ssh_has_command brew; then
        echo "brew"
    else
        echo "unknown"
    fi
}

# =============================================================================
# SSH Server Installation
# =============================================================================

ssh_is_server_installed() {
    # Check if SSH server is installed
    if _ssh_has_command sshd; then
        return 0
    fi

    case "$(_ssh_get_os)" in
        darwin)
            # macOS has sshd built-in
            [ -f /usr/sbin/sshd ]
            ;;
        linux|freebsd)
            _ssh_has_command sshd
            ;;
        *)
            return 1
            ;;
    esac
}

ssh_install_server() {
    # Install SSH server
    local pkg_mgr
    pkg_mgr=$(_ssh_get_package_manager)

    case "$(_ssh_get_os)" in
        darwin)
            # macOS has SSH built-in, just needs to be enabled
            return 0
            ;;
        linux)
            case "$pkg_mgr" in
                apt)
                    apt-get update -qq
                    apt-get install -y openssh-server
                    ;;
                yum|dnf)
                    $pkg_mgr install -y openssh-server
                    ;;
                pacman)
                    pacman -S --noconfirm openssh
                    ;;
                zypper)
                    zypper install -y openssh
                    ;;
                *)
                    return 1
                    ;;
            esac
            ;;
        freebsd)
            # FreeBSD has SSH built-in
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# SSH Server Status
# =============================================================================

ssh_is_server_running() {
    # Check if SSH server is running
    local service_name
    service_name=$(_ssh_get_service_name)

    case "$(_ssh_get_os)" in
        darwin)
            launchctl list | grep -q com.openssh.sshd
            ;;
        linux)
            if _ssh_has_command systemctl; then
                systemctl is-active "$service_name" >/dev/null 2>&1
            else
                service "$service_name" status >/dev/null 2>&1
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

ssh_is_server_enabled() {
    # Check if SSH server is enabled at boot
    local service_name
    service_name=$(_ssh_get_service_name)

    case "$(_ssh_get_os)" in
        darwin)
            # Check if launchd service is enabled
            launchctl print-disabled system | grep -q "com.openssh.sshd.*false"
            ;;
        linux)
            if _ssh_has_command systemctl; then
                systemctl is-enabled "$service_name" >/dev/null 2>&1
            else
                # Check if service is in default runlevel
                chkconfig "$service_name" 2>/dev/null | grep -q "on"
            fi
            ;;
        freebsd)
            grep -q '^sshd_enable="YES"' /etc/rc.conf 2>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

ssh_get_server_version() {
    # Get SSH server version
    if _ssh_has_command sshd; then
        sshd -V 2>&1 | head -1 | awk '{print $1}'
    fi
}

ssh_get_server_port() {
    # Get configured SSH port
    ssh_get_config_value "Port" "22"
}

# =============================================================================
# SSH Server Control
# =============================================================================

ssh_start_server() {
    # Start SSH server
    local service_name
    service_name=$(_ssh_get_service_name)

    case "$(_ssh_get_os)" in
        darwin)
            launchctl load -w /System/Library/LaunchDaemons/ssh.plist 2>/dev/null ||
            launchctl enable system/com.openssh.sshd
            ;;
        linux)
            if _ssh_has_command systemctl; then
                systemctl start "$service_name"
            else
                service "$service_name" start
            fi
            ;;
        freebsd)
            service sshd start
            ;;
        *)
            return 1
            ;;
    esac
}

ssh_stop_server() {
    # Stop SSH server
    local service_name
    service_name=$(_ssh_get_service_name)

    case "$(_ssh_get_os)" in
        darwin)
            launchctl unload /System/Library/LaunchDaemons/ssh.plist 2>/dev/null ||
            launchctl disable system/com.openssh.sshd
            ;;
        linux)
            if _ssh_has_command systemctl; then
                systemctl stop "$service_name"
            else
                service "$service_name" stop
            fi
            ;;
        freebsd)
            service sshd stop
            ;;
        *)
            return 1
            ;;
    esac
}

ssh_restart_server() {
    # Restart SSH server
    local service_name
    service_name=$(_ssh_get_service_name)

    case "$(_ssh_get_os)" in
        darwin)
            launchctl unload /System/Library/LaunchDaemons/ssh.plist 2>/dev/null
            launchctl load -w /System/Library/LaunchDaemons/ssh.plist 2>/dev/null
            ;;
        linux)
            if _ssh_has_command systemctl; then
                systemctl restart "$service_name"
            else
                service "$service_name" restart
            fi
            ;;
        freebsd)
            service sshd restart
            ;;
        *)
            return 1
            ;;
    esac
}

ssh_enable_server() {
    # Enable SSH server at boot
    local service_name
    service_name=$(_ssh_get_service_name)

    case "$(_ssh_get_os)" in
        darwin)
            launchctl load -w /System/Library/LaunchDaemons/ssh.plist 2>/dev/null ||
            launchctl enable system/com.openssh.sshd
            ;;
        linux)
            if _ssh_has_command systemctl; then
                systemctl enable "$service_name"
            else
                chkconfig "$service_name" on
            fi
            ;;
        freebsd)
            sysrc sshd_enable="YES"
            ;;
        *)
            return 1
            ;;
    esac
}

ssh_disable_server() {
    # Disable SSH server at boot
    local service_name
    service_name=$(_ssh_get_service_name)

    case "$(_ssh_get_os)" in
        darwin)
            launchctl unload /System/Library/LaunchDaemons/ssh.plist 2>/dev/null ||
            launchctl disable system/com.openssh.sshd
            ;;
        linux)
            if _ssh_has_command systemctl; then
                systemctl disable "$service_name"
            else
                chkconfig "$service_name" off
            fi
            ;;
        freebsd)
            sysrc sshd_enable="NO"
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# SSH Configuration Management
# =============================================================================

ssh_get_config_value() {
    # Get value from sshd_config
    local key="$1"
    local default="${2:-}"
    local config_path
    config_path=$(_ssh_get_config_path)

    if [ ! -f "$config_path" ]; then
        echo "$default"
        return 1
    fi

    local value
    value=$(grep -E "^\s*${key}\s+" "$config_path" 2>/dev/null | tail -1 | awk '{print $2}' || echo "")

    if [ -z "$value" ]; then
        echo "$default"
    else
        echo "$value"
    fi
}

ssh_set_config_value() {
    # Set value in sshd_config
    local key="$1"
    local value="$2"
    local config_path
    config_path=$(_ssh_get_config_path)

    if [ ! -f "$config_path" ]; then
        return 1
    fi

    # Backup first
    ssh_backup_config

    # Check if key exists and update or add
    if grep -qE "^\s*#?\s*${key}\s" "$config_path" 2>/dev/null; then
        # Update existing (including commented)
        sed -i.tmp "s/^\s*#*\s*${key}\s.*/${key} ${value}/" "$config_path"
        rm -f "${config_path}.tmp"
    else
        # Add new setting
        echo "$key $value" >> "$config_path"
    fi
}

ssh_backup_config() {
    # Backup SSH configuration
    local config_path
    config_path=$(_ssh_get_config_path)

    if [ ! -f "$config_path" ]; then
        return 1
    fi

    local backup_dir="/etc/ssh/backups"
    mkdir -p "$backup_dir"

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$backup_dir/sshd_config.$timestamp"

    cp "$config_path" "$backup_file"

    # Keep only last 10 backups
    ls -t "$backup_dir"/sshd_config.* 2>/dev/null | tail -n +11 | xargs -r rm -f

    echo "$backup_file"
}

ssh_restore_config() {
    # Restore SSH configuration from backup
    local backup_file="$1"
    local config_path
    config_path=$(_ssh_get_config_path)

    if [ ! -f "$backup_file" ]; then
        return 1
    fi

    cp "$backup_file" "$config_path"
}

ssh_validate_config() {
    # Validate SSH configuration syntax
    if _ssh_has_command sshd; then
        sshd -t 2>&1
        return $?
    fi
    return 1
}

# =============================================================================
# SSH Connection Testing
# =============================================================================

ssh_test_connection() {
    # Test SSH connection to host
    local host="${1:-localhost}"
    local port="${2:-22}"
    local timeout="${3:-5}"

    # Test with nc/netcat
    if _ssh_has_command nc; then
        nc -z -w "$timeout" "$host" "$port" 2>/dev/null
        return $?
    fi

    # Test with timeout + /dev/tcp
    if _ssh_has_command timeout; then
        timeout "$timeout" bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null
        return $?
    fi

    # Fallback: try SSH connection
    if _ssh_has_command ssh; then
        ssh -o ConnectTimeout="$timeout" -o BatchMode=yes "$host" -p "$port" echo "test" 2>/dev/null
        local result=$?
        [ $result -eq 255 ] && return 1  # Connection failed
        return 0  # Connection succeeded (even if auth failed)
    fi

    return 1
}

ssh_get_listening_ports() {
    # Get ports SSH server is listening on
    if _ssh_has_command ss; then
        ss -tlnp 2>/dev/null | grep sshd | awk '{print $4}' | sed 's/.*://'
    elif _ssh_has_command netstat; then
        netstat -tlnp 2>/dev/null | grep sshd | awk '{print $4}' | sed 's/.*://'
    fi
}

ssh_count_active_connections() {
    # Count active SSH connections
    if _ssh_has_command ss; then
        ss -tn 2>/dev/null | grep -c :22
    elif _ssh_has_command netstat; then
        netstat -tn 2>/dev/null | grep -c :22
    else
        who | grep -c pts
    fi
}

# =============================================================================
# SSH Security & Hardening
# =============================================================================

ssh_check_root_login() {
    # Check if root login is enabled
    local value
    value=$(ssh_get_config_value "PermitRootLogin" "yes")
    [ "$value" = "no" ] && return 1
    return 0
}

ssh_check_password_auth() {
    # Check if password authentication is enabled
    local value
    value=$(ssh_get_config_value "PasswordAuthentication" "yes")
    [ "$value" = "no" ] && return 1
    return 0
}

ssh_check_empty_passwords() {
    # Check if empty passwords are permitted
    local value
    value=$(ssh_get_config_value "PermitEmptyPasswords" "no")
    [ "$value" = "yes" ] && return 0
    return 1
}

ssh_get_security_score() {
    # Calculate security score (0-100)
    local score=100

    # Root login enabled: -20
    ssh_check_root_login && score=$((score - 20))

    # Password auth enabled: -15
    ssh_check_password_auth && score=$((score - 15))

    # Empty passwords allowed: -30
    ssh_check_empty_passwords && score=$((score - 30))

    # Default port (22): -10
    local port
    port=$(ssh_get_server_port)
    [ "$port" = "22" ] && score=$((score - 10))

    # X11 forwarding enabled: -5
    local x11
    x11=$(ssh_get_config_value "X11Forwarding" "no")
    [ "$x11" = "yes" ] && score=$((score - 5))

    # No idle timeout: -10
    local timeout
    timeout=$(ssh_get_config_value "ClientAliveInterval" "0")
    [ "$timeout" = "0" ] && score=$((score - 10))

    # High max auth tries: -5
    local max_tries
    max_tries=$(ssh_get_config_value "MaxAuthTries" "6")
    [ "$max_tries" -gt 3 ] && score=$((score - 5))

    # No AllowUsers/AllowGroups: -5
    local allow_users allow_groups
    allow_users=$(ssh_get_config_value "AllowUsers" "")
    allow_groups=$(ssh_get_config_value "AllowGroups" "")
    [ -z "$allow_users" ] && [ -z "$allow_groups" ] && score=$((score - 5))

    [ $score -lt 0 ] && score=0
    echo $score
}

# =============================================================================
# SSH Logs & Monitoring
# =============================================================================

ssh_get_log_path() {
    # Get SSH log file path
    case "$(_ssh_get_os)" in
        darwin)
            echo "/var/log/system.log"
            ;;
        linux)
            if [ -f /var/log/auth.log ]; then
                echo "/var/log/auth.log"
            elif [ -f /var/log/secure ]; then
                echo "/var/log/secure"
            else
                echo "/var/log/syslog"
            fi
            ;;
        freebsd)
            echo "/var/log/auth.log"
            ;;
        *)
            echo ""
            ;;
    esac
}

ssh_tail_logs() {
    # Tail SSH logs
    local lines="${1:-50}"
    local log_path
    log_path=$(ssh_get_log_path)

    if [ -f "$log_path" ]; then
        grep -i ssh "$log_path" | tail -n "$lines"
    elif _ssh_has_command journalctl; then
        journalctl -u "$(_ssh_get_service_name)" -n "$lines" --no-pager
    fi
}

ssh_count_failed_logins() {
    # Count failed login attempts
    local log_path
    log_path=$(ssh_get_log_path)

    if [ -f "$log_path" ]; then
        grep -c "Failed password" "$log_path" 2>/dev/null || echo "0"
    elif _ssh_has_command journalctl; then
        journalctl -u "$(_ssh_get_service_name)" --no-pager | grep -c "Failed password" || echo "0"
    else
        echo "0"
    fi
}

ssh_get_last_failed_logins() {
    # Get last failed login attempts
    local count="${1:-10}"
    local log_path
    log_path=$(ssh_get_log_path)

    if [ -f "$log_path" ]; then
        grep "Failed password" "$log_path" 2>/dev/null | tail -n "$count"
    elif _ssh_has_command journalctl; then
        journalctl -u "$(_ssh_get_service_name)" --no-pager | grep "Failed password" | tail -n "$count"
    fi
}

# =============================================================================
# TODO: Future Enhancements
# =============================================================================

# TODO: SSH Certificate Authority (CA) support
#   - ssh_ca_init() - Initialize CA
#   - ssh_ca_sign_host_key() - Sign host key
#   - ssh_ca_sign_user_key() - Sign user key
#   - ssh_ca_revoke_cert() - Revoke certificate

# TODO: Multi-server management (Phase 2)
#   - ssh_remote_install() - Install on remote server
#   - ssh_remote_configure() - Configure remote server
#   - ssh_remote_harden() - Harden remote server
#   - ssh_bulk_operation() - Operate on multiple servers

# TODO: SSH Tunnel management
#   - ssh_create_tunnel() - Create SSH tunnel
#   - ssh_list_tunnels() - List active tunnels
#   - ssh_close_tunnel() - Close tunnel

# =============================================================================
# Module Initialization
# =============================================================================

# Detect OS on source
_ssh_get_os >/dev/null

