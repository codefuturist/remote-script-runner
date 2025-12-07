#!/bin/bash
# =============================================================================
# @id           audit
# @name         security-audit
# @displayName  Security Audit
# @description  Audit system security: open ports, logins, SUID files, permissions
# @category     security
# @version      1.0.0
# @author       codefuturist
# @tags         security,audit,ports,suid,permissions,logins,hardening
# @shells       bash
# =============================================================================

set -euo pipefail

# Script metadata
SCRIPT_NAME="Security Audit"
SCRIPT_VERSION="1.0.0"

# Default values
VERBOSE=false
SECTIONS=()
SEVERITY_FILTER=""
QUICK_MODE=false
DEEP_MODE=false
REPORT_FILE=""
REPORT_FORMAT="text"
CIS_REFS=false

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# Counters by severity
CRITICAL_COUNT=0
HIGH_COUNT=0
MEDIUM_COUNT=0
LOW_COUNT=0
INFO_COUNT=0

# Exit codes
EXIT_OK=0
EXIT_ERROR=1
EXIT_INVALID_ARGS=2
EXIT_PERMISSION=3
EXIT_CRITICAL=4
EXIT_HIGH=5
EXIT_MEDIUM=6
EXIT_LOW=7

usage() {
    cat << EOF
${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}

Audit system security: open ports, authentication, file permissions, and more.

${YELLOW}Usage:${NC}
    $0 [OPTIONS]

${BOLD}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -a, --all               Run all security checks
    -s, --section SECTION   Run specific section (can repeat)
    --severity LEVEL        Show only issues at level (critical, high, medium, low)
    --quick                 Quick scan (skip slow checks)
    --deep                  Deep scan (more thorough)
    -r, --report FILE       Generate report to file
    --format FMT            Report format: text, json, html (default: text)
    --cis                   Include CIS benchmark references

${BOLD}Sections:${NC}
    ports       Open ports and listening services
    auth        Authentication failures and brute force
    files       File permissions, world-writable, SUID/SGID
    users       User account security
    network     Firewall, IP forwarding, connections
    ssh         SSH configuration security
    updates     Pending security updates
    processes   Running processes analysis
    kernel      Kernel security settings

${BOLD}Examples:${NC}
    ${DIM}# Full security audit${NC}
    $0 -a

    ${DIM}# Check ports and authentication${NC}
    $0 -s ports -s auth

    ${DIM}# Quick scan${NC}
    $0 --quick

    ${DIM}# Deep thorough scan${NC}
    sudo $0 -a --deep

    ${DIM}# JSON output${NC}
    $0 -a --format json

    ${DIM}# HTML report${NC}
    $0 -a -r /tmp/audit.html --format html

${BOLD}Exit Codes:${NC}
    0 - No security issues found
    1 - General error
    2 - Invalid arguments
    3 - Permission denied
    4 - Critical issues found
    5 - High severity issues found
    6 - Medium severity issues found
    7 - Low severity issues found

EOF
    exit 0
}

log_info() { echo -e "${BLUE}▸${NC} $1"; }
log_ok() { echo -e "${GREEN}✓${NC} $1"; }
log_debug() { [[ "$VERBOSE" == "true" ]] && echo -e "${DIM}  $1${NC}"; }

# Finding functions with severity
finding_critical() {
    ((CRITICAL_COUNT++)) || true
    [[ -n "$SEVERITY_FILTER" && "$SEVERITY_FILTER" != "critical" ]] && return
    echo -e "${RED}${BOLD}[CRITICAL]${NC} $1"
}

finding_high() {
    ((HIGH_COUNT++)) || true
    [[ -n "$SEVERITY_FILTER" && "$SEVERITY_FILTER" != "high" ]] && return
    echo -e "${RED}[HIGH]${NC} $1"
}

finding_medium() {
    ((MEDIUM_COUNT++)) || true
    [[ -n "$SEVERITY_FILTER" && "$SEVERITY_FILTER" != "medium" ]] && return
    echo -e "${YELLOW}[MEDIUM]${NC} $1"
}

finding_low() {
    ((LOW_COUNT++)) || true
    [[ -n "$SEVERITY_FILTER" && "$SEVERITY_FILTER" != "low" ]] && return
    echo -e "${CYAN}[LOW]${NC} $1"
}

finding_info() {
    ((INFO_COUNT++)) || true
    echo -e "${DIM}[INFO]${NC} $1"
}

print_header() {
    echo ""
    echo -e "${BOLD}${MAGENTA}═══ $1 ═══${NC}"
    echo ""
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage ;;
            -v|--verbose) VERBOSE=true; shift ;;
            -a|--all) SECTIONS=("ports" "auth" "files" "users" "network" "ssh" "updates" "processes" "kernel"); shift ;;
            -s|--section) SECTIONS+=("$2"); shift 2 ;;
            --severity) SEVERITY_FILTER="$2"; shift 2 ;;
            --quick) QUICK_MODE=true; shift ;;
            --deep) DEEP_MODE=true; shift ;;
            -r|--report) REPORT_FILE="$2"; shift 2 ;;
            --format) REPORT_FORMAT="$2"; shift 2 ;;
            --cis) CIS_REFS=true; shift ;;
            -*) echo "Unknown option: $1" >&2; exit $EXIT_INVALID_ARGS ;;
            *) shift ;;
        esac
    done

    # Default to quick scan if nothing specified
    if [[ ${#SECTIONS[@]} -eq 0 ]]; then
        SECTIONS=("ports" "auth" "files" "users" "ssh")
    fi
}

# Audit open ports
audit_ports() {
    print_header "Open Ports & Services"

    log_info "Scanning listening ports..."

    local ports_found=false

    # Use ss if available, fallback to netstat
    if command -v ss &>/dev/null; then
        local listening
        listening=$(ss -tlnp 2>/dev/null || ss -tln 2>/dev/null || true)

        if [[ -n "$listening" ]]; then
            ports_found=true
            echo "$listening" | tail -n +2 | while read -r line; do
                local addr port
                addr=$(echo "$line" | awk '{print $4}')

                # Check for world-accessible ports
                if [[ "$addr" =~ ^0\.0\.0\.0:|^\*:|^\[::\]: ]]; then
                    port=$(echo "$addr" | grep -oE '[0-9]+$' || true)

                    case "$port" in
                        22) finding_info "SSH (22) listening on all interfaces" ;;
                        23) finding_critical "Telnet (23) listening - insecure protocol!" ;;
                        21) finding_high "FTP (21) listening - consider SFTP instead" ;;
                        25) finding_medium "SMTP (25) listening on all interfaces" ;;
                        3306) finding_high "MySQL (3306) exposed on all interfaces" ;;
                        5432) finding_high "PostgreSQL (5432) exposed on all interfaces" ;;
                        6379) finding_critical "Redis (6379) exposed - usually should be localhost only!" ;;
                        27017) finding_critical "MongoDB (27017) exposed - usually should be localhost only!" ;;
                        11211) finding_critical "Memcached (11211) exposed - should be localhost only!" ;;
                        *) log_debug "Port $port listening on all interfaces" ;;
                    esac
                fi
            done
        fi
    elif command -v netstat &>/dev/null; then
        netstat -tlnp 2>/dev/null | tail -n +3 || true
        ports_found=true
    fi

    if [[ "$ports_found" == "false" ]]; then
        log_ok "No exposed ports detected (or unable to scan)"
    fi

    # Check for common dangerous ports
    for port in 23 69 111 135 139 445 512 513 514; do
        if ss -tln 2>/dev/null | grep -qE ":${port}\s" || netstat -tln 2>/dev/null | grep -qE ":${port}\s"; then
            finding_high "Potentially dangerous port $port is open"
        fi
    done
}

# Audit authentication
audit_auth() {
    print_header "Authentication Security"

    # Check failed logins
    log_info "Checking authentication failures..."

    local failed_count=0

    if [[ -f /var/log/auth.log ]]; then
        failed_count=$(grep -c "Failed password" /var/log/auth.log 2>/dev/null || echo "0")
    elif [[ -f /var/log/secure ]]; then
        failed_count=$(grep -c "Failed password" /var/log/secure 2>/dev/null || echo "0")
    fi

    if [[ "$failed_count" -gt 100 ]]; then
        finding_high "High number of failed login attempts: $failed_count"
    elif [[ "$failed_count" -gt 20 ]]; then
        finding_medium "Multiple failed login attempts: $failed_count"
    else
        log_ok "Failed login attempts: $failed_count"
    fi

    # Check for root login attempts
    if [[ -f /var/log/auth.log ]]; then
        local root_attempts
        root_attempts=$(grep -c "Failed password for root" /var/log/auth.log 2>/dev/null || echo "0")
        if [[ "$root_attempts" -gt 10 ]]; then
            finding_high "Root login brute force attempts detected: $root_attempts"
        fi
    fi

    # Check PAM configuration
    if [[ -f /etc/pam.d/common-auth ]]; then
        if ! grep -q "pam_faillock\|pam_tally2" /etc/pam.d/common-auth 2>/dev/null; then
            finding_medium "Account lockout not configured in PAM"
            [[ "$CIS_REFS" == "true" ]] && echo "    CIS: 5.4.2 - Ensure lockout for failed password attempts is configured"
        fi
    fi

    # Check for empty passwords
    if [[ $EUID -eq 0 ]]; then
        local empty_pass
        empty_pass=$(awk -F: '($2 == "" ) { print $1 }' /etc/shadow 2>/dev/null || true)
        if [[ -n "$empty_pass" ]]; then
            finding_critical "Users with empty passwords: $empty_pass"
        else
            log_ok "No empty passwords found"
        fi
    fi
}

# Audit file permissions
audit_files() {
    print_header "File Permissions"

    # Check world-writable files
    log_info "Scanning for world-writable files..."

    if [[ "$QUICK_MODE" != "true" ]]; then
        local ww_files
        ww_files=$(find /etc /usr /var -xdev -type f -perm -0002 2>/dev/null | head -20 || true)

        if [[ -n "$ww_files" ]]; then
            finding_medium "World-writable files found:"
            echo "$ww_files" | while read -r file; do
                echo "    $file"
            done
        else
            log_ok "No world-writable files in system directories"
        fi
    fi

    # Check SUID/SGID files
    log_info "Scanning for SUID/SGID binaries..."

    local known_suid="/usr/bin/sudo /usr/bin/su /usr/bin/passwd /usr/bin/chsh /usr/bin/chfn /usr/bin/newgrp /usr/bin/gpasswd /usr/bin/mount /usr/bin/umount /usr/bin/ping /usr/bin/crontab"

    local suid_files
    suid_files=$(find /usr /bin /sbin -xdev -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null || true)

    local unusual_suid=()
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        if [[ ! " $known_suid " =~ " $file " ]]; then
            unusual_suid+=("$file")
        fi
    done <<< "$suid_files"

    if [[ ${#unusual_suid[@]} -gt 0 ]]; then
        finding_medium "Unusual SUID/SGID binaries found:"
        for file in "${unusual_suid[@]}"; do
            local perms owner
            perms=$(stat -c %a "$file" 2>/dev/null || echo "?")
            owner=$(stat -c %U "$file" 2>/dev/null || echo "?")
            echo "    [$perms] $owner: $file"
        done
    else
        log_ok "No unusual SUID/SGID binaries found"
    fi

    # Check /etc/passwd and /etc/shadow permissions
    local passwd_perms shadow_perms
    passwd_perms=$(stat -c %a /etc/passwd 2>/dev/null || echo "?")

    if [[ "$passwd_perms" != "644" ]]; then
        finding_medium "/etc/passwd has unusual permissions: $passwd_perms (should be 644)"
    fi

    if [[ -f /etc/shadow ]]; then
        shadow_perms=$(stat -c %a /etc/shadow 2>/dev/null || echo "?")
        if [[ "$shadow_perms" != "640" && "$shadow_perms" != "600" && "$shadow_perms" != "000" ]]; then
            finding_high "/etc/shadow has insecure permissions: $shadow_perms"
        fi
    fi

    # Check for unowned files
    if [[ "$DEEP_MODE" == "true" && $EUID -eq 0 ]]; then
        log_info "Scanning for unowned files (deep scan)..."
        local unowned
        unowned=$(find / -xdev \( -nouser -o -nogroup \) 2>/dev/null | head -10 || true)
        if [[ -n "$unowned" ]]; then
            finding_low "Unowned files found:"
            echo "$unowned"
        fi
    fi
}

# Audit user security
audit_users() {
    print_header "User Account Security"

    # Check for UID 0 accounts
    log_info "Checking for root-equivalent accounts..."
    local uid0
    uid0=$(awk -F: '$3 == 0 && $1 != "root" { print $1 }' /etc/passwd)

    if [[ -n "$uid0" ]]; then
        finding_critical "Non-root accounts with UID 0: $uid0"
    else
        log_ok "No unauthorized UID 0 accounts"
    fi

    # Check for accounts without passwords
    if [[ $EUID -eq 0 ]]; then
        local no_pass
        no_pass=$(awk -F: '($2 == "" || $2 == "!") && $7 !~ /nologin|false/ { print $1 }' /etc/shadow 2>/dev/null || true)
        if [[ -n "$no_pass" ]]; then
            finding_high "Accounts without passwords (with shell access): $no_pass"
        fi
    fi

    # Check sudo group
    log_info "Checking sudo privileges..."
    local sudo_users
    sudo_users=$(getent group sudo wheel admin 2>/dev/null | cut -d: -f4 | tr ',' '\n' | sort -u | grep -v '^$' || true)

    if [[ -n "$sudo_users" ]]; then
        finding_info "Users with sudo access:"
        echo "$sudo_users" | while read -r user; do
            [[ -n "$user" ]] && echo "    • $user"
        done
    fi

    # Check for users with login shell who shouldn't have one
    log_info "Checking system account shells..."
    while IFS=: read -r user _ uid _ _ _ shell; do
        if [[ "$uid" -lt 1000 && "$uid" -ne 0 ]]; then
            if [[ "$shell" != */nologin && "$shell" != */false && "$shell" != "/bin/sync" && -n "$shell" ]]; then
                finding_low "System user '$user' (UID $uid) has login shell: $shell"
            fi
        fi
    done < /etc/passwd
}

# Audit network security
audit_network() {
    print_header "Network Security"

    # Check firewall status
    log_info "Checking firewall status..."

    local fw_enabled=false

    if command -v ufw &>/dev/null; then
        if ufw status 2>/dev/null | grep -q "Status: active"; then
            log_ok "UFW firewall is active"
            fw_enabled=true
        else
            finding_high "UFW firewall is installed but not active"
        fi
    fi

    if command -v firewall-cmd &>/dev/null; then
        if firewall-cmd --state 2>/dev/null | grep -q "running"; then
            log_ok "firewalld is running"
            fw_enabled=true
        else
            finding_high "firewalld is installed but not running"
        fi
    fi

    if [[ "$fw_enabled" == "false" ]]; then
        # Check iptables directly
        local rules
        rules=$(iptables -L -n 2>/dev/null | grep -cv "^Chain\|^target\|^$" || echo "0")
        if [[ "$rules" -gt 3 ]]; then
            log_ok "iptables rules are configured ($rules rules)"
            fw_enabled=true
        else
            finding_high "No firewall appears to be configured"
        fi
    fi

    # Check IP forwarding
    log_info "Checking IP forwarding..."
    local ip_forward
    ip_forward=$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo "0")

    if [[ "$ip_forward" == "1" ]]; then
        finding_medium "IP forwarding is enabled - ensure this is intentional"
    else
        log_ok "IP forwarding is disabled"
    fi

    # Check for promiscuous mode
    if ip link show 2>/dev/null | grep -q "PROMISC"; then
        finding_high "Network interface in promiscuous mode detected"
    fi

    # Check established connections
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "Established connections:"
        ss -tnp 2>/dev/null | grep ESTAB | head -10 || netstat -tnp 2>/dev/null | grep ESTABLISHED | head -10 || true
    fi
}

# Audit SSH configuration
audit_ssh() {
    print_header "SSH Configuration"

    local sshd_config="/etc/ssh/sshd_config"

    if [[ ! -f "$sshd_config" ]]; then
        log_info "SSH server not installed"
        return
    fi

    log_info "Auditing SSH configuration..."

    # Check root login
    local root_login
    root_login=$(grep -E "^PermitRootLogin" "$sshd_config" 2>/dev/null | awk '{print $2}' || echo "")

    if [[ "$root_login" == "yes" ]]; then
        finding_high "Root login is enabled via SSH"
        [[ "$CIS_REFS" == "true" ]] && echo "    CIS: 5.2.10 - Ensure SSH root login is disabled"
    elif [[ "$root_login" == "prohibit-password" || "$root_login" == "without-password" ]]; then
        finding_medium "Root login allowed with key only"
    elif [[ -z "$root_login" ]]; then
        finding_medium "PermitRootLogin not explicitly set (defaults may vary)"
    else
        log_ok "Root login is disabled"
    fi

    # Check password authentication
    local pass_auth
    pass_auth=$(grep -E "^PasswordAuthentication" "$sshd_config" 2>/dev/null | awk '{print $2}' || echo "")

    if [[ "$pass_auth" == "yes" || -z "$pass_auth" ]]; then
        finding_medium "Password authentication is enabled - consider key-only"
    else
        log_ok "Password authentication is disabled"
    fi

    # Check for weak ciphers
    local ciphers
    ciphers=$(grep -E "^Ciphers" "$sshd_config" 2>/dev/null || echo "")

    if [[ -n "$ciphers" ]]; then
        if echo "$ciphers" | grep -qiE "3des|arcfour|blowfish|cast128"; then
            finding_high "Weak SSH ciphers are enabled"
        else
            log_ok "No weak ciphers detected"
        fi
    fi

    # Check protocol version
    local protocol
    protocol=$(grep -E "^Protocol" "$sshd_config" 2>/dev/null | awk '{print $2}' || echo "")

    if [[ "$protocol" == "1" || "$protocol" == "1,2" ]]; then
        finding_critical "SSH Protocol 1 is enabled - highly insecure!"
    fi

    # Check for empty passwords
    local empty_pass
    empty_pass=$(grep -E "^PermitEmptyPasswords" "$sshd_config" 2>/dev/null | awk '{print $2}' || echo "no")

    if [[ "$empty_pass" == "yes" ]]; then
        finding_critical "Empty passwords are permitted via SSH!"
    fi

    # Check X11 forwarding
    local x11
    x11=$(grep -E "^X11Forwarding" "$sshd_config" 2>/dev/null | awk '{print $2}' || echo "")

    if [[ "$x11" == "yes" ]]; then
        finding_low "X11 forwarding is enabled"
    fi
}

# Audit pending updates
audit_updates() {
    print_header "Security Updates"

    log_info "Checking for pending security updates..."

    if command -v apt-get &>/dev/null; then
        apt-get update -qq 2>/dev/null || true
        local updates
        updates=$(apt-get upgrade -s 2>/dev/null | grep -ci "security" || echo "0")

        if [[ "$updates" -gt 0 ]]; then
            finding_high "Security updates available: $updates"
        else
            log_ok "No pending security updates"
        fi
    elif command -v yum &>/dev/null; then
        local updates
        updates=$(yum check-update --security 2>/dev/null | grep -cE "^\S+\s+\S+\s+\S+" || echo "0")

        if [[ "$updates" -gt 0 ]]; then
            finding_high "Security updates available: $updates"
        else
            log_ok "No pending security updates"
        fi
    elif command -v dnf &>/dev/null; then
        local updates
        updates=$(dnf updateinfo list --security 2>/dev/null | grep -cE "^\S+" || echo "0")

        if [[ "$updates" -gt 0 ]]; then
            finding_high "Security updates available: $updates"
        else
            log_ok "No pending security updates"
        fi
    else
        log_info "Unable to check for security updates (unsupported package manager)"
    fi
}

# Audit running processes
audit_processes() {
    print_header "Process Analysis"

    log_info "Analyzing running processes..."

    # Check for processes running as root
    local root_procs
    root_procs=$(ps aux 2>/dev/null | awk '$1 == "root" { print $11 }' | sort -u | wc -l || echo "0")
    finding_info "Processes running as root: $root_procs"

    # Check for suspicious processes
    local suspicious="nc ncat netcat socat cryptominer xmrig minerd"
    for proc in $suspicious; do
        if pgrep -x "$proc" &>/dev/null; then
            finding_critical "Suspicious process running: $proc"
        fi
    done

    # Check for processes with deleted binaries
    if [[ "$DEEP_MODE" == "true" && $EUID -eq 0 ]]; then
        log_info "Checking for processes with deleted binaries..."
        local deleted
        deleted=$(find /proc/*/exe -type l 2>/dev/null | xargs ls -la 2>/dev/null | grep deleted | head -5 || true)
        if [[ -n "$deleted" ]]; then
            finding_medium "Processes running from deleted binaries:"
            echo "$deleted"
        fi
    fi

    # Check for processes listening on network
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "Network-listening processes:"
        ss -tlnp 2>/dev/null | tail -n +2 || netstat -tlnp 2>/dev/null | tail -n +3 || true
    fi
}

# Audit kernel security
audit_kernel() {
    print_header "Kernel Security"

    log_info "Checking kernel security settings..."

    # ASLR
    local aslr
    aslr=$(cat /proc/sys/kernel/randomize_va_space 2>/dev/null || echo "?")
    if [[ "$aslr" == "2" ]]; then
        log_ok "ASLR is fully enabled"
    elif [[ "$aslr" == "1" ]]; then
        finding_medium "ASLR is partially enabled (should be 2)"
    elif [[ "$aslr" == "0" ]]; then
        finding_high "ASLR is disabled"
    fi

    # Kernel pointers
    local kptr
    kptr=$(cat /proc/sys/kernel/kptr_restrict 2>/dev/null || echo "?")
    if [[ "$kptr" == "0" ]]; then
        finding_medium "Kernel pointers are exposed (kptr_restrict=0)"
    else
        log_ok "Kernel pointers are restricted"
    fi

    # dmesg restrict
    local dmesg
    dmesg=$(cat /proc/sys/kernel/dmesg_restrict 2>/dev/null || echo "?")
    if [[ "$dmesg" == "0" ]]; then
        finding_low "dmesg is accessible to all users"
    fi

    # Core dumps
    local core_pattern
    core_pattern=$(cat /proc/sys/kernel/core_pattern 2>/dev/null || echo "")
    if [[ -n "$core_pattern" && "$core_pattern" != "|"* && "$core_pattern" != "core" ]]; then
        finding_info "Core dump pattern: $core_pattern"
    fi

    # SYN cookies
    local syncookies
    syncookies=$(cat /proc/sys/net/ipv4/tcp_syncookies 2>/dev/null || echo "?")
    if [[ "$syncookies" == "0" ]]; then
        finding_medium "TCP SYN cookies are disabled (DoS protection)"
    else
        log_ok "TCP SYN cookies are enabled"
    fi

    # Check loaded kernel modules for known malicious ones
    if [[ "$DEEP_MODE" == "true" ]]; then
        log_info "Checking loaded kernel modules..."
        local suspicious_modules="rootkit diamorphine reptile"
        for mod in $suspicious_modules; do
            if lsmod 2>/dev/null | grep -qi "$mod"; then
                finding_critical "Suspicious kernel module loaded: $mod"
            fi
        done
    fi
}

# Print summary
print_summary() {
    echo ""
    echo -e "${BOLD}═══ Security Audit Summary ═══${NC}"
    echo ""

    local total=$((CRITICAL_COUNT + HIGH_COUNT + MEDIUM_COUNT + LOW_COUNT))

    printf "${RED}${BOLD}Critical:${NC} %d\n" "$CRITICAL_COUNT"
    printf "${RED}High:${NC}     %d\n" "$HIGH_COUNT"
    printf "${YELLOW}Medium:${NC}   %d\n" "$MEDIUM_COUNT"
    printf "${CYAN}Low:${NC}      %d\n" "$LOW_COUNT"
    echo "─────────────"
    printf "${BOLD}Total:${NC}    %d\n" "$total"

    echo ""

    if [[ $CRITICAL_COUNT -gt 0 ]]; then
        echo -e "${RED}${BOLD}⚠ CRITICAL ISSUES REQUIRE IMMEDIATE ATTENTION${NC}"
    elif [[ $HIGH_COUNT -gt 0 ]]; then
        echo -e "${RED}⚠ High severity issues should be addressed soon${NC}"
    elif [[ $MEDIUM_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}⚠ Medium severity issues found${NC}"
    elif [[ $total -eq 0 ]]; then
        echo -e "${GREEN}✓ No security issues detected${NC}"
    fi
}

# Generate report
generate_report() {
    [[ -z "$REPORT_FILE" ]] && return

    log_info "Generating report to $REPORT_FILE..."

    case "$REPORT_FORMAT" in
        json)
            cat > "$REPORT_FILE" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "summary": {
    "critical": $CRITICAL_COUNT,
    "high": $HIGH_COUNT,
    "medium": $MEDIUM_COUNT,
    "low": $LOW_COUNT,
    "total": $((CRITICAL_COUNT + HIGH_COUNT + MEDIUM_COUNT + LOW_COUNT))
  }
}
EOF
            ;;
        html)
            cat > "$REPORT_FILE" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Security Audit Report - $(hostname)</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        .critical { color: #d32f2f; font-weight: bold; }
        .high { color: #f44336; }
        .medium { color: #ff9800; }
        .low { color: #2196f3; }
        .summary { background: #f5f5f5; padding: 15px; border-radius: 5px; }
    </style>
</head>
<body>
    <h1>Security Audit Report</h1>
    <p>Host: $(hostname) | Date: $(date)</p>
    <div class="summary">
        <h2>Summary</h2>
        <p class="critical">Critical: $CRITICAL_COUNT</p>
        <p class="high">High: $HIGH_COUNT</p>
        <p class="medium">Medium: $MEDIUM_COUNT</p>
        <p class="low">Low: $LOW_COUNT</p>
    </div>
</body>
</html>
EOF
            ;;
        *)
            # Text format - redirect output
            ;;
    esac

    log_ok "Report saved to $REPORT_FILE"
}

# Main function
main() {
    parse_args "$@"

    echo -e "${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}"
    echo -e "${DIM}Hostname: $(hostname) | Date: $(date)${NC}"

    # Run sections
    for section in "${SECTIONS[@]}"; do
        case "$section" in
            ports) audit_ports ;;
            auth) audit_auth ;;
            files) audit_files ;;
            users) audit_users ;;
            network) audit_network ;;
            ssh) audit_ssh ;;
            updates) audit_updates ;;
            processes) audit_processes ;;
            kernel) audit_kernel ;;
            *) log_info "Unknown section: $section" ;;
        esac
    done

    print_summary
    generate_report

    # Exit codes based on findings
    if [[ $CRITICAL_COUNT -gt 0 ]]; then
        exit $EXIT_CRITICAL
    elif [[ $HIGH_COUNT -gt 0 ]]; then
        exit $EXIT_HIGH
    elif [[ $MEDIUM_COUNT -gt 0 ]]; then
        exit $EXIT_MEDIUM
    elif [[ $LOW_COUNT -gt 0 ]]; then
        exit $EXIT_LOW
    fi

    exit $EXIT_OK
}

main "$@"

