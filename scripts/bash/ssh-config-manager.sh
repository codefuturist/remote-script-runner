#!/bin/bash

# SSH Configuration Manager
# A comprehensive script for managing SSH configurations, keys, and security settings
# Author: Remote Script Runner
# Version: 1.0.0

set -euo pipefail

# Script information
readonly SCRIPT_NAME="SSH Configuration Manager"
readonly SCRIPT_VERSION="1.0.0"
# Handle cases where script is piped through stdin
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    readonly SCRIPT_DIR="$(pwd)"
fi

# Default values
SSH_DIR="${HOME}/.ssh"
CONFIG_FILE="${SSH_DIR}/config"
AUTHORIZED_KEYS="${SSH_DIR}/authorized_keys"
KNOWN_HOSTS="${SSH_DIR}/known_hosts"
BACKUP_DIR="${SSH_DIR}/backups"
VERBOSE=false
DRY_RUN=false
FORCE=false

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

debug() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $*"
    fi
}

# Display usage information
usage() {
    cat << EOF
${SCRIPT_NAME} v${SCRIPT_VERSION}

USAGE:
    $(basename "$0") [OPTIONS] COMMAND [ARGS]

COMMANDS:
    init                    Initialize SSH directory with secure permissions
    generate-key            Generate new SSH key pair
    add-host                Add host configuration to SSH config
    remove-host             Remove host configuration from SSH config
    list-hosts              List all configured hosts
    backup                  Backup SSH configuration
    restore                 Restore SSH configuration from backup
    harden                  Apply security hardening to SSH configuration
    check-permissions       Check and fix SSH file permissions
    clean-known-hosts       Clean duplicate entries from known_hosts
    test-connection         Test SSH connection to a host

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -n, --dry-run           Show what would be done without making changes
    -f, --force             Force operation without confirmation
    -d, --ssh-dir DIR       Specify SSH directory (default: ~/.ssh)
    -b, --backup-dir DIR    Specify backup directory (default: ~/.ssh/backups)

EXAMPLES:
    # Initialize SSH configuration
    $(basename "$0") init

    # Generate new ED25519 key
    $(basename "$0") generate-key -t ed25519 -C "user@example.com"

    # Add host configuration
    $(basename "$0") add-host myserver -H example.com -u myuser -p 22

    # Apply security hardening
    $(basename "$0") harden

    # Backup current configuration
    $(basename "$0") backup

REMOTE EXECUTION:
    curl -fsSL https://raw.githubusercontent.com/codefuturist/remote-script-runner/main/ssh-config-manager.sh | bash -s -- init

EOF
}

# Parse command line arguments
parse_args() {
    local args=()
    local parsing_global=true
    
    while [[ $# -gt 0 ]]; do
        if [[ "$parsing_global" == true ]]; then
            case $1 in
                -h|--help)
                    usage
                    exit 0
                    ;;
                -v|--verbose)
                    VERBOSE=true
                    shift
                    ;;
                -n|--dry-run)
                    DRY_RUN=true
                    shift
                    ;;
                -f|--force)
                    FORCE=true
                    shift
                    ;;
                -d|--ssh-dir)
                    SSH_DIR="$2"
                    CONFIG_FILE="${SSH_DIR}/config"
                    AUTHORIZED_KEYS="${SSH_DIR}/authorized_keys"
                    KNOWN_HOSTS="${SSH_DIR}/known_hosts"
                    shift 2
                    ;;
                -b|--backup-dir)
                    BACKUP_DIR="$2"
                    shift 2
                    ;;
                -*)
                    error "Unknown option: $1"
                    usage
                    exit 1
                    ;;
                *)
                    # Found command, stop parsing global options
                    parsing_global=false
                    args+=("$1")
                    shift
                    ;;
            esac
        else
            # After command, just collect all remaining arguments
            args+=("$1")
            shift
        fi
    done
    
    # Restore positional parameters
    set -- "${args[@]}"
    
    # Get command
    COMMAND="${1:-}"
    shift || true
    
    # Store remaining arguments
    ARGS=("$@")
}

# Execute command with dry-run support
execute() {
    local cmd="$*"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would execute: $cmd"
    else
        debug "Executing: $cmd"
        eval "$cmd"
    fi
}

# Create backup of SSH configuration
create_backup() {
    local backup_name="${1:-backup}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="${BACKUP_DIR}/${backup_name}_${timestamp}"
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        execute "mkdir -p '$BACKUP_DIR'"
        execute "chmod 700 '$BACKUP_DIR'"
    fi
    
    if [[ -d "$SSH_DIR" ]]; then
        log "Creating backup at: $backup_path"
        execute "cp -r '$SSH_DIR' '$backup_path'"
        return 0
    else
        warning "SSH directory not found, nothing to backup"
        return 1
    fi
}

# Initialize SSH directory with proper permissions
cmd_init() {
    log "Initializing SSH configuration directory..."
    
    # Create SSH directory if it doesn't exist
    if [[ ! -d "$SSH_DIR" ]]; then
        execute "mkdir -p '$SSH_DIR'"
    fi
    
    # Set proper permissions
    execute "chmod 700 '$SSH_DIR'"
    
    # Create config file if it doesn't exist
    if [[ ! -f "$CONFIG_FILE" ]]; then
        execute "touch '$CONFIG_FILE'"
        execute "chmod 600 '$CONFIG_FILE'"
        
        # Add basic configuration
        if [[ "$DRY_RUN" != true ]]; then
            cat > "$CONFIG_FILE" << 'EOF'
# SSH Client Configuration
# Generated by SSH Configuration Manager

# Global settings
Host *
    # Use SSH protocol 2 only
    Protocol 2
    
    # Enable compression
    Compression yes
    
    # Keep connections alive
    ServerAliveInterval 60
    ServerAliveCountMax 3
    
    # Reuse connections
    ControlMaster auto
    ControlPath ~/.ssh/control-%h-%p-%r
    ControlPersist 10m
    
    # Security settings
    HashKnownHosts yes
    StrictHostKeyChecking ask
    
    # Preferred algorithms (secure defaults)
    KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
    HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
    Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
    MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com

# Host-specific configurations below
EOF
        fi
    fi
    
    # Create authorized_keys if it doesn't exist
    if [[ ! -f "$AUTHORIZED_KEYS" ]]; then
        execute "touch '$AUTHORIZED_KEYS'"
        execute "chmod 600 '$AUTHORIZED_KEYS'"
    fi
    
    # Create known_hosts if it doesn't exist
    if [[ ! -f "$KNOWN_HOSTS" ]]; then
        execute "touch '$KNOWN_HOSTS'"
        execute "chmod 644 '$KNOWN_HOSTS'"
    fi
    
    log "SSH configuration initialized successfully"
}

# Generate SSH key pair
cmd_generate_key() {
    local key_type="ed25519"
    local key_comment=""
    local key_name=""
    local key_bits=""
    
    # Parse generate-key specific arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--type)
                key_type="$2"
                shift 2
                ;;
            -C|--comment)
                key_comment="$2"
                shift 2
                ;;
            -f|--file)
                key_name="$2"
                shift 2
                ;;
            -b|--bits)
                key_bits="$2"
                shift 2
                ;;
            *)
                error "Unknown option for generate-key: $1"
                exit 1
                ;;
        esac
    done
    
    # Set default key name if not specified
    if [[ -z "$key_name" ]]; then
        key_name="id_${key_type}"
    fi
    
    # Full path to key
    local key_path="${SSH_DIR}/${key_name}"
    
    # Check if key already exists
    if [[ -f "$key_path" ]] && [[ "$FORCE" != true ]]; then
        error "Key already exists: $key_path"
        error "Use --force to overwrite"
        exit 1
    fi
    
    # Set default comment if not specified
    if [[ -z "$key_comment" ]]; then
        key_comment="${USER}@$(hostname)"
    fi
    
    log "Generating ${key_type} key pair..."
    
    # Build ssh-keygen command
    local keygen_cmd="ssh-keygen -t '$key_type' -f '$key_path' -C '$key_comment'"
    
    # Add bits for RSA keys
    if [[ "$key_type" == "rsa" ]]; then
        key_bits="${key_bits:-4096}"
        keygen_cmd="$keygen_cmd -b $key_bits"
    fi
    
    # Add -N '' for non-interactive mode
    if [[ "$FORCE" == true ]] || [[ "$DRY_RUN" == true ]]; then
        keygen_cmd="$keygen_cmd -N ''"
    fi
    
    execute "$keygen_cmd"
    
    if [[ "$DRY_RUN" != true ]]; then
        # Set proper permissions
        execute "chmod 600 '$key_path'"
        execute "chmod 644 '${key_path}.pub'"
        
        log "Key pair generated successfully:"
        log "  Private key: $key_path"
        log "  Public key: ${key_path}.pub"
        
        # Display public key
        if [[ -f "${key_path}.pub" ]]; then
            echo
            log "Public key content:"
            cat "${key_path}.pub"
        fi
    fi
}

# Add host configuration
cmd_add_host() {
    local host_alias="$1"
    local hostname=""
    local username=""
    local port="22"
    local identity_file=""
    local proxy_jump=""
    
    if [[ -z "$host_alias" ]]; then
        error "Host alias is required"
        echo "Usage: $(basename "$0") add-host ALIAS [OPTIONS]"
        exit 1
    fi
    
    # Remove the host alias from arguments
    shift
    
    # Parse add-host specific arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -H|--hostname)
                hostname="$2"
                shift 2
                ;;
            -u|--user)
                username="$2"
                shift 2
                ;;
            -p|--port)
                port="$2"
                shift 2
                ;;
            -i|--identity)
                identity_file="$2"
                shift 2
                ;;
            -J|--jump)
                proxy_jump="$2"
                shift 2
                ;;
            *)
                error "Unknown option for add-host: $1"
                exit 1
                ;;
        esac
    done
    
    if [[ -z "$hostname" ]]; then
        error "Hostname is required"
        echo "Usage: $(basename "$0") add-host ALIAS -H HOSTNAME [OPTIONS]"
        exit 1
    fi
    
    # Check if host already exists
    if grep -q "^Host ${host_alias}$" "$CONFIG_FILE" 2>/dev/null && [[ "$FORCE" != true ]]; then
        error "Host '$host_alias' already exists in config"
        error "Use --force to overwrite"
        exit 1
    fi
    
    log "Adding host configuration for: $host_alias"
    
    # Build host configuration
    local host_config=$'\n'"Host ${host_alias}"$'\n'
    host_config+="    HostName ${hostname}"$'\n'
    
    if [[ -n "$username" ]]; then
        host_config+="    User ${username}"$'\n'
    fi
    
    if [[ "$port" != "22" ]]; then
        host_config+="    Port ${port}"$'\n'
    fi
    
    if [[ -n "$identity_file" ]]; then
        # Expand ~ to home directory
        identity_file="${identity_file/#\~/$HOME}"
        host_config+="    IdentityFile ${identity_file}"$'\n'
        host_config+="    IdentitiesOnly yes"$'\n'
    fi
    
    if [[ -n "$proxy_jump" ]]; then
        host_config+="    ProxyJump ${proxy_jump}"$'\n'
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would add to $CONFIG_FILE:"
        echo "$host_config"
    else
        # Remove existing host if force is enabled
        if [[ "$FORCE" == true ]] && grep -q "^Host ${host_alias}$" "$CONFIG_FILE"; then
            debug "Removing existing host configuration"
            # Create temporary file
            local temp_file=$(mktemp)
            awk -v host="$host_alias" '
                /^Host / { 
                    if ($2 == host) { skip=1 } 
                    else { skip=0 }
                }
                !skip { print }
            ' "$CONFIG_FILE" > "$temp_file"
            mv "$temp_file" "$CONFIG_FILE"
            chmod 600 "$CONFIG_FILE"
        fi
        
        # Add new host configuration
        echo "$host_config" >> "$CONFIG_FILE"
        log "Host '$host_alias' added successfully"
    fi
}

# Remove host configuration
cmd_remove_host() {
    local host_alias="${ARGS[0]:-}"
    
    if [[ -z "$host_alias" ]]; then
        error "Host alias is required"
        echo "Usage: $(basename "$0") remove-host ALIAS"
        exit 1
    fi
    
    if ! grep -q "^Host ${host_alias}$" "$CONFIG_FILE" 2>/dev/null; then
        error "Host '$host_alias' not found in config"
        exit 1
    fi
    
    if [[ "$FORCE" != true ]] && [[ "$DRY_RUN" != true ]]; then
        read -p "Remove host '$host_alias'? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Operation cancelled"
            exit 0
        fi
    fi
    
    log "Removing host: $host_alias"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would remove host '$host_alias' from $CONFIG_FILE"
    else
        # Create temporary file
        local temp_file=$(mktemp)
        awk -v host="$host_alias" '
            /^Host / { 
                if ($2 == host) { skip=1 } 
                else { skip=0 }
            }
            !skip { print }
        ' "$CONFIG_FILE" > "$temp_file"
        mv "$temp_file" "$CONFIG_FILE"
        chmod 600 "$CONFIG_FILE"
        log "Host '$host_alias' removed successfully"
    fi
}

# List all configured hosts
cmd_list_hosts() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        warning "No SSH config file found"
        exit 0
    fi
    
    log "Configured SSH hosts:"
    echo
    
    # Parse config file and display hosts with their settings
    awk '
        /^Host / && $2 != "*" {
            if (host) print_host()
            host = $2
            hostname = ""
            user = ""
            port = ""
            identity = ""
            jump = ""
        }
        /^[[:space:]]+HostName/ { hostname = $2 }
        /^[[:space:]]+User/ { user = $2 }
        /^[[:space:]]+Port/ { port = $2 }
        /^[[:space:]]+IdentityFile/ { identity = $2 }
        /^[[:space:]]+ProxyJump/ { jump = $2 }
        
        END { if (host) print_host() }
        
        function print_host() {
            printf "  %-20s", host
            if (hostname) printf " %s", hostname
            if (user) printf " (%s)", user
            if (port && port != "22") printf " :%s", port
            if (jump) printf " [via %s]", jump
            printf "\n"
            if (identity) printf "  %-20s   Key: %s\n", "", identity
        }
    ' "$CONFIG_FILE"
}

# Apply security hardening
cmd_harden() {
    log "Applying SSH security hardening..."
    
    # Create backup before making changes
    create_backup "pre-harden"
    
    # Check and fix file permissions
    cmd_check_permissions
    
    # Update global SSH config with hardened settings
    if [[ "$DRY_RUN" != true ]]; then
        # Check if we already have hardened settings
        if ! grep -q "# Security hardening applied" "$CONFIG_FILE" 2>/dev/null; then
            log "Updating SSH config with hardened settings..."
            
            # Create temporary file with hardened config
            local temp_file=$(mktemp)
            cat > "$temp_file" << 'EOF'
# SSH Client Configuration
# Security hardening applied by SSH Configuration Manager

# Global security settings
Host *
    # Use SSH protocol 2 only
    Protocol 2
    
    # Security settings
    PasswordAuthentication no
    ChallengeResponseAuthentication no
    PubkeyAuthentication yes
    HostbasedAuthentication no
    
    # Strict host key checking
    StrictHostKeyChecking ask
    HashKnownHosts yes
    
    # Use only secure algorithms
    KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256
    HostKeyAlgorithms ssh-ed25519-cert-v01@openssh.com,ssh-rsa-cert-v01@openssh.com,ssh-ed25519,rsa-sha2-512,rsa-sha2-256
    Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
    MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com
    
    # Connection settings
    ServerAliveInterval 60
    ServerAliveCountMax 3
    TCPKeepAlive yes
    
    # Compression
    Compression yes
    
    # Connection multiplexing
    ControlMaster auto
    ControlPath ~/.ssh/control-%h-%p-%r
    ControlPersist 10m
    
    # Disable potentially dangerous features
    ForwardAgent no
    ForwardX11 no
    PermitLocalCommand no
    
    # Use secure defaults
    UseRoaming no

EOF
            
            # Append existing host-specific configurations
            echo "" >> "$temp_file"
            echo "# Host-specific configurations" >> "$temp_file"
            awk '/^Host / && $2 != "*" { found=1 } found { print }' "$CONFIG_FILE" >> "$temp_file"
            
            # Replace original config
            mv "$temp_file" "$CONFIG_FILE"
            chmod 600 "$CONFIG_FILE"
        else
            log "Security hardening already applied"
        fi
    fi
    
    # Create sshd_config hardening recommendations
    local sshd_recommendations="${SSH_DIR}/sshd_config_recommendations.txt"
    
    if [[ "$DRY_RUN" != true ]]; then
        cat > "$sshd_recommendations" << 'EOF'
# SSH Server Hardening Recommendations
# Apply these settings to /etc/ssh/sshd_config on your servers

# Disable root login
PermitRootLogin no

# Use key-based authentication only
PasswordAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes

# Limit user access
AllowUsers your_username
# Or use AllowGroups ssh_users

# Use strong encryption
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com

# Security settings
Protocol 2
StrictModes yes
MaxAuthTries 3
MaxSessions 2
LoginGraceTime 30

# Disable unnecessary features
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
PermitTunnel no

# Logging
LogLevel VERBOSE

# Banner
Banner /etc/ssh/banner.txt

# After making changes, restart SSH:
# sudo systemctl restart sshd
EOF
        
        log "Server hardening recommendations saved to: $sshd_recommendations"
    fi
    
    log "Security hardening completed"
}

# Check and fix SSH file permissions
cmd_check_permissions() {
    log "Checking SSH file permissions..."
    
    local issues_found=false
    
    # Check SSH directory
    if [[ -d "$SSH_DIR" ]]; then
        local dir_perms=$(stat -f %Mp%Lp "$SSH_DIR" 2>/dev/null || stat -c %a "$SSH_DIR" 2>/dev/null)
        if [[ "$dir_perms" != "700" ]]; then
            warning "SSH directory has incorrect permissions: $dir_perms (should be 700)"
            execute "chmod 700 '$SSH_DIR'"
            issues_found=true
        fi
    fi
    
    # Check private keys
    while IFS= read -r -d '' key_file; do
        local key_perms=$(stat -f %Mp%Lp "$key_file" 2>/dev/null || stat -c %a "$key_file" 2>/dev/null)
        if [[ "$key_perms" != "600" ]]; then
            warning "Private key has incorrect permissions: $(basename "$key_file") - $key_perms (should be 600)"
            execute "chmod 600 '$key_file'"
            issues_found=true
        fi
    done < <(find "$SSH_DIR" -type f -name "id_*" ! -name "*.pub" -print0 2>/dev/null)
    
    # Check public keys
    while IFS= read -r -d '' pub_file; do
        local pub_perms=$(stat -f %Mp%Lp "$pub_file" 2>/dev/null || stat -c %a "$pub_file" 2>/dev/null)
        if [[ "$pub_perms" != "644" ]]; then
            warning "Public key has incorrect permissions: $(basename "$pub_file") - $pub_perms (should be 644)"
            execute "chmod 644 '$pub_file'"
            issues_found=true
        fi
    done < <(find "$SSH_DIR" -type f -name "*.pub" -print0 2>/dev/null)
    
    # Check config file
    if [[ -f "$CONFIG_FILE" ]]; then
        local config_perms=$(stat -f %Mp%Lp "$CONFIG_FILE" 2>/dev/null || stat -c %a "$CONFIG_FILE" 2>/dev/null)
        if [[ "$config_perms" != "600" ]]; then
            warning "Config file has incorrect permissions: $config_perms (should be 600)"
            execute "chmod 600 '$CONFIG_FILE'"
            issues_found=true
        fi
    fi
    
    # Check authorized_keys
    if [[ -f "$AUTHORIZED_KEYS" ]]; then
        local auth_perms=$(stat -f %Mp%Lp "$AUTHORIZED_KEYS" 2>/dev/null || stat -c %a "$AUTHORIZED_KEYS" 2>/dev/null)
        if [[ "$auth_perms" != "600" ]]; then
            warning "Authorized keys file has incorrect permissions: $auth_perms (should be 600)"
            execute "chmod 600 '$AUTHORIZED_KEYS'"
            issues_found=true
        fi
    fi
    
    # Check known_hosts
    if [[ -f "$KNOWN_HOSTS" ]]; then
        local known_perms=$(stat -f %Mp%Lp "$KNOWN_HOSTS" 2>/dev/null || stat -c %a "$KNOWN_HOSTS" 2>/dev/null)
        if [[ "$known_perms" != "644" ]]; then
            warning "Known hosts file has incorrect permissions: $known_perms (should be 644)"
            execute "chmod 644 '$KNOWN_HOSTS'"
            issues_found=true
        fi
    fi
    
    if [[ "$issues_found" == false ]]; then
        log "All SSH file permissions are correct"
    else
        log "File permissions have been fixed"
    fi
}

# Clean known_hosts file
cmd_clean_known_hosts() {
    log "Cleaning known_hosts file..."
    
    if [[ ! -f "$KNOWN_HOSTS" ]]; then
        warning "No known_hosts file found"
        return 0
    fi
    
    # Create backup
    create_backup "pre-clean"
    
    if [[ "$DRY_RUN" != true ]]; then
        # Remove duplicate entries
        local temp_file=$(mktemp)
        sort -u "$KNOWN_HOSTS" > "$temp_file"
        
        local original_lines=$(wc -l < "$KNOWN_HOSTS")
        local cleaned_lines=$(wc -l < "$temp_file")
        local removed_lines=$((original_lines - cleaned_lines))
        
        if [[ $removed_lines -gt 0 ]]; then
            mv "$temp_file" "$KNOWN_HOSTS"
            chmod 644 "$KNOWN_HOSTS"
            log "Removed $removed_lines duplicate entries"
        else
            rm "$temp_file"
            log "No duplicate entries found"
        fi
        
        # Report on hashed vs unhashed entries
        local hashed_count=$(grep -c "^|" "$KNOWN_HOSTS" || true)
        local unhashed_count=$(grep -v -c "^|" "$KNOWN_HOSTS" || true)
        
        log "Known hosts statistics:"
        log "  Hashed entries: $hashed_count"
        log "  Unhashed entries: $unhashed_count"
        
        if [[ $unhashed_count -gt 0 ]] && [[ "$VERBOSE" == true ]]; then
            debug "Consider hashing all entries for better security"
            debug "Run: ssh-keygen -H -f $KNOWN_HOSTS"
        fi
    fi
}

# Test SSH connection
cmd_test_connection() {
    local host="${ARGS[0]:-}"
    
    if [[ -z "$host" ]]; then
        error "Host is required"
        echo "Usage: $(basename "$0") test-connection HOST"
        exit 1
    fi
    
    log "Testing SSH connection to: $host"
    
    # Check if host exists in config
    if grep -q "^Host ${host}$" "$CONFIG_FILE" 2>/dev/null; then
        debug "Found host in SSH config"
    else
        debug "Host not found in SSH config, will use as hostname"
    fi
    
    # Test connection with various checks
    log "Running connection tests..."
    
    # Test 1: Basic connectivity
    echo -n "  Basic connectivity: "
    if execute "ssh -o ConnectTimeout=5 -o PasswordAuthentication=no -o BatchMode=yes '$host' exit 2>/dev/null"; then
        echo -e "${GREEN}PASS${NC}"
    else
        echo -e "${RED}FAIL${NC}"
        
        # Try to determine the issue
        echo -n "  Checking host resolution: "
        if execute "ssh -G '$host' 2>/dev/null | grep -q hostname"; then
            echo -e "${GREEN}PASS${NC}"
            
            # Get actual hostname and port
            local actual_host=$(ssh -G "$host" 2>/dev/null | grep "^hostname " | cut -d' ' -f2)
            local actual_port=$(ssh -G "$host" 2>/dev/null | grep "^port " | cut -d' ' -f2)
            
            echo -n "  Checking port connectivity ($actual_host:$actual_port): "
            if command -v nc >/dev/null 2>&1; then
                if nc -z -w5 "$actual_host" "$actual_port" 2>/dev/null; then
                    echo -e "${GREEN}PASS${NC}"
                    warning "Connection failed - likely authentication issue"
                else
                    echo -e "${RED}FAIL${NC}"
                    error "Cannot reach $actual_host on port $actual_port"
                fi
            else
                echo "SKIP (nc not available)"
            fi
        else
            echo -e "${RED}FAIL${NC}"
            error "Cannot resolve host: $host"
        fi
    fi
    
    # Test 2: Key authentication
    if [[ "$VERBOSE" == true ]]; then
        echo
        log "Verbose SSH connection attempt:"
        execute "ssh -vv -o ConnectTimeout=5 -o PasswordAuthentication=no -o BatchMode=yes '$host' exit 2>&1 | grep -E '(Offering|Accepted|denied|Failed)' || true"
    fi
    
    # Test 3: Configuration details
    if [[ "$VERBOSE" == true ]]; then
        echo
        log "Effective SSH configuration for $host:"
        execute "ssh -G '$host' | grep -E '^(hostname|user|port|identityfile|proxyjump|proxycommand)' | sort"
    fi
}

# Backup SSH configuration
cmd_backup() {
    local backup_name="${ARGS[0]:-manual}"
    
    if create_backup "$backup_name"; then
        log "Backup completed successfully"
        
        # List recent backups
        if [[ -d "$BACKUP_DIR" ]]; then
            log "Recent backups:"
            ls -lt "$BACKUP_DIR" | head -6 | tail -5 | awk '{print "  " $9 " (" $6 " " $7 " " $8 ")"}'
        fi
    fi
}

# Restore SSH configuration
cmd_restore() {
    local backup_name="${ARGS[0]:-}"
    
    if [[ -z "$backup_name" ]]; then
        # List available backups
        if [[ ! -d "$BACKUP_DIR" ]]; then
            error "No backup directory found"
            exit 1
        fi
        
        log "Available backups:"
        ls -lt "$BACKUP_DIR" | tail -n +2 | awk '{print "  " NR ". " $9 " (" $6 " " $7 " " $8 ")"}'
        
        echo
        read -p "Enter backup number or name to restore: " backup_choice
        
        if [[ "$backup_choice" =~ ^[0-9]+$ ]]; then
            backup_name=$(ls -t "$BACKUP_DIR" | sed -n "${backup_choice}p")
        else
            backup_name="$backup_choice"
        fi
    fi
    
    local backup_path="${BACKUP_DIR}/${backup_name}"
    
    if [[ ! -d "$backup_path" ]]; then
        error "Backup not found: $backup_path"
        exit 1
    fi
    
    if [[ "$FORCE" != true ]] && [[ "$DRY_RUN" != true ]]; then
        read -p "Restore from backup '$backup_name'? Current configuration will be overwritten. [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Operation cancelled"
            exit 0
        fi
    fi
    
    # Create backup of current state
    create_backup "pre-restore"
    
    log "Restoring from backup: $backup_name"
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY-RUN] Would restore SSH configuration from: $backup_path"
    else
        # Remove current SSH directory contents (except backups)
        find "$SSH_DIR" -mindepth 1 -maxdepth 1 ! -name "backups" -exec rm -rf {} \;
        
        # Restore from backup
        cp -r "$backup_path"/* "$SSH_DIR"/
        
        # Fix permissions
        cmd_check_permissions
        
        log "Configuration restored successfully"
    fi
}

# Main execution
main() {
    parse_args "$@"
    
    # Validate command
    case "$COMMAND" in
        init)
            cmd_init
            ;;
        generate-key)
            cmd_generate_key "${ARGS[@]}"
            ;;
        add-host)
            cmd_add_host "${ARGS[@]}"
            ;;
        remove-host)
            cmd_remove_host
            ;;
        list-hosts)
            cmd_list_hosts
            ;;
        backup)
            cmd_backup
            ;;
        restore)
            cmd_restore
            ;;
        harden)
            cmd_harden
            ;;
        check-permissions)
            cmd_check_permissions
            ;;
        clean-known-hosts)
            cmd_clean_known_hosts
            ;;
        test-connection)
            cmd_test_connection
            ;;
        "")
            error "No command specified"
            usage
            exit 1
            ;;
        *)
            error "Unknown command: $COMMAND"
            usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
