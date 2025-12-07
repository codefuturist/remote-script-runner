#!/bin/bash
# =============================================================================
# @id           update
# @name         system-update
# @displayName  System Update
# @description  Update system packages, security patches, and kernel
# @category     maintenance
# @version      1.0.0
# @author       codefuturist
# @tags         update,packages,security,patches,kernel,upgrade,maintenance
# @shells       bash
# =============================================================================

set -euo pipefail

# Script metadata
SCRIPT_NAME="System Update"
SCRIPT_VERSION="1.0.0"

# Default values
VERBOSE=false
CHECK_ONLY=false
LIST_UPDATES=false
INSTALL_ALL=false
SECURITY_ONLY=false
EXCLUDE_PACKAGES=()
SHOW_CHANGELOG=false
AUTO_YES=false
CHECK_REBOOT=false
REBOOT_IF_NEEDED=false
DRY_RUN=false
OUTPUT_FORMAT="text"

# Package manager detection
PKG_MANAGER=""
PKG_UPDATE_CMD=""
PKG_UPGRADE_CMD=""
PKG_LIST_CMD=""
PKG_SECURITY_CMD=""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# Exit codes
EXIT_OK=0
EXIT_ERROR=1
EXIT_INVALID_ARGS=2
EXIT_PERMISSION=3
EXIT_LOCKED=4
EXIT_DISK_SPACE=5
EXIT_UPDATE_FAILED=6
EXIT_REBOOT_REQUIRED=7
EXIT_NO_UPDATES=100

usage() {
    cat << EOF
${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}

Update system packages, security patches, and kernel.

${YELLOW}Usage:${NC}
    $0 [OPTIONS]

${BOLD}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -c, --check             Check for available updates only
    -l, --list              List available updates with details
    -a, --all               Install all available updates
    --security              Install security updates only
    -e, --exclude PKG       Exclude package(s) from update (repeatable)
    --changelog             Show changelog for updates
    -y, --yes               Automatic yes to prompts
    --reboot-required       Check if reboot is needed
    --reboot-if-needed      Auto reboot if needed (requires --yes)
    -d, --dry-run           Show what would be updated
    --json                  Output in JSON format

${BOLD}Supported Package Managers:${NC}
    apt (Debian/Ubuntu), yum/dnf (RHEL/CentOS/Fedora),
    pacman (Arch), zypper (openSUSE), apk (Alpine)

${BOLD}Examples:${NC}
    ${DIM}# Check for updates${NC}
    $0 -c

    ${DIM}# List available updates${NC}
    $0 -l

    ${DIM}# Dry run full update${NC}
    $0 -a -d

    ${DIM}# Install all updates non-interactive${NC}
    sudo $0 -a -y

    ${DIM}# Security updates only${NC}
    sudo $0 --security -y

    ${DIM}# Check if reboot needed${NC}
    $0 --reboot-required

    ${DIM}# Update all except nginx${NC}
    sudo $0 -a -e nginx

${BOLD}Exit Codes:${NC}
    0   - Updates completed successfully
    1   - General error
    2   - Invalid arguments
    3   - Permission denied (need root)
    4   - Package manager locked
    5   - Insufficient disk space
    6   - Update failed
    7   - Reboot required (after successful update)
    100 - No updates available

EOF
    exit 0
}

log_info() { echo -e "${BLUE}▸${NC} $1"; }
log_ok() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1" >&2; }
log_debug() { [[ "$VERBOSE" == "true" ]] && echo -e "${DIM}  $1${NC}"; }

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help) usage ;;
            -v | --verbose)
                VERBOSE=true
                shift
                ;;
            -c | --check)
                CHECK_ONLY=true
                shift
                ;;
            -l | --list)
                LIST_UPDATES=true
                shift
                ;;
            -a | --all)
                INSTALL_ALL=true
                shift
                ;;
            --security)
                SECURITY_ONLY=true
                shift
                ;;
            -e | --exclude)
                EXCLUDE_PACKAGES+=("$2")
                shift 2
                ;;
            --changelog)
                SHOW_CHANGELOG=true
                shift
                ;;
            -y | --yes)
                AUTO_YES=true
                shift
                ;;
            --reboot-required)
                CHECK_REBOOT=true
                shift
                ;;
            --reboot-if-needed)
                REBOOT_IF_NEEDED=true
                shift
                ;;
            -d | --dry-run)
                DRY_RUN=true
                shift
                ;;
            --json)
                OUTPUT_FORMAT="json"
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

# Detect package manager
detect_pkg_manager() {
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt"
        PKG_UPDATE_CMD="apt-get update"
        PKG_UPGRADE_CMD="apt-get upgrade"
        PKG_LIST_CMD="apt list --upgradable"
        PKG_SECURITY_CMD="apt-get upgrade -s | grep -i security"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        PKG_UPDATE_CMD="dnf check-update"
        PKG_UPGRADE_CMD="dnf upgrade"
        PKG_LIST_CMD="dnf check-update"
        PKG_SECURITY_CMD="dnf upgrade --security"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        PKG_UPDATE_CMD="yum check-update"
        PKG_UPGRADE_CMD="yum update"
        PKG_LIST_CMD="yum check-update"
        PKG_SECURITY_CMD="yum update --security"
    elif command -v pacman &> /dev/null; then
        PKG_MANAGER="pacman"
        PKG_UPDATE_CMD="pacman -Sy"
        PKG_UPGRADE_CMD="pacman -Su"
        PKG_LIST_CMD="pacman -Qu"
        PKG_SECURITY_CMD="" # Arch doesn't separate security updates
    elif command -v zypper &> /dev/null; then
        PKG_MANAGER="zypper"
        PKG_UPDATE_CMD="zypper refresh"
        PKG_UPGRADE_CMD="zypper update"
        PKG_LIST_CMD="zypper list-updates"
        PKG_SECURITY_CMD="zypper patch --category security"
    elif command -v apk &> /dev/null; then
        PKG_MANAGER="apk"
        PKG_UPDATE_CMD="apk update"
        PKG_UPGRADE_CMD="apk upgrade"
        PKG_LIST_CMD="apk version -l '<'"
        PKG_SECURITY_CMD="" # Alpine doesn't separate security updates
    else
        log_error "No supported package manager found"
        exit $EXIT_ERROR
    fi

    log_debug "Detected package manager: $PKG_MANAGER"
}

# Check if package manager is locked
check_lock() {
    case "$PKG_MANAGER" in
        apt)
            if fuser /var/lib/dpkg/lock &> /dev/null || fuser /var/lib/apt/lists/lock &> /dev/null; then
                log_error "Package manager is locked. Another process is using apt."
                exit $EXIT_LOCKED
            fi
            ;;
        dnf | yum)
            if [[ -f /var/run/yum.pid ]]; then
                log_error "Package manager is locked. Another process is using yum/dnf."
                exit $EXIT_LOCKED
            fi
            ;;
        pacman)
            if [[ -f /var/lib/pacman/db.lck ]]; then
                log_error "Package manager is locked. Remove /var/lib/pacman/db.lck if no other pacman is running."
                exit $EXIT_LOCKED
            fi
            ;;
    esac
}

# Check disk space
check_disk_space() {
    local available
    available=$(df -P /var 2> /dev/null | tail -1 | awk '{print $4}')

    # Require at least 500MB
    if [[ -n "$available" && "$available" -lt 512000 ]]; then
        log_error "Insufficient disk space. Only $((available / 1024))MB available in /var"
        exit $EXIT_DISK_SPACE
    fi
}

# Refresh package lists
refresh_packages() {
    log_info "Refreshing package lists..."

    case "$PKG_MANAGER" in
        apt)
            apt-get update -qq 2>&1 || {
                log_error "Failed to update package lists"
                exit $EXIT_ERROR
            }
            ;;
        dnf)
            dnf makecache -q 2>&1 || true
            ;;
        yum)
            yum makecache -q 2>&1 || true
            ;;
        pacman)
            pacman -Sy --noconfirm 2>&1 || {
                log_error "Failed to sync package database"
                exit $EXIT_ERROR
            }
            ;;
        zypper)
            zypper refresh -q 2>&1 || true
            ;;
        apk)
            apk update -q 2>&1 || true
            ;;
    esac

    log_ok "Package lists updated"
}

# Count available updates
count_updates() {
    local count=0

    case "$PKG_MANAGER" in
        apt)
            count=$(apt list --upgradable 2> /dev/null | grep -c "upgradable" || echo "0")
            ;;
        dnf | yum)
            count=$($PKG_MANAGER check-update 2> /dev/null | grep -cE "^\S+\s+\S+\s+\S+" || echo "0")
            ;;
        pacman)
            count=$(pacman -Qu 2> /dev/null | wc -l || echo "0")
            ;;
        zypper)
            count=$(zypper list-updates 2> /dev/null | grep -cE "^\s*v\s*\|" || echo "0")
            ;;
        apk)
            count=$(apk version -l '<' 2> /dev/null | wc -l || echo "0")
            ;;
    esac

    echo "$count"
}

# List available updates
list_available_updates() {
    log_info "Checking for available updates..."

    local count
    count=$(count_updates)

    if [[ "$count" -eq 0 ]]; then
        log_ok "System is up to date"
        return 0
    fi

    echo ""
    echo -e "${BOLD}Available updates: $count${NC}"
    echo ""

    case "$PKG_MANAGER" in
        apt)
            apt list --upgradable 2> /dev/null | tail -n +2 | while read -r line; do
                local pkg current new
                pkg=$(echo "$line" | cut -d/ -f1)
                new=$(echo "$line" | awk '{print $2}')
                current=$(dpkg-query -W -f='${Version}' "$pkg" 2> /dev/null || echo "?")
                printf "  ${CYAN}%-30s${NC} %s → ${GREEN}%s${NC}\n" "$pkg" "$current" "$new"
            done
            ;;
        dnf | yum)
            $PKG_MANAGER check-update 2> /dev/null | grep -E "^\S+\s+\S+\s+\S+" | while read -r pkg ver repo; do
                printf "  ${CYAN}%-30s${NC} → ${GREEN}%s${NC} (%s)\n" "$pkg" "$ver" "$repo"
            done
            ;;
        pacman)
            pacman -Qu 2> /dev/null | while read -r pkg ver; do
                printf "  ${CYAN}%-30s${NC} → ${GREEN}%s${NC}\n" "$pkg" "$ver"
            done
            ;;
        zypper)
            zypper list-updates 2> /dev/null | grep -E "^\s*v\s*\|" | while IFS='|' read -r _ _ pkg _ cur new _; do
                pkg=$(echo "$pkg" | xargs)
                cur=$(echo "$cur" | xargs)
                new=$(echo "$new" | xargs)
                printf "  ${CYAN}%-30s${NC} %s → ${GREEN}%s${NC}\n" "$pkg" "$cur" "$new"
            done
            ;;
        apk)
            apk version -l '<' 2> /dev/null | while read -r pkg ver; do
                printf "  ${CYAN}%-30s${NC} %s\n" "$pkg" "$ver"
            done
            ;;
    esac

    echo ""
    return 0
}

# Check if security updates available
check_security_updates() {
    log_info "Checking for security updates..."

    local security_count=0

    case "$PKG_MANAGER" in
        apt)
            security_count=$(apt-get upgrade -s 2> /dev/null | grep -ci "security" || echo "0")
            ;;
        dnf)
            security_count=$(dnf updateinfo list --security 2> /dev/null | grep -cE "^\S+" || echo "0")
            ;;
        yum)
            security_count=$(yum updateinfo list security 2> /dev/null | grep -cE "^\S+" || echo "0")
            ;;
        zypper)
            security_count=$(zypper list-patches --category security 2> /dev/null | grep -cE "^\s*\|" || echo "0")
            ;;
        *)
            log_warn "Security update detection not supported for $PKG_MANAGER"
            return
            ;;
    esac

    if [[ "$security_count" -gt 0 ]]; then
        log_warn "$security_count security update(s) available"
    else
        log_ok "No security updates pending"
    fi
}

# Check if reboot is required
check_reboot_required() {
    local reboot_needed=false

    # Debian/Ubuntu
    if [[ -f /var/run/reboot-required ]]; then
        reboot_needed=true
        if [[ -f /var/run/reboot-required.pkgs ]]; then
            log_warn "Reboot required by packages:"
            cat /var/run/reboot-required.pkgs | while read -r pkg; do
                echo "    • $pkg"
            done
        else
            log_warn "Reboot required"
        fi
    fi

    # RHEL/CentOS
    if command -v needs-restarting &> /dev/null; then
        if needs-restarting -r &> /dev/null; then
            : # No reboot needed
        else
            reboot_needed=true
            log_warn "Reboot required (kernel or core libraries updated)"
        fi
    fi

    # Check running kernel vs installed
    if [[ -f /boot/vmlinuz-$(uname -r) ]]; then
        : # Current kernel exists
    else
        local latest_kernel
        latest_kernel=$(ls -t /boot/vmlinuz-* 2> /dev/null | head -1 || true)
        if [[ -n "$latest_kernel" ]]; then
            local running current
            running=$(uname -r)
            current=$(basename "$latest_kernel" | sed 's/vmlinuz-//')
            if [[ "$running" != "$current" ]]; then
                reboot_needed=true
                log_warn "New kernel available: $current (running: $running)"
            fi
        fi
    fi

    if [[ "$reboot_needed" == "false" ]]; then
        log_ok "No reboot required"
    fi

    return $([ "$reboot_needed" == "true" ] && echo 1 || echo 0)
}

# Build exclude arguments
build_exclude_args() {
    local args=""

    for pkg in "${EXCLUDE_PACKAGES[@]}"; do
        case "$PKG_MANAGER" in
            apt)
                args="$args --exclude=$pkg"
                ;;
            dnf | yum)
                args="$args --exclude=$pkg"
                ;;
            pacman)
                args="$args --ignore $pkg"
                ;;
            zypper)
                # Zypper uses locks for exclusion
                ;;
        esac
    done

    echo "$args"
}

# Perform update
perform_update() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Root access required for system updates"
        exit $EXIT_PERMISSION
    fi

    check_lock
    check_disk_space

    local count
    count=$(count_updates)

    if [[ "$count" -eq 0 ]]; then
        log_ok "System is already up to date"
        exit $EXIT_NO_UPDATES
    fi

    log_info "Preparing to update $count package(s)..."

    local exclude_args
    exclude_args=$(build_exclude_args)

    local confirm_flag=""
    if [[ "$AUTO_YES" == "true" ]]; then
        case "$PKG_MANAGER" in
            apt) confirm_flag="-y" ;;
            dnf | yum) confirm_flag="-y" ;;
            pacman) confirm_flag="--noconfirm" ;;
            zypper) confirm_flag="-y" ;;
            apk) confirm_flag="" ;; # apk doesn't need confirmation
        esac
    fi

    local dry_flag=""
    if [[ "$DRY_RUN" == "true" ]]; then
        case "$PKG_MANAGER" in
            apt) dry_flag="-s" ;;
            dnf | yum) dry_flag="--assumeno" ;;
            pacman) dry_flag="--print" ;;
            zypper) dry_flag="--dry-run" ;;
            apk) dry_flag="-s" ;;
        esac
        log_info "Dry run mode - no changes will be made"
    fi

    echo ""

    if [[ "$SECURITY_ONLY" == "true" ]]; then
        log_info "Installing security updates only..."
        case "$PKG_MANAGER" in
            apt)
                apt-get upgrade $confirm_flag $dry_flag $exclude_args -o Dir::Etc::SourceList=/etc/apt/sources.list \
                    -o Dir::Etc::SourceParts=/dev/null 2>&1 || exit $EXIT_UPDATE_FAILED
                ;;
            dnf)
                dnf upgrade --security $confirm_flag $dry_flag $exclude_args 2>&1 || exit $EXIT_UPDATE_FAILED
                ;;
            yum)
                yum update --security $confirm_flag $dry_flag $exclude_args 2>&1 || exit $EXIT_UPDATE_FAILED
                ;;
            zypper)
                zypper patch --category security $confirm_flag $dry_flag 2>&1 || exit $EXIT_UPDATE_FAILED
                ;;
            *)
                log_warn "Security-only updates not supported for $PKG_MANAGER, running full update"
                perform_full_update "$confirm_flag" "$dry_flag" "$exclude_args"
                ;;
        esac
    else
        perform_full_update "$confirm_flag" "$dry_flag" "$exclude_args"
    fi

    if [[ "$DRY_RUN" != "true" ]]; then
        echo ""
        log_ok "Update completed successfully"

        # Check if reboot is now required
        if check_reboot_required; then
            :
        else
            if [[ "$REBOOT_IF_NEEDED" == "true" && "$AUTO_YES" == "true" ]]; then
                log_warn "Rebooting system in 10 seconds..."
                sleep 10
                reboot
            fi
            exit $EXIT_REBOOT_REQUIRED
        fi
    fi
}

perform_full_update() {
    local confirm_flag="$1"
    local dry_flag="$2"
    local exclude_args="$3"

    case "$PKG_MANAGER" in
        apt)
            DEBIAN_FRONTEND=noninteractive apt-get upgrade $confirm_flag $dry_flag $exclude_args 2>&1 || exit $EXIT_UPDATE_FAILED
            ;;
        dnf)
            dnf upgrade $confirm_flag $dry_flag $exclude_args 2>&1 || exit $EXIT_UPDATE_FAILED
            ;;
        yum)
            yum update $confirm_flag $dry_flag $exclude_args 2>&1 || exit $EXIT_UPDATE_FAILED
            ;;
        pacman)
            pacman -Su $confirm_flag $dry_flag $exclude_args 2>&1 || exit $EXIT_UPDATE_FAILED
            ;;
        zypper)
            zypper update $confirm_flag $dry_flag 2>&1 || exit $EXIT_UPDATE_FAILED
            ;;
        apk)
            apk upgrade $dry_flag 2>&1 || exit $EXIT_UPDATE_FAILED
            ;;
    esac
}

# Show changelog for updates
show_changelog() {
    log_info "Fetching changelogs..."

    case "$PKG_MANAGER" in
        apt)
            apt list --upgradable 2> /dev/null | tail -n +2 | cut -d/ -f1 | while read -r pkg; do
                echo ""
                echo -e "${BOLD}=== $pkg ===${NC}"
                apt-get changelog "$pkg" 2> /dev/null | head -30 || echo "Changelog not available"
            done
            ;;
        dnf)
            dnf updateinfo list 2> /dev/null || echo "Changelog not available"
            ;;
        *)
            log_warn "Changelog viewing not supported for $PKG_MANAGER"
            ;;
    esac
}

# Main function
main() {
    parse_args "$@"

    echo -e "${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}"
    echo ""

    detect_pkg_manager

    # Refresh packages first (if we have permission)
    if [[ $EUID -eq 0 ]]; then
        refresh_packages
    fi

    # Handle check-only mode
    if [[ "$CHECK_ONLY" == "true" ]]; then
        local count
        count=$(count_updates)
        if [[ "$count" -eq 0 ]]; then
            log_ok "System is up to date"
            exit $EXIT_NO_UPDATES
        else
            log_warn "$count update(s) available"
            check_security_updates
            exit $EXIT_OK
        fi
    fi

    # Handle list mode
    if [[ "$LIST_UPDATES" == "true" ]]; then
        list_available_updates
        check_security_updates
        exit $EXIT_OK
    fi

    # Handle reboot check
    if [[ "$CHECK_REBOOT" == "true" ]]; then
        if check_reboot_required; then
            exit $EXIT_OK
        else
            exit $EXIT_REBOOT_REQUIRED
        fi
    fi

    # Handle changelog
    if [[ "$SHOW_CHANGELOG" == "true" ]]; then
        show_changelog
        exit $EXIT_OK
    fi

    # Handle update
    if [[ "$INSTALL_ALL" == "true" || "$SECURITY_ONLY" == "true" ]]; then
        perform_update
        exit $EXIT_OK
    fi

    # Default: show status and available updates
    list_available_updates
    check_security_updates

    local count
    count=$(count_updates)
    if [[ "$count" -gt 0 ]]; then
        echo ""
        log_info "Run with -a to install all updates, or --security for security updates only"
    fi
}

main "$@"
