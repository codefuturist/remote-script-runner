#!/bin/bash
# =============================================================================
# @id           users
# @name         user-management
# @displayName  User Management
# @description  Comprehensive user management: create/delete accounts, passwords, groups, permissions, monitoring
# @category     security
# @version      1.0.0
# @author       codefuturist
# @tags         users,accounts,passwords,permissions,groups,security,access-control,sudo
# @shells       bash
# @requires     sudo (for most operations)
# @os           linux,macos
# @sudo         required
# =============================================================================

# This script can be run remotely with curl and accepts subcommands
# Example: /bin/bash -c "$(curl -fsSL https://codefuturist.github.io/remote-script-runner/scripts/bash/user-management.sh)" -- create -u john -c "John Doe"

set -euo pipefail

# =============================================================================
# Load RSR Library
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RSR_LIB_DIR="${SCRIPT_DIR}/../../../lib"

# Load the RSR library with required modules
if [[ -f "$RSR_LIB_DIR/rsr-lib.sh" ]]; then
    source "$RSR_LIB_DIR/rsr-lib.sh" users validate interactive
else
    echo "ERROR: RSR library not found at $RSR_LIB_DIR/rsr-lib.sh" >&2
    exit 1
fi

# =============================================================================
# Script Metadata
# =============================================================================

SCRIPT_NAME="User Management"
SCRIPT_VERSION="1.0.0"
SCRIPT_URL="https://github.com/codefuturist/remote-script-runner"

# =============================================================================
# Default Configuration
# =============================================================================

VERBOSE=false
DRY_RUN=false
INTERACTIVE=auto
RSR_YES=0
SUBCOMMAND=""

# User creation defaults
USERNAME=""
USER_COMMENT=""
USER_SHELL=""
USER_HOME=""
USER_UID=""
USER_GID=""
USER_GROUPS=()
CREATE_HOME=true

# Password options
PASSWORD=""
PASSWORD_LENGTH=16
FORCE_CHANGE=false

# Group options
GROUPNAME=""
GROUP_GID=""

# Permission options
PERMISSION_PATH=""
PERMISSION_MODE=""
PERMISSION_OWNER=""
PERMISSION_RECURSIVE=false

# Session options
SESSION_USERNAME=""
SESSION_LINES=20

# Batch import
BATCH_FILE=""

# =============================================================================
# Logging Aliases (use RSR library functions)
# =============================================================================

log_info() { rsr_log_info "$*"; }
log_ok() { rsr_log_ok "$*"; }
log_warn() { rsr_log_warn "$*"; }
log_error() { rsr_log_error "$*"; }
log_debug() { [[ "$VERBOSE" == "true" ]] && rsr_log_debug "$*"; }

# Colors from RSR library
BLUE="$RSR_COLOR_BLUE"
GREEN="$RSR_COLOR_GREEN"
YELLOW="$RSR_COLOR_YELLOW"
RED="$RSR_COLOR_RED"
CYAN="$RSR_COLOR_CYAN"
DIM="$RSR_COLOR_DIM"
BOLD="$RSR_COLOR_BOLD"
NC="$RSR_COLOR_RESET"

print_header() {
    rsr_print_header "$1"
}

# =============================================================================
# Usage/Help
# =============================================================================

usage() {
    cat << EOF
${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}

Comprehensive cross-platform user management with support for Linux and macOS.

${YELLOW}Usage:${NC}
    $0 <subcommand> [OPTIONS]

${BOLD}Subcommands:${NC}

  ${CYAN}Account Management:${NC}
    create              Create new user account
    delete              Delete user account
    modify              Modify user account
    lock                Lock user account (disable login)
    unlock              Unlock user account
    list                List user accounts

  ${CYAN}Password Management:${NC}
    password reset      Reset user password
    password expire     Force password change on next login
    password generate   Generate random password
    password policy     Show password policy settings

  ${CYAN}Group Management:${NC}
    group create        Create new group
    group add           Add user to group
    group remove        Remove user from group
    group list          List group members
    group show          Show user's groups

  ${CYAN}Permission Management:${NC}
    permission set      Set file/folder permissions
    permission get      Show current permissions
    permission template Apply permission template

  ${CYAN}SSH Key Management:${NC}
    ssh generate        Generate SSH key pair for user
    ssh add             Add public key to authorized_keys
    ssh remove          Remove key from authorized_keys
    ssh list            List authorized keys
    ssh copy            Copy keys from another user
    ssh validate        Validate authorized_keys file
    ssh fix             Fix SSH directory permissions

  ${CYAN}Session & Monitoring:${NC}
    session list        List active user sessions
    session history     Show login history
    session failures    Show failed login attempts
    session kill        Kill user session

  ${CYAN}Audit & Reporting:${NC}
    audit               Run comprehensive user audit
    report              Generate user report

${BOLD}Global Options:${NC}
    -h, --help          Display this help message
    -v, --verbose       Enable verbose output
    -i, --interactive   Run in interactive mode
    --no-interactive    Disable interactive mode
    -y, --yes           Auto-confirm all prompts
    -d, --dry-run       Show what would be done

${BOLD}Examples:${NC}

    ${DIM}# Create user with home directory${NC}
    sudo $0 create -u john -c "John Doe" -s /bin/bash

    ${DIM}# Create user and add to groups${NC}
    sudo $0 create -u jane -g sudo,docker

    ${DIM}# Delete user and remove home${NC}
    sudo $0 delete -u john --remove-home

    ${DIM}# Reset password (interactive)${NC}
    sudo $0 password reset -u john

    ${DIM}# Generate and set random password${NC}
    sudo $0 password generate -u jane --set

    ${DIM}# Add user to group${NC}
    sudo $0 group add -u john -g docker

    ${DIM}# List active sessions${NC}
    $0 session list

    ${DIM}# Show login history${NC}
    $0 session history -u john

    ${DIM}# Set permissions${NC}
    sudo $0 permission set -p /var/www -m 755 -o www-data:www-data -R

    ${DIM}# Run user audit${NC}
    sudo $0 audit

${BOLD}Documentation:${NC}
    $SCRIPT_URL

EOF
    exit 0
}

usage_create() {
    cat << EOF
${BOLD}Create User Account${NC}

${YELLOW}Usage:${NC}
    $0 create [OPTIONS]

${BOLD}Options:${NC}
    -u, --username USER     Username (required)
    -c, --comment TEXT      Full name or comment
    -s, --shell SHELL       Login shell (default: /bin/bash)
    -h, --home PATH         Home directory path
    --uid UID               User ID
    --gid GID               Primary group ID
    -g, --groups GROUPS     Additional groups (comma-separated)
    --no-create-home        Don't create home directory
    -p, --password PASS     Set password (use --generate for random)
    --generate              Generate random password
    --force-change          Force password change on first login

${BOLD}Examples:${NC}
    $0 create -u john -c "John Doe"
    $0 create -u jane -s /bin/zsh -g sudo,docker
    $0 create -u admin --generate --force-change
EOF
    exit 0
}

# =============================================================================
# Permission Checks
# =============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This operation requires root privileges"
        log_info "Please run with sudo: sudo $0 $*"
        exit 3
    fi
}

# =============================================================================
# Subcommand: Create User
# =============================================================================

cmd_create() {
    parse_create_args "$@"

    if [[ -z "$USERNAME" ]]; then
        log_error "Username is required"
        log_info "Use: $0 create -u USERNAME"
        exit 2
    fi

    check_root "$@"

    print_header "Create User: $USERNAME"

    # Check if user exists
    if user_exists "$USERNAME"; then
        log_error "User '$USERNAME' already exists"
        exit 1
    fi

    # Build user creation options
    local user_opts=()
    [[ -n "$USER_UID" ]] && user_opts+=(--uid "$USER_UID")
    [[ -n "$USER_GID" ]] && user_opts+=(--gid "$USER_GID")
    [[ -n "$USER_HOME" ]] && user_opts+=(--home "$USER_HOME")
    [[ -n "$USER_SHELL" ]] && user_opts+=(--shell "$USER_SHELL")
    [[ -n "$USER_COMMENT" ]] && user_opts+=(--comment "$USER_COMMENT")
    [[ "$CREATE_HOME" == "false" ]] && user_opts+=(--no-create-home)

    log_info "Creating user '$USERNAME'..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create user: $USERNAME"
        [[ -n "$USER_COMMENT" ]] && log_info "  Comment: $USER_COMMENT"
        [[ -n "$USER_SHELL" ]] && log_info "  Shell: $USER_SHELL"
        [[ -n "$USER_HOME" ]] && log_info "  Home: $USER_HOME"
        [[ ${#USER_GROUPS[@]} -gt 0 ]] && log_info "  Groups: ${USER_GROUPS[*]}"
        return 0
    fi

    # Create user
    if user_create "$USERNAME" "${user_opts[@]}"; then
        log_ok "User '$USERNAME' created successfully"
    else
        log_error "Failed to create user '$USERNAME'"
        exit 1
    fi

    # Add to additional groups
    if [[ ${#USER_GROUPS[@]} -gt 0 ]]; then
        log_info "Adding user to groups..."
        for group in "${USER_GROUPS[@]}"; do
            if group_exists "$group"; then
                if group_add_member "$group" "$USERNAME"; then
                    log_ok "Added to group: $group"
                else
                    log_warn "Failed to add to group: $group"
                fi
            else
                log_warn "Group '$group' does not exist, skipping"
            fi
        done
    fi

    # Set password
    if [[ -n "$PASSWORD" ]]; then
        log_info "Setting password..."
        if password_set_string "$USERNAME" "$PASSWORD"; then
            log_ok "Password set successfully"
            [[ "$VERBOSE" == "true" ]] && echo "Password: $PASSWORD"
        else
            log_warn "Failed to set password"
        fi
    elif [[ "$PASSWORD_LENGTH" -gt 0 ]]; then
        local generated_pass
        generated_pass=$(password_generate "$PASSWORD_LENGTH")
        log_info "Generated password: ${BOLD}$generated_pass${NC}"

        if password_set_string "$USERNAME" "$generated_pass"; then
            log_ok "Password set successfully"
        else
            log_warn "Failed to set password"
        fi

        PASSWORD="$generated_pass"
    fi

    # Force password change
    if [[ "$FORCE_CHANGE" == "true" && -n "$PASSWORD" ]]; then
        log_info "Setting password to expire on next login..."
        if password_expire_now "$USERNAME"; then
            log_ok "User must change password on first login"
        else
            log_warn "Failed to expire password"
        fi
    fi

    echo ""
    log_ok "User creation complete!"

    # Show summary
    local info
    info=$(user_get_info "$USERNAME")
    if [[ -n "$info" ]]; then
        IFS=':' read -r uid gid home shell <<< "$info"
        echo ""
        echo -e "${BOLD}User Details:${NC}"
        echo "  Username: $USERNAME"
        echo "  UID: $uid"
        echo "  GID: $gid"
        echo "  Home: $home"
        echo "  Shell: $shell"
        [[ ${#USER_GROUPS[@]} -gt 0 ]] && echo "  Groups: ${USER_GROUPS[*]}"
        [[ -n "$PASSWORD" ]] && echo "  Password: $PASSWORD"
    fi
}

parse_create_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage_create ;;
            -u|--username) USERNAME="$2"; shift 2 ;;
            -c|--comment) USER_COMMENT="$2"; shift 2 ;;
            -s|--shell) USER_SHELL="$2"; shift 2 ;;
            --home) USER_HOME="$2"; shift 2 ;;
            --uid) USER_UID="$2"; shift 2 ;;
            --gid) USER_GID="$2"; shift 2 ;;
            -g|--groups) IFS=',' read -ra USER_GROUPS <<< "$2"; shift 2 ;;
            --no-create-home) CREATE_HOME=false; shift ;;
            -p|--password) PASSWORD="$2"; shift 2 ;;
            --generate) PASSWORD_LENGTH=16; shift ;;
            --force-change) FORCE_CHANGE=true; shift ;;
            *) shift ;;
        esac
    done
}

# =============================================================================
# Subcommand: Delete User
# =============================================================================

cmd_delete() {
    local remove_home=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage_delete ;;
            -u|--username) USERNAME="$2"; shift 2 ;;
            --remove-home) remove_home=true; shift ;;
            *) shift ;;
        esac
    done

    if [[ -z "$USERNAME" ]]; then
        log_error "Username is required"
        exit 2
    fi

    check_root "$@"

    print_header "Delete User: $USERNAME"

    if ! user_exists "$USERNAME"; then
        log_error "User '$USERNAME' does not exist"
        exit 1
    fi

    # Safety check
    if [[ "$USERNAME" == "root" ]]; then
        log_error "Cannot delete root user"
        exit 1
    fi

    # Confirmation
    if [[ "$RSR_YES" != "1" && "$DRY_RUN" != "true" ]]; then
        echo -e "${YELLOW}WARNING: This will delete user '$USERNAME'${NC}"
        [[ "$remove_home" == "true" ]] && echo -e "${YELLOW}  Home directory will also be removed${NC}"
        read -p "Are you sure? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            log_info "Cancelled"
            exit 0
        fi
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete user: $USERNAME"
        [[ "$remove_home" == "true" ]] && log_info "  Would remove home directory"
        return 0
    fi

    log_info "Deleting user '$USERNAME'..."

    local opts=()
    [[ "$remove_home" == "true" ]] && opts+=(--remove-home)

    if user_delete "$USERNAME" "${opts[@]}"; then
        log_ok "User '$USERNAME' deleted successfully"
    else
        log_error "Failed to delete user '$USERNAME'"
        exit 1
    fi
}

# =============================================================================
# Subcommand: Lock/Unlock User
# =============================================================================

cmd_lock() {
    parse_username_arg "$@"
    check_root "$@"

    print_header "Lock User: $USERNAME"

    if ! user_exists "$USERNAME"; then
        log_error "User '$USERNAME' does not exist"
        exit 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would lock user: $USERNAME"
        return 0
    fi

    if user_lock "$USERNAME"; then
        log_ok "User '$USERNAME' locked successfully"
    else
        log_error "Failed to lock user '$USERNAME'"
        exit 1
    fi
}

cmd_unlock() {
    parse_username_arg "$@"
    check_root "$@"

    print_header "Unlock User: $USERNAME"

    if ! user_exists "$USERNAME"; then
        log_error "User '$USERNAME' does not exist"
        exit 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would unlock user: $USERNAME"
        return 0
    fi

    if user_unlock "$USERNAME"; then
        log_ok "User '$USERNAME' unlocked successfully"
    else
        log_error "Failed to unlock user '$USERNAME'"
        exit 1
    fi
}

# =============================================================================
# Subcommand: List Users
# =============================================================================

cmd_list() {
    local show_all=false
    local show_sudo=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage_list ;;
            -a|--all) show_all=true; shift ;;
            --sudo) show_sudo=true; shift ;;
            *) shift ;;
        esac
    done

    print_header "User Accounts"

    printf "${BOLD}%-15s %-6s %-6s %-20s %-30s %s${NC}\n" \
        "USERNAME" "UID" "GID" "SHELL" "HOME" "SUDO"
    echo "────────────────────────────────────────────────────────────────────────────────────────"

    local users
    if [[ "$show_all" == "true" ]]; then
        users=$(user_list_all)
    else
        users=$(user_list_humans)
    fi

    while IFS= read -r username; do
        [[ -z "$username" ]] && continue

        local info
        info=$(user_get_info "$username")
        [[ -z "$info" ]] && continue

        IFS=':' read -r uid gid home shell <<< "$info"

        local sudo_marker=""
        if user_has_sudo "$username"; then
            sudo_marker="${GREEN}✓${NC}"
        else
            [[ "$show_sudo" == "true" ]] && continue
        fi

        printf "%-15s %-6s %-6s %-20s %-30s %b\n" \
            "$username" "$uid" "$gid" "$shell" "$home" "$sudo_marker"
    done <<< "$users"
}

# =============================================================================
# Subcommand: Password Management
# =============================================================================

cmd_password() {
    local subcmd="${1:-}"
    shift || true

    case "$subcmd" in
        reset) cmd_password_reset "$@" ;;
        expire) cmd_password_expire "$@" ;;
        generate) cmd_password_generate "$@" ;;
        policy) cmd_password_policy "$@" ;;
        *) usage ;;
    esac
}

cmd_password_reset() {
    local set_password=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -u|--username) USERNAME="$2"; shift 2 ;;
            -p|--password) PASSWORD="$2"; set_password=true; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$USERNAME" ]]; then
        log_error "Username is required"
        exit 2
    fi

    check_root "$@"

    print_header "Reset Password: $USERNAME"

    if ! user_exists "$USERNAME"; then
        log_error "User '$USERNAME' does not exist"
        exit 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would reset password for: $USERNAME"
        return 0
    fi

    if [[ "$set_password" == "true" ]]; then
        if password_set_string "$USERNAME" "$PASSWORD"; then
            log_ok "Password reset successfully"
        else
            log_error "Failed to reset password"
            exit 1
        fi
    else
        log_info "Enter new password for '$USERNAME':"
        if password_set "$USERNAME"; then
            log_ok "Password reset successfully"
        else
            log_error "Failed to reset password"
            exit 1
        fi
    fi
}

cmd_password_expire() {
    parse_username_arg "$@"
    check_root "$@"

    print_header "Expire Password: $USERNAME"

    if ! user_exists "$USERNAME"; then
        log_error "User '$USERNAME' does not exist"
        exit 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would expire password for: $USERNAME"
        return 0
    fi

    if password_expire_now "$USERNAME"; then
        log_ok "Password expired - user must change on next login"
    else
        log_error "Failed to expire password"
        exit 1
    fi
}

cmd_password_generate() {
    local length=16
    local set_generated=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -u|--username) USERNAME="$2"; shift 2 ;;
            -l|--length) length="$2"; shift 2 ;;
            --set) set_generated=true; shift ;;
            *) shift ;;
        esac
    done

    local password
    password=$(password_generate "$length")

    print_header "Generate Password"
    echo -e "${BOLD}Generated Password:${NC} $password"
    echo ""

    if [[ "$set_generated" == "true" && -n "$USERNAME" ]]; then
        check_root "$@"

        if ! user_exists "$USERNAME"; then
            log_error "User '$USERNAME' does not exist"
            exit 1
        fi

        if [[ "$DRY_RUN" != "true" ]]; then
            if password_set_string "$USERNAME" "$password"; then
                log_ok "Password set for user '$USERNAME'"
            else
                log_error "Failed to set password"
                exit 1
            fi
        fi
    fi
}

cmd_password_policy() {
    parse_username_arg "$@"

    print_header "Password Policy"

    if [[ -n "$USERNAME" ]]; then
        if ! user_exists "$USERNAME"; then
            log_error "User '$USERNAME' does not exist"
            exit 1
        fi

        log_info "Password policy for '$USERNAME':"
        password_get_expiry "$USERNAME" || log_warn "Password policy info not available"
    else
        log_info "System password policy:"

        case "$(uname -s)" in
            Darwin)
                pwpolicy -getaccountpolicies 2>/dev/null || \
                    log_warn "Password policy not available"
                ;;
            Linux)
                if [[ -f /etc/login.defs ]]; then
                    echo ""
                    grep -E "^PASS_" /etc/login.defs
                fi

                if [[ -f /etc/security/pwquality.conf ]]; then
                    echo ""
                    grep -v "^#" /etc/security/pwquality.conf | grep -v "^$"
                fi
                ;;
        esac
    fi
}

# =============================================================================
# Subcommand: Group Management
# =============================================================================

cmd_group() {
    local subcmd="${1:-}"
    shift || true

    case "$subcmd" in
        create) cmd_group_create "$@" ;;
        add) cmd_group_add "$@" ;;
        remove) cmd_group_remove "$@" ;;
        list) cmd_group_list "$@" ;;
        show) cmd_group_show "$@" ;;
        *) usage ;;
    esac
}

cmd_group_create() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -g|--group) GROUPNAME="$2"; shift 2 ;;
            --gid) GROUP_GID="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$GROUPNAME" ]]; then
        log_error "Group name is required"
        exit 2
    fi

    check_root "$@"

    print_header "Create Group: $GROUPNAME"

    if group_exists "$GROUPNAME"; then
        log_error "Group '$GROUPNAME' already exists"
        exit 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create group: $GROUPNAME"
        return 0
    fi

    local opts=()
    [[ -n "$GROUP_GID" ]] && opts+=(--gid "$GROUP_GID")

    if group_create "$GROUPNAME" "${opts[@]}"; then
        log_ok "Group '$GROUPNAME' created successfully"
    else
        log_error "Failed to create group"
        exit 1
    fi
}

cmd_group_add() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -u|--username) USERNAME="$2"; shift 2 ;;
            -g|--group) GROUPNAME="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$USERNAME" || -z "$GROUPNAME" ]]; then
        log_error "Username and group name are required"
        exit 2
    fi

    check_root "$@"

    print_header "Add User to Group"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would add '$USERNAME' to group '$GROUPNAME'"
        return 0
    fi

    if group_add_member "$GROUPNAME" "$USERNAME"; then
        log_ok "User '$USERNAME' added to group '$GROUPNAME'"
    else
        log_error "Failed to add user to group"
        exit 1
    fi
}

cmd_group_remove() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -u|--username) USERNAME="$2"; shift 2 ;;
            -g|--group) GROUPNAME="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$USERNAME" || -z "$GROUPNAME" ]]; then
        log_error "Username and group name are required"
        exit 2
    fi

    check_root "$@"

    print_header "Remove User from Group"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would remove '$USERNAME' from group '$GROUPNAME'"
        return 0
    fi

    if group_remove_member "$GROUPNAME" "$USERNAME"; then
        log_ok "User '$USERNAME' removed from group '$GROUPNAME'"
    else
        log_error "Failed to remove user from group"
        exit 1
    fi
}

cmd_group_list() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -g|--group) GROUPNAME="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$GROUPNAME" ]]; then
        log_error "Group name is required"
        exit 2
    fi

    print_header "Group Members: $GROUPNAME"

    if ! group_exists "$GROUPNAME"; then
        log_error "Group '$GROUPNAME' does not exist"
        exit 1
    fi

    local members
    members=$(group_list_members "$GROUPNAME")

    if [[ -n "$members" ]]; then
        echo "$members" | while read -r member; do
            [[ -n "$member" ]] && echo "  • $member"
        done
    else
        log_info "No members in group '$GROUPNAME'"
    fi
}

cmd_group_show() {
    parse_username_arg "$@"

    if [[ -z "$USERNAME" ]]; then
        log_error "Username is required"
        exit 2
    fi

    print_header "Groups for User: $USERNAME"

    if ! user_exists "$USERNAME"; then
        log_error "User '$USERNAME' does not exist"
        exit 1
    fi

    local groups_output
    groups_output=$(groups "$USERNAME" 2>/dev/null)

    echo "$groups_output"
}

# =============================================================================
# Subcommand: Permission Management
# =============================================================================

cmd_permission() {
    local subcmd="${1:-}"
    shift || true

    case "$subcmd" in
        set) cmd_permission_set "$@" ;;
        get) cmd_permission_get "$@" ;;
        template) cmd_permission_template "$@" ;;
        *) usage ;;
    esac
}

cmd_permission_set() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--path) PERMISSION_PATH="$2"; shift 2 ;;
            -m|--mode) PERMISSION_MODE="$2"; shift 2 ;;
            -o|--owner) PERMISSION_OWNER="$2"; shift 2 ;;
            -R|--recursive) PERMISSION_RECURSIVE=true; shift ;;
            *) shift ;;
        esac
    done

    if [[ -z "$PERMISSION_PATH" || -z "$PERMISSION_MODE" ]]; then
        log_error "Path and mode are required"
        exit 2
    fi

    check_root "$@"

    print_header "Set Permissions"

    if [[ ! -e "$PERMISSION_PATH" ]]; then
        log_error "Path '$PERMISSION_PATH' does not exist"
        exit 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would set permissions on: $PERMISSION_PATH"
        log_info "  Mode: $PERMISSION_MODE"
        [[ -n "$PERMISSION_OWNER" ]] && log_info "  Owner: $PERMISSION_OWNER"
        [[ "$PERMISSION_RECURSIVE" == "true" ]] && log_info "  Recursive: yes"
        return 0
    fi

    if [[ "$PERMISSION_RECURSIVE" == "true" ]]; then
        if permission_set_recursive "$PERMISSION_PATH" "$PERMISSION_MODE" "$PERMISSION_OWNER"; then
            log_ok "Permissions set recursively on '$PERMISSION_PATH'"
        else
            log_error "Failed to set permissions"
            exit 1
        fi
    else
        if permission_set "$PERMISSION_PATH" "$PERMISSION_MODE" "$PERMISSION_OWNER"; then
            log_ok "Permissions set on '$PERMISSION_PATH'"
        else
            log_error "Failed to set permissions"
            exit 1
        fi
    fi
}

cmd_permission_get() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--path) PERMISSION_PATH="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$PERMISSION_PATH" ]]; then
        log_error "Path is required"
        exit 2
    fi

    print_header "Permissions: $PERMISSION_PATH"

    if [[ ! -e "$PERMISSION_PATH" ]]; then
        log_error "Path '$PERMISSION_PATH' does not exist"
        exit 1
    fi

    ls -ld "$PERMISSION_PATH"
}

cmd_permission_template() {
    local template=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--path) PERMISSION_PATH="$2"; shift 2 ;;
            -t|--template) template="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$PERMISSION_PATH" || -z "$template" ]]; then
        log_error "Path and template are required"
        log_info "Available templates: web, shared, private, service"
        exit 2
    fi

    check_root "$@"

    print_header "Apply Permission Template: $template"

    case "$template" in
        web)
            PERMISSION_MODE="755"
            PERMISSION_OWNER="www-data:www-data"
            log_info "Web server template: 755, www-data:www-data"
            ;;
        shared)
            PERMISSION_MODE="775"
            log_info "Shared directory template: 775"
            ;;
        private)
            PERMISSION_MODE="700"
            log_info "Private directory template: 700"
            ;;
        service)
            PERMISSION_MODE="644"
            log_info "Service file template: 644"
            ;;
        *)
            log_error "Unknown template: $template"
            exit 2
            ;;
    esac

    PERMISSION_RECURSIVE=true
    cmd_permission_set -p "$PERMISSION_PATH" -m "$PERMISSION_MODE" -o "$PERMISSION_OWNER" -R
}

# =============================================================================
# Subcommand: SSH Key Management
# =============================================================================

cmd_ssh() {
    local subcmd="${1:-}"
    shift || true

    case "$subcmd" in
        generate) cmd_ssh_generate "$@" ;;
        add) cmd_ssh_add "$@" ;;
        remove) cmd_ssh_remove "$@" ;;
        list) cmd_ssh_list "$@" ;;
        copy) cmd_ssh_copy "$@" ;;
        validate) cmd_ssh_validate "$@" ;;
        fix) cmd_ssh_fix "$@" ;;
        *) usage ;;
    esac
}

cmd_ssh_generate() {
    local key_type="ed25519"         # Default to ed25519 (recommended)
    local purpose="default"          # Default purpose
    local key_bits="4096"            # Only used for RSA keys
    local rounds="100"               # KDF rounds for ed25519/ecdsa
    local comment=""
    local passphrase=""
    local generate_passphrase=false
    local passphrase_length="24"
    local encrypt_with_sops=false
    local sops_age=""
    local output_passphrase=false
    local key_file=""
    local hostname_override=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -u|--username) USERNAME="$2"; shift 2 ;;
            -t|--type) key_type="$2"; shift 2 ;;
            -p|--purpose) purpose="$2"; shift 2 ;;
            -b|--bits) key_bits="$2"; shift 2 ;;
            -a|--rounds) rounds="$2"; shift 2 ;;
            -c|--comment) comment="$2"; shift 2 ;;
            -P|--passphrase) passphrase="$2"; shift 2 ;;
            -G|--generate-passphrase) generate_passphrase=true; shift ;;
            -L|--passphrase-length) passphrase_length="$2"; shift 2 ;;
            -S|--sops) encrypt_with_sops=true; shift ;;
            --sops-age) sops_age="$2"; shift 2 ;;
            -O|--output-passphrase) output_passphrase=true; shift ;;
            -f|--file) key_file="$2"; shift 2 ;;
            -H|--hostname) hostname_override="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$USERNAME" ]]; then
        log_error "Username is required"
        echo ""
        echo "Usage: ssh generate -u USERNAME [OPTIONS]"
        echo ""
        echo "Key Options:"
        echo "  -u, --username              Username (required)"
        echo "  -t, --type TYPE             Key type: ed25519 (default), ecdsa, rsa, dsa"
        echo "  -p, --purpose PURPOSE       Key purpose/label (default: 'default')"
        echo "                              Creates: id_<type>_<purpose>"
        echo "  -a, --rounds NUM            KDF rounds for ed25519/ecdsa (default: 100)"
        echo "  -b, --bits NUM              Bit size for RSA keys (default: 4096)"
        echo "  -c, --comment TEXT          Custom comment (auto-generated if not set)"
        echo ""
        echo "Passphrase Options:"
        echo "  -P, --passphrase TEXT       Manual passphrase"
        echo "  -G, --generate-passphrase   Auto-generate random passphrase"
        echo "  -L, --passphrase-length NUM Length of generated passphrase (default: 24)"
        echo "  -S, --sops                  Encrypt passphrase with SOPS"
        echo "  --sops-age KEY              Age public key for SOPS encryption"
        echo "  -O, --output-passphrase     Display generated passphrase"
        echo ""
        echo "Override Options:"
        echo "  -f, --file PATH             Override key file path"
        echo "  -H, --hostname NAME         Override hostname in comment"
        echo ""
        echo "Examples:"
        echo "  ssh generate -u john -p github"
        echo "  ssh generate -u john -t rsa -p legacy -b 4096"
        echo "  ssh generate -u john -p prod -G -S"
        echo "  ssh generate -u john -p work -G -O"
        echo "  ssh generate -u john -p github -H webserver01"
        exit 2
    fi

    check_root "$@"

    print_header "Generate SSH Key: $USERNAME"

    if ! user_exists "$USERNAME"; then
        log_error "User '$USERNAME' does not exist"
        exit 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would generate $key_type SSH key for: $USERNAME (purpose: $purpose)"
        [ "$generate_passphrase" = true ] && log_info "[DRY RUN] Would generate passphrase ($passphrase_length chars)"
        [ "$encrypt_with_sops" = true ] && log_info "[DRY RUN] Would encrypt passphrase with SOPS"
        return 0
    fi

    log_info "Generating $key_type SSH key pair..."
    echo "  Purpose: $purpose"
    if [[ "$key_type" == "ed25519" || "$key_type" == "ecdsa" ]]; then
        echo "  KDF rounds: $rounds"
    elif [[ "$key_type" == "rsa" ]]; then
        echo "  Key size: $key_bits bits"
    fi
    if [ "$generate_passphrase" = true ]; then
        echo "  Passphrase: Auto-generated ($passphrase_length chars)"
    elif [ -n "$passphrase" ]; then
        echo "  Passphrase: Manual"
    else
        echo "  ${YELLOW}Passphrase: None (unencrypted key)${NC}"
    fi
    [ "$encrypt_with_sops" = true ] && echo "  SOPS: Enabled"
    echo ""

    # Build options array
    local opts=("--type" "$key_type" "--purpose" "$purpose")
    [[ "$key_type" == "ed25519" || "$key_type" == "ecdsa" ]] && opts+=("--rounds" "$rounds")
    [[ "$key_type" == "rsa" || "$key_type" == "dsa" ]] && opts+=("--bits" "$key_bits")
    [[ -n "$comment" ]] && opts+=("--comment" "$comment")
    [[ -n "$passphrase" ]] && opts+=("--passphrase" "$passphrase")
    [[ "$generate_passphrase" = true ]] && opts+=("--generate-passphrase" "--passphrase-length" "$passphrase_length")
    [[ "$encrypt_with_sops" = true ]] && opts+=("--sops")
    [[ -n "$sops_age" ]] && opts+=("--sops-age" "$sops_age")
    [[ "$output_passphrase" = true ]] && opts+=("--output-passphrase")
    [[ -n "$key_file" ]] && opts+=("--file" "$key_file")
    [[ -n "$hostname_override" ]] && opts+=("--hostname" "$hostname_override")

    local key_file_result
    if key_file_result=$(ssh_generate_key "$USERNAME" "${opts[@]}"); then
        log_ok "SSH key generated successfully"
        echo ""
        echo -e "  ${CYAN}Private key:${NC} $key_file_result"
        echo -e "  ${CYAN}Public key:${NC}  ${key_file_result}.pub"

        # Check for passphrase files
        if [ -f "${key_file_result}.passphrase.enc" ]; then
            echo -e "  ${GREEN}Passphrase (encrypted):${NC} ${key_file_result}.passphrase.enc"
            echo ""
            echo -e "  ${GRAY}To decrypt passphrase: sops --decrypt ${key_file_result}.passphrase.enc${NC}"
        elif [ -f "${key_file_result}.passphrase" ]; then
            echo -e "  ${YELLOW}Passphrase (unencrypted):${NC} ${key_file_result}.passphrase"
            echo ""
            echo -e "  ${RED}⚠ WARNING: Passphrase file is unencrypted!${NC}"
        fi

        echo ""
        echo -e "${YELLOW}Public key content (copy this to remote servers):${NC}"
        cat "${key_file_result}.pub"
    else
        log_error "Failed to generate SSH key"
        exit 1
    fi
}

cmd_ssh_add() {
    local key_content=""
    local key_file=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -u|--username) USERNAME="$2"; shift 2 ;;
            -k|--key) key_content="$2"; shift 2 ;;
            -f|--file) key_file="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$USERNAME" ]]; then
        log_error "Username is required"
        exit 2
    fi

    if [[ -z "$key_content" && -z "$key_file" ]]; then
        log_error "Either --key or --file is required"
        exit 2
    fi

    check_root "$@"

    print_header "Add SSH Key: $USERNAME"

    if ! user_exists "$USERNAME"; then
        log_error "User '$USERNAME' does not exist"
        exit 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would add SSH key to authorized_keys for: $USERNAME"
        return 0
    fi

    if [[ -n "$key_file" ]]; then
        log_info "Adding key from file: $key_file"
        if ssh_add_key_file "$USERNAME" "$key_file"; then
            log_ok "SSH key added successfully"
        else
            log_error "Failed to add SSH key"
            exit 1
        fi
    else
        log_info "Adding SSH key..."
        if ssh_add_key "$USERNAME" "$key_content"; then
            log_ok "SSH key added successfully"
        else
            log_error "Failed to add SSH key"
            exit 1
        fi
    fi
}

cmd_ssh_remove() {
    local identifier=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -u|--username) USERNAME="$2"; shift 2 ;;
            -i|--identifier) identifier="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$USERNAME" ]]; then
        log_error "Username is required"
        exit 2
    fi

    if [[ -z "$identifier" ]]; then
        log_error "Key identifier is required (fingerprint, comment, or key part)"
        exit 2
    fi

    check_root "$@"

    print_header "Remove SSH Key: $USERNAME"

    if ! user_exists "$USERNAME"; then
        log_error "User '$USERNAME' does not exist"
        exit 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would remove SSH key matching: $identifier"
        return 0
    fi

    log_info "Removing SSH key..."
    if ssh_remove_key "$USERNAME" "$identifier"; then
        log_ok "SSH key removed successfully"
        log_info "Backup created: ~/.ssh/authorized_keys.backup"
    else
        log_error "Failed to remove SSH key"
        exit 1
    fi
}

cmd_ssh_list() {
    local show_fingerprints=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -u|--username) USERNAME="$2"; shift 2 ;;
            -f|--fingerprints) show_fingerprints=true; shift ;;
            *) shift ;;
        esac
    done

    if [[ -z "$USERNAME" ]]; then
        log_error "Username is required"
        exit 2
    fi

    print_header "SSH Keys: $USERNAME"

    if ! user_exists "$USERNAME"; then
        log_error "User '$USERNAME' does not exist"
        exit 1
    fi

    if [[ "$show_fingerprints" == "true" ]]; then
        log_info "Key fingerprints:"
        echo ""
        ssh_get_fingerprints "$USERNAME" || log_warn "No keys found"
    else
        local keys
        keys=$(ssh_list_keys "$USERNAME")
        if [[ -n "$keys" ]]; then
            echo "$keys"
        else
            log_info "No SSH keys found for user '$USERNAME'"
        fi
    fi
}

cmd_ssh_copy() {
    local source_user=""
    local dest_user=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|--source) source_user="$2"; shift 2 ;;
            -d|--dest) dest_user="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$source_user" || -z "$dest_user" ]]; then
        log_error "Both source and destination users are required"
        exit 2
    fi

    check_root "$@"

    print_header "Copy SSH Keys"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would copy SSH keys from '$source_user' to '$dest_user'"
        return 0
    fi

    log_info "Copying SSH keys from '$source_user' to '$dest_user'..."
    if ssh_copy_keys "$source_user" "$dest_user"; then
        log_ok "SSH keys copied successfully"
    else
        log_error "Failed to copy SSH keys"
        exit 1
    fi
}

cmd_ssh_validate() {
    parse_username_arg "$@"

    print_header "Validate SSH Keys: $USERNAME"

    if ! user_exists "$USERNAME"; then
        log_error "User '$USERNAME' does not exist"
        exit 1
    fi

    log_info "Validating authorized_keys..."
    echo ""

    if ssh_validate_keys "$USERNAME"; then
        log_ok "All SSH keys are valid"
    else
        log_warn "Some SSH keys are invalid"
        exit 1
    fi
}

cmd_ssh_fix() {
    parse_username_arg "$@"
    check_root "$@"

    print_header "Fix SSH Permissions: $USERNAME"

    if ! user_exists "$USERNAME"; then
        log_error "User '$USERNAME' does not exist"
        exit 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would fix SSH directory permissions for: $USERNAME"
        return 0
    fi

    log_info "Fixing SSH directory permissions..."
    if ssh_fix_permissions "$USERNAME"; then
        log_ok "SSH permissions fixed successfully"
    else
        log_error "Failed to fix SSH permissions"
        exit 1
    fi
}

# =============================================================================
# Subcommand: Session Management
# =============================================================================

cmd_session() {
    local subcmd="${1:-}"
    shift || true

    case "$subcmd" in
        list) cmd_session_list "$@" ;;
        history) cmd_session_history "$@" ;;
        failures) cmd_session_failures "$@" ;;
        *) usage ;;
    esac
}

cmd_session_list() {
    print_header "Active User Sessions"
    session_list_detailed
}

cmd_session_history() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -u|--username) SESSION_USERNAME="$2"; shift 2 ;;
            -n|--lines) SESSION_LINES="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    print_header "Login History"

    if [[ -n "$SESSION_USERNAME" ]]; then
        log_info "Showing history for user: $SESSION_USERNAME"
        login_history "$SESSION_USERNAME" "$SESSION_LINES"
    else
        login_history "" "$SESSION_LINES"
    fi
}

cmd_session_failures() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--lines) SESSION_LINES="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    print_header "Failed Login Attempts"

    login_failures "$SESSION_LINES" || log_warn "Failed login log not accessible"
}

# =============================================================================
# Subcommand: Audit
# =============================================================================

cmd_audit() {
    print_header "User Management Audit"

    log_info "Running comprehensive user audit..."

    if [[ -f "$SCRIPT_DIR/user-audit.sh" ]]; then
        bash "$SCRIPT_DIR/user-audit.sh" "$@"
    else
        log_warn "user-audit.sh not found, running basic audit"

        echo ""
        echo -e "${BOLD}User Accounts:${NC}"
        cmd_list --all

        echo ""
        echo -e "${BOLD}Active Sessions:${NC}"
        session_list

        echo ""
        echo -e "${BOLD}Recent Logins:${NC}"
        login_history "" 10
    fi
}

# =============================================================================
# Helper Functions
# =============================================================================

parse_username_arg() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -u|--username) USERNAME="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$USERNAME" ]]; then
        log_error "Username is required"
        exit 2
    fi
}

# =============================================================================
# Main Entry Point
# =============================================================================

main() {
    # Setup colors if from common.sh
    [[ "$(type -t setup_colors)" == "function" ]] && setup_colors

    # Parse global options first
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage ;;
            -v|--verbose) VERBOSE=true; shift ;;
            -d|--dry-run) DRY_RUN=true; shift ;;
            -i|--interactive) INTERACTIVE=true; shift ;;
            --no-interactive) INTERACTIVE=false; shift ;;
            -y|--yes) RSR_YES=1; shift ;;
            -*) shift ;; # Skip other flags for now
            *)
                SUBCOMMAND="$1"
                shift
                break
                ;;
        esac
    done

    # Show help if no subcommand
    if [[ -z "$SUBCOMMAND" ]]; then
        usage
    fi

    # Route to subcommand
    case "$SUBCOMMAND" in
        create) cmd_create "$@" ;;
        delete) cmd_delete "$@" ;;
        lock) cmd_lock "$@" ;;
        unlock) cmd_unlock "$@" ;;
        list) cmd_list "$@" ;;
        password) cmd_password "$@" ;;
        group) cmd_group "$@" ;;
        permission) cmd_permission "$@" ;;
        ssh) cmd_ssh "$@" ;;
        session) cmd_session "$@" ;;
        audit) cmd_audit "$@" ;;
        *)
            log_error "Unknown subcommand: $SUBCOMMAND"
            log_info "Run '$0 --help' for usage"
            exit 2
            ;;
    esac
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

