#!/bin/bash
# =============================================================================
# @id           users
# @name         user-audit
# @displayName  User Audit
# @description  Audit user accounts, sudo access, login history, and orphaned files
# @category     security
# @version      1.0.0
# @author       codefuturist
# @tags         users,accounts,sudo,security,audit,login,permissions
# @shells       bash
# =============================================================================

set -euo pipefail

# =============================================================================
# Load RSR Library
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RSR_LIB_DIR="${SCRIPT_DIR}/../../../lib"

if [[ -f "$RSR_LIB_DIR/rsr-lib.sh" ]]; then
    source "$RSR_LIB_DIR/rsr-lib.sh" users validate
fi

# Script metadata
SCRIPT_NAME="User Audit"
SCRIPT_VERSION="1.0.0"

# Default values
VERBOSE=false
INTERACTIVE=auto
SECTIONS=()
TARGET_USER=""
SUDO_ONLY=false
EXPIRED_ONLY=false
NO_LOGIN_ONLY=false
WARN_DAYS=14
OUTPUT_FORMAT="text"

# Color codes (from RSR library or fallback)
RED="${RSR_COLOR_RED:-\033[0;31m}"
GREEN="${RSR_COLOR_GREEN:-\033[0;32m}"
YELLOW="${RSR_COLOR_YELLOW:-\033[1;33m}"
BLUE="${RSR_COLOR_BLUE:-\033[0;34m}"
CYAN="${RSR_COLOR_CYAN:-\033[0;36m}"
DIM="${RSR_COLOR_DIM:-\033[2m}"
BOLD="${RSR_COLOR_BOLD:-\033[1m}"
NC="${RSR_COLOR_RESET:-\033[0m}"

# Counters
ISSUES_CRITICAL=0
ISSUES_WARNING=0

usage() {
    cat << EOF
${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}

Audit user accounts, sudo access, login history, and find orphaned files.

${YELLOW}Usage:${NC}
    $0 [OPTIONS]

${BOLD}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -i, --interactive       Run in interactive mode (default when no args)
    --no-interactive        Disable interactive mode
    -a, --all               Run all audit checks
    -s, --section SECTION   Run specific section (can repeat)
    -u, --user USER         Audit specific user only
    --sudo-only             Show only users with sudo access
    --expired               Show only expired/expiring accounts
    --no-login              Show accounts that should be nologin
    --orphans               Find files with no owner
    --ssh-keys              Audit SSH authorized keys
    --failed-logins         Show failed login attempts
    -w, --warn-days DAYS    Warn if password expires within N days (default: 14)
    --json                  Output in JSON format

${BOLD}Sections:${NC}
    accounts    List all user accounts with details
    sudo        Sudo/wheel group membership
    passwords   Password status and expiry
    logins      Login history and failed attempts
    ssh         SSH key audit
    orphans     Orphaned files scan

${BOLD}Examples:${NC}
    ${DIM}# Full user audit${NC}
    $0 -a

    ${DIM}# Check sudo and password status${NC}
    $0 -s sudo -s passwords

    ${DIM}# List only sudo users${NC}
    $0 --sudo-only

    ${DIM}# Find orphaned files${NC}
    sudo $0 --orphans

    ${DIM}# Detailed audit of specific user${NC}
    $0 -u admin -v

${BOLD}Exit Codes:${NC}
    0 - Audit complete, no critical issues
    1 - General error
    2 - Invalid arguments
    3 - Permission denied (need root for full audit)
    4 - Critical security issues found
    5 - Warnings found (non-critical)

EOF
    exit 0
}

# Logging functions (use RSR if available)
if type rsr_log_info &>/dev/null; then
    log_info() { rsr_log_info "$1"; }
    log_ok() { rsr_log_ok "$1"; }
    log_error() { rsr_log_error "$1"; }
    log_debug() { [[ "$VERBOSE" == "true" ]] && rsr_log_debug "$1"; }
    print_header() { rsr_print_header "$1"; }
else
    log_info() { echo -e "${BLUE}▸${NC} $1"; }
    log_ok() { echo -e "${GREEN}✓${NC} $1"; }
    log_error() { echo -e "${RED}✗${NC} $1" >&2; }
    log_debug() { [[ "$VERBOSE" == "true" ]] && echo -e "${DIM}  $1${NC}"; }
    print_header() { echo -e "\n${BOLD}${CYAN}═══ $1 ═══${NC}\n"; }
fi

log_warn() {
    if type rsr_log_warn &>/dev/null; then rsr_log_warn "$1"; else echo -e "${YELLOW}⚠${NC} $1"; fi
    ((ISSUES_WARNING++)) || true
}
log_critical() {
    echo -e "${RED}${BOLD}✗${NC} $1"
    ((ISSUES_CRITICAL++)) || true
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help) usage ;;
            -v | --verbose)
                VERBOSE=true
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
            -a | --all)
                SECTIONS=("accounts" "sudo" "passwords" "logins" "ssh" "orphans")
                shift
                ;;
            -s | --section)
                SECTIONS+=("$2")
                shift 2
                ;;
            -u | --user)
                TARGET_USER="$2"
                shift 2
                ;;
            --sudo-only)
                SUDO_ONLY=true
                shift
                ;;
            --expired)
                EXPIRED_ONLY=true
                shift
                ;;
            --no-login)
                NO_LOGIN_ONLY=true
                shift
                ;;
            --orphans)
                SECTIONS+=("orphans")
                shift
                ;;
            --ssh-keys)
                SECTIONS+=("ssh")
                shift
                ;;
            --failed-logins)
                SECTIONS+=("logins")
                shift
                ;;
            -w | --warn-days)
                WARN_DAYS="$2"
                shift 2
                ;;
            --json)
                OUTPUT_FORMAT="json"
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                exit 2
                ;;
            *) shift ;;
        esac
    done

    # Default to accounts if no sections specified
    if [[ ${#SECTIONS[@]} -eq 0 && -z "$TARGET_USER" && "$SUDO_ONLY" == "false" && "$EXPIRED_ONLY" == "false" && "$NO_LOGIN_ONLY" == "false" ]]; then
        SECTIONS=("accounts")
    fi
}

# Get all human users (UID >= 1000 or UID 0)
get_human_users() {
    awk -F: '$3 >= 1000 || $3 == 0 { print $1 }' /etc/passwd
}

# Get all users
get_all_users() {
    awk -F: '{ print $1 }' /etc/passwd
}

# Get user info
get_user_info() {
    local user="$1"
    local info
    info=$(getent passwd "$user" 2> /dev/null || true)
    if [[ -n "$info" ]]; then
        echo "$info"
    fi
}

# Check if user has sudo access
has_sudo_access() {
    local user="$1"

    # Check sudo group
    if groups "$user" 2> /dev/null | grep -qE '\b(sudo|wheel|admin)\b'; then
        return 0
    fi

    # Check sudoers file
    if [[ -r /etc/sudoers ]]; then
        if grep -qE "^${user}\s" /etc/sudoers 2> /dev/null; then
            return 0
        fi
    fi

    # Check sudoers.d
    if [[ -d /etc/sudoers.d ]]; then
        if grep -rqE "^${user}\s" /etc/sudoers.d/ 2> /dev/null; then
            return 0
        fi
    fi

    return 1
}

# Audit accounts section
audit_accounts() {
    print_header "User Accounts"

    local users
    if [[ -n "$TARGET_USER" ]]; then
        users="$TARGET_USER"
    else
        users=$(get_all_users)
    fi

    printf "${BOLD}%-15s %-6s %-6s %-20s %s${NC}\n" "USERNAME" "UID" "GID" "SHELL" "HOME"
    echo "─────────────────────────────────────────────────────────────────────────"

    local count=0
    local system_count=0
    local human_count=0

    while IFS= read -r user; do
        local info
        info=$(get_user_info "$user")
        [[ -z "$info" ]] && continue

        local uid gid shell home
        uid=$(echo "$info" | cut -d: -f3)
        gid=$(echo "$info" | cut -d: -f4)
        shell=$(echo "$info" | cut -d: -f7)
        home=$(echo "$info" | cut -d: -f6)

        # Apply filters
        if [[ "$SUDO_ONLY" == "true" ]] && ! has_sudo_access "$user"; then
            continue
        fi

        if [[ "$NO_LOGIN_ONLY" == "true" ]] && [[ "$shell" != */nologin && "$shell" != */false ]]; then
            continue
        fi

        # Color code based on type
        local color=""
        if [[ "$uid" -eq 0 ]]; then
            color="${RED}"
            [[ "$user" != "root" ]] && log_critical "User '$user' has UID 0 (root equivalent)"
        elif [[ "$uid" -lt 1000 ]]; then
            color="${DIM}"
            ((system_count++)) || true
        else
            color="${NC}"
            ((human_count++)) || true
        fi

        printf "${color}%-15s %-6s %-6s %-20s %s${NC}\n" "$user" "$uid" "$gid" "$shell" "$home"
        ((count++)) || true

    done <<< "$users"

    echo ""
    log_info "Total: $count users ($human_count human, $system_count system)"
}

# Audit sudo access
audit_sudo() {
    print_header "Sudo Access"

    local sudo_users=()
    local wheel_users=()

    # Check sudo group
    if getent group sudo &> /dev/null; then
        local members
        members=$(getent group sudo | cut -d: -f4)
        if [[ -n "$members" ]]; then
            IFS=',' read -ra sudo_users <<< "$members"
        fi
    fi

    # Check wheel group
    if getent group wheel &> /dev/null; then
        local members
        members=$(getent group wheel | cut -d: -f4)
        if [[ -n "$members" ]]; then
            IFS=',' read -ra wheel_users <<< "$members"
        fi
    fi

    if [[ ${#sudo_users[@]} -gt 0 ]]; then
        log_info "Users in 'sudo' group:"
        for user in "${sudo_users[@]}"; do
            [[ -n "$user" ]] && echo "    • $user"
        done
    fi

    if [[ ${#wheel_users[@]} -gt 0 ]]; then
        log_info "Users in 'wheel' group:"
        for user in "${wheel_users[@]}"; do
            [[ -n "$user" ]] && echo "    • $user"
        done
    fi

    # Check for NOPASSWD in sudoers
    if [[ -r /etc/sudoers ]]; then
        local nopasswd
        nopasswd=$(grep -E "NOPASSWD" /etc/sudoers 2> /dev/null | grep -v "^#" || true)
        if [[ -n "$nopasswd" ]]; then
            log_warn "NOPASSWD entries found in sudoers:"
            echo "$nopasswd" | while read -r line; do
                echo "    ${YELLOW}$line${NC}"
            done
        fi
    fi

    # Check sudoers.d
    if [[ -d /etc/sudoers.d ]]; then
        for file in /etc/sudoers.d/*; do
            [[ -f "$file" ]] || continue
            if grep -qE "NOPASSWD" "$file" 2> /dev/null; then
                log_warn "NOPASSWD entry in $file"
            fi
        done
    fi

    # Check for users with UID 0
    local uid0_users
    uid0_users=$(awk -F: '$3 == 0 && $1 != "root" { print $1 }' /etc/passwd)
    if [[ -n "$uid0_users" ]]; then
        log_critical "Non-root users with UID 0 (root equivalent):"
        echo "$uid0_users" | while read -r user; do
            echo "    ${RED}$user${NC}"
        done
    fi
}

# Audit password status
audit_passwords() {
    print_header "Password Status"

    if [[ $EUID -ne 0 ]]; then
        log_warn "Root access required for full password audit"
        return
    fi

    local users
    if [[ -n "$TARGET_USER" ]]; then
        users="$TARGET_USER"
    else
        users=$(get_human_users)
    fi

    printf "${BOLD}%-15s %-12s %-12s %-12s %s${NC}\n" "USER" "STATUS" "LAST CHANGE" "EXPIRES" "WARN"
    echo "─────────────────────────────────────────────────────────────────────────"

    while IFS= read -r user; do
        [[ -z "$user" ]] && continue

        local shadow_info status last_change expires warn_info=""

        # Get shadow info
        shadow_info=$(getent shadow "$user" 2> /dev/null || true)
        [[ -z "$shadow_info" ]] && continue

        local passwd_field
        passwd_field=$(echo "$shadow_info" | cut -d: -f2)

        # Determine status
        if [[ "$passwd_field" == "!" || "$passwd_field" == "!!" ]]; then
            status="${YELLOW}locked${NC}"
        elif [[ "$passwd_field" == "*" ]]; then
            status="${DIM}disabled${NC}"
        elif [[ -z "$passwd_field" ]]; then
            status="${RED}EMPTY${NC}"
            log_critical "User '$user' has empty password!"
        else
            status="${GREEN}set${NC}"
        fi

        # Get password aging info
        local last_change_days expire_days
        last_change_days=$(echo "$shadow_info" | cut -d: -f3)
        expire_days=$(echo "$shadow_info" | cut -d: -f5)

        if [[ -n "$last_change_days" && "$last_change_days" -gt 0 ]]; then
            local last_date
            last_date=$(date -d "1970-01-01 + $last_change_days days" +%Y-%m-%d 2> /dev/null || echo "N/A")
            last_change="$last_date"
        else
            last_change="never"
        fi

        if [[ -n "$expire_days" && "$expire_days" -gt 0 && -n "$last_change_days" && "$last_change_days" -gt 0 ]]; then
            local expire_date days_left
            expire_date=$(date -d "1970-01-01 + $((last_change_days + expire_days)) days" +%Y-%m-%d 2> /dev/null || echo "N/A")
            days_left=$(((last_change_days + expire_days) - ($(date +%s) / 86400)))

            if [[ $days_left -lt 0 ]]; then
                expires="${RED}EXPIRED${NC}"
                warn_info="${RED}!${NC}"
                log_critical "User '$user' password has expired"
            elif [[ $days_left -lt $WARN_DAYS ]]; then
                expires="${YELLOW}$expire_date${NC}"
                warn_info="${YELLOW}${days_left}d${NC}"
                log_warn "User '$user' password expires in $days_left days"
            else
                expires="$expire_date"
            fi
        else
            expires="never"
        fi

        # Apply filters
        if [[ "$EXPIRED_ONLY" == "true" ]]; then
            [[ "$expires" != *"EXPIRED"* && -z "$warn_info" ]] && continue
        fi

        printf "%-15s %-20s %-12s %-20s %s\n" "$user" "$status" "$last_change" "$expires" "$warn_info"

    done <<< "$users"
}

# Audit login history
audit_logins() {
    print_header "Login History"

    log_info "Recent logins:"
    if command -v last &> /dev/null; then
        last -n 10 2> /dev/null | head -15 || true
    else
        log_warn "last command not available"
    fi

    echo ""
    log_info "Failed login attempts:"
    if command -v lastb &> /dev/null && [[ $EUID -eq 0 ]]; then
        local failed
        failed=$(lastb -n 20 2> /dev/null | head -20 || true)
        if [[ -n "$failed" && "$failed" != *"btmp begins"* ]]; then
            echo "$failed"

            # Count by IP
            local ip_counts
            ip_counts=$(lastb 2> /dev/null | awk '{print $3}' | grep -E '^[0-9]+\.' | sort | uniq -c | sort -rn | head -5 || true)
            if [[ -n "$ip_counts" ]]; then
                echo ""
                log_warn "Top failed login sources:"
                echo "$ip_counts"
            fi
        else
            log_ok "No failed login attempts recorded"
        fi
    elif [[ -f /var/log/auth.log ]]; then
        grep "Failed password" /var/log/auth.log 2> /dev/null | tail -10 || log_ok "No failed logins found"
    elif [[ -f /var/log/secure ]]; then
        grep "Failed password" /var/log/secure 2> /dev/null | tail -10 || log_ok "No failed logins found"
    else
        log_warn "Need root access for failed login history"
    fi

    # Users who never logged in
    echo ""
    log_info "Users who never logged in:"
    local never_logged=()
    while IFS= read -r user; do
        [[ -z "$user" ]] && continue
        local last_login
        last_login=$(lastlog -u "$user" 2> /dev/null | tail -1 | grep -c "Never logged in" || true)
        if [[ "$last_login" -gt 0 ]]; then
            never_logged+=("$user")
        fi
    done <<< "$(get_human_users)"

    if [[ ${#never_logged[@]} -gt 0 ]]; then
        printf "    %s\n" "${never_logged[@]}"
    else
        log_ok "All users have logged in at least once"
    fi
}

# Audit SSH keys
audit_ssh() {
    print_header "SSH Key Audit"

    local users
    if [[ -n "$TARGET_USER" ]]; then
        users="$TARGET_USER"
    else
        users=$(get_human_users)
    fi

    while IFS= read -r user; do
        [[ -z "$user" ]] && continue

        local home
        home=$(getent passwd "$user" | cut -d: -f6)
        [[ -z "$home" || ! -d "$home" ]] && continue

        local auth_keys="$home/.ssh/authorized_keys"
        local auth_keys2="$home/.ssh/authorized_keys2"

        local found=false

        for keyfile in "$auth_keys" "$auth_keys2"; do
            if [[ -f "$keyfile" ]]; then
                found=true
                local key_count
                key_count=$(grep -c "^ssh-" "$keyfile" 2> /dev/null || echo "0")

                if [[ "$key_count" -gt 0 ]]; then
                    log_info "User '$user' has $key_count SSH key(s) in $keyfile"

                    if [[ "$VERBOSE" == "true" ]]; then
                        while IFS= read -r line; do
                            [[ "$line" =~ ^ssh- ]] || continue
                            local key_type key_comment
                            key_type=$(echo "$line" | awk '{print $1}')
                            key_comment=$(echo "$line" | awk '{print $NF}')
                            echo "        ${DIM}$key_type ... $key_comment${NC}"
                        done < "$keyfile"
                    fi

                    # Check permissions
                    local perms
                    perms=$(stat -c %a "$keyfile" 2> /dev/null || stat -f %OLp "$keyfile" 2> /dev/null || echo "")
                    if [[ "$perms" != "600" && "$perms" != "644" ]]; then
                        log_warn "Insecure permissions ($perms) on $keyfile"
                    fi
                fi
            fi
        done

        # Check for root authorized_keys
        if [[ "$user" == "root" && "$found" == "true" ]]; then
            log_warn "Root user has SSH authorized_keys"
        fi

    done <<< "$users"
}

# Audit orphaned files
audit_orphans() {
    print_header "Orphaned Files"

    if [[ $EUID -ne 0 ]]; then
        log_warn "Root access required for orphaned file scan"
        return
    fi

    log_info "Scanning for files with no owner (this may take a while)..."

    local orphaned
    orphaned=$(find /home /var /tmp -nouser -o -nogroup 2> /dev/null | head -50 || true)

    if [[ -n "$orphaned" ]]; then
        local count
        count=$(echo "$orphaned" | wc -l)
        log_warn "Found $count orphaned files (showing first 50):"
        echo "$orphaned" | while read -r file; do
            local owner group
            owner=$(stat -c %u "$file" 2> /dev/null || echo "?")
            group=$(stat -c %g "$file" 2> /dev/null || echo "?")
            echo "    ${YELLOW}[$owner:$group]${NC} $file"
        done
    else
        log_ok "No orphaned files found"
    fi
}

# Print summary
print_summary() {
    echo ""
    echo -e "${BOLD}═══ Summary ═══${NC}"
    echo ""

    if [[ $ISSUES_CRITICAL -gt 0 ]]; then
        echo -e "${RED}Critical issues: $ISSUES_CRITICAL${NC}"
    fi

    if [[ $ISSUES_WARNING -gt 0 ]]; then
        echo -e "${YELLOW}Warnings: $ISSUES_WARNING${NC}"
    fi

    if [[ $ISSUES_CRITICAL -eq 0 && $ISSUES_WARNING -eq 0 ]]; then
        log_ok "No security issues found"
    fi
}

# =============================================================================
# Interactive Mode
# =============================================================================

run_interactive() {
    print_interactive_header "$SCRIPT_NAME" "$SCRIPT_VERSION"

    echo ""

    # Audit scope
    local scope
    scope=$(prompt_select "What would you like to audit?" \
        "Full user audit (all sections)" \
        "Specific user account" \
        "Select specific sections" \
        "Quick checks (sudo users, expired accounts)")

    case "$scope" in
        "Full user audit (all sections)")
            SECTIONS=("accounts" "sudo" "passwords" "logins" "ssh" "orphans")
            ;;
        "Specific user account")
            echo ""
            TARGET_USER=$(prompt_input "Enter username to audit" "")
            if [[ -z "$TARGET_USER" ]]; then
                log_error "No username specified"
                return 1
            fi
            SECTIONS=("accounts" "sudo" "passwords" "ssh")
            ;;
        "Select specific sections")
            echo ""
            local selected
            selected=$(prompt_multiselect "Select sections to audit:" \
                "User accounts list" \
                "Sudo/wheel group membership" \
                "Password status and expiry" \
                "Login history" \
                "SSH authorized keys" \
                "Orphaned files scan")

            SECTIONS=()
            [[ "$selected" == *"User accounts"* ]] && SECTIONS+=("accounts")
            [[ "$selected" == *"Sudo/wheel"* ]] && SECTIONS+=("sudo")
            [[ "$selected" == *"Password status"* ]] && SECTIONS+=("passwords")
            [[ "$selected" == *"Login history"* ]] && SECTIONS+=("logins")
            [[ "$selected" == *"SSH authorized"* ]] && SECTIONS+=("ssh")
            [[ "$selected" == *"Orphaned files"* ]] && SECTIONS+=("orphans")
            ;;
        "Quick checks (sudo users, expired accounts)")
            SUDO_ONLY=true
            EXPIRED_ONLY=true
            SECTIONS=("accounts" "sudo" "passwords")
            ;;
    esac

    if [[ ${#SECTIONS[@]} -eq 0 && -z "$TARGET_USER" && "$SUDO_ONLY" != "true" ]]; then
        log_error "No sections selected"
        return 1
    fi

    echo ""

    # Additional options
    if prompt_yes_no "Enable verbose output?" "n"; then
        VERBOSE=true
    fi

    # Summary
    echo ""
    log_info "Audit configuration:"
    [[ -n "$TARGET_USER" ]] && echo -e "  ${CYAN}•${NC} Target user: $TARGET_USER"
    [[ ${#SECTIONS[@]} -gt 0 ]] && echo -e "  ${CYAN}•${NC} Sections: ${SECTIONS[*]}"
    [[ "$SUDO_ONLY" == "true" ]] && echo -e "  ${CYAN}•${NC} Filter: Sudo users only"
    [[ "$EXPIRED_ONLY" == "true" ]] && echo -e "  ${CYAN}•${NC} Filter: Expired/expiring accounts"
    echo ""

    if prompt_yes_no "Start user audit?" "y"; then
        return 0
    else
        log_info "Audit cancelled"
        exit 0
    fi
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
    if [[ "$INTERACTIVE" == "true" ]] && type -t rsr_is_interactive &>/dev/null && rsr_is_interactive; then
        run_interactive
    fi

    echo -e "${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}"
    echo ""

    # Run sections
    for section in "${SECTIONS[@]}"; do
        case "$section" in
            accounts) audit_accounts ;;
            sudo) audit_sudo ;;
            passwords) audit_passwords ;;
            logins) audit_logins ;;
            ssh) audit_ssh ;;
            orphans) audit_orphans ;;
            *) log_warn "Unknown section: $section" ;;
        esac
    done

    # Handle special flags
    if [[ "$SUDO_ONLY" == "true" || "$EXPIRED_ONLY" == "true" || "$NO_LOGIN_ONLY" == "true" ]]; then
        audit_accounts
    fi

    if [[ -n "$TARGET_USER" && ${#SECTIONS[@]} -eq 0 ]]; then
        # Full audit for specific user
        audit_accounts
        audit_sudo
        audit_passwords
        audit_ssh
    fi

    print_summary

    # Exit codes
    if [[ $ISSUES_CRITICAL -gt 0 ]]; then
        exit 4
    elif [[ $ISSUES_WARNING -gt 0 ]]; then
        exit 5
    fi

    exit 0
}

main "$@"
