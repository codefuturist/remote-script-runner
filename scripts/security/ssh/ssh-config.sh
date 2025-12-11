#!/bin/bash
# =============================================================================
# @id           ssh-config
# @name         ssh-config
# @displayName  SSH Client Configuration
# @description  Manage SSH client configuration, hosts, tunnels, and best practices
# @category     security
# @version      1.0.0
# @author       codefuturist
# @tags         ssh,client,config,tunnels,hosts,configuration
# @shells       bash
# @requires     ssh,ssh-keygen
# @os           linux,macos,freebsd
# =============================================================================

set -eo pipefail

# =============================================================================
# Load RSR Library
# =============================================================================

SCRIPT_SOURCE="${BASH_SOURCE[0]:-${0:-}}"
if [ -n "${SCRIPT_SOURCE}" ] && [ "${SCRIPT_SOURCE}" != "bash" ] && [ "${SCRIPT_SOURCE}" != "sh" ] && [ "${SCRIPT_SOURCE}" != "-bash" ] && [ "${SCRIPT_SOURCE}" != "-sh" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_SOURCE}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
else
    SCRIPT_DIR=""
fi
SCRIPT_NAME="SSH Client Configuration"
SCRIPT_VERSION="1.0.0"
RSR_LIB_DIR="${SCRIPT_DIR}/../../../lib"

if [[ -f "$RSR_LIB_DIR/rsr-lib.sh" ]]; then
    source "$RSR_LIB_DIR/rsr-lib.sh" ssh validate interactive
else
    echo "ERROR: RSR library not found at $RSR_LIB_DIR/rsr-lib.sh" >&2
    exit 1
fi

# Default values
VERBOSE=false
DRY_RUN=false
SUBCOMMAND=""
SSH_DIR="${HOME}/.ssh"
SSH_CONFIG="${SSH_DIR}/config"
SSH_CONFIG_D="${SSH_DIR}/config.d"

# Exit codes
EXIT_OK=$RSR_EXIT_SUCCESS
EXIT_ERROR=$RSR_EXIT_ERROR
EXIT_INVALID_ARGS=$RSR_EXIT_USAGE

# Colors
RED="$RSR_COLOR_RED"
GREEN="$RSR_COLOR_GREEN"
YELLOW="$RSR_COLOR_YELLOW"
BLUE="$RSR_COLOR_BLUE"
CYAN="$RSR_COLOR_CYAN"
BOLD="$RSR_COLOR_BOLD"
DIM="$RSR_COLOR_DIM"
NC="$RSR_COLOR_RESET"

# =============================================================================
# Helper Functions
# =============================================================================

log_info() { rsr_log_info "$1"; }
log_ok() { rsr_log_ok "$1"; }
log_warn() { rsr_log_warn "$1"; }
log_error() { rsr_log_error "$1"; }
log_debug() { [[ "$VERBOSE" == "true" ]] && rsr_log_debug "$1"; }

print_header() {
    rsr_print_header "$1"
}

usage() {
    cat << EOF
${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}

Manage SSH client configuration, hosts, tunnels, and best practices.

${YELLOW}Usage:${NC}
    $0 <subcommand> [OPTIONS]

${BOLD}Subcommands:${NC}

  ${CYAN}Setup & Configuration:${NC}
    init, setup           Initialize SSH config with best practices
    permissions, perms    Audit and fix SSH directory permissions

  ${CYAN}Host Management:${NC}
    hosts, host           Manage SSH host configurations
      list, ls            List configured hosts
      add HOST            Add new host configuration
      edit HOST           Edit existing host configuration
      remove HOST         Remove host configuration
      show HOST           Show full config for a host
      test HOST           Test connection to configured host

  ${CYAN}Templates:${NC}
    templates, template   Pre-built SSH configurations
      list                List available templates
      apply TEMPLATE      Apply a template configuration

  ${CYAN}Tunnel Management:${NC}
    tunnel, tun           SSH tunneling and port forwarding
      local PORT HOST REMOTE_PORT    Local port forward
      remote PORT HOST REMOTE_PORT   Remote port forward
      dynamic PORT HOST              SOCKS proxy
      list                List active tunnels
      stop [ID|all]       Stop tunnel(s)

  ${CYAN}Backup & Restore:${NC}
    backup                Backup entire ~/.ssh/ directory
    restore FILE          Restore from backup

${BOLD}Global Options:${NC}
    -h, --help            Display this help message
    -v, --verbose         Enable verbose output
    -d, --dry-run         Show what would be done
    --force               Force operation (skip confirmations)

${BOLD}Examples:${NC}
    ${DIM}# Initialize SSH with best practices${NC}
    $0 init

    ${DIM}# Add a new host${NC}
    $0 hosts add myserver

    ${DIM}# Apply GitHub template${NC}
    $0 templates apply github

    ${DIM}# Create local port forward${NC}
    $0 tunnel local 8080 myserver 80

    ${DIM}# Fix permissions${NC}
    $0 permissions --fix

EOF
}

# =============================================================================
# Utility Functions
# =============================================================================

ensure_ssh_dir() {
    if [[ ! -d "$SSH_DIR" ]]; then
        log_info "Creating SSH directory: $SSH_DIR"
        mkdir -p "$SSH_DIR"
        chmod 700 "$SSH_DIR"
    fi
}

get_ssh_hosts() {
    local hosts=()
    
    # Parse main config
    if [[ -f "$SSH_CONFIG" ]]; then
        while IFS= read -r line; do
            if [[ "$line" =~ ^Host[[:space:]]+([^*]+) ]]; then
                local host="${BASH_REMATCH[1]}"
                host="${host//[[:space:]]/}"
                [[ -n "$host" ]] && hosts+=("$host")
            fi
        done < "$SSH_CONFIG"
    fi
    
    # Parse config.d files
    if [[ -d "$SSH_CONFIG_D" ]]; then
        shopt -s nullglob
        for conf_file in "$SSH_CONFIG_D"/*.conf; do
            [[ -f "$conf_file" ]] || continue
            while IFS= read -r line; do
                if [[ "$line" =~ ^Host[[:space:]]+([^*]+) ]]; then
                    local host="${BASH_REMATCH[1]}"
                    host="${host//[[:space:]]/}"
                    [[ -n "$host" ]] && hosts+=("$host")
                fi
            done < "$conf_file"
        done
    fi
    
    printf '%s\n' "${hosts[@]}" | sort -u
}

get_host_info() {
    local host="$1"
    local info=""
    
    # Use ssh -G to get the configuration for a host
    if command -v ssh >/dev/null 2>&1; then
        info=$(ssh -G "$host" 2>/dev/null)
    fi
    
    echo "$info"
}

# =============================================================================
# Init Subcommand
# =============================================================================

cmd_init() {
    local force=false
    local defaults=false
    local preview=false
    local minimal=false
    local secure=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force) force=true; shift ;;
            --defaults) defaults=true; shift ;;
            --preview) preview=true; shift ;;
            --minimal) minimal=true; shift ;;
            --secure) secure=true; shift ;;
            -h|--help)
                cat << EOF
${BOLD}Initialize SSH Configuration${NC}

Creates ~/.ssh/ structure with best practice configuration.

${YELLOW}Usage:${NC}
    $0 init [OPTIONS]

${BOLD}Options:${NC}
    --force         Overwrite existing configuration
    --defaults      Use all defaults (non-interactive)
    --preview       Preview what will be created
    --minimal       Minimal configuration only
    --secure        Include strict security settings

${BOLD}Creates:${NC}
    ~/.ssh/config          Main configuration file
    ~/.ssh/config.d/       Directory for modular configs
    ~/.ssh/keys/           Organized key storage

EOF
                return $EXIT_OK
                ;;
            *)
                log_error "Unknown option: $1"
                return $EXIT_INVALID_ARGS
                ;;
        esac
    done
    
    print_header "Initialize SSH Configuration"
    
    # Check if already initialized
    if [[ -f "$SSH_CONFIG" ]] && [[ "$force" != "true" ]]; then
        log_warn "SSH config already exists: $SSH_CONFIG"
        if [[ "$defaults" != "true" ]]; then
            read -p "Overwrite existing configuration? [y/N]: " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Cancelled"
                return $EXIT_OK
            fi
        else
            log_info "Use --force to overwrite"
            return $EXIT_OK
        fi
    fi
    
    # Backup existing config
    if [[ -f "$SSH_CONFIG" ]]; then
        local backup="${SSH_CONFIG}.backup.$(date +%Y%m%d-%H%M%S)"
        log_info "Backing up existing config to: $backup"
        cp "$SSH_CONFIG" "$backup"
    fi
    
    # Create directory structure
    ensure_ssh_dir
    mkdir -p "$SSH_CONFIG_D"
    mkdir -p "${SSH_DIR}/keys"
    mkdir -p "${SSH_DIR}/sockets"
    
    # Generate config content
    local config_content
    config_content="# RSR SSH Configuration - Best Practices
# Generated: $(date)
# Managed by: rsr ssh-config

"
    
    if [[ "$minimal" != "true" ]]; then
        config_content+="# Global SSH Client Configuration
Host *
    # Security
    AddKeysToAgent yes
    IdentitiesOnly yes
"
        
        if [[ "$secure" == "true" ]]; then
            config_content+="    HashKnownHosts yes
    
    # Modern cryptography
    KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256
    Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
    MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
"
        fi
        
        config_content+="    
    # Connection stability
    ServerAliveInterval 60
    ServerAliveCountMax 3
    TCPKeepAlive yes
    
    # Convenience
    VisualHostKey yes
    Compression yes
    
    # Connection multiplexing (faster repeated connections)
    ControlMaster auto
    ControlPath ${SSH_DIR}/sockets/%r@%h-%p
    ControlPersist 600

"
    fi
    
    config_content+="# Include modular host configurations
Include config.d/*
"
    
    if [[ "$preview" == "true" ]]; then
        echo
        echo "${BOLD}Preview of ${SSH_CONFIG}:${NC}"
        echo "${DIM}────────────────────────────────────────${NC}"
        echo "$config_content"
        echo "${DIM}────────────────────────────────────────${NC}"
        echo
        return $EXIT_OK
    fi
    
    # Write config
    if [[ "$DRY_RUN" != "true" ]]; then
        echo "$config_content" > "$SSH_CONFIG"
        chmod 600 "$SSH_CONFIG"
        chmod 700 "$SSH_CONFIG_D"
        chmod 700 "${SSH_DIR}/keys"
        chmod 700 "${SSH_DIR}/sockets"
        
        log_ok "SSH configuration initialized"
        echo
        echo "${BOLD}Created:${NC}"
        echo "  ${GREEN}✓${NC} ${SSH_CONFIG}"
        echo "  ${GREEN}✓${NC} ${SSH_CONFIG_D}/"
        echo "  ${GREEN}✓${NC} ${SSH_DIR}/keys/"
        echo "  ${GREEN}✓${NC} ${SSH_DIR}/sockets/"
        echo
        
        if [[ "$minimal" != "true" ]]; then
            echo "${BOLD}Features enabled:${NC}"
            echo "  ${GREEN}✓${NC} SSH agent key caching"
            echo "  ${GREEN}✓${NC} Connection multiplexing"
            echo "  ${GREEN}✓${NC} Server keep-alive"
            echo "  ${GREEN}✓${NC} Visual host keys"
            [[ "$secure" == "true" ]] && echo "  ${GREEN}✓${NC} Modern cryptography"
            echo
        fi
        
        echo "${DIM}Next steps:${NC}"
        echo "  • Add hosts: ${CYAN}$0 hosts add${NC}"
        echo "  • Apply templates: ${CYAN}$0 templates list${NC}"
        echo "  • Check permissions: ${CYAN}$0 permissions${NC}"
    else
        log_info "[DRY RUN] Would create SSH configuration"
    fi
    
    return $EXIT_OK
}

# =============================================================================
# Hosts Subcommand
# =============================================================================

cmd_hosts() {
    local action="${1:-list}"
    shift || true
    
    case "$action" in
        list|ls|'')
            cmd_hosts_list "$@"
            ;;
        add|new)
            cmd_hosts_add "$@"
            ;;
        edit)
            cmd_hosts_edit "$@"
            ;;
        remove|rm|delete)
            cmd_hosts_remove "$@"
            ;;
        show)
            cmd_hosts_show "$@"
            ;;
        test)
            cmd_hosts_test "$@"
            ;;
        -h|--help)
            cat << EOF
${BOLD}SSH Host Management${NC}

Manage SSH host configurations in ~/.ssh/config.d/

${YELLOW}Usage:${NC}
    $0 hosts <action> [OPTIONS]

${BOLD}Actions:${NC}
    list, ls            List all configured hosts
    add HOST            Add new host configuration
    edit HOST           Edit existing host configuration
    remove HOST         Remove host configuration
    show HOST           Show full configuration for host
    test HOST           Test connection to host

${BOLD}Examples:${NC}
    $0 hosts list
    $0 hosts add myserver
    $0 hosts test production

EOF
            return $EXIT_OK
            ;;
        *)
            log_error "Unknown action: $action"
            log_info "Use '$0 hosts --help' for usage information"
            return $EXIT_INVALID_ARGS
            ;;
    esac
}

cmd_hosts_list() {
    print_header "Configured SSH Hosts"
    
    local hosts
    mapfile -t hosts < <(get_ssh_hosts)
    
    if [[ ${#hosts[@]} -eq 0 ]]; then
        echo "${DIM}No hosts configured yet${NC}"
        echo
        echo "Add hosts with: ${CYAN}$0 hosts add${NC}"
        return $EXIT_OK
    fi
    
    # Table header
    printf "${BOLD}%-20s %-15s %-25s %-6s %s${NC}\n" "HOST" "USER" "HOSTNAME" "PORT" "KEY"
    printf "${DIM}%s${NC}\n" "$(printf '%.0s─' {1..80})"
    
    for host in "${hosts[@]}"; do
        local info
        info=$(get_host_info "$host")
        
        local hostname=$(echo "$info" | grep "^hostname " | awk '{print $2}')
        local user=$(echo "$info" | grep "^user " | awk '{print $2}')
        local port=$(echo "$info" | grep "^port " | awk '{print $2}')
        local identity=$(echo "$info" | grep "^identityfile " | head -1 | awk '{print $2}')
        
        # Get just the key filename
        if [[ -n "$identity" ]]; then
            identity=$(basename "$identity")
        else
            identity="-"
        fi
        
        [[ -z "$hostname" ]] && hostname="-"
        [[ -z "$user" ]] && user="-"
        [[ -z "$port" ]] && port="22"
        
        printf "%-20s %-15s %-25s %-6s %s\n" "$host" "$user" "$hostname" "$port" "$identity"
    done
    
    echo
    echo "${DIM}${#hosts[@]} host(s) configured${NC}"
    
    return $EXIT_OK
}

cmd_hosts_add() {
    local host="$1"
    local hostname=""
    local user=""
    local port="22"
    local identity=""
    local jump_host=""
    local interactive=true
    
    # Parse options
    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --hostname) hostname="$2"; shift 2 ;;
            --user) user="$2"; shift 2 ;;
            --port) port="$2"; shift 2 ;;
            --key) identity="$2"; shift 2 ;;
            --jump) jump_host="$2"; shift 2 ;;
            --non-interactive) interactive=false; shift ;;
            -h|--help)
                cat << EOF
${BOLD}Add SSH Host${NC}

Add a new host configuration.

${YELLOW}Usage:${NC}
    $0 hosts add HOST [OPTIONS]

${BOLD}Options:${NC}
    --hostname HOSTNAME   Remote hostname or IP
    --user USER           SSH username
    --port PORT           SSH port (default: 22)
    --key PATH            Identity file path
    --jump HOST           Jump host for connection
    --non-interactive     Skip wizard (use all options)

${BOLD}Examples:${NC}
    $0 hosts add myserver
    $0 hosts add prod --hostname 10.0.1.5 --user deploy --key ~/.ssh/id_deploy

EOF
                return $EXIT_OK
                ;;
            *)
                log_error "Unknown option: $1"
                return $EXIT_INVALID_ARGS
                ;;
        esac
    done
    
    if [[ -z "$host" ]]; then
        log_error "Host alias is required"
        log_info "Usage: $0 hosts add HOST [OPTIONS]"
        return $EXIT_INVALID_ARGS
    fi
    
    print_header "Add SSH Host"
    
    # Check if host already exists
    if get_ssh_hosts | grep -q "^${host}$"; then
        log_error "Host '$host' already exists"
        log_info "Use '$0 hosts edit $host' to modify"
        return $EXIT_ERROR
    fi
    
    # Interactive wizard
    if [[ "$interactive" == "true" ]] && [[ "$hostname" == "" ]]; then
        echo "${BOLD}Host alias:${NC} ${GREEN}$host${NC}"
        echo
        
        read -p "Hostname (IP or domain): " hostname
        [[ -z "$hostname" ]] && hostname="$host"
        
        read -p "Username [${USER}]: " user
        [[ -z "$user" ]] && user="$USER"
        
        read -p "Port [22]: " port
        [[ -z "$port" ]] && port="22"
        
        read -p "Identity file [auto-detect]: " identity
        
        read -p "Jump host (optional): " jump_host
        
        echo
    fi
    
    # Validate required fields
    [[ -z "$hostname" ]] && hostname="$host"
    [[ -z "$user" ]] && user="$USER"
    
    # Generate config
    ensure_ssh_dir
    mkdir -p "$SSH_CONFIG_D"
    
    local config_file="${SSH_CONFIG_D}/${host}.conf"
    local config_content="# Host: $host
# Added: $(date)

Host $host
    HostName $hostname
    User $user
    Port $port
"
    
    if [[ -n "$identity" ]]; then
        config_content+="    IdentityFile $identity
"
    fi
    
    if [[ -n "$jump_host" ]]; then
        config_content+="    ProxyJump $jump_host
"
    fi
    
    if [[ "$DRY_RUN" != "true" ]]; then
        echo "$config_content" > "$config_file"
        chmod 600 "$config_file"
        
        log_ok "Host '$host' added to ${config_file}"
        
        # Test connection
        if [[ "$interactive" == "true" ]]; then
            echo
            read -p "Test connection now? [Y/n]: " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$|^$ ]]; then
                cmd_hosts_test "$host"
            fi
        fi
    else
        log_info "[DRY RUN] Would add host '$host'"
        echo "$config_content"
    fi
    
    return $EXIT_OK
}

cmd_hosts_remove() {
    local host="$1"
    
    if [[ -z "$host" ]]; then
        log_error "Host is required"
        log_info "Usage: $0 hosts remove HOST"
        return $EXIT_INVALID_ARGS
    fi
    
    print_header "Remove SSH Host"
    
    local config_file="${SSH_CONFIG_D}/${host}.conf"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Host '$host' not found"
        return $EXIT_ERROR
    fi
    
    echo "Removing host: ${BOLD}$host${NC}"
    echo "File: ${DIM}$config_file${NC}"
    echo
    
    if [[ "$DRY_RUN" != "true" ]]; then
        read -p "Are you sure? [y/N]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm "$config_file"
            log_ok "Host '$host' removed"
        else
            log_info "Cancelled"
        fi
    else
        log_info "[DRY RUN] Would remove host '$host'"
    fi
    
    return $EXIT_OK
}

cmd_hosts_show() {
    local host="$1"
    
    if [[ -z "$host" ]]; then
        log_error "Host is required"
        log_info "Usage: $0 hosts show HOST"
        return $EXIT_INVALID_ARGS
    fi
    
    print_header "SSH Host Configuration: $host"
    
    local info
    info=$(get_host_info "$host")
    
    if [[ -z "$info" ]]; then
        log_error "Host '$host' not found or SSH error"
        return $EXIT_ERROR
    fi
    
    echo "$info" | grep -v "^$" | head -20
    
    return $EXIT_OK
}

cmd_hosts_test() {
    local host="$1"
    
    if [[ -z "$host" ]]; then
        log_error "Host is required"
        log_info "Usage: $0 hosts test HOST"
        return $EXIT_INVALID_ARGS
    fi
    
    print_header "Test SSH Connection: $host"
    
    local info
    info=$(get_host_info "$host")
    
    local hostname=$(echo "$info" | grep "^hostname " | awk '{print $2}')
    local user=$(echo "$info" | grep "^user " | awk '{print $2}')
    local port=$(echo "$info" | grep "^port " | awk '{print $2}')
    
    echo "Testing connection to: ${BOLD}${user}@${hostname}:${port}${NC}"
    echo
    
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" exit 2>/dev/null; then
        log_ok "Connection successful"
        return $EXIT_OK
    else
        log_error "Connection failed"
        echo
        echo "${DIM}Troubleshooting:${NC}"
        echo "  • Check that the host is reachable"
        echo "  • Verify SSH keys are set up: ${CYAN}$0 hosts show $host${NC}"
        echo "  • Test manually: ${CYAN}ssh -v $host${NC}"
        return $EXIT_ERROR
    fi
}

cmd_hosts_edit() {
    local host="$1"
    
    if [[ -z "$host" ]]; then
        log_error "Host is required"
        log_info "Usage: $0 hosts edit HOST"
        return $EXIT_INVALID_ARGS
    fi
    
    local config_file="${SSH_CONFIG_D}/${host}.conf"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Host '$host' not found"
        return $EXIT_ERROR
    fi
    
    local editor="${EDITOR:-vi}"
    
    print_header "Edit SSH Host: $host"
    echo "Opening in editor: ${BOLD}$editor${NC}"
    echo
    
    "$editor" "$config_file"
    
    log_ok "Host configuration updated"
    
    return $EXIT_OK
}

# =============================================================================
# Permissions Subcommand
# =============================================================================

cmd_permissions() {
    local fix=false
    local strict=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --fix) fix=true; shift ;;
            --strict) strict=true; shift ;;
            -h|--help)
                cat << EOF
${BOLD}SSH Permissions Audit${NC}

Audit and fix SSH directory permissions.

${YELLOW}Usage:${NC}
    $0 permissions [OPTIONS]

${BOLD}Options:${NC}
    --fix           Auto-fix permission issues
    --strict        Enforce stricter permissions

${BOLD}Examples:${NC}
    $0 permissions              # Audit only
    $0 permissions --fix        # Fix issues

EOF
                return $EXIT_OK
                ;;
            *)
                log_error "Unknown option: $1"
                return $EXIT_INVALID_ARGS
                ;;
        esac
    done
    
    print_header "SSH Permissions Audit"
    
    local issues=0
    local checks=0
    
    check_perm() {
        local path="$1"
        local expected="$2"
        local name="$3"
        local why="$4"
        
        checks=$((checks + 1))
        
        if [[ ! -e "$path" ]]; then
            echo "${DIM}⊘${NC} ${DIM}$name${NC} (not found)"
            return
        fi
        
        local current
        current=$(stat -f "%OLp" "$path" 2>/dev/null || stat -c "%a" "$path" 2>/dev/null)
        
        if [[ "$current" == "$expected" ]]; then
            echo "${GREEN}✓${NC} $name ${DIM}$current ($expected)${NC}"
        else
            echo "${RED}✗${NC} $name ${YELLOW}$current${NC} → should be ${GREEN}$expected${NC}"
            [[ -n "$why" ]] && echo "  ${DIM}$why${NC}"
            issues=$((issues + 1))
            
            if [[ "$fix" == "true" ]]; then
                chmod "$expected" "$path"
                log_ok "  Fixed: chmod $expected $path"
            fi
        fi
    }
    
    # Check main directory
    check_perm "$SSH_DIR" "700" "~/.ssh/" "Directory must not be accessible by others"
    
    # Check config files
    check_perm "$SSH_CONFIG" "600" "~/.ssh/config" "Config file must not be readable by others"
    check_perm "${SSH_DIR}/known_hosts" "644" "~/.ssh/known_hosts" "Known hosts can be world-readable"
    
    if [[ -d "$SSH_CONFIG_D" ]]; then
        check_perm "$SSH_CONFIG_D" "700" "~/.ssh/config.d/" "Config directory must not be accessible by others"
        
        shopt -s nullglob
        for conf in "$SSH_CONFIG_D"/*.conf; do
            [[ -f "$conf" ]] || continue
            local name=$(basename "$conf")
            check_perm "$conf" "600" "~/.ssh/config.d/$name" "Config files must not be readable by others"
        done
    fi
    
    # Check private keys
    shopt -s nullglob
    for key in "$SSH_DIR"/id_* "$SSH_DIR"/keys/id_*; do
        [[ -f "$key" ]] || continue
        [[ "$key" == *.pub ]] && continue
        
        local name=$(basename "$key")
        check_perm "$key" "600" "~/.ssh/$name" "Private keys must not be readable by others"
    done
    
    # Check public keys
    for pubkey in "$SSH_DIR"/*.pub "$SSH_DIR"/keys/*.pub; do
        [[ -f "$pubkey" ]] || continue
        local name=$(basename "$pubkey")
        check_perm "$pubkey" "644" "~/.ssh/$name" "Public keys can be world-readable"
    done
    
    # Summary
    echo
    if [[ $issues -eq 0 ]]; then
        log_ok "All permissions are correct ($checks checks)"
    else
        log_warn "$issues issue(s) found in $checks checks"
        if [[ "$fix" != "true" ]]; then
            echo
            echo "Fix with: ${CYAN}$0 permissions --fix${NC}"
        fi
    fi
    
    return $EXIT_OK
}

# =============================================================================
# Templates Subcommand
# =============================================================================

cmd_templates() {
    local action="${1:-list}"
    shift || true
    
    case "$action" in
        list|ls|'')
            cmd_templates_list "$@"
            ;;
        apply)
            cmd_templates_apply "$@"
            ;;
        -h|--help)
            cat << EOF
${BOLD}SSH Configuration Templates${NC}

Pre-built SSH configurations for common services.

${YELLOW}Usage:${NC}
    $0 templates <action> [OPTIONS]

${BOLD}Actions:${NC}
    list                List available templates
    apply TEMPLATE      Apply a template configuration

${BOLD}Examples:${NC}
    $0 templates list
    $0 templates apply github

EOF
            return $EXIT_OK
            ;;
        *)
            log_error "Unknown action: $action"
            return $EXIT_INVALID_ARGS
            ;;
    esac
}

cmd_templates_list() {
    print_header "Available SSH Templates"
    
    local templates_dir="${SCRIPT_DIR}/templates"
    
    if [[ ! -d "$templates_dir" ]]; then
        echo "${DIM}No templates available yet${NC}"
        return $EXIT_OK
    fi
    
    printf "${BOLD}%-15s %s${NC}\n" "TEMPLATE" "DESCRIPTION"
    printf "${DIM}%s${NC}\n" "$(printf '%.0s─' {1..60})"
    
    shopt -s nullglob
    for template in "$templates_dir"/*.conf; do
        [[ -f "$template" ]] || continue
        
        local name=$(basename "$template" .conf)
        local desc=$(grep "^#" "$template" | head -1 | sed 's/^# *//')
        
        [[ -z "$desc" ]] && desc="SSH configuration for $name"
        
        printf "%-15s %s\n" "$name" "$desc"
    done
    
    return $EXIT_OK
}

cmd_templates_apply() {
    local template="$1"
    
    if [[ -z "$template" ]]; then
        log_error "Template name is required"
        log_info "Usage: $0 templates apply TEMPLATE"
        return $EXIT_INVALID_ARGS
    fi
    
    local templates_dir="${SCRIPT_DIR}/templates"
    local template_file="${templates_dir}/${template}.conf"
    
    if [[ ! -f "$template_file" ]]; then
        log_error "Template '$template' not found"
        log_info "Available templates: $0 templates list"
        return $EXIT_ERROR
    fi
    
    print_header "Apply Template: $template"
    
    ensure_ssh_dir
    mkdir -p "$SSH_CONFIG_D"
    
    local output_file="${SSH_CONFIG_D}/${template}.conf"
    
    if [[ -f "$output_file" ]]; then
        log_warn "Template '$template' already applied"
        read -p "Overwrite? [y/N]: " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && return $EXIT_OK
    fi
    
    if [[ "$DRY_RUN" != "true" ]]; then
        cp "$template_file" "$output_file"
        chmod 600 "$output_file"
        
        log_ok "Template applied to $output_file"
        echo
        echo "${DIM}Review and customize:${NC}"
        echo "  ${CYAN}$0 hosts edit $template${NC}"
    else
        log_info "[DRY RUN] Would apply template '$template'"
    fi
    
    return $EXIT_OK
}

# =============================================================================
# Tunnel Subcommand
# =============================================================================

cmd_tunnel() {
    local action="${1:-list}"
    shift || true
    
    case "$action" in
        local|l)
            cmd_tunnel_local "$@"
            ;;
        remote|r)
            cmd_tunnel_remote "$@"
            ;;
        dynamic|d)
            cmd_tunnel_dynamic "$@"
            ;;
        list|ls|'')
            cmd_tunnel_list "$@"
            ;;
        stop)
            cmd_tunnel_stop "$@"
            ;;
        -h|--help)
            cat << EOF
${BOLD}SSH Tunnel Management${NC}

Create and manage SSH tunnels and port forwards.

${YELLOW}Usage:${NC}
    $0 tunnel <action> [OPTIONS]

${BOLD}Actions:${NC}
    local PORT HOST REMOTE_PORT    Local port forward
    remote PORT HOST REMOTE_PORT   Remote port forward
    dynamic PORT HOST              SOCKS proxy
    list                           List active tunnels
    stop [PID|all]                Stop tunnel(s)

${BOLD}Examples:${NC}
    $0 tunnel local 8080 myserver 80
    $0 tunnel dynamic 1080 myserver
    $0 tunnel list
    $0 tunnel stop all

EOF
            return $EXIT_OK
            ;;
        *)
            log_error "Unknown action: $action"
            return $EXIT_INVALID_ARGS
            ;;
    esac
}

cmd_tunnel_local() {
    local local_port="$1"
    local host="$2"
    local remote_port="$3"
    
    if [[ -z "$local_port" ]] || [[ -z "$host" ]] || [[ -z "$remote_port" ]]; then
        log_error "Usage: $0 tunnel local PORT HOST REMOTE_PORT"
        return $EXIT_INVALID_ARGS
    fi
    
    print_header "Local Port Forward"
    
    echo "Creating tunnel: ${BOLD}localhost:${local_port}${NC} → ${BOLD}${host}:${remote_port}${NC}"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        ssh -f -N -L "${local_port}:localhost:${remote_port}" "$host"
        local pid=$!
        
        log_ok "Tunnel established"
        echo
        echo "Access at: ${CYAN}http://localhost:${local_port}${NC}"
        echo "Stop with: ${CYAN}$0 tunnel stop all${NC}"
    else
        log_info "[DRY RUN] Would create tunnel"
    fi
    
    return $EXIT_OK
}

cmd_tunnel_dynamic() {
    local local_port="$1"
    local host="$2"
    
    if [[ -z "$local_port" ]] || [[ -z "$host" ]]; then
        log_error "Usage: $0 tunnel dynamic PORT HOST"
        return $EXIT_INVALID_ARGS
    fi
    
    print_header "Dynamic SOCKS Proxy"
    
    echo "Creating SOCKS5 proxy on: ${BOLD}localhost:${local_port}${NC}"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        ssh -f -N -D "${local_port}" "$host"
        
        log_ok "SOCKS proxy established"
        echo
        echo "Configure applications to use:"
        echo "  SOCKS5 proxy: ${CYAN}localhost:${local_port}${NC}"
    else
        log_info "[DRY RUN] Would create SOCKS proxy"
    fi
    
    return $EXIT_OK
}

cmd_tunnel_list() {
    print_header "Active SSH Tunnels"
    
    local tunnels
    tunnels=$(ps aux | grep "ssh -[fN]" | grep -v grep || true)
    
    if [[ -z "$tunnels" ]]; then
        echo "${DIM}No active tunnels${NC}"
        return $EXIT_OK
    fi
    
    printf "${BOLD}%-8s %-50s${NC}\n" "PID" "COMMAND"
    printf "${DIM}%s${NC}\n" "$(printf '%.0s─' {1..60})"
    
    echo "$tunnels" | while read -r line; do
        local pid=$(echo "$line" | awk '{print $2}')
        local cmd=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf "%s ", $i}')
        printf "%-8s %-50s\n" "$pid" "${cmd:0:50}"
    done
    
    return $EXIT_OK
}

cmd_tunnel_stop() {
    local target="${1:-all}"
    
    if [[ "$target" == "all" ]]; then
        print_header "Stop All SSH Tunnels"
        
        local pids
        pids=$(ps aux | grep "ssh -[fN]" | grep -v grep | awk '{print $2}' || true)
        
        if [[ -z "$pids" ]]; then
            log_info "No active tunnels"
            return $EXIT_OK
        fi
        
        if [[ "$DRY_RUN" != "true" ]]; then
            echo "$pids" | while read -r pid; do
                log_info "Stopping tunnel $pid"
                kill "$pid" 2>/dev/null && log_ok "Stopped" || log_warn "Already stopped"
            done
        else
            log_info "[DRY RUN] Would stop all tunnels"
        fi
    else
        print_header "Stop SSH Tunnel"
        
        if [[ "$DRY_RUN" != "true" ]]; then
            kill "$target" 2>/dev/null && log_ok "Tunnel $target stopped" || log_error "Failed to stop tunnel"
        else
            log_info "[DRY RUN] Would stop tunnel $target"
        fi
    fi
    
    return $EXIT_OK
}

# =============================================================================
# Backup/Restore Subcommands
# =============================================================================

cmd_backup() {
    local encrypt=false
    local output=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --encrypt) encrypt=true; shift ;;
            --output|-o) output="$2"; shift 2 ;;
            -h|--help)
                cat << EOF
${BOLD}Backup SSH Configuration${NC}

Backup entire ~/.ssh/ directory.

${YELLOW}Usage:${NC}
    $0 backup [OPTIONS]

${BOLD}Options:${NC}
    --encrypt       Encrypt backup with GPG
    --output FILE   Output file path

${BOLD}Examples:${NC}
    $0 backup
    $0 backup --encrypt
    $0 backup --output /backup/ssh.tar.gz

EOF
                return $EXIT_OK
                ;;
            *)
                log_error "Unknown option: $1"
                return $EXIT_INVALID_ARGS
                ;;
        esac
    done
    
    print_header "Backup SSH Configuration"
    
    local timestamp=$(date +%Y%m%d-%H%M%S)
    [[ -z "$output" ]] && output="${HOME}/ssh-backup-${timestamp}.tar.gz"
    
    log_info "Creating backup of $SSH_DIR"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        tar -czf "$output" -C "$(dirname "$SSH_DIR")" "$(basename "$SSH_DIR")" \
            --exclude='sockets/*' --exclude='*.sock' 2>/dev/null
        
        local size=$(du -h "$output" | awk '{print $1}')
        
        log_ok "Backup created: $output"
        echo "  Size: ${BOLD}$size${NC}"
        
        if [[ "$encrypt" == "true" ]] && command -v gpg >/dev/null 2>&1; then
            log_info "Encrypting backup..."
            gpg -c "$output" && rm "$output"
            log_ok "Encrypted: ${output}.gpg"
        fi
    else
        log_info "[DRY RUN] Would create backup at $output"
    fi
    
    return $EXIT_OK
}

cmd_restore() {
    local backup_file="$1"
    
    if [[ -z "$backup_file" ]]; then
        log_error "Backup file is required"
        log_info "Usage: $0 restore FILE"
        return $EXIT_INVALID_ARGS
    fi
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return $EXIT_ERROR
    fi
    
    print_header "Restore SSH Configuration"
    
    log_warn "This will overwrite your current SSH configuration!"
    echo
    read -p "Continue? [y/N]: " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cancelled"
        return $EXIT_OK
    fi
    
    # Backup current config
    local current_backup="${SSH_DIR}.backup.$(date +%Y%m%d-%H%M%S)"
    log_info "Backing up current config to: $current_backup"
    mv "$SSH_DIR" "$current_backup"
    
    # Restore
    if [[ "$DRY_RUN" != "true" ]]; then
        tar -xzf "$backup_file" -C "$HOME"
        log_ok "SSH configuration restored"
        
        # Fix permissions
        cmd_permissions --fix
    else
        log_info "[DRY RUN] Would restore from $backup_file"
    fi
    
    return $EXIT_OK
}

# =============================================================================
# Main Entry Point
# =============================================================================

main() {
    # Parse global options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                return $EXIT_OK
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                return $EXIT_INVALID_ARGS
                ;;
            *)
                break
                ;;
        esac
    done
    
    SUBCOMMAND="${1:-}"
    shift || true
    
    # Route to subcommand
    case "$SUBCOMMAND" in
        init|setup)
            cmd_init "$@"
            ;;
        hosts|host|h)
            cmd_hosts "$@"
            ;;
        templates|template|t)
            cmd_templates "$@"
            ;;
        tunnel|tun)
            cmd_tunnel "$@"
            ;;
        permissions|perms|p)
            cmd_permissions "$@"
            ;;
        backup)
            cmd_backup "$@"
            ;;
        restore)
            cmd_restore "$@"
            ;;
        '')
            log_error "Subcommand required"
            echo
            usage
            return $EXIT_INVALID_ARGS
            ;;
        *)
            log_error "Unknown subcommand: $SUBCOMMAND"
            echo
            usage
            return $EXIT_INVALID_ARGS
            ;;
    esac
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit $?
fi
