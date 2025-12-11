#!/bin/bash
# =============================================================================
# @id           ssh-keys
# @name         ssh-keys
# @displayName  SSH Key Management
# @description  Generate, distribute, and manage SSH keys across hosts
# @category     security
# @version      1.0.0
# @author       codefuturist
# @tags         ssh,keys,authentication,distribution,security
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
SCRIPT_NAME="SSH Key Management"
SCRIPT_VERSION="1.0.0"
RSR_LIB_DIR="${SCRIPT_DIR}/../../../lib"

# Load the RSR library with required modules
if [[ -f "$RSR_LIB_DIR/rsr-lib.sh" ]]; then
    source "$RSR_LIB_DIR/rsr-lib.sh" ssh validate
else
    echo "ERROR: RSR library not found at $RSR_LIB_DIR/rsr-lib.sh" >&2
    exit 1
fi

# Default values
VERBOSE=false
DRY_RUN=false
SUBCOMMAND=""

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

Generate, distribute, and manage SSH keys across hosts.

${YELLOW}Usage:${NC}
    $0 <subcommand> [OPTIONS]

${BOLD}Subcommands:${NC}

  ${CYAN}Key Generation:${NC}
    generate            Generate new SSH key pair

  ${CYAN}Key Distribution:${NC}
    copy HOST           Copy public key to a single host
    distribute          Distribute key to multiple hosts (bulk)

  ${CYAN}Key Management:${NC}
    list                List local SSH keys
    test HOST           Test key-based authentication
    revoke HOST         Remove key from remote host(s)

  ${CYAN}SSH Agent:${NC}
    agent               SSH agent management
      status            Show agent status and loaded keys
      start             Start SSH agent
      add [KEY]         Add key to agent
      remove [KEY|all]  Remove key(s) from agent
      list              List loaded keys
      lock              Lock agent with passphrase
      unlock            Unlock agent

${BOLD}Global Options:${NC}
    -h, --help          Display this help message
    -v, --verbose       Enable verbose output
    -d, --dry-run       Show what would be done

${BOLD}Examples:${NC}

    ${DIM}# Generate a new ed25519 key${NC}
    $0 generate

    ${DIM}# Copy key to a server${NC}
    $0 copy admin@myserver.com

    ${DIM}# Distribute to multiple hosts from file${NC}
    $0 distribute -f hosts.txt

    ${DIM}# List local keys with fingerprints${NC}
    $0 list --fingerprints

    ${DIM}# Test key authentication${NC}
    $0 test myserver.com

${BOLD}Help for Subcommands:${NC}
    $0 <subcommand> --help

EOF
    exit 0
}

# =============================================================================
# Subcommand: generate
# =============================================================================

cmd_generate() {
    local key_type="ed25519"
    local key_bits=4096
    local key_file="$HOME/.ssh/id_ed25519"
    local key_comment="$(whoami)@$(hostname)"
    local use_passphrase=false
    local force=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                cat << EOF
${BOLD}Generate SSH Key Pair${NC}

${YELLOW}Usage:${NC} $0 generate [OPTIONS]

${BOLD}Options:${NC}
    -t, --type TYPE       Key type: ed25519 (default), rsa, ecdsa
    -b, --bits N          RSA key bits (default: 4096)
    -f, --file PATH       Output file (default: ~/.ssh/id_ed25519)
    -C, --comment TEXT    Key comment (default: user@hostname)
    -p, --passphrase      Prompt for passphrase
    --force               Overwrite existing key

${BOLD}Examples:${NC}
    $0 generate
    $0 generate -t rsa -b 4096 -p
    $0 generate -f ~/.ssh/id_work -C "work@company.com"

EOF
                exit 0
                ;;
            -t|--type) key_type="$2"; shift 2 ;;
            -b|--bits) key_bits="$2"; shift 2 ;;
            -f|--file) key_file="$2"; shift 2 ;;
            -C|--comment) key_comment="$2"; shift 2 ;;
            -p|--passphrase) use_passphrase=true; shift ;;
            --force) force=true; shift ;;
            *) log_error "Unknown option: $1"; exit $EXIT_INVALID_ARGS ;;
        esac
    done

    print_header "Generate SSH Key"

    # Adjust file name based on type
    if [[ "$key_file" == "$HOME/.ssh/id_ed25519" && "$key_type" != "ed25519" ]]; then
        key_file="$HOME/.ssh/id_${key_type}"
    fi

    # Expand tilde
    key_file="${key_file/#\~/$HOME}"

    # Check if key exists
    if [[ -f "$key_file" ]] && [[ "$force" == "false" ]]; then
        log_error "Key already exists: $key_file"
        log_info "Use --force to overwrite"
        exit $EXIT_ERROR
    fi

    # Create .ssh directory
    mkdir -p "$(dirname "$key_file")"
    chmod 700 "$(dirname "$key_file")"

    # Build ssh-keygen command
    local ssh_keygen_cmd="ssh-keygen -t $key_type -C \"$key_comment\" -f \"$key_file\""
    
    # Add RSA bits if applicable
    if [[ "$key_type" == "rsa" ]]; then
        ssh_keygen_cmd="$ssh_keygen_cmd -b $key_bits"
    fi

    # Add passphrase option
    if [[ "$use_passphrase" == "false" ]]; then
        ssh_keygen_cmd="$ssh_keygen_cmd -N \"\""
    fi

    log_info "Generating $key_type key..."
    log_debug "Command: $ssh_keygen_cmd"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would generate key: $key_file"
        exit 0
    fi

    # Execute
    eval $ssh_keygen_cmd

    # Set permissions
    chmod 600 "$key_file"
    chmod 644 "${key_file}.pub"

    log_ok "Key generated: $key_file"
    echo ""
    echo "${BOLD}Public key:${NC}"
    cat "${key_file}.pub"
    echo ""
    echo "${DIM}Fingerprint:${NC}"
    ssh-keygen -lf "${key_file}.pub"
}

# =============================================================================
# Subcommand: copy
# =============================================================================

cmd_copy() {
    local target=""
    local user=""
    local port=22
    local identity=""
    local test_after=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                cat << EOF
${BOLD}Copy SSH Key to Host${NC}

${YELLOW}Usage:${NC} $0 copy HOST [OPTIONS]

${BOLD}Arguments:${NC}
    HOST                  Target host ([user@]host[:port])

${BOLD}Options:${NC}
    -u, --user USER       Remote username
    -p, --port PORT       SSH port (default: 22)
    -i, --identity FILE   Path to public key (auto-detect if not specified)
    --test                Test connection after copying
    -h, --help            Show this help

${BOLD}Examples:${NC}
    $0 copy myserver.com
    $0 copy admin@192.168.1.10
    $0 copy server:2222 -i ~/.ssh/id_rsa.pub --test
    $0 copy root@myserver -p 2222

EOF
                exit 0
                ;;
            -u|--user) user="$2"; shift 2 ;;
            -p|--port) port="$2"; shift 2 ;;
            -i|--identity) identity="$2"; shift 2 ;;
            --test) test_after=true; shift ;;
            -*)
                log_error "Unknown option: $1"
                exit $EXIT_INVALID_ARGS
                ;;
            *)
                target="$1"
                shift
                ;;
        esac
    done

    [[ -z "$target" ]] && { log_error "Host required"; exit $EXIT_INVALID_ARGS; }

    print_header "Copy SSH Key"

    # Parse target (user@host:port)
    if [[ "$target" =~ ^([^@]+)@(.+)$ ]]; then
        [[ -z "$user" ]] && user="${BASH_REMATCH[1]}"
        target="${BASH_REMATCH[2]}"
    fi

    if [[ "$target" =~ ^(.+):([0-9]+)$ ]]; then
        target="${BASH_REMATCH[1]}"
        port="${BASH_REMATCH[2]}"
    fi

    # Build full target
    local full_target="$target"
    [[ -n "$user" ]] && full_target="${user}@${target}"

    # Auto-detect identity if not specified
    if [[ -z "$identity" ]]; then
        for key in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub" "$HOME/.ssh/id_ecdsa.pub"; do
            if [[ -f "$key" ]]; then
                identity="$key"
                break
            fi
        done
    fi

    [[ ! -f "$identity" ]] && { log_error "Public key not found: $identity"; exit $EXIT_ERROR; }

    log_info "Copying key to $full_target:$port"
    log_debug "Using key: $identity"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would copy $identity to $full_target"
        exit 0
    fi

    # Read public key
    local pubkey
    pubkey=$(cat "$identity")

    # Copy key using ssh
    if ssh -p "$port" "$full_target" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$pubkey' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && echo 'Key added successfully'" 2>/dev/null; then
        log_ok "Key copied successfully"
    else
        log_error "Failed to copy key"
        log_info "Make sure you can connect with password authentication first"
        exit $EXIT_ERROR
    fi

    # Test connection if requested
    if [[ "$test_after" == "true" ]]; then
        log_info "Testing key-based authentication..."
        if ssh -o BatchMode=yes -o ConnectTimeout=5 -p "$port" "$full_target" exit 2>/dev/null; then
            log_ok "Key authentication works!"
        else
            log_warn "Key authentication test failed"
        fi
    fi
}

# =============================================================================
# Subcommand: list
# =============================================================================

cmd_list() {
    local show_fingerprints=false
    local show_public=false
    local show_agents=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                cat << EOF
${BOLD}List SSH Keys${NC}

${YELLOW}Usage:${NC} $0 list [OPTIONS]

${BOLD}Options:${NC}
    --fingerprints        Show key fingerprints
    --public              Show public key content
    --agents              List keys in SSH agent
    -h, --help            Show this help

${BOLD}Examples:${NC}
    $0 list
    $0 list --fingerprints
    $0 list --public --agents

EOF
                exit 0
                ;;
            --fingerprints) show_fingerprints=true; shift ;;
            --public) show_public=true; shift ;;
            --agents) show_agents=true; shift ;;
            *) log_error "Unknown option: $1"; exit $EXIT_INVALID_ARGS ;;
        esac
    done

    print_header "Local SSH Keys"

    # List local keys
    local keys=()
    while IFS= read -r key; do
        keys+=("$key")
    done < <(rsr_ssh_list_local_keys)

    if [[ ${#keys[@]} -eq 0 ]]; then
        log_warn "No SSH keys found in ~/.ssh/"
        echo ""
        log_info "Generate a new key with: $0 generate"
        exit 0
    fi

    for key in "${keys[@]}"; do
        local key_name
        key_name=$(basename "$key")
        echo ""
        echo "${BOLD}${key_name}${NC}"
        echo "${DIM}  Path: $key${NC}"

        if [[ "$show_fingerprints" == "true" ]]; then
            local fingerprint
            fingerprint=$(rsr_ssh_get_key_fingerprint "$key")
            echo "  Fingerprint: $fingerprint"
        fi

        if [[ "$show_public" == "true" ]]; then
            echo "  Public key:"
            sed 's/^/    /' "$key"
        fi
    done

    # List agent keys if requested
    if [[ "$show_agents" == "true" ]]; then
        echo ""
        print_header "SSH Agent Keys"
        if ssh-add -l &>/dev/null; then
            ssh-add -l
        else
            log_warn "No SSH agent running or no keys loaded"
        fi
    fi

    echo ""
}

# =============================================================================
# Subcommand: test
# =============================================================================

cmd_test() {
    local target=""
    local user=""
    local port=22
    local identity=""
    local verbose_ssh=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                cat << EOF
${BOLD}Test SSH Key Authentication${NC}

${YELLOW}Usage:${NC} $0 test HOST [OPTIONS]

${BOLD}Arguments:${NC}
    HOST                  Target host ([user@]host[:port])

${BOLD}Options:${NC}
    -u, --user USER       Remote username
    -p, --port PORT       SSH port (default: 22)
    -i, --identity FILE   Private key to test
    -v, --verbose         Show detailed SSH connection info
    -h, --help            Show this help

${BOLD}Examples:${NC}
    $0 test myserver.com
    $0 test admin@192.168.1.10 -v
    $0 test server:2222 -i ~/.ssh/id_rsa

EOF
                exit 0
                ;;
            -u|--user) user="$2"; shift 2 ;;
            -p|--port) port="$2"; shift 2 ;;
            -i|--identity) identity="$2"; shift 2 ;;
            --verbose|-v) verbose_ssh=true; VERBOSE=true; shift ;;
            -*)
                log_error "Unknown option: $1"
                exit $EXIT_INVALID_ARGS
                ;;
            *)
                target="$1"
                shift
                ;;
        esac
    done

    [[ -z "$target" ]] && { log_error "Host required"; exit $EXIT_INVALID_ARGS; }

    print_header "Test SSH Key Authentication"

    # Parse target
    if [[ "$target" =~ ^([^@]+)@(.+)$ ]]; then
        [[ -z "$user" ]] && user="${BASH_REMATCH[1]}"
        target="${BASH_REMATCH[2]}"
    fi

    if [[ "$target" =~ ^(.+):([0-9]+)$ ]]; then
        target="${BASH_REMATCH[1]}"
        port="${BASH_REMATCH[2]}"
    fi

    local full_target="$target"
    [[ -n "$user" ]] && full_target="${user}@${target}"

    log_info "Testing connection to $full_target:$port"
    [[ -n "$identity" ]] && log_debug "Using key: $identity"

    # Build SSH command
    local ssh_opts="-o BatchMode=yes -o ConnectTimeout=5 -o PreferredAuthentications=publickey"
    [[ "$verbose_ssh" == "true" ]] && ssh_opts="$ssh_opts -vvv"
    [[ -n "$identity" ]] && ssh_opts="$ssh_opts -i $identity"

    if ssh $ssh_opts -p "$port" "$full_target" exit 2>&1; then
        log_ok "Key authentication successful!"
        exit 0
    else
        log_error "Key authentication failed"
        echo ""
        log_info "Troubleshooting steps:"
        echo "  1. Copy your key: $0 copy $full_target"
        echo "  2. Check key exists: $0 list"
        echo "  3. Run with -v for details: $0 test $full_target -v"
        exit $EXIT_ERROR
    fi
}

# =============================================================================
# Subcommand: distribute
# =============================================================================

cmd_distribute() {
    local hosts_file=""
    local hosts_list=""
    local identity=""
    local parallel=5
    local timeout=10
    local report=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                cat << EOF
${BOLD}Distribute SSH Key to Multiple Hosts${NC}

${YELLOW}Usage:${NC} $0 distribute [OPTIONS]

${BOLD}Options:${NC}
    -f, --file FILE       Hosts file (one per line: [user@]host[:port])
    -H, --hosts "H1 H2"   Space-separated host list
    -i, --identity FILE   Public key to distribute
    --parallel N          Parallel connections (default: 5)
    --timeout SEC         Connection timeout (default: 10)
    --report              Generate distribution report
    -h, --help            Show this help

${BOLD}Hosts File Format:${NC}
    # Comments and empty lines ignored
    server1.example.com
    admin@server2.example.com
    root@192.168.1.10:2222

${BOLD}Examples:${NC}
    $0 distribute -f hosts.txt
    $0 distribute -H "server1 server2 server3"
    $0 distribute -f servers.txt --parallel 10 --report

EOF
                exit 0
                ;;
            -f|--file) hosts_file="$2"; shift 2 ;;
            -H|--hosts) hosts_list="$2"; shift 2 ;;
            -i|--identity) identity="$2"; shift 2 ;;
            --parallel) parallel="$2"; shift 2 ;;
            --timeout) timeout="$2"; shift 2 ;;
            --report) report=true; shift ;;
            *) log_error "Unknown option: $1"; exit $EXIT_INVALID_ARGS ;;
        esac
    done

    # Need either file or hosts list
    [[ -z "$hosts_file" && -z "$hosts_list" ]] && {
        log_error "Either --file or --hosts required"
        exit $EXIT_INVALID_ARGS
    }

    print_header "Distribute SSH Key"

    # Auto-detect identity if not specified
    if [[ -z "$identity" ]]; then
        for key in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub"; do
            if [[ -f "$key" ]]; then
                identity="$key"
                break
            fi
        done
    fi

    [[ ! -f "$identity" ]] && { log_error "Public key not found: $identity"; exit $EXIT_ERROR; }

    log_info "Using key: $identity"

    # Build host list
    local hosts=()
    if [[ -n "$hosts_file" ]]; then
        [[ ! -f "$hosts_file" ]] && { log_error "Hosts file not found: $hosts_file"; exit $EXIT_ERROR; }
        while IFS= read -r line; do
            # Skip comments and empty lines
            [[ "$line" =~ ^#.* || -z "$line" ]] && continue
            hosts+=("$line")
        done < "$hosts_file"
    else
        IFS=' ' read -ra hosts <<< "$hosts_list"
    fi

    log_info "Distributing to ${#hosts[@]} host(s)"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would distribute to:"
        printf '  %s\n' "${hosts[@]}"
        exit 0
    fi

    # Distribute (simple sequential for now, parallel would use GNU parallel or xargs)
    local success=0
    local failed=0
    local failed_hosts=()

    for host in "${hosts[@]}"; do
        echo ""
        log_info "Copying to $host..."
        if rsr_ssh_copy_key_to_host "$host" "$identity" 22 &>/dev/null; then
            log_ok "$host"
            ((success++))
        else
            log_error "$host"
            ((failed++))
            failed_hosts+=("$host")
        fi
    done

    echo ""
    print_header "Distribution Summary"
    echo "${GREEN}Success: $success${NC}"
    echo "${RED}Failed: $failed${NC}"

    if [[ ${#failed_hosts[@]} -gt 0 ]]; then
        echo ""
        echo "${BOLD}Failed hosts:${NC}"
        printf '  %s\n' "${failed_hosts[@]}"
    fi

    [[ $failed -gt 0 ]] && exit $EXIT_ERROR
}

# =============================================================================
# Subcommand: revoke
# =============================================================================

cmd_revoke() {
    local target=""
    local user=""
    local port=22
    local identity=""
    local hosts_file=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                cat << EOF
${BOLD}Revoke SSH Key from Host${NC}

${YELLOW}Usage:${NC} $0 revoke HOST [OPTIONS]

${BOLD}Arguments:${NC}
    HOST                  Target host ([user@]host[:port])

${BOLD}Options:${NC}
    -u, --user USER       Remote username
    -p, --port PORT       SSH port (default: 22)
    -i, --identity FILE   Public key to revoke
    -f, --file FILE       Hosts file for bulk revocation
    -h, --help            Show this help

${BOLD}Examples:${NC}
    $0 revoke myserver.com -i ~/.ssh/id_rsa.pub
    $0 revoke admin@192.168.1.10
    $0 revoke -f hosts.txt -i ~/.ssh/old_key.pub

EOF
                exit 0
                ;;
            -u|--user) user="$2"; shift 2 ;;
            -p|--port) port="$2"; shift 2 ;;
            -i|--identity) identity="$2"; shift 2 ;;
            -f|--file) hosts_file="$2"; shift 2 ;;
            -*)
                log_error "Unknown option: $1"
                exit $EXIT_INVALID_ARGS
                ;;
            *)
                target="$1"
                shift
                ;;
        esac
    done

    [[ -z "$target" && -z "$hosts_file" ]] && {
        log_error "Host or hosts file required"
        exit $EXIT_INVALID_ARGS
    }

    print_header "Revoke SSH Key"

    # Auto-detect identity
    if [[ -z "$identity" ]]; then
        for key in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub"; do
            if [[ -f "$key" ]]; then
                identity="$key"
                break
            fi
        done
    fi

    [[ ! -f "$identity" ]] && { log_error "Public key not found: $identity"; exit $EXIT_ERROR; }

    # Get key pattern (use comment or first few chars)
    local pattern
    pattern=$(awk '{print $3}' "$identity" 2>/dev/null || awk '{print substr($2, 1, 20)}' "$identity")

    log_info "Revoking key: $identity"
    log_debug "Pattern: $pattern"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would revoke key from $target"
        exit 0
    fi

    # Parse target
    if [[ "$target" =~ ^([^@]+)@(.+)$ ]]; then
        [[ -z "$user" ]] && user="${BASH_REMATCH[1]}"
        target="${BASH_REMATCH[2]}"
    fi

    if [[ "$target" =~ ^(.+):([0-9]+)$ ]]; then
        target="${BASH_REMATCH[1]}"
        port="${BASH_REMATCH[2]}"
    fi

    local full_target="$target"
    [[ -n "$user" ]] && full_target="${user}@${target}"

    log_info "Revoking from $full_target:$port..."

    if rsr_ssh_revoke_key_from_host "$full_target" "$pattern" "$port" &>/dev/null; then
        log_ok "Key revoked successfully"
    else
        log_error "Failed to revoke key"
        exit $EXIT_ERROR
    fi
}

# =============================================================================
# Subcommand: agent
# =============================================================================

cmd_agent() {
    local action="${1:-status}"
    shift || true
    
    case "$action" in
        status)
            cmd_agent_status "$@"
            ;;
        start)
            cmd_agent_start "$@"
            ;;
        add)
            cmd_agent_add "$@"
            ;;
        remove|rm)
            cmd_agent_remove "$@"
            ;;
        list|ls)
            cmd_agent_list "$@"
            ;;
        lock)
            cmd_agent_lock "$@"
            ;;
        unlock)
            cmd_agent_unlock "$@"
            ;;
        -h|--help)
            cat << EOF
${BOLD}SSH Agent Management${NC}

Manage SSH agent and loaded keys.

${YELLOW}Usage:${NC}
    $0 agent <action> [OPTIONS]

${BOLD}Actions:${NC}
    status              Show agent status and loaded keys
    start               Start SSH agent
    add [KEY]           Add key to agent (auto-detect if not specified)
    remove [KEY|all]    Remove key(s) from agent
    list                List loaded keys
    lock                Lock agent with passphrase
    unlock              Unlock agent

${BOLD}Options (add):${NC}
    -t TIME             Key lifetime (e.g., 1h, 8h, 1d)
    --all               Add all keys from ~/.ssh/

${BOLD}Examples:${NC}
    $0 agent status
    $0 agent add ~/.ssh/id_ed25519
    $0 agent add --all
    $0 agent add ~/.ssh/id_work -t 8h
    $0 agent remove all
    $0 agent lock

EOF
            return $EXIT_OK
            ;;
        *)
            log_error "Unknown action: $action"
            log_info "Use '$0 agent --help' for usage information"
            return $EXIT_INVALID_ARGS
            ;;
    esac
}

cmd_agent_status() {
    print_header "SSH Agent Status"
    
    if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
        echo "${RED}✗${NC} Agent not running"
        echo
        echo "Start agent with: ${CYAN}$0 agent start${NC}"
        return $EXIT_ERROR
    fi
    
    if ! ssh-add -l >/dev/null 2>&1; then
        local exit_code=$?
        if [[ $exit_code -eq 2 ]]; then
            echo "${RED}✗${NC} Agent not running"
            return $EXIT_ERROR
        elif [[ $exit_code -eq 1 ]]; then
            echo "${GREEN}✓${NC} Agent running (PID: ${SSH_AGENT_PID:-unknown})"
            echo "Loaded keys: ${DIM}0${NC}"
            return $EXIT_OK
        fi
    fi
    
    echo "${GREEN}✓${NC} Agent running (PID: ${SSH_AGENT_PID:-unknown})"
    
    local keys
    keys=$(ssh-add -l 2>/dev/null)
    local key_count=$(echo "$keys" | wc -l | tr -d ' ')
    
    echo "Loaded keys: ${BOLD}$key_count${NC}"
    echo
    
    if [[ -n "$keys" ]]; then
        echo "${BOLD}Keys:${NC}"
        while IFS= read -r line; do
            local bits=$(echo "$line" | awk '{print $1}')
            local hash=$(echo "$line" | awk '{print $2}')
            local path=$(echo "$line" | awk '{print $3}')
            local type=$(echo "$line" | awk '{print $4}' | tr -d '()')
            
            echo "  ${GREEN}✓${NC} $hash"
            echo "    ${DIM}Type: $type, Bits: $bits, Path: $path${NC}"
        done <<< "$keys"
    fi
    
    return $EXIT_OK
}

cmd_agent_start() {
    print_header "Start SSH Agent"
    
    if [[ -n "${SSH_AUTH_SOCK:-}" ]] && ssh-add -l >/dev/null 2>&1; then
        log_warn "Agent already running (PID: ${SSH_AGENT_PID:-unknown})"
        return $EXIT_OK
    fi
    
    log_info "Starting SSH agent..."
    
    eval "$(ssh-agent -s)"
    
    if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
        log_ok "Agent started (PID: $SSH_AGENT_PID)"
        echo
        echo "${BOLD}Important:${NC} To use this agent in your current shell, run:"
        echo "  ${CYAN}eval \"\$(ssh-agent -s)\"${NC}"
        echo
        echo "Or add to your shell profile:"
        echo "  ${CYAN}# Start SSH agent if not running${NC}"
        echo "  ${CYAN}if [ -z \"\$SSH_AUTH_SOCK\" ]; then${NC}"
        echo "  ${CYAN}    eval \"\$(ssh-agent -s)\" > /dev/null${NC}"
        echo "  ${CYAN}fi${NC}"
    else
        log_error "Failed to start agent"
        return $EXIT_ERROR
    fi
    
    return $EXIT_OK
}

cmd_agent_add() {
    local key_path=""
    local lifetime=""
    local add_all=false
    local added=0
    local skipped=0
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--lifetime)
                lifetime="$2"
                shift 2
                ;;
            --all)
                add_all=true
                shift
                ;;
            -h|--help)
                cat << EOF
${BOLD}Add Key to SSH Agent${NC}

${YELLOW}Usage:${NC}
    $0 agent add [KEY] [OPTIONS]

${BOLD}Options:${NC}
    -t, --lifetime TIME    Key lifetime (e.g., 1h, 8h, 1d)
    --all                  Add all keys from ~/.ssh/

${BOLD}Examples:${NC}
    $0 agent add
    $0 agent add ~/.ssh/id_ed25519
    $0 agent add ~/.ssh/id_work -t 8h
    $0 agent add --all

EOF
                return $EXIT_OK
                ;;
            *)
                key_path="$1"
                shift
                ;;
        esac
    done
    
    # Check agent is running
    if [[ -z "${SSH_AUTH_SOCK:-}" ]] || ! ssh-add -l >/dev/null 2>&1; then
        log_error "SSH agent not running"
        log_info "Start with: $0 agent start"
        return $EXIT_ERROR
    fi
    
    print_header "Add Keys to Agent"
    
    if [[ "$add_all" == "true" ]]; then
        log_info "Adding all keys from ~/.ssh/"
        
        shopt -s nullglob
        for key in ~/.ssh/id_* ~/.ssh/keys/id_*; do
            [[ -f "$key" ]] || continue
            [[ "$key" == *.pub ]] && continue
            
            local key_name=$(basename "$key")
            
            # Check if already loaded
            if ssh-add -l 2>/dev/null | grep -q "$key"; then
                echo "${YELLOW}⚠${NC}  Skipped: $key_name (already loaded)"
                skipped=$((skipped + 1))
                continue
            fi
            
            if [[ -n "$lifetime" ]]; then
                ssh-add -t "$lifetime" "$key" 2>/dev/null
            else
                ssh-add "$key" 2>/dev/null
            fi
            
            if [[ $? -eq 0 ]]; then
                local lifetime_msg=""
                [[ -n "$lifetime" ]] && lifetime_msg=" (expires in $lifetime)"
                echo "${GREEN}✓${NC} Added: $key_name$lifetime_msg"
                added=$((added + 1))
            else
                echo "${RED}✗${NC} Failed: $key_name"
            fi
        done
        
        echo
        echo "${BOLD}Summary:${NC} $added added, $skipped skipped"
        
    elif [[ -n "$key_path" ]]; then
        if [[ ! -f "$key_path" ]]; then
            log_error "Key not found: $key_path"
            return $EXIT_ERROR
        fi
        
        if ssh-add -l 2>/dev/null | grep -q "$key_path"; then
            log_warn "Key already loaded: $(basename "$key_path")"
            return $EXIT_OK
        fi
        
        if [[ -n "$lifetime" ]]; then
            ssh-add -t "$lifetime" "$key_path"
        else
            ssh-add "$key_path"
        fi
        
        if [[ $? -eq 0 ]]; then
            local lifetime_msg=""
            [[ -n "$lifetime" ]] && lifetime_msg=" (expires in $lifetime)"
            log_ok "Added: $(basename "$key_path")$lifetime_msg"
        else
            log_error "Failed to add key"
            return $EXIT_ERROR
        fi
        
    else
        # Auto-detect default key
        local default_keys=("~/.ssh/id_ed25519" "~/.ssh/id_rsa" "~/.ssh/id_ecdsa")
        local found=false
        
        for key in "${default_keys[@]}"; do
            key="${key/#\~/$HOME}"
            if [[ -f "$key" ]]; then
                log_info "Auto-detected key: $(basename "$key")"
                
                if ssh-add -l 2>/dev/null | grep -q "$key"; then
                    log_warn "Key already loaded"
                    return $EXIT_OK
                fi
                
                if [[ -n "$lifetime" ]]; then
                    ssh-add -t "$lifetime" "$key"
                else
                    ssh-add "$key"
                fi
                
                if [[ $? -eq 0 ]]; then
                    log_ok "Added to agent"
                    found=true
                    break
                fi
            fi
        done
        
        if [[ "$found" != "true" ]]; then
            log_error "No default SSH key found"
            log_info "Generate one with: $0 generate"
            return $EXIT_ERROR
        fi
    fi
    
    return $EXIT_OK
}

cmd_agent_remove() {
    local target="${1:-}"
    
    if [[ -z "$target" ]]; then
        log_error "Key path or 'all' required"
        log_info "Usage: $0 agent remove [KEY|all]"
        return $EXIT_INVALID_ARGS
    fi
    
    print_header "Remove Keys from Agent"
    
    if [[ "$target" == "all" ]]; then
        if [[ "$DRY_RUN" != "true" ]]; then
            ssh-add -D
            log_ok "All keys removed from agent"
        else
            log_info "[DRY RUN] Would remove all keys"
        fi
    else
        if [[ ! -f "$target" ]]; then
            log_error "Key not found: $target"
            return $EXIT_ERROR
        fi
        
        if [[ "$DRY_RUN" != "true" ]]; then
            ssh-add -d "$target"
            if [[ $? -eq 0 ]]; then
                log_ok "Removed: $(basename "$target")"
            else
                log_error "Failed to remove key"
                return $EXIT_ERROR
            fi
        else
            log_info "[DRY RUN] Would remove: $(basename "$target")"
        fi
    fi
    
    return $EXIT_OK
}

cmd_agent_list() {
    cmd_agent_status "$@"
}

cmd_agent_lock() {
    print_header "Lock SSH Agent"
    
    if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
        log_error "Agent not running"
        return $EXIT_ERROR
    fi
    
    log_info "Locking agent (you will be prompted for a passphrase)..."
    
    if ssh-add -x; then
        log_ok "Agent locked"
        echo
        echo "Unlock with: ${CYAN}$0 agent unlock${NC}"
    else
        log_error "Failed to lock agent"
        return $EXIT_ERROR
    fi
    
    return $EXIT_OK
}

cmd_agent_unlock() {
    print_header "Unlock SSH Agent"
    
    if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
        log_error "Agent not running"
        return $EXIT_ERROR
    fi
    
    log_info "Unlocking agent (enter lock passphrase)..."
    
    if ssh-add -X; then
        log_ok "Agent unlocked"
    else
        log_error "Failed to unlock agent"
        return $EXIT_ERROR
    fi
    
    return $EXIT_OK
}

# =============================================================================
# Main Entry Point
# =============================================================================

main() {
    # Parse global flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage ;;
            -v|--verbose) VERBOSE=true; shift ;;
            -d|--dry-run) DRY_RUN=true; shift ;;
            -*) 
                log_error "Unknown option: $1"
                usage
                ;;
            *)
                SUBCOMMAND="$1"
                shift
                break
                ;;
        esac
    done

    # Check subcommand
    case "$SUBCOMMAND" in
        generate) cmd_generate "$@" ;;
        copy) cmd_copy "$@" ;;
        list|ls) cmd_list "$@" ;;
        test) cmd_test "$@" ;;
        distribute|dist) cmd_distribute "$@" ;;
        revoke) cmd_revoke "$@" ;;
        agent) cmd_agent "$@" ;;
        "")
            log_error "Subcommand required"
            echo ""
            usage
            ;;
        *)
            log_error "Unknown subcommand: $SUBCOMMAND"
            echo ""
            usage
            ;;
    esac
}

main "$@"
