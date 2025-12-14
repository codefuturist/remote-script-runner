#!/bin/bash
# =============================================================================
# @id           ssh-harden
# @name         ssh-hardening
# @displayName  SSH Hardening
# @description  Harden SSH: disable root login, enforce keys, configure fail2ban
# @category     security
# @version      1.0.0
# @author       codefuturist
# @tags         ssh,security,hardening,fail2ban,keys,authentication
# @shells       bash
# =============================================================================

set -eo pipefail

# =============================================================================
# Load RSR Library
# =============================================================================

SCRIPT_SOURCE="${BASH_SOURCE[0]:-${0:-}}"
if [ -n "${SCRIPT_SOURCE}" ] && [ "${SCRIPT_SOURCE}" != "bash" ] && [ "${SCRIPT_SOURCE}" != "sh" ] && [ "${SCRIPT_SOURCE}" != "-bash" ] && [ "${SCRIPT_SOURCE}" != "-sh" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_SOURCE}")" 2> /dev/null && pwd)" || SCRIPT_DIR=""
else
    SCRIPT_DIR=""
fi
RSR_LIB_DIR="${SCRIPT_DIR}/../../../lib"

if [[ -f "$RSR_LIB_DIR/rsr-lib.sh" ]]; then
    source "$RSR_LIB_DIR/rsr-lib.sh" ssh validate
fi

# Script metadata
SCRIPT_NAME="SSH Hardening"
SCRIPT_VERSION="1.0.0"

# Default values
VERBOSE=false
DRY_RUN=false
INTERACTIVE=auto
APPLY_ALL=false
SHOW_STATUS=false
DISABLE_ROOT=false
KEY_ONLY=false
NEW_PORT=""
IDLE_TIMEOUT=300
MAX_AUTH_TRIES=3
ALLOW_USERS=""
ALLOW_GROUPS=""
INSTALL_FAIL2BAN=false
STRONG_CRYPTO=false
GENERATE_KEY_USER=""
DO_BACKUP=true
DO_ROLLBACK=false

# Config file
SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_DIR="/etc/ssh/backups"

# Color codes (from RSR library or fallback)
RED="${RSR_COLOR_RED:-\033[0;31m}"
GREEN="${RSR_COLOR_GREEN:-\033[0;32m}"
YELLOW="${RSR_COLOR_YELLOW:-\033[1;33m}"
BLUE="${RSR_COLOR_BLUE:-\033[0;34m}"
CYAN="${RSR_COLOR_CYAN:-\033[0;36m}"
DIM="${RSR_COLOR_DIM:-\033[2m}"
BOLD="${RSR_COLOR_BOLD:-\033[1m}"
NC="${RSR_COLOR_RESET:-\033[0m}"

# Exit codes
EXIT_OK="${RSR_EXIT_SUCCESS:-0}"
EXIT_ERROR="${RSR_EXIT_ERROR:-1}"
EXIT_INVALID_ARGS="${RSR_EXIT_USAGE:-2}"
EXIT_PERMISSION="${RSR_EXIT_PERMISSION:-3}"
EXIT_CONFIG_ERROR=4
EXIT_RESTART_FAILED=5
EXIT_LOCKOUT=6
EXIT_ROLLBACK=7

# Changes tracking
CHANGES_MADE=false

usage() {
    cat << EOF
${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}

Harden SSH server configuration with security best practices.

${YELLOW}Usage:${NC}
    $0 [OPTIONS]

${BOLD}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -a, --all               Apply all hardening measures
    -d, --dry-run           Show changes without applying
    -i, --interactive       Run in interactive mode (default when no args)
    --no-interactive        Disable interactive mode
    -y, --yes               Auto-confirm all prompts
    --status                Show current SSH configuration status
    --no-root               Disable root login
    --key-only              Disable password authentication
    -p, --port PORT         Change SSH port
    --timeout SEC           Set idle timeout (default: 300)
    --max-auth N            Max authentication attempts (default: 3)
    --allow-users USERS     Restrict to users (comma-separated)
    --allow-groups GROUPS   Restrict to groups (comma-separated)
    --fail2ban              Install and configure fail2ban
    --strong-crypto         Apply strong cipher/MAC/Kex settings
    --generate-key USER     Generate SSH key for user
    --backup                Backup config before changes (default)
    --no-backup             Skip config backup
    --rollback              Rollback to previous configuration

${BOLD}Examples:${NC}
    ${DIM}# Show current config status${NC}
    $0 --status

    ${DIM}# Dry run all hardening${NC}
    $0 -a -d

    ${DIM}# Disable root and passwords${NC}
    sudo $0 --no-root --key-only

    ${DIM}# Change SSH port${NC}
    sudo $0 -p 2222

    ${DIM}# Install fail2ban${NC}
    sudo $0 --fail2ban

    ${DIM}# Restrict users${NC}
    sudo $0 --allow-users admin,deploy

    ${DIM}# Rollback changes${NC}
    sudo $0 --rollback

${BOLD}Exit Codes:${NC}
    0 - Hardening applied successfully
    1 - General error
    2 - Invalid arguments
    3 - Permission denied (need root)
    4 - SSH config syntax error
    5 - Failed to restart SSH
    6 - Would lock out user (aborted)
    7 - Rollback required

EOF
    exit 0
}

# Logging functions (use RSR if available)
if type rsr_log_info &> /dev/null; then
    log_info() { rsr_log_info "$1"; }
    log_ok() { rsr_log_ok "$1"; }
    log_warn() { rsr_log_warn "$1"; }
    log_error() { rsr_log_error "$1"; }
    log_debug() { [[ "$VERBOSE" == "true" ]] && rsr_log_debug "$1"; }
    print_header() { rsr_print_header "$1"; }
else
    log_info() { echo -e "${BLUE}▸${NC} $1"; }
    log_ok() { echo -e "${GREEN}✓${NC} $1"; }
    log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
    log_error() { echo -e "${RED}✗${NC} $1" >&2; }
    log_debug() { [[ "$VERBOSE" == "true" ]] && echo -e "${DIM}  $1${NC}"; }
    print_header() { echo -e "\n${BOLD}${CYAN}═══ $1 ═══${NC}\n"; }
fi

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help) usage ;;
            -v | --verbose)
                VERBOSE=true
                shift
                ;;
            -a | --all)
                APPLY_ALL=true
                shift
                ;;
            -d | --dry-run)
                DRY_RUN=true
                shift
                ;;
            -i | --interactive)
                INTERACTIVE=true
                shift
                ;;
            --no-interactive)
                INTERACTIVE=false
                shift
                ;;
            -y | --yes)
                RSR_YES=1
                INTERACTIVE=false
                shift
                ;;
            --status)
                SHOW_STATUS=true
                shift
                ;;
            --no-root)
                DISABLE_ROOT=true
                shift
                ;;
            --key-only)
                KEY_ONLY=true
                shift
                ;;
            -p | --port)
                NEW_PORT="$2"
                shift 2
                ;;
            --timeout)
                IDLE_TIMEOUT="$2"
                shift 2
                ;;
            --max-auth)
                MAX_AUTH_TRIES="$2"
                shift 2
                ;;
            --allow-users)
                ALLOW_USERS="$2"
                shift 2
                ;;
            --allow-groups)
                ALLOW_GROUPS="$2"
                shift 2
                ;;
            --fail2ban)
                INSTALL_FAIL2BAN=true
                shift
                ;;
            --strong-crypto)
                STRONG_CRYPTO=true
                shift
                ;;
            --generate-key)
                GENERATE_KEY_USER="$2"
                shift 2
                ;;
            --backup)
                DO_BACKUP=true
                shift
                ;;
            --no-backup)
                DO_BACKUP=false
                shift
                ;;
            --rollback)
                DO_ROLLBACK=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                exit $EXIT_INVALID_ARGS
                ;;
            *) shift ;;
        esac
    done

    # --all enables multiple options
    if [[ "$APPLY_ALL" == "true" ]]; then
        DISABLE_ROOT=true
        KEY_ONLY=true
        STRONG_CRYPTO=true
    fi
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 && "$SHOW_STATUS" != "true" && "$DRY_RUN" != "true" ]]; then
        log_error "Root access required for SSH configuration changes"
        exit $EXIT_PERMISSION
    fi
}

# Get current setting from sshd_config
get_setting() {
    local key="$1"
    local default="${2:-}"

    local value
    value=$(grep -E "^\s*${key}\s+" "$SSHD_CONFIG" 2> /dev/null | tail -1 | awk '{print $2}' || echo "")

    if [[ -z "$value" ]]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# Show current SSH configuration status
show_status() {
    print_header "SSH Configuration Status"

    if [[ ! -f "$SSHD_CONFIG" ]]; then
        log_error "SSH server config not found at $SSHD_CONFIG"
        return 1
    fi

    printf "${BOLD}%-25s %-20s %s${NC}\n" "SETTING" "VALUE" "RECOMMENDATION"
    echo "─────────────────────────────────────────────────────────────────"

    # Port
    local port
    port=$(get_setting "Port" "22")
    local port_status="$NC"
    [[ "$port" == "22" ]] && port_status="$YELLOW"
    printf "%-25s ${port_status}%-20s${NC} %s\n" "Port" "$port" "(consider non-standard)"

    # PermitRootLogin
    local root_login
    root_login=$(get_setting "PermitRootLogin" "yes")
    local root_status="$GREEN"
    local root_rec="✓"
    if [[ "$root_login" == "yes" ]]; then
        root_status="$RED"
        root_rec="Change to 'no'"
    elif [[ "$root_login" == "prohibit-password" ]]; then
        root_status="$YELLOW"
        root_rec="Consider 'no'"
    fi
    printf "%-25s ${root_status}%-20s${NC} %s\n" "PermitRootLogin" "$root_login" "$root_rec"

    # PasswordAuthentication
    local pass_auth
    pass_auth=$(get_setting "PasswordAuthentication" "yes")
    local pass_status="$GREEN"
    local pass_rec="✓"
    if [[ "$pass_auth" == "yes" ]]; then
        pass_status="$YELLOW"
        pass_rec="Consider 'no' (key-only)"
    fi
    printf "%-25s ${pass_status}%-20s${NC} %s\n" "PasswordAuthentication" "$pass_auth" "$pass_rec"

    # PermitEmptyPasswords
    local empty_pass
    empty_pass=$(get_setting "PermitEmptyPasswords" "no")
    local empty_status="$GREEN"
    local empty_rec="✓"
    if [[ "$empty_pass" == "yes" ]]; then
        empty_status="$RED"
        empty_rec="Change to 'no' IMMEDIATELY"
    fi
    printf "%-25s ${empty_status}%-20s${NC} %s\n" "PermitEmptyPasswords" "$empty_pass" "$empty_rec"

    # MaxAuthTries
    local max_auth
    max_auth=$(get_setting "MaxAuthTries" "6")
    local auth_status="$NC"
    local auth_rec="✓"
    if [[ "$max_auth" -gt 4 ]]; then
        auth_status="$YELLOW"
        auth_rec="Consider lower (3-4)"
    fi
    printf "%-25s ${auth_status}%-20s${NC} %s\n" "MaxAuthTries" "$max_auth" "$auth_rec"

    # X11Forwarding
    local x11
    x11=$(get_setting "X11Forwarding" "yes")
    local x11_status="$NC"
    local x11_rec="✓"
    if [[ "$x11" == "yes" ]]; then
        x11_status="$YELLOW"
        x11_rec="Consider 'no' if unused"
    fi
    printf "%-25s ${x11_status}%-20s${NC} %s\n" "X11Forwarding" "$x11" "$x11_rec"

    # ClientAliveInterval
    local alive
    alive=$(get_setting "ClientAliveInterval" "0")
    local alive_rec="Consider 300"
    [[ "$alive" -gt 0 ]] && alive_rec="✓"
    printf "%-25s %-20s %s\n" "ClientAliveInterval" "$alive" "$alive_rec"

    # Protocol (old systems)
    local protocol
    protocol=$(get_setting "Protocol" "2")
    if [[ "$protocol" == "1" || "$protocol" == "1,2" ]]; then
        printf "%-25s ${RED}%-20s${NC} %s\n" "Protocol" "$protocol" "CRITICAL: Use Protocol 2 only!"
    fi

    # Check for AllowUsers/AllowGroups
    local allow_users allow_groups
    allow_users=$(get_setting "AllowUsers" "")
    allow_groups=$(get_setting "AllowGroups" "")

    if [[ -n "$allow_users" ]]; then
        printf "%-25s %-20s %s\n" "AllowUsers" "$allow_users" "✓"
    fi
    if [[ -n "$allow_groups" ]]; then
        printf "%-25s %-20s %s\n" "AllowGroups" "$allow_groups" "✓"
    fi

    echo ""

    # Check fail2ban
    log_info "Checking fail2ban..."
    if systemctl is-active fail2ban &> /dev/null; then
        log_ok "fail2ban is running"
    elif command -v fail2ban-client &> /dev/null; then
        log_warn "fail2ban is installed but not running"
    else
        log_info "fail2ban is not installed"
    fi

    return 0
}

# Backup configuration
backup_config() {
    [[ "$DO_BACKUP" != "true" ]] && return 0

    log_info "Backing up SSH configuration..."

    mkdir -p "$BACKUP_DIR"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/sshd_config.$timestamp"

    cp "$SSHD_CONFIG" "$backup_file"
    log_ok "Backup saved to $backup_file"

    # Keep only last 5 backups
    ls -t "$BACKUP_DIR"/sshd_config.* 2> /dev/null | tail -n +6 | xargs -r rm -f

    return 0
}

# Rollback to previous configuration
rollback_config() {
    log_info "Looking for backup to restore..."

    local latest_backup
    latest_backup=$(ls -t "$BACKUP_DIR"/sshd_config.* 2> /dev/null | head -1 || true)

    if [[ -z "$latest_backup" ]]; then
        log_error "No backup found in $BACKUP_DIR"
        exit $EXIT_ERROR
    fi

    log_info "Restoring from $latest_backup..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would restore $latest_backup"
        return 0
    fi

    cp "$latest_backup" "$SSHD_CONFIG"

    # Validate and restart
    if validate_config; then
        restart_sshd
        log_ok "Configuration rolled back successfully"
    else
        log_error "Rollback failed - restored config is invalid"
        exit $EXIT_CONFIG_ERROR
    fi
}

# Validate SSH configuration
validate_config() {
    log_info "Validating SSH configuration..."

    if sshd -t 2>&1; then
        log_ok "Configuration syntax is valid"
        return 0
    else
        log_error "Configuration syntax error"
        return 1
    fi
}

# Restart SSH daemon
restart_sshd() {
    log_info "Restarting SSH service..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would restart SSH service"
        return 0
    fi

    if systemctl restart sshd 2> /dev/null || systemctl restart ssh 2> /dev/null || service ssh restart 2> /dev/null || service sshd restart 2> /dev/null; then
        log_ok "SSH service restarted"
        return 0
    else
        log_error "Failed to restart SSH service"
        return 1
    fi
}

# Set a configuration value
set_config() {
    local key="$1"
    local value="$2"
    local current
    current=$(get_setting "$key" "")

    if [[ "$current" == "$value" ]]; then
        log_debug "$key already set to $value"
        return 0
    fi

    log_info "Setting $key to $value"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would set $key $value"
        return 0
    fi

    CHANGES_MADE=true

    # Check if key exists and update or add
    if grep -qE "^\s*#?\s*${key}\s" "$SSHD_CONFIG" 2> /dev/null; then
        # Update existing (including commented)
        sed -i.tmp "s/^\s*#*\s*${key}\s.*/${key} ${value}/" "$SSHD_CONFIG"
        rm -f "${SSHD_CONFIG}.tmp"
    else
        # Add new setting
        echo "$key $value" >> "$SSHD_CONFIG"
    fi

    return 0
}

# Check if current user would be locked out
check_lockout() {
    local current_user
    current_user=$(whoami)
    local current_ip
    current_ip=$(who am i 2> /dev/null | awk '{print $5}' | tr -d '()' || echo "local")

    log_info "Checking if changes would lock out current session..."

    # Check if user would be allowed
    if [[ -n "$ALLOW_USERS" ]]; then
        if ! echo "$ALLOW_USERS" | grep -qE "(^|,)${current_user}($|,)"; then
            log_error "WARNING: Current user '$current_user' not in AllowUsers list!"
            log_error "This would lock you out of the server!"
            return 1
        fi
    fi

    # Check if key-only and user has no key
    if [[ "$KEY_ONLY" == "true" ]]; then
        local user_home
        user_home=$(getent passwd "$current_user" | cut -d: -f6)
        if [[ ! -f "$user_home/.ssh/authorized_keys" ]]; then
            log_warn "Enabling key-only but $current_user has no authorized_keys"
            log_warn "Make sure you have an SSH key configured before applying!"
        fi
    fi

    return 0
}

# Apply hardening settings
apply_hardening() {
    print_header "Applying SSH Hardening"

    backup_config

    # Check for lockout first
    if ! check_lockout; then
        if [[ "$DRY_RUN" != "true" ]]; then
            log_error "Aborting to prevent lockout. Use --dry-run to preview changes."
            exit $EXIT_LOCKOUT
        fi
    fi

    # Disable root login
    if [[ "$DISABLE_ROOT" == "true" ]]; then
        set_config "PermitRootLogin" "no"
    fi

    # Key-only authentication
    if [[ "$KEY_ONLY" == "true" ]]; then
        set_config "PasswordAuthentication" "no"
        set_config "ChallengeResponseAuthentication" "no"
        set_config "UsePAM" "yes"
    fi

    # Change port
    if [[ -n "$NEW_PORT" ]]; then
        if [[ "$NEW_PORT" -lt 1 || "$NEW_PORT" -gt 65535 ]]; then
            log_error "Invalid port number: $NEW_PORT"
            exit $EXIT_INVALID_ARGS
        fi
        set_config "Port" "$NEW_PORT"
        log_warn "Remember to update firewall rules for port $NEW_PORT"
    fi

    # Idle timeout
    set_config "ClientAliveInterval" "$IDLE_TIMEOUT"
    set_config "ClientAliveCountMax" "2"

    # Max auth tries
    set_config "MaxAuthTries" "$MAX_AUTH_TRIES"

    # Allow users
    if [[ -n "$ALLOW_USERS" ]]; then
        local users
        users=$(echo "$ALLOW_USERS" | tr ',' ' ')
        set_config "AllowUsers" "$users"
    fi

    # Allow groups
    if [[ -n "$ALLOW_GROUPS" ]]; then
        local groups
        groups=$(echo "$ALLOW_GROUPS" | tr ',' ' ')
        set_config "AllowGroups" "$groups"
    fi

    # Strong crypto
    if [[ "$STRONG_CRYPTO" == "true" ]]; then
        apply_strong_crypto
    fi

    # Common hardening settings
    set_config "PermitEmptyPasswords" "no"
    set_config "X11Forwarding" "no"
    set_config "MaxSessions" "10"
    set_config "LoginGraceTime" "60"
    set_config "StrictModes" "yes"

    # Validate and apply
    if [[ "$CHANGES_MADE" == "true" && "$DRY_RUN" != "true" ]]; then
        if validate_config; then
            restart_sshd
            log_ok "SSH hardening applied successfully"
        else
            log_error "Configuration invalid - rolling back"
            rollback_config
            exit $EXIT_CONFIG_ERROR
        fi
    elif [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] No changes were applied"
    else
        log_ok "No changes needed"
    fi
}

# Apply strong cryptographic settings
apply_strong_crypto() {
    log_info "Applying strong cryptographic settings..."

    # Modern ciphers only
    set_config "Ciphers" "chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr"

    # Strong MACs
    set_config "MACs" "hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256"

    # Strong key exchange
    set_config "KexAlgorithms" "curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group-exchange-sha256"

    # Host key algorithms
    set_config "HostKeyAlgorithms" "ssh-ed25519,ssh-ed25519-cert-v01@openssh.com,rsa-sha2-512,rsa-sha2-256"
}

# Install and configure fail2ban
setup_fail2ban() {
    print_header "Fail2ban Setup"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would install and configure fail2ban"
        return 0
    fi

    # Install fail2ban
    log_info "Installing fail2ban..."

    if command -v apt-get &> /dev/null; then
        apt-get update -qq
        apt-get install -y fail2ban
    elif command -v yum &> /dev/null; then
        yum install -y epel-release
        yum install -y fail2ban
    elif command -v dnf &> /dev/null; then
        dnf install -y fail2ban
    elif command -v pacman &> /dev/null; then
        pacman -S --noconfirm fail2ban
    else
        log_error "Unsupported package manager"
        return 1
    fi

    # Configure fail2ban for SSH
    log_info "Configuring fail2ban..."

    local port
    port=$(get_setting "Port" "22")

    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = $port
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 1h
EOF

    # Start fail2ban
    systemctl enable fail2ban
    systemctl restart fail2ban

    log_ok "fail2ban configured and started"

    # Show status
    fail2ban-client status sshd 2> /dev/null || true
}

# =============================================================================
# Interactive Mode
# =============================================================================

run_interactive() {
    print_interactive_header "$SCRIPT_NAME" "$SCRIPT_VERSION"

    # Show current status first
    show_status

    echo ""

    # Main action selection
    local action
    action=$(prompt_select "What would you like to do?" \
        "Apply recommended hardening" \
        "Configure specific settings" \
        "Install/configure fail2ban" \
        "Generate SSH key for user" \
        "Change SSH port" \
        "Rollback to previous config" \
        "View status only")

    case "$action" in
        "Apply recommended hardening")
            interactive_apply_all
            ;;
        "Configure specific settings")
            interactive_specific_settings
            ;;
        "Install/configure fail2ban")
            interactive_fail2ban
            ;;
        "Generate SSH key for user")
            interactive_generate_key
            ;;
        "Change SSH port")
            interactive_change_port
            ;;
        "Rollback to previous config")
            interactive_rollback
            ;;
        "View status only")
            return 0
            ;;
    esac
}

interactive_apply_all() {
    echo ""
    log_info "Recommended hardening measures:"
    echo ""
    echo -e "  ${CYAN}•${NC} Disable root login"
    echo -e "  ${CYAN}•${NC} Disable password authentication (key-only)"
    echo -e "  ${CYAN}•${NC} Set idle timeout to 300 seconds"
    echo -e "  ${CYAN}•${NC} Limit authentication attempts to 3"
    echo -e "  ${CYAN}•${NC} Apply strong cryptographic settings"
    echo ""

    if prompt_yes_no "Also install and configure fail2ban?" "y"; then
        INSTALL_FAIL2BAN=true
    fi

    echo ""

    # Critical warning
    echo -e "${RED}${BOLD}⚠ IMPORTANT WARNING${NC}"
    echo ""
    echo -e "Before disabling password authentication, ensure you have:"
    echo -e "  ${YELLOW}1.${NC} SSH key access configured and tested"
    echo -e "  ${YELLOW}2.${NC} Console/physical access in case of lockout"
    echo -e "  ${YELLOW}3.${NC} Backup of your SSH configuration"
    echo ""

    if ! confirm_destructive "These changes may lock you out if SSH keys are not properly configured"; then
        log_info "Operation cancelled"
        return 0
    fi

    check_root

    APPLY_ALL=true
    DISABLE_ROOT=true
    KEY_ONLY=true
    STRONG_CRYPTO=true

    backup_config
    apply_hardening

    if [[ "$INSTALL_FAIL2BAN" == "true" ]]; then
        setup_fail2ban
    fi

    echo ""
    log_ok "SSH hardening applied successfully!"
    echo ""
    show_status
}

interactive_specific_settings() {
    echo ""

    # Multi-select for settings
    local settings_options=(
        "Disable root login"
        "Disable password authentication (key-only)"
        "Apply strong cipher settings"
        "Set idle timeout"
        "Restrict to specific users"
        "Restrict to specific groups")

    readarray -t selected_settings < <(prompt_multiselect "Select settings to configure:" "${settings_options[@]}")

    if [[ ${#selected_settings[@]} -eq 0 ]]; then
        log_warn "No settings selected"
        return 0
    fi

    # Process selections
    for setting in "${selected_settings[@]}"; do
        case "$setting" in
            "Disable root login")
                DISABLE_ROOT=true
                ;;
            "Disable password authentication (key-only)")
                KEY_ONLY=true
                ;;
            "Apply strong cipher settings")
                STRONG_CRYPTO=true
                ;;
            "Set idle timeout")
                local timeout
                timeout=$(prompt_input "Idle timeout in seconds" "300")
                IDLE_TIMEOUT="$timeout"
                ;;
            "Restrict to specific users")
                local users
                users=$(prompt_input "Allowed users (comma-separated)" "")
                [[ -n "$users" ]] && ALLOW_USERS="$users"
                ;;
            "Restrict to specific groups")
                local groups
                groups=$(prompt_input "Allowed groups (comma-separated)" "")
                [[ -n "$groups" ]] && ALLOW_GROUPS="$groups"
                ;;
        esac
    done

    echo ""
    log_info "Selected changes:"
    [[ "$DISABLE_ROOT" == "true" ]] && echo -e "  ${CYAN}•${NC} Disable root login"
    [[ "$KEY_ONLY" == "true" ]] && echo -e "  ${CYAN}•${NC} Disable password authentication"
    [[ "$STRONG_CRYPTO" == "true" ]] && echo -e "  ${CYAN}•${NC} Strong cipher settings"
    [[ -n "${ALLOW_USERS:-}" ]] && echo -e "  ${CYAN}•${NC} Allow users: $ALLOW_USERS"
    [[ -n "${ALLOW_GROUPS:-}" ]] && echo -e "  ${CYAN}•${NC} Allow groups: $ALLOW_GROUPS"
    echo ""

    if confirm_destructive "Apply these SSH configuration changes?"; then
        check_root
        backup_config
        apply_hardening

        echo ""
        log_ok "Settings applied successfully!"
    fi
}

interactive_fail2ban() {
    echo ""

    if systemctl is-active fail2ban &> /dev/null; then
        log_ok "fail2ban is already running"
        if prompt_yes_no "Reconfigure fail2ban?" "n"; then
            check_root
            setup_fail2ban
        fi
    else
        if prompt_yes_no "Install and configure fail2ban?" "y"; then
            check_root
            setup_fail2ban
            log_ok "fail2ban installed and configured"
        fi
    fi
}

interactive_generate_key() {
    echo ""
    local username
    username=$(prompt_input "Enter username to generate SSH key for" "$USER")

    if [[ -n "$username" ]]; then
        check_root
        generate_ssh_key "$username"
    fi
}

interactive_change_port() {
    echo ""
    local current_port
    current_port=$(get_setting "Port" "22")

    log_info "Current SSH port: $current_port"
    echo ""

    local new_port
    new_port=$(prompt_input "Enter new SSH port" "2222")

    if [[ "$new_port" == "$current_port" ]]; then
        log_info "Port unchanged"
        return 0
    fi

    echo ""
    echo -e "${YELLOW}⚠ Remember to:${NC}"
    echo -e "  ${CYAN}•${NC} Update firewall rules for port $new_port"
    echo -e "  ${CYAN}•${NC} Update any SSH clients/scripts"
    echo -e "  ${CYAN}•${NC} Test connection on new port before disconnecting"
    echo ""

    if confirm_destructive "Change SSH port from $current_port to $new_port?"; then
        check_root
        NEW_PORT="$new_port"
        backup_config
        apply_hardening

        echo ""
        log_ok "SSH port changed to $new_port"
        log_warn "Remember to update your firewall rules!"
    fi
}

interactive_rollback() {
    echo ""

    local backups
    backups=$(ls -t "$BACKUP_DIR"/sshd_config.* 2> /dev/null | head -5 || true)

    if [[ -z "$backups" ]]; then
        log_error "No backups found in $BACKUP_DIR"
        return 1
    fi

    log_info "Available backups:"
    echo "$backups" | while read -r backup; do
        echo -e "  ${CYAN}•${NC} $(basename "$backup")"
    done
    echo ""

    if confirm_destructive "Restore the most recent backup?"; then
        check_root
        rollback_config
    fi
}

# Generate SSH key for user
generate_ssh_key() {
    local user="$1"

    print_header "SSH Key Generation"

    local user_home
    user_home=$(getent passwd "$user" | cut -d: -f6)

    if [[ -z "$user_home" ]]; then
        log_error "User '$user' not found"
        exit $EXIT_ERROR
    fi

    local ssh_dir="$user_home/.ssh"
    local key_file="$ssh_dir/id_ed25519"

    if [[ -f "$key_file" ]]; then
        log_warn "SSH key already exists at $key_file"
        return 0
    fi

    log_info "Generating Ed25519 SSH key for $user..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would generate key at $key_file"
        return 0
    fi

    mkdir -p "$ssh_dir"
    ssh-keygen -t ed25519 -f "$key_file" -N "" -C "$user@$(hostname)"

    # Set permissions
    chown -R "$user:$user" "$ssh_dir"
    chmod 700 "$ssh_dir"
    chmod 600 "$key_file"
    chmod 644 "${key_file}.pub"

    log_ok "SSH key generated"
    echo ""
    echo "Public key:"
    cat "${key_file}.pub"
    echo ""
    log_info "Add this key to ~/.ssh/authorized_keys on remote servers"
}

# Main function
main() {
    local original_args=("$@")
    parse_args "$@"

    # Determine if interactive mode should be enabled
    if [[ "$INTERACTIVE" == "auto" ]]; then
        if [[ ${#original_args[@]} -eq 0 ]] && [[ -t 0 ]] && [[ -t 1 ]]; then
            INTERACTIVE=true
        else
            INTERACTIVE=false
        fi
    fi

    # Run interactive mode if enabled
    if [[ "$INTERACTIVE" == "true" ]] && type -t rsr_is_interactive &> /dev/null && rsr_is_interactive; then
        run_interactive
        exit $EXIT_OK
    fi

    echo -e "${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}"
    echo ""

    # Show status if requested
    if [[ "$SHOW_STATUS" == "true" ]]; then
        show_status
        exit $EXIT_OK
    fi

    # Rollback if requested
    if [[ "$DO_ROLLBACK" == "true" ]]; then
        check_root
        rollback_config
        exit $EXIT_OK
    fi

    # Generate key if requested
    if [[ -n "$GENERATE_KEY_USER" ]]; then
        check_root
        generate_ssh_key "$GENERATE_KEY_USER"
        exit $EXIT_OK
    fi

    # Install fail2ban if requested
    if [[ "$INSTALL_FAIL2BAN" == "true" ]]; then
        check_root
        setup_fail2ban
        [[ "$DISABLE_ROOT" != "true" && "$KEY_ONLY" != "true" && "$STRONG_CRYPTO" != "true" ]] && exit $EXIT_OK
    fi

    # Apply hardening
    if [[ "$DISABLE_ROOT" == "true" || "$KEY_ONLY" == "true" || -n "$NEW_PORT" || -n "$ALLOW_USERS" || -n "$ALLOW_GROUPS" || "$STRONG_CRYPTO" == "true" || "$APPLY_ALL" == "true" ]]; then
        check_root
        apply_hardening
    else
        # No options specified, show help
        usage
    fi

    exit $EXIT_OK
}

main "$@"
