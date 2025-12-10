#!/bin/bash
# =============================================================================
# @id           ssh-server
# @name         ssh-server
# @displayName  SSH Server Management
# @description  Complete SSH server management: install, configure, harden, monitor
# @category     network
# @version      1.0.0
# @author       codefuturist
# @tags         ssh,server,security,configuration,hardening,monitoring
# @shells       bash
# @requires     root (for most operations)
# @os           linux,macos,freebsd
# =============================================================================

set -euo pipefail

# =============================================================================
# Script Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="SSH Server Management"
SCRIPT_VERSION="1.0.0"

# Source libraries
[[ -f "$SCRIPT_DIR/../../lib/common.sh" ]] && source "$SCRIPT_DIR/../../lib/common.sh"
[[ -f "$SCRIPT_DIR/../../lib/ssh.sh" ]] && source "$SCRIPT_DIR/../../lib/ssh.sh"
[[ -f "$SCRIPT_DIR/../../lib/interactive.sh" ]] && source "$SCRIPT_DIR/../../lib/interactive.sh"

# Default values
VERBOSE=false
DRY_RUN=false
SUBCOMMAND=""

# Exit codes
EXIT_OK=0
EXIT_ERROR=1
EXIT_INVALID_ARGS=2
EXIT_PERMISSION=3
EXIT_NOT_INSTALLED=4

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# =============================================================================
# Helper Functions
# =============================================================================

log_info() { echo -e "${BLUE}▸${NC} $1"; }
log_ok() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1" >&2; }
log_debug() { [[ "$VERBOSE" == "true" ]] && echo -e "  $1"; }

print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}═══ $1 ═══${NC}"
    echo ""
}

usage() {
    cat << EOF
${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}

Complete SSH server management with installation, configuration, hardening, and monitoring.

${YELLOW}Usage:${NC}
    $0 <subcommand> [OPTIONS]

${BOLD}Subcommands:${NC}

  ${CYAN}Installation & Setup:${NC}
    install             Install SSH server
    uninstall           Uninstall SSH server (WARNING: destructive)

  ${CYAN}Service Control:${NC}
    start               Start SSH server
    stop                Stop SSH server
    restart             Restart SSH server
    enable              Enable SSH server at boot
    disable             Disable SSH server at boot
    status              Show SSH server status

  ${CYAN}Configuration:${NC}
    configure           Interactive configuration wizard ✨
    config get KEY      Get configuration value
    config set KEY VAL  Set configuration value
    config backup       Backup current configuration
    config restore      Restore from backup
    config validate     Validate configuration syntax
    config show         Show full configuration

  ${CYAN}Security & Hardening:${NC}
    harden              Apply security hardening (calls ssh-hardening script)
    audit               Run security audit
    score               Show security score (0-100)

  ${CYAN}Testing & Diagnostics:${NC}
    test                Test SSH connection to localhost
    test HOST [PORT]    Test connection to remote host
    connections         Show active SSH connections
    logs [LINES]        Show SSH logs (default: 50 lines)
    failed              Show failed login attempts

${BOLD}Global Options:${NC}
    -h, --help          Display this help message
    -v, --verbose       Enable verbose output
    -d, --dry-run       Show what would be done (where applicable)

${BOLD}Examples:${NC}

    ${DIM}# Interactive configuration wizard${NC}
    sudo $0 configure

    ${DIM}# Show server status${NC}
    $0 status

    ${DIM}# Install and enable SSH server${NC}
    sudo $0 install
    sudo $0 enable
    sudo $0 start

    ${DIM}# Apply security hardening${NC}
    sudo $0 harden

    ${DIM}# Check security score${NC}
    $0 score

    ${DIM}# Change SSH port${NC}
    sudo $0 config set Port 2222
    sudo $0 restart

    ${DIM}# Test connection${NC}
    $0 test myserver.com 22

    ${DIM}# Monitor failed logins${NC}
    $0 failed

    ${DIM}# View logs${NC}
    $0 logs 100

${BOLD}Notes:${NC}
  • Most operations require root/sudo privileges
  • Hardening operations call the dedicated ssh-hardening script
  • Always backup configuration before making changes
  • Test changes before applying in production

${BOLD}Related Commands:${NC}
  rsr ssh-harden      Advanced security hardening with detailed options
  rsr usermgmt ssh    User SSH key management

EOF
    exit 0
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This operation requires root privileges"
        log_info "Run with: sudo $0 $SUBCOMMAND"
        exit $EXIT_PERMISSION
    fi
}

# =============================================================================
# Subcommand: Install
# =============================================================================

cmd_install() {
    print_header "Install SSH Server"

    check_root

    if ssh_is_server_installed; then
        log_ok "SSH server is already installed"
        local version
        version=$(ssh_get_server_version)
        log_info "Version: $version"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would install SSH server"
        return 0
    fi

    log_info "Installing SSH server..."

    if ssh_install_server; then
        log_ok "SSH server installed successfully"

        # Show post-install info
        echo ""
        log_info "Next steps:"
        echo "  1. Enable at boot: sudo $0 enable"
        echo "  2. Start service:   sudo $0 start"
        echo "  3. Check status:    $0 status"
        echo "  4. Harden security: sudo $0 harden"
    else
        log_error "Failed to install SSH server"
        exit $EXIT_ERROR
    fi
}

# =============================================================================
# Subcommand: Service Control
# =============================================================================

cmd_start() {
    print_header "Start SSH Server"
    check_root

    if ssh_is_server_running; then
        log_ok "SSH server is already running"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would start SSH server"
        return 0
    fi

    log_info "Starting SSH server..."
    if ssh_start_server; then
        log_ok "SSH server started successfully"
    else
        log_error "Failed to start SSH server"
        exit $EXIT_ERROR
    fi
}

cmd_stop() {
    print_header "Stop SSH Server"
    check_root

    if ! ssh_is_server_running; then
        log_info "SSH server is not running"
        return 0
    fi

    # Warning
    echo -e "${YELLOW}WARNING: Stopping SSH server will terminate all SSH connections${NC}"
    read -p "Are you sure? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "Cancelled"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would stop SSH server"
        return 0
    fi

    log_info "Stopping SSH server..."
    if ssh_stop_server; then
        log_ok "SSH server stopped"
    else
        log_error "Failed to stop SSH server"
        exit $EXIT_ERROR
    fi
}

cmd_restart() {
    print_header "Restart SSH Server"
    check_root

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would restart SSH server"
        return 0
    fi

    log_info "Restarting SSH server..."
    if ssh_restart_server; then
        log_ok "SSH server restarted successfully"
    else
        log_error "Failed to restart SSH server"
        exit $EXIT_ERROR
    fi
}

cmd_enable() {
    print_header "Enable SSH Server"
    check_root

    if ssh_is_server_enabled; then
        log_ok "SSH server is already enabled at boot"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would enable SSH server at boot"
        return 0
    fi

    log_info "Enabling SSH server at boot..."
    if ssh_enable_server; then
        log_ok "SSH server enabled at boot"
    else
        log_error "Failed to enable SSH server"
        exit $EXIT_ERROR
    fi
}

cmd_disable() {
    print_header "Disable SSH Server"
    check_root

    # Warning
    echo -e "${YELLOW}WARNING: Disabling SSH server will prevent automatic start at boot${NC}"
    read -p "Are you sure? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "Cancelled"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would disable SSH server at boot"
        return 0
    fi

    log_info "Disabling SSH server at boot..."
    if ssh_disable_server; then
        log_ok "SSH server disabled at boot"
    else
        log_error "Failed to disable SSH server"
        exit $EXIT_ERROR
    fi
}

cmd_status() {
    print_header "SSH Server Status"

    # Installation status
    if ssh_is_server_installed; then
        log_ok "SSH server is installed"
        local version
        version=$(ssh_get_server_version)
        echo "  Version: $version"
    else
        log_error "SSH server is NOT installed"
        echo ""
        log_info "Install with: sudo $0 install"
        exit $EXIT_NOT_INSTALLED
    fi

    echo ""

    # Running status
    if ssh_is_server_running; then
        log_ok "SSH server is running"
    else
        log_warn "SSH server is NOT running"
        echo "  Start with: sudo $0 start"
    fi

    echo ""

    # Boot status
    if ssh_is_server_enabled; then
        log_ok "SSH server is enabled at boot"
    else
        log_warn "SSH server is NOT enabled at boot"
        echo "  Enable with: sudo $0 enable"
    fi

    echo ""

    # Port & connections
    local port
    port=$(ssh_get_server_port)
    echo -e "${CYAN}Port:${NC} $port"

    local ports
    ports=$(ssh_get_listening_ports)
    if [[ -n "$ports" ]]; then
        echo -e "${CYAN}Listening on:${NC} $ports"
    fi

    local conn_count
    conn_count=$(ssh_count_active_connections)
    echo -e "${CYAN}Active connections:${NC} $conn_count"

    echo ""

    # Security score
    local score
    score=$(ssh_get_security_score)
    local color=$GREEN
    [[ $score -lt 80 ]] && color=$YELLOW
    [[ $score -lt 60 ]] && color=$RED

    echo -e "${CYAN}Security score:${NC} ${color}${score}/100${NC}"

    if [[ $score -lt 80 ]]; then
        echo "  Improve with: sudo $0 harden"
    fi
}

# =============================================================================
# Subcommand: Configuration
# =============================================================================

cmd_config() {
    local action="${1:-}"
    shift || true

    case "$action" in
        get) cmd_config_get "$@" ;;
        set) cmd_config_set "$@" ;;
        backup) cmd_config_backup "$@" ;;
        restore) cmd_config_restore "$@" ;;
        validate) cmd_config_validate "$@" ;;
        show) cmd_config_show "$@" ;;
        *)
            log_error "Unknown config action: $action"
            log_info "Use: config {get|set|backup|restore|validate|show}"
            exit $EXIT_INVALID_ARGS
            ;;
    esac
}

cmd_config_get() {
    local key="$1"
    local value
    value=$(ssh_get_config_value "$key")
    echo "$value"
}

cmd_config_set() {
    local key="$1"
    local value="$2"

    print_header "Set Configuration: $key = $value"
    check_root

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would set $key to $value"
        return 0
    fi

    log_info "Setting $key to $value..."

    if ssh_set_config_value "$key" "$value"; then
        log_ok "Configuration updated"

        # Validate
        if ssh_validate_config; then
            log_ok "Configuration is valid"
            log_info "Restart SSH to apply: sudo $0 restart"
        else
            log_error "Configuration is invalid!"
            log_warn "Restoring from backup..."
            ssh_restore_config "$(ls -t /etc/ssh/backups/sshd_config.* | head -1)"
            exit $EXIT_ERROR
        fi
    else
        log_error "Failed to update configuration"
        exit $EXIT_ERROR
    fi
}

cmd_config_backup() {
    print_header "Backup Configuration"

    local backup_file
    backup_file=$(ssh_backup_config)

    if [[ -n "$backup_file" ]]; then
        log_ok "Configuration backed up to: $backup_file"
    else
        log_error "Failed to backup configuration"
        exit $EXIT_ERROR
    fi
}

cmd_config_validate() {
    print_header "Validate Configuration"

    log_info "Validating SSH configuration..."

    if ssh_validate_config; then
        log_ok "Configuration is valid"
    else
        log_error "Configuration has errors"
        exit $EXIT_ERROR
    fi
}

cmd_config_show() {
    print_header "SSH Configuration"

    local config_path
    config_path=$(_ssh_get_config_path)

    if [[ -f "$config_path" ]]; then
        grep -v '^#' "$config_path" | grep -v '^$'
    else
        log_error "Configuration file not found: $config_path"
        exit $EXIT_ERROR
    fi
}

# =============================================================================
# Subcommand: Interactive Configuration
# =============================================================================

cmd_configure() {
    print_header "SSH Server Configuration Wizard"

    check_root

    # Check if interactive mode is available
    if ! type prompt_select &>/dev/null; then
        log_error "Interactive mode not available (lib/interactive.sh not loaded)"
        log_info "Use 'config set KEY VALUE' for manual configuration"
        exit $EXIT_ERROR
    fi

    # Backup config first
    log_info "Creating configuration backup..."
    ssh_backup_config >/dev/null 2>&1 || true

    # Show current status first
    echo -e "${BOLD}Current Configuration:${NC}"
    echo ""
    printf "  ${CYAN}%-25s${NC} %s\n" "Port:" "$(ssh_get_config_value Port 22)"
    printf "  ${CYAN}%-25s${NC} %s\n" "PermitRootLogin:" "$(ssh_get_config_value PermitRootLogin yes)"
    printf "  ${CYAN}%-25s${NC} %s\n" "PasswordAuthentication:" "$(ssh_get_config_value PasswordAuthentication yes)"
    printf "  ${CYAN}%-25s${NC} %s\n" "PubkeyAuthentication:" "$(ssh_get_config_value PubkeyAuthentication yes)"
    printf "  ${CYAN}%-25s${NC} %s\n" "PermitEmptyPasswords:" "$(ssh_get_config_value PermitEmptyPasswords no)"
    printf "  ${CYAN}%-25s${NC} %s\n" "MaxAuthTries:" "$(ssh_get_config_value MaxAuthTries 6)"
    printf "  ${CYAN}%-25s${NC} %s\n" "ClientAliveInterval:" "$(ssh_get_config_value ClientAliveInterval 0)s"
    printf "  ${CYAN}%-25s${NC} %s\n" "X11Forwarding:" "$(ssh_get_config_value X11Forwarding yes)"
    printf "  ${CYAN}%-25s${NC} %s\n" "AllowUsers:" "$(ssh_get_config_value AllowUsers "(not set)")"
    printf "  ${CYAN}%-25s${NC} %s\n" "AllowGroups:" "$(ssh_get_config_value AllowGroups "(not set)")"
    echo ""

    local score
    score=$(ssh_get_security_score)
    local score_color=$GREEN
    [[ $score -lt 80 ]] && score_color=$YELLOW
    [[ $score -lt 60 ]] && score_color=$RED
    echo -e "${BOLD}Security Score:${NC} ${score_color}${score}/100${NC}"
    echo ""

    # Main menu
    local action
    action=$(prompt_select "What would you like to configure?" \
        "🔒 Change SSH Port" \
        "👤 Configure Root Login" \
        "🔑 Configure Password Authentication" \
        "🔐 Configure Public Key Authentication" \
        "⏰ Configure Idle Timeout" \
        "🔢 Configure Max Auth Attempts" \
        "👥 Configure Allowed Users" \
        "📋 Configure Allowed Groups" \
        "🖥️  Configure X11 Forwarding" \
        "⚡ Apply Quick Hardening (Recommended)" \
        "📄 Show All Settings" \
        "🚪 Exit")

    case "$action" in
        *"Change SSH Port"*)
            configure_port
            ;;
        *"Configure Root Login"*)
            configure_root_login
            ;;
        *"Configure Password Authentication"*)
            configure_password_auth
            ;;
        *"Configure Public Key Authentication"*)
            configure_pubkey_auth
            ;;
        *"Configure Idle Timeout"*)
            configure_idle_timeout
            ;;
        *"Configure Max Auth Attempts"*)
            configure_max_auth
            ;;
        *"Configure Allowed Users"*)
            configure_allowed_users
            ;;
        *"Configure Allowed Groups"*)
            configure_allowed_groups
            ;;
        *"Configure X11 Forwarding"*)
            configure_x11
            ;;
        *"Apply Quick Hardening"*)
            configure_quick_harden
            ;;
        *"Show All Settings"*)
            cmd_config_show
            ;;
        *"Exit"*)
            return 0
            ;;
    esac

    # Ask if user wants to configure more
    echo ""
    if prompt_yes_no "Configure another setting?" "y"; then
        cmd_configure
    else
        # Validate config
        if ssh_validate_config; then
            echo ""
            if prompt_yes_no "Restart SSH server to apply changes?" "y"; then
                ssh_restart_server
                log_ok "SSH server restarted - changes applied"
            else
                log_info "Remember to restart SSH: sudo $0 restart"
            fi
        else
            log_error "Configuration has errors - please fix before restarting"
        fi
    fi
}

configure_port() {
    local current_port
    current_port=$(ssh_get_config_value Port 22)

    echo ""
    log_info "Current SSH port: $current_port"
    echo ""

    local new_port
    new_port=$(prompt_input "Enter new SSH port (1-65535)" "$current_port")

    # Validate port number
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [[ "$new_port" -lt 1 ]] || [[ "$new_port" -gt 65535 ]]; then
        log_error "Invalid port number: $new_port"
        return 1
    fi

    if [[ "$new_port" == "$current_port" ]]; then
        log_info "Port unchanged"
        return 0
    fi

    log_info "Setting SSH port to $new_port..."
    ssh_set_config_value "Port" "$new_port"
    log_ok "Port changed to $new_port"

    if [[ "$new_port" != "22" ]]; then
        echo ""
        log_warn "Remember to update firewall rules for port $new_port"
        echo "  Example: sudo ufw allow $new_port/tcp"
    fi
}

configure_root_login() {
    local current
    current=$(ssh_get_config_value PermitRootLogin yes)

    echo ""
    log_info "Current PermitRootLogin: $current"
    echo ""

    local choice
    choice=$(prompt_select "Allow root login?" \
        "no - Completely disable root login (RECOMMENDED)" \
        "prohibit-password - Allow only with SSH key" \
        "yes - Allow root login with password (NOT RECOMMENDED)")

    local value
    case "$choice" in
        "no"*) value="no" ;;
        "prohibit-password"*) value="prohibit-password" ;;
        "yes"*) value="yes" ;;
        *) return 0 ;;
    esac

    if [[ "$value" == "$current" ]]; then
        log_info "Setting unchanged"
        return 0
    fi

    log_info "Setting PermitRootLogin to $value..."
    ssh_set_config_value "PermitRootLogin" "$value"
    log_ok "PermitRootLogin set to $value"
}

configure_password_auth() {
    local current
    current=$(ssh_get_config_value PasswordAuthentication yes)

    echo ""
    log_info "Current PasswordAuthentication: $current"
    echo ""

    echo -e "${YELLOW}⚠ WARNING: Disabling password authentication requires SSH keys to be set up${NC}"
    echo -e "${YELLOW}  Make sure you have key-based access before disabling passwords!${NC}"
    echo ""

    local choice
    choice=$(prompt_select "Allow password authentication?" \
        "no - Key-only authentication (MORE SECURE)" \
        "yes - Allow password authentication")

    local value
    case "$choice" in
        "no"*) value="no" ;;
        "yes"*) value="yes" ;;
        *) return 0 ;;
    esac

    if [[ "$value" == "$current" ]]; then
        log_info "Setting unchanged"
        return 0
    fi

    if [[ "$value" == "no" ]]; then
        echo ""
        if ! prompt_yes_no "Are you SURE you have SSH key access configured?" "n"; then
            log_info "Cancelled - set up SSH keys first"
            log_info "Use: rsr usermgmt ssh generate -u USERNAME"
            return 0
        fi
    fi

    log_info "Setting PasswordAuthentication to $value..."
    ssh_set_config_value "PasswordAuthentication" "$value"
    log_ok "PasswordAuthentication set to $value"
}

configure_pubkey_auth() {
    local current
    current=$(ssh_get_config_value PubkeyAuthentication yes)

    echo ""
    log_info "Current PubkeyAuthentication: $current"
    echo ""

    local choice
    choice=$(prompt_select "Allow public key authentication?" \
        "yes - Allow public key authentication" \
        "no - Disallow public key authentication")

    local value
    case "$choice" in
        "yes"*) value="yes" ;;
        "no"*) value="no" ;;
        *) return 0 ;;
    esac

    if [[ "$value" == "$current" ]]; then
        log_info "Setting unchanged"
        return 0
    fi

    log_info "Setting PubkeyAuthentication to $value..."
    ssh_set_config_value "PubkeyAuthentication" "$value"
    log_ok "PubkeyAuthentication set to $value"
}

configure_idle_timeout() {
    local current
    current=$(ssh_get_config_value ClientAliveInterval 0)

    echo ""
    log_info "Current idle timeout: ${current}s (0 = disabled)"
    echo ""

    local choice
    choice=$(prompt_select "Set idle timeout?" \
        "300 - 5 minutes (RECOMMENDED)" \
        "600 - 10 minutes" \
        "900 - 15 minutes" \
        "1800 - 30 minutes" \
        "0 - Disabled (no timeout)" \
        "Custom - Enter custom value")

    local value
    case "$choice" in
        "300"*) value="300" ;;
        "600"*) value="600" ;;
        "900"*) value="900" ;;
        "1800"*) value="1800" ;;
        "0"*) value="0" ;;
        "Custom"*)
            value=$(prompt_input "Enter timeout in seconds" "300")
            ;;
        *) return 0 ;;
    esac

    if [[ "$value" == "$current" ]]; then
        log_info "Setting unchanged"
        return 0
    fi

    log_info "Setting ClientAliveInterval to $value..."
    ssh_set_config_value "ClientAliveInterval" "$value"
    ssh_set_config_value "ClientAliveCountMax" "2"
    log_ok "Idle timeout set to ${value}s"
}

configure_max_auth() {
    local current
    current=$(ssh_get_config_value MaxAuthTries 6)

    echo ""
    log_info "Current MaxAuthTries: $current"
    echo ""

    local choice
    choice=$(prompt_select "Maximum authentication attempts?" \
        "3 - Strict (RECOMMENDED)" \
        "4 - Moderate" \
        "6 - Default" \
        "Custom - Enter custom value")

    local value
    case "$choice" in
        "3"*) value="3" ;;
        "4"*) value="4" ;;
        "6"*) value="6" ;;
        "Custom"*)
            value=$(prompt_input "Enter max attempts (1-10)" "3")
            ;;
        *) return 0 ;;
    esac

    if [[ "$value" == "$current" ]]; then
        log_info "Setting unchanged"
        return 0
    fi

    log_info "Setting MaxAuthTries to $value..."
    ssh_set_config_value "MaxAuthTries" "$value"
    log_ok "MaxAuthTries set to $value"
}

configure_allowed_users() {
    local current
    current=$(ssh_get_config_value AllowUsers "")

    echo ""
    if [[ -n "$current" ]]; then
        log_info "Current AllowUsers: $current"
    else
        log_info "AllowUsers: Not set (all users allowed)"
    fi
    echo ""

    local choice
    choice=$(prompt_select "Configure allowed users?" \
        "Set allowed users" \
        "Clear restriction (allow all users)" \
        "Keep current setting")

    case "$choice" in
        "Set allowed users")
            local users
            users=$(prompt_input "Enter usernames (space-separated)" "$current")
            if [[ -n "$users" ]]; then
                ssh_set_config_value "AllowUsers" "$users"
                log_ok "AllowUsers set to: $users"
            fi
            ;;
        "Clear restriction"*)
            local config_path
            config_path=$(_ssh_get_config_path)
            if [[ -f "$config_path" ]]; then
                sed -i.tmp 's/^AllowUsers/#AllowUsers/' "$config_path"
                rm -f "${config_path}.tmp"
                log_ok "AllowUsers restriction removed"
            fi
            ;;
        *) return 0 ;;
    esac
}

configure_allowed_groups() {
    local current
    current=$(ssh_get_config_value AllowGroups "")

    echo ""
    if [[ -n "$current" ]]; then
        log_info "Current AllowGroups: $current"
    else
        log_info "AllowGroups: Not set (all groups allowed)"
    fi
    echo ""

    local choice
    choice=$(prompt_select "Configure allowed groups?" \
        "Set allowed groups" \
        "Clear restriction (allow all groups)" \
        "Keep current setting")

    case "$choice" in
        "Set allowed groups")
            local groups
            groups=$(prompt_input "Enter group names (space-separated)" "$current")
            if [[ -n "$groups" ]]; then
                ssh_set_config_value "AllowGroups" "$groups"
                log_ok "AllowGroups set to: $groups"
            fi
            ;;
        "Clear restriction"*)
            local config_path
            config_path=$(_ssh_get_config_path)
            if [[ -f "$config_path" ]]; then
                sed -i.tmp 's/^AllowGroups/#AllowGroups/' "$config_path"
                rm -f "${config_path}.tmp"
                log_ok "AllowGroups restriction removed"
            fi
            ;;
        *) return 0 ;;
    esac
}

configure_x11() {
    local current
    current=$(ssh_get_config_value X11Forwarding yes)

    echo ""
    log_info "Current X11Forwarding: $current"
    echo ""

    local choice
    choice=$(prompt_select "Allow X11 Forwarding?" \
        "no - Disable X11 forwarding (RECOMMENDED if not needed)" \
        "yes - Enable X11 forwarding (for GUI applications)")

    local value
    case "$choice" in
        "no"*) value="no" ;;
        "yes"*) value="yes" ;;
        *) return 0 ;;
    esac

    if [[ "$value" == "$current" ]]; then
        log_info "Setting unchanged"
        return 0
    fi

    log_info "Setting X11Forwarding to $value..."
    ssh_set_config_value "X11Forwarding" "$value"
    log_ok "X11Forwarding set to $value"
}

configure_quick_harden() {
    echo ""
    echo -e "${BOLD}Quick Hardening will apply these security settings:${NC}"
    echo ""
    echo "  • PermitRootLogin: no"
    echo "  • PasswordAuthentication: no (key-only)"
    echo "  • PermitEmptyPasswords: no"
    echo "  • X11Forwarding: no"
    echo "  • MaxAuthTries: 3"
    echo "  • ClientAliveInterval: 300 (5 min timeout)"
    echo "  • ClientAliveCountMax: 2"
    echo ""

    echo -e "${RED}${BOLD}⚠ IMPORTANT WARNING${NC}"
    echo -e "${YELLOW}Make sure you have SSH key access configured before applying!${NC}"
    echo -e "${YELLOW}You could lock yourself out if password auth is disabled without keys.${NC}"
    echo ""

    if ! prompt_yes_no "Apply quick hardening?" "n"; then
        log_info "Cancelled"
        return 0
    fi

    echo ""
    if ! prompt_yes_no "Confirm: You have SSH key access already set up?" "n"; then
        log_info "Set up SSH keys first: rsr usermgmt ssh generate -u USERNAME"
        return 0
    fi

    log_info "Applying quick hardening..."

    ssh_set_config_value "PermitRootLogin" "no"
    log_ok "Disabled root login"

    ssh_set_config_value "PasswordAuthentication" "no"
    log_ok "Disabled password authentication"

    ssh_set_config_value "PermitEmptyPasswords" "no"
    log_ok "Disabled empty passwords"

    ssh_set_config_value "X11Forwarding" "no"
    log_ok "Disabled X11 forwarding"

    ssh_set_config_value "MaxAuthTries" "3"
    log_ok "Limited auth attempts to 3"

    ssh_set_config_value "ClientAliveInterval" "300"
    ssh_set_config_value "ClientAliveCountMax" "2"
    log_ok "Set idle timeout to 5 minutes"

    echo ""

    if ssh_validate_config; then
        log_ok "Configuration is valid"

        local score
        score=$(ssh_get_security_score)
        echo ""
        echo -e "${BOLD}New Security Score:${NC} ${GREEN}${score}/100${NC}"
    else
        log_error "Configuration validation failed"
        log_warn "Rolling back changes..."
        ssh_restore_config "$(ls -t /etc/ssh/backups/sshd_config.* 2>/dev/null | head -1)"
        return 1
    fi
}

# =============================================================================
# Subcommand: Security & Hardening
# =============================================================================

cmd_harden() {
    print_header "SSH Security Hardening"

    # Check if ssh-hardening script exists
    local harden_script="$SCRIPT_DIR/ssh-hardening.sh"

    if [[ -f "$harden_script" ]]; then
        log_info "Calling dedicated hardening script..."
        exec bash "$harden_script" "$@"
    else
        log_warn "Dedicated hardening script not found at: $harden_script"
        log_info "Applying basic hardening..."

        check_root

        # Basic hardening
        ssh_set_config_value "PermitRootLogin" "no"
        ssh_set_config_value "PasswordAuthentication" "no"
        ssh_set_config_value "PermitEmptyPasswords" "no"
        ssh_set_config_value "X11Forwarding" "no"
        ssh_set_config_value "MaxAuthTries" "3"
        ssh_set_config_value "ClientAliveInterval" "300"
        ssh_set_config_value "ClientAliveCountMax" "2"

        if ssh_validate_config; then
            log_ok "Basic hardening applied"
            log_info "Restart SSH to apply: sudo $0 restart"
        else
            log_error "Configuration validation failed"
            exit $EXIT_ERROR
        fi
    fi
}

cmd_audit() {
    print_header "SSH Security Audit"

    echo -e "${BOLD}Security Configuration:${NC}"
    echo ""

    # Check various security settings
    local items=(
        "PermitRootLogin:Root Login"
        "PasswordAuthentication:Password Auth"
        "PermitEmptyPasswords:Empty Passwords"
        "X11Forwarding:X11 Forwarding"
        "MaxAuthTries:Max Auth Tries"
        "ClientAliveInterval:Idle Timeout"
        "AllowUsers:Allowed Users"
        "AllowGroups:Allowed Groups"
    )

    for item in "${items[@]}"; do
        local key="${item%%:*}"
        local label="${item##*:}"
        local value
        value=$(ssh_get_config_value "$key" "default")

        printf "%-20s %s\n" "$label:" "$value"
    done

    echo ""

    # Failed login attempts
    local failed_count
    failed_count=$(ssh_count_failed_logins)
    echo -e "${BOLD}Failed Login Attempts:${NC} $failed_count"

    echo ""

    # Security score
    cmd_score
}

cmd_score() {
    local score
    score=$(ssh_get_security_score)

    local color=$GREEN
    local grade="A"

    if [[ $score -lt 90 ]]; then
        color=$GREEN
        grade="A"
    fi

    if [[ $score -lt 80 ]]; then
        color=$YELLOW
        grade="B"
    fi

    if [[ $score -lt 70 ]]; then
        color=$YELLOW
        grade="C"
    fi

    if [[ $score -lt 60 ]]; then
        color=$RED
        grade="D"
    fi

    if [[ $score -lt 50 ]]; then
        color=$RED
        grade="F"
    fi

    echo ""
    echo -e "${BOLD}SSH Security Score:${NC} ${color}${score}/100 (Grade: $grade)${NC}"
    echo ""

    if [[ $score -lt 80 ]]; then
        log_info "Recommendations:"

        ssh_check_root_login && echo "  • Disable root login: sudo $0 config set PermitRootLogin no"
        ssh_check_password_auth && echo "  • Disable password auth: sudo $0 config set PasswordAuthentication no"
        ssh_check_empty_passwords && echo "  • Disable empty passwords: sudo $0 config set PermitEmptyPasswords no"

        local port
        port=$(ssh_get_server_port)
        [[ "$port" == "22" ]] && echo "  • Change default port: sudo $0 config set Port 2222"

        echo ""
        echo "  Or run: sudo $0 harden"
    fi
}

# =============================================================================
# Subcommand: Testing & Diagnostics
# =============================================================================

cmd_test() {
    local host="${1:-localhost}"
    local port="${2:-22}"

    print_header "Test SSH Connection"

    log_info "Testing connection to $host:$port..."

    if ssh_test_connection "$host" "$port" 5; then
        log_ok "Connection successful to $host:$port"
    else
        log_error "Connection failed to $host:$port"
        exit $EXIT_ERROR
    fi
}

cmd_connections() {
    print_header "Active SSH Connections"

    local count
    count=$(ssh_count_active_connections)

    echo -e "${BOLD}Total connections:${NC} $count"
    echo ""

    if command -v ss >/dev/null 2>&1; then
        ss -tn | grep :22 || echo "No active connections"
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tn | grep :22 || echo "No active connections"
    else
        who | grep pts || echo "No active connections"
    fi
}

cmd_logs() {
    local lines="${1:-50}"

    print_header "SSH Logs (last $lines lines)"

    ssh_tail_logs "$lines"
}

cmd_failed() {
    print_header "Failed Login Attempts"

    local count
    count=$(ssh_count_failed_logins)

    echo -e "${BOLD}Total failed attempts:${NC} $count"
    echo ""

    if [[ $count -gt 0 ]]; then
        log_info "Last 10 failed attempts:"
        echo ""
        ssh_get_last_failed_logins 10
    else
        log_ok "No failed login attempts found"
    fi
}

# =============================================================================
# Main Entry Point
# =============================================================================

main() {
    # Parse global options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage ;;
            -v|--verbose) VERBOSE=true; shift ;;
            -d|--dry-run) DRY_RUN=true; shift ;;
            -*)
                log_error "Unknown option: $1"
                exit $EXIT_INVALID_ARGS
                ;;
            *)
                SUBCOMMAND="$1"
                shift
                break
                ;;
        esac
    done

    # Check for subcommand
    if [[ -z "$SUBCOMMAND" ]]; then
        usage
    fi

    # Route to subcommand
    case "$SUBCOMMAND" in
        install) cmd_install "$@" ;;
        start) cmd_start "$@" ;;
        stop) cmd_stop "$@" ;;
        restart) cmd_restart "$@" ;;
        enable) cmd_enable "$@" ;;
        disable) cmd_disable "$@" ;;
        status) cmd_status "$@" ;;
        configure) cmd_configure "$@" ;;
        config) cmd_config "$@" ;;
        harden) cmd_harden "$@" ;;
        audit) cmd_audit "$@" ;;
        score) cmd_score "$@" ;;
        test) cmd_test "$@" ;;
        connections) cmd_connections "$@" ;;
        logs) cmd_logs "$@" ;;
        failed) cmd_failed "$@" ;;
        *)
            log_error "Unknown subcommand: $SUBCOMMAND"
            log_info "Run '$0 --help' for usage"
            exit $EXIT_INVALID_ARGS
            ;;
    esac
}

# Run main
main "$@"
