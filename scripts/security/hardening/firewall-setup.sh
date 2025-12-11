#!/bin/bash
# =============================================================================
# @id           firewall
# @name         firewall-setup
# @displayName  Firewall Setup
# @description  Configure firewall with ufw/iptables/firewalld presets
# @category     security
# @version      1.0.0
# @author       codefuturist
# @tags         firewall,ufw,iptables,firewalld,security,network,ports
# @shells       bash
# =============================================================================

set -euo pipefail

# =============================================================================
# Load RSR Library
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RSR_LIB_DIR="${SCRIPT_DIR}/../../../lib"

if [[ -f "$RSR_LIB_DIR/rsr-lib.sh" ]]; then
    source "$RSR_LIB_DIR/rsr-lib.sh" validate
fi

# Script metadata
SCRIPT_NAME="Firewall Setup"
SCRIPT_VERSION="1.0.0"

# Default values
VERBOSE=false
DRY_RUN=false
INTERACTIVE=auto
PRESET=""
ALLOW_PORTS=()
DENY_PORTS=()
ALLOW_FROM=()
DENY_FROM=()
RATE_LIMIT_PORTS=()
DO_ENABLE=false
DO_DISABLE=false
SHOW_STATUS=false
DO_RESET=false
BACKUP_FILE=""
RESTORE_FILE=""
IPV6=true

# Detected firewall
FIREWALL=""

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
EXIT_NO_FIREWALL=4
EXIT_SYNTAX_ERROR=5
EXIT_SSH_LOCKOUT=6

usage() {
    cat << EOF
${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}

Configure firewall with preset profiles or custom rules.

${YELLOW}Usage:${NC}
    $0 [OPTIONS]

${BOLD}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -d, --dry-run           Show what would be configured
    -i, --interactive       Run in interactive mode (default when no args)
    --no-interactive        Disable interactive mode
    -y, --yes               Auto-confirm all prompts
    -p, --preset PRESET     Apply preset profile
    -a, --allow PORT[/PROTO] Allow port (e.g., 3000/tcp)
    -D, --deny PORT[/PROTO]  Deny port
    --allow-from IP         Allow from IP/CIDR
    --deny-from IP          Deny from IP/CIDR
    --rate-limit PORT       Enable rate limiting on port
    --enable                Enable firewall
    --disable               Disable firewall
    --status                Show current status and rules
    --reset                 Reset to defaults
    --backup FILE           Backup current rules
    --restore FILE          Restore rules from backup
    --ipv6                  Include IPv6 rules (default)
    --no-ipv6               Disable IPv6

${BOLD}Presets:${NC}
    minimal     SSH only (port 22)
    web         SSH, HTTP, HTTPS (22, 80, 443)
    database    SSH + MySQL/PostgreSQL (localhost only)
    docker      SSH, HTTP, HTTPS + Docker ports
    mail        SSH + SMTP, IMAP, POP3 with SSL

${BOLD}Examples:${NC}
    ${DIM}# Show current status${NC}
    $0 --status

    ${DIM}# Dry run web preset${NC}
    $0 -p web -d

    ${DIM}# Apply minimal preset${NC}
    sudo $0 -p minimal

    ${DIM}# Allow port 8080${NC}
    sudo $0 -a 8080/tcp

    ${DIM}# Allow MySQL from internal network${NC}
    sudo $0 -a 3306/tcp --allow-from 10.0.0.0/8

    ${DIM}# Rate limit SSH${NC}
    sudo $0 --rate-limit 22

    ${DIM}# Backup rules${NC}
    sudo $0 --backup /tmp/fw.bak

${BOLD}Exit Codes:${NC}
    0 - Firewall configured successfully
    1 - General error
    2 - Invalid arguments
    3 - Permission denied (need root)
    4 - No supported firewall found
    5 - Rule syntax error
    6 - Would lock out SSH (aborted)

EOF
    exit 0
}

# Logging functions (use RSR if available)
if type rsr_log_info &>/dev/null; then
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
            -p | --preset)
                PRESET="$2"
                shift 2
                ;;
            -a | --allow)
                ALLOW_PORTS+=("$2")
                shift 2
                ;;
            -D | --deny)
                DENY_PORTS+=("$2")
                shift 2
                ;;
            --allow-from)
                ALLOW_FROM+=("$2")
                shift 2
                ;;
            --deny-from)
                DENY_FROM+=("$2")
                shift 2
                ;;
            --rate-limit)
                RATE_LIMIT_PORTS+=("$2")
                shift 2
                ;;
            --enable)
                DO_ENABLE=true
                shift
                ;;
            --disable)
                DO_DISABLE=true
                shift
                ;;
            --status)
                SHOW_STATUS=true
                shift
                ;;
            --reset)
                DO_RESET=true
                shift
                ;;
            --backup)
                BACKUP_FILE="$2"
                shift 2
                ;;
            --restore)
                RESTORE_FILE="$2"
                shift 2
                ;;
            --ipv6)
                IPV6=true
                shift
                ;;
            --no-ipv6)
                IPV6=false
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                exit $EXIT_INVALID_ARGS
                ;;
            *) shift ;;
        esac
    done
}

# Detect firewall system
detect_firewall() {
    if command -v ufw &> /dev/null; then
        FIREWALL="ufw"
    elif command -v firewall-cmd &> /dev/null; then
        FIREWALL="firewalld"
    elif command -v nft &> /dev/null; then
        FIREWALL="nftables"
    elif command -v iptables &> /dev/null; then
        FIREWALL="iptables"
    else
        log_error "No supported firewall found"
        log_info "Install ufw, firewalld, or iptables"
        exit $EXIT_NO_FIREWALL
    fi

    log_debug "Detected firewall: $FIREWALL"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 && "$SHOW_STATUS" != "true" && "$DRY_RUN" != "true" ]]; then
        log_error "Root access required for firewall configuration"
        exit $EXIT_PERMISSION
    fi
}

# Show firewall status
show_status() {
    print_header "Firewall Status"

    case "$FIREWALL" in
        ufw)
            ufw status verbose 2> /dev/null || ufw status
            ;;
        firewalld)
            echo "State: $(firewall-cmd --state 2> /dev/null || echo 'unknown')"
            echo ""
            echo "Active zones:"
            firewall-cmd --get-active-zones 2> /dev/null || true
            echo ""
            echo "Public zone services:"
            firewall-cmd --zone=public --list-all 2> /dev/null || true
            ;;
        nftables)
            nft list ruleset 2> /dev/null | head -50
            ;;
        iptables)
            echo "IPv4 Rules:"
            iptables -L -n --line-numbers 2> /dev/null || true
            if [[ "$IPV6" == "true" ]]; then
                echo ""
                echo "IPv6 Rules:"
                ip6tables -L -n --line-numbers 2> /dev/null || true
            fi
            ;;
    esac
}

# Backup firewall rules
backup_rules() {
    local file="$1"

    log_info "Backing up firewall rules to $file..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would backup to $file"
        return 0
    fi

    case "$FIREWALL" in
        ufw)
            # UFW stores rules in /etc/ufw
            tar -czf "$file" /etc/ufw 2> /dev/null
            ;;
        firewalld)
            firewall-cmd --runtime-to-permanent 2> /dev/null || true
            tar -czf "$file" /etc/firewalld 2> /dev/null
            ;;
        iptables)
            {
                echo "# IPv4 rules"
                iptables-save
                if [[ "$IPV6" == "true" ]]; then
                    echo "# IPv6 rules"
                    ip6tables-save
                fi
            } > "$file"
            ;;
        nftables)
            nft list ruleset > "$file"
            ;;
    esac

    log_ok "Backup saved to $file"
}

# Restore firewall rules
restore_rules() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        log_error "Backup file not found: $file"
        exit $EXIT_ERROR
    fi

    log_info "Restoring firewall rules from $file..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would restore from $file"
        return 0
    fi

    case "$FIREWALL" in
        ufw)
            tar -xzf "$file" -C / 2> /dev/null
            ufw reload
            ;;
        firewalld)
            tar -xzf "$file" -C / 2> /dev/null
            firewall-cmd --reload
            ;;
        iptables)
            iptables-restore < "$file"
            ;;
        nftables)
            nft -f "$file"
            ;;
    esac

    log_ok "Rules restored from $file"
}

# Reset firewall to defaults
reset_firewall() {
    log_info "Resetting firewall to defaults..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would reset firewall"
        return 0
    fi

    case "$FIREWALL" in
        ufw)
            ufw --force reset
            ;;
        firewalld)
            # Reset to defaults
            rm -f /etc/firewalld/zones/*.xml 2> /dev/null || true
            firewall-cmd --reload
            ;;
        iptables)
            iptables -F
            iptables -X
            iptables -P INPUT ACCEPT
            iptables -P FORWARD ACCEPT
            iptables -P OUTPUT ACCEPT
            if [[ "$IPV6" == "true" ]]; then
                ip6tables -F
                ip6tables -X
                ip6tables -P INPUT ACCEPT
                ip6tables -P FORWARD ACCEPT
                ip6tables -P OUTPUT ACCEPT
            fi
            ;;
        nftables)
            nft flush ruleset
            ;;
    esac

    log_ok "Firewall reset to defaults"
}

# Enable firewall
enable_firewall() {
    log_info "Enabling firewall..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would enable firewall"
        return 0
    fi

    case "$FIREWALL" in
        ufw)
            ufw --force enable
            ;;
        firewalld)
            systemctl enable firewalld
            systemctl start firewalld
            ;;
        iptables)
            # Save rules for persistence
            if command -v iptables-save &> /dev/null; then
                iptables-save > /etc/iptables.rules 2> /dev/null || true
            fi
            ;;
        nftables)
            systemctl enable nftables
            systemctl start nftables
            ;;
    esac

    log_ok "Firewall enabled"
}

# Disable firewall
disable_firewall() {
    log_warn "Disabling firewall..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would disable firewall"
        return 0
    fi

    case "$FIREWALL" in
        ufw)
            ufw disable
            ;;
        firewalld)
            systemctl stop firewalld
            systemctl disable firewalld
            ;;
        iptables)
            iptables -F
            iptables -P INPUT ACCEPT
            iptables -P FORWARD ACCEPT
            iptables -P OUTPUT ACCEPT
            ;;
        nftables)
            systemctl stop nftables
            systemctl disable nftables
            ;;
    esac

    log_ok "Firewall disabled"
}

# Allow a port
allow_port() {
    local port_spec="$1"
    local port proto

    # Parse port/proto
    if [[ "$port_spec" =~ / ]]; then
        port=$(echo "$port_spec" | cut -d/ -f1)
        proto=$(echo "$port_spec" | cut -d/ -f2)
    else
        port="$port_spec"
        proto="tcp"
    fi

    log_info "Allowing port $port/$proto..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would allow $port/$proto"
        return 0
    fi

    case "$FIREWALL" in
        ufw)
            ufw allow "$port/$proto"
            ;;
        firewalld)
            firewall-cmd --permanent --add-port="$port/$proto"
            ;;
        iptables)
            iptables -A INPUT -p "$proto" --dport "$port" -j ACCEPT
            if [[ "$IPV6" == "true" ]]; then
                ip6tables -A INPUT -p "$proto" --dport "$port" -j ACCEPT
            fi
            ;;
        nftables)
            nft add rule inet filter input "$proto" dport "$port" accept 2> /dev/null \
                || nft add rule ip filter INPUT "$proto" dport "$port" accept
            ;;
    esac

    log_ok "Port $port/$proto allowed"
}

# Deny a port
deny_port() {
    local port_spec="$1"
    local port proto

    if [[ "$port_spec" =~ / ]]; then
        port=$(echo "$port_spec" | cut -d/ -f1)
        proto=$(echo "$port_spec" | cut -d/ -f2)
    else
        port="$port_spec"
        proto="tcp"
    fi

    log_info "Denying port $port/$proto..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deny $port/$proto"
        return 0
    fi

    case "$FIREWALL" in
        ufw)
            ufw deny "$port/$proto"
            ;;
        firewalld)
            firewall-cmd --permanent --remove-port="$port/$proto" 2> /dev/null || true
            ;;
        iptables)
            iptables -A INPUT -p "$proto" --dport "$port" -j DROP
            ;;
        nftables)
            nft add rule inet filter input "$proto" dport "$port" drop 2> /dev/null \
                || nft add rule ip filter INPUT "$proto" dport "$port" drop
            ;;
    esac

    log_ok "Port $port/$proto denied"
}

# Allow from IP/CIDR
allow_from_ip() {
    local ip="$1"

    log_info "Allowing traffic from $ip..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would allow from $ip"
        return 0
    fi

    case "$FIREWALL" in
        ufw)
            ufw allow from "$ip"
            ;;
        firewalld)
            firewall-cmd --permanent --add-source="$ip"
            ;;
        iptables)
            iptables -A INPUT -s "$ip" -j ACCEPT
            ;;
        nftables)
            nft add rule inet filter input ip saddr "$ip" accept 2> /dev/null \
                || nft add rule ip filter INPUT ip saddr "$ip" accept
            ;;
    esac

    log_ok "Traffic from $ip allowed"
}

# Deny from IP/CIDR
deny_from_ip() {
    local ip="$1"

    log_info "Denying traffic from $ip..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deny from $ip"
        return 0
    fi

    case "$FIREWALL" in
        ufw)
            ufw deny from "$ip"
            ;;
        firewalld)
            firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=$ip reject"
            ;;
        iptables)
            iptables -A INPUT -s "$ip" -j DROP
            ;;
        nftables)
            nft add rule inet filter input ip saddr "$ip" drop 2> /dev/null \
                || nft add rule ip filter INPUT ip saddr "$ip" drop
            ;;
    esac

    log_ok "Traffic from $ip denied"
}

# Rate limit a port
rate_limit_port() {
    local port="$1"

    log_info "Adding rate limiting on port $port..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would rate limit port $port"
        return 0
    fi

    case "$FIREWALL" in
        ufw)
            ufw limit "$port/tcp"
            ;;
        firewalld)
            firewall-cmd --permanent --add-rich-rule="rule service name=ssh limit value='10/m' accept" 2> /dev/null \
                || firewall-cmd --permanent --add-rich-rule="rule port port=$port protocol=tcp limit value='10/m' accept"
            ;;
        iptables)
            # Rate limit: 10 connections per minute per IP
            iptables -A INPUT -p tcp --dport "$port" -m state --state NEW -m recent --set
            iptables -A INPUT -p tcp --dport "$port" -m state --state NEW -m recent --update --seconds 60 --hitcount 10 -j DROP
            iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
            ;;
        nftables)
            nft add rule inet filter input tcp dport "$port" limit rate 10/minute accept 2> /dev/null \
                || log_warn "Rate limiting not configured for nftables"
            ;;
    esac

    log_ok "Rate limiting enabled on port $port"
}

# Apply preset configuration
apply_preset() {
    local preset="$1"

    print_header "Applying Preset: $preset"

    # Always ensure SSH is allowed first
    local ssh_port
    ssh_port=$(grep -E "^Port" /etc/ssh/sshd_config 2> /dev/null | awk '{print $2}' || echo "22")

    log_info "Ensuring SSH (port $ssh_port) is allowed..."
    allow_port "$ssh_port/tcp"

    case "$preset" in
        minimal)
            log_info "Preset: Minimal (SSH only)"
            # SSH already allowed
            ;;
        web)
            log_info "Preset: Web Server"
            allow_port "80/tcp"
            allow_port "443/tcp"
            ;;
        database)
            log_info "Preset: Database Server"
            # MySQL and PostgreSQL on localhost only
            if [[ "$FIREWALL" == "ufw" ]]; then
                ufw allow from 127.0.0.1 to any port 3306
                ufw allow from 127.0.0.1 to any port 5432
            elif [[ "$FIREWALL" == "firewalld" ]]; then
                firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=127.0.0.1 port port=3306 protocol=tcp accept'
                firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=127.0.0.1 port port=5432 protocol=tcp accept'
            elif [[ "$FIREWALL" == "iptables" ]]; then
                iptables -A INPUT -p tcp -s 127.0.0.1 --dport 3306 -j ACCEPT
                iptables -A INPUT -p tcp -s 127.0.0.1 --dport 5432 -j ACCEPT
            fi
            log_ok "MySQL (3306) and PostgreSQL (5432) allowed from localhost only"
            ;;
        docker)
            log_info "Preset: Docker Host"
            allow_port "80/tcp"
            allow_port "443/tcp"
            allow_port "2375/tcp" # Docker API (insecure - localhost only recommended)
            allow_port "2376/tcp" # Docker API TLS
            ;;
        mail)
            log_info "Preset: Mail Server"
            allow_port "25/tcp"  # SMTP
            allow_port "465/tcp" # SMTPS
            allow_port "587/tcp" # Submission
            allow_port "110/tcp" # POP3
            allow_port "995/tcp" # POP3S
            allow_port "143/tcp" # IMAP
            allow_port "993/tcp" # IMAPS
            ;;
        *)
            log_error "Unknown preset: $preset"
            log_info "Available presets: minimal, web, database, docker, mail"
            exit $EXIT_INVALID_ARGS
            ;;
    esac

    # Set default policies
    if [[ "$DRY_RUN" != "true" ]]; then
        case "$FIREWALL" in
            ufw)
                ufw default deny incoming
                ufw default allow outgoing
                ;;
            firewalld)
                firewall-cmd --set-default-zone=public
                firewall-cmd --reload
                ;;
            iptables)
                # Allow established connections
                iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
                # Allow loopback
                iptables -A INPUT -i lo -j ACCEPT
                # Set default policy to drop
                iptables -P INPUT DROP
                iptables -P FORWARD DROP
                iptables -P OUTPUT ACCEPT
                ;;
        esac
    fi

    log_ok "Preset '$preset' applied"
}

# Reload firewall rules
reload_firewall() {
    log_info "Reloading firewall rules..."

    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    case "$FIREWALL" in
        ufw)
            ufw reload 2> /dev/null || true
            ;;
        firewalld)
            firewall-cmd --reload
            ;;
        iptables)
            # Rules are applied immediately
            ;;
        nftables)
            systemctl reload nftables 2> /dev/null || true
            ;;
    esac
}

# =============================================================================
# Interactive Mode
# =============================================================================

run_interactive() {
    print_interactive_header "$SCRIPT_NAME" "$SCRIPT_VERSION"

    log_info "Detected firewall: ${BOLD}$FIREWALL${NC}"
    echo ""

    # Main action selection
    local action
    action=$(prompt_select "What would you like to do?" \
        "Apply a preset profile" \
        "Allow/deny specific ports" \
        "Allow/deny IP addresses" \
        "Show current status" \
        "Backup rules" \
        "Restore rules" \
        "Reset to defaults" \
        "Enable/disable firewall")

    case "$action" in
        "Apply a preset profile")
            interactive_preset
            ;;
        "Allow/deny specific ports")
            interactive_ports
            ;;
        "Allow/deny IP addresses")
            interactive_ips
            ;;
        "Show current status")
            show_status
            return 0
            ;;
        "Backup rules")
            interactive_backup
            ;;
        "Restore rules")
            interactive_restore
            ;;
        "Reset to defaults")
            interactive_reset
            ;;
        "Enable/disable firewall")
            interactive_enable_disable
            ;;
    esac
}

interactive_preset() {
    echo ""
    local preset_choice
    preset_choice=$(prompt_select "Select a firewall preset:" \
        "minimal - SSH only (port 22)" \
        "web - SSH, HTTP, HTTPS (22, 80, 443)" \
        "database - SSH + MySQL/PostgreSQL (localhost only)" \
        "docker - SSH, HTTP, HTTPS + Docker ports" \
        "mail - SSH + SMTP, IMAP, POP3 with SSL")

    PRESET=$(echo "$preset_choice" | cut -d' ' -f1)

    echo ""
    log_info "Selected preset: ${BOLD}$PRESET${NC}"
    echo ""

    # Show what will be configured
    case "$PRESET" in
        minimal)
            echo -e "  ${CYAN}•${NC} Allow SSH (port 22)"
            echo -e "  ${CYAN}•${NC} Block all other incoming traffic"
            ;;
        web)
            echo -e "  ${CYAN}•${NC} Allow SSH (port 22)"
            echo -e "  ${CYAN}•${NC} Allow HTTP (port 80)"
            echo -e "  ${CYAN}•${NC} Allow HTTPS (port 443)"
            echo -e "  ${CYAN}•${NC} Block all other incoming traffic"
            ;;
        database)
            echo -e "  ${CYAN}•${NC} Allow SSH (port 22)"
            echo -e "  ${CYAN}•${NC} Allow MySQL (port 3306) from localhost only"
            echo -e "  ${CYAN}•${NC} Allow PostgreSQL (port 5432) from localhost only"
            ;;
        docker)
            echo -e "  ${CYAN}•${NC} Allow SSH (port 22)"
            echo -e "  ${CYAN}•${NC} Allow HTTP (port 80)"
            echo -e "  ${CYAN}•${NC} Allow HTTPS (port 443)"
            echo -e "  ${CYAN}•${NC} Allow Docker API (ports 2375, 2376)"
            ;;
        mail)
            echo -e "  ${CYAN}•${NC} Allow SSH (port 22)"
            echo -e "  ${CYAN}•${NC} Allow SMTP (25), SMTPS (465), Submission (587)"
            echo -e "  ${CYAN}•${NC} Allow POP3 (110), POP3S (995)"
            echo -e "  ${CYAN}•${NC} Allow IMAP (143), IMAPS (993)"
            ;;
    esac

    echo ""

    # Ask about additional options
    if prompt_yes_no "Enable rate limiting on SSH?" "y"; then
        RATE_LIMIT_PORTS+=("22")
    fi

    if prompt_yes_no "Enable IPv6 rules?" "y"; then
        IPV6=true
    else
        IPV6=false
    fi

    echo ""

    # Confirmation
    if confirm_destructive "This will modify your firewall rules. Make sure you have console access in case of SSH lockout."; then
        check_root
        apply_preset "$PRESET"

        for port in "${RATE_LIMIT_PORTS[@]}"; do
            rate_limit_port "$port"
        done

        if prompt_yes_no "Enable firewall now?" "y"; then
            enable_firewall
        fi

        reload_firewall

        echo ""
        log_ok "Firewall configured successfully!"
        echo ""
        show_status
    else
        log_info "Operation cancelled"
    fi
}

interactive_ports() {
    echo ""
    local port_action
    port_action=$(prompt_select "What would you like to do?" \
        "Allow a port" \
        "Deny a port" \
        "Rate limit a port")

    echo ""
    local port_input
    port_input=$(prompt_input "Enter port number (e.g., 8080 or 8080/tcp)" "")

    if [[ -z "$port_input" ]]; then
        log_error "No port specified"
        return 1
    fi

    echo ""
    if prompt_yes_no "Apply this change?" "y"; then
        check_root
        case "$port_action" in
            "Allow a port")
                allow_port "$port_input"
                ;;
            "Deny a port")
                deny_port "$port_input"
                ;;
            "Rate limit a port")
                rate_limit_port "${port_input%%/*}"
                ;;
        esac
        reload_firewall
        log_ok "Port rule applied"
    fi
}

interactive_ips() {
    echo ""
    local ip_action
    ip_action=$(prompt_select "What would you like to do?" \
        "Allow traffic from IP/CIDR" \
        "Deny traffic from IP/CIDR")

    echo ""
    local ip_input
    ip_input=$(prompt_input "Enter IP address or CIDR (e.g., 192.168.1.0/24)" "")

    if [[ -z "$ip_input" ]]; then
        log_error "No IP specified"
        return 1
    fi

    echo ""
    if prompt_yes_no "Apply this change?" "y"; then
        check_root
        case "$ip_action" in
            "Allow traffic from IP/CIDR")
                allow_from_ip "$ip_input"
                ;;
            "Deny traffic from IP/CIDR")
                deny_from_ip "$ip_input"
                ;;
        esac
        reload_firewall
        log_ok "IP rule applied"
    fi
}

interactive_backup() {
    echo ""
    local backup_path
    backup_path=$(prompt_input "Enter backup file path" "/tmp/firewall-backup-$(date +%Y%m%d-%H%M%S).bak")

    if [[ -n "$backup_path" ]]; then
        check_root
        backup_rules "$backup_path"
    fi
}

interactive_restore() {
    echo ""
    local restore_path
    restore_path=$(prompt_input "Enter backup file path to restore from" "")

    if [[ -z "$restore_path" ]]; then
        log_error "No file specified"
        return 1
    fi

    if [[ ! -f "$restore_path" ]]; then
        log_error "File not found: $restore_path"
        return 1
    fi

    echo ""
    if confirm_destructive "This will replace your current firewall rules with the backup"; then
        check_root
        restore_rules "$restore_path"
    fi
}

interactive_reset() {
    echo ""
    if confirm_destructive "This will reset all firewall rules to system defaults. You may lose SSH access!"; then
        check_root
        reset_firewall
        log_ok "Firewall reset to defaults"
    fi
}

interactive_enable_disable() {
    echo ""
    local fw_action
    fw_action=$(prompt_select "Select action:" \
        "Enable firewall" \
        "Disable firewall")

    echo ""
    case "$fw_action" in
        "Enable firewall")
            if prompt_yes_no "Enable the firewall?" "y"; then
                check_root
                enable_firewall
            fi
            ;;
        "Disable firewall")
            if confirm_destructive "Disabling the firewall will expose all ports to the network"; then
                check_root
                disable_firewall
            fi
            ;;
    esac
}

# =============================================================================
# Main Function
# =============================================================================

# Main function
main() {
    local original_args=("$@")
    parse_args "$@"

    # Determine if interactive mode should be enabled
    # Auto-enable if: terminal + no arguments provided
    if [[ "$INTERACTIVE" == "auto" ]]; then
        if [[ ${#original_args[@]} -eq 0 ]] && [[ -t 0 ]] && [[ -t 1 ]]; then
            INTERACTIVE=true
        else
            INTERACTIVE=false
        fi
    fi

    detect_firewall

    # Run interactive mode if enabled
    if [[ "$INTERACTIVE" == "true" ]] && type -t rsr_is_interactive &>/dev/null && rsr_is_interactive; then
        run_interactive
        exit $EXIT_OK
    fi

    echo -e "${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}"
    echo ""

    # Handle status
    if [[ "$SHOW_STATUS" == "true" ]]; then
        show_status
        exit $EXIT_OK
    fi

    check_root

    # Handle backup
    if [[ -n "$BACKUP_FILE" ]]; then
        backup_rules "$BACKUP_FILE"
        exit $EXIT_OK
    fi

    # Handle restore
    if [[ -n "$RESTORE_FILE" ]]; then
        restore_rules "$RESTORE_FILE"
        exit $EXIT_OK
    fi

    # Handle reset
    if [[ "$DO_RESET" == "true" ]]; then
        reset_firewall
        exit $EXIT_OK
    fi

    # Handle disable
    if [[ "$DO_DISABLE" == "true" ]]; then
        disable_firewall
        exit $EXIT_OK
    fi

    # Apply preset
    if [[ -n "$PRESET" ]]; then
        apply_preset "$PRESET"
    fi

    # Allow ports
    for port in "${ALLOW_PORTS[@]}"; do
        allow_port "$port"
    done

    # Deny ports
    for port in "${DENY_PORTS[@]}"; do
        deny_port "$port"
    done

    # Allow from IPs
    for ip in "${ALLOW_FROM[@]}"; do
        allow_from_ip "$ip"
    done

    # Deny from IPs
    for ip in "${DENY_FROM[@]}"; do
        deny_from_ip "$ip"
    done

    # Rate limit ports
    for port in "${RATE_LIMIT_PORTS[@]}"; do
        rate_limit_port "$port"
    done

    # Enable firewall if requested
    if [[ "$DO_ENABLE" == "true" ]]; then
        enable_firewall
    fi

    # Reload to apply changes
    reload_firewall

    # Show final status
    if [[ "$VERBOSE" == "true" || ${#ALLOW_PORTS[@]} -gt 0 || -n "$PRESET" ]]; then
        echo ""
        log_info "Current firewall status:"
        show_status
    fi

    exit $EXIT_OK
}

main "$@"
