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
    source "$RSR_LIB_DIR/rsr-lib.sh" validate
fi

# Script metadata
SCRIPT_NAME="System Update"
SCRIPT_VERSION="1.0.0"

# Default values
VERBOSE=false
INTERACTIVE=auto
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
INCLUDE_FLATPAK=false
INCLUDE_SNAP=false
INCLUDE_FIRMWARE=false
INCLUDE_LANGUAGE_PKGS=false
LANGUAGE_MANAGERS=()

# Package manager detection
PKG_MANAGER=""
PKG_UPDATE_CMD=""
PKG_UPGRADE_CMD=""
PKG_LIST_CMD=""
PKG_SECURITY_CMD=""

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
    -i, --interactive       Run in interactive mode (default when no args)
    --no-interactive        Disable interactive mode
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
    --flatpak               Include Flatpak updates
    --snap                  Include Snap updates
    --firmware              Include firmware updates (fwupd)
    --lang                  Include language package managers
    --lang-only MANAGER     Only update specific language manager (pip,npm,cargo,gem)

${BOLD}Supported Package Managers:${NC}
    apt (Debian/Ubuntu), yum/dnf (RHEL/CentOS/Fedora),
    pacman (Arch), zypper (openSUSE), apk (Alpine)

${BOLD}Extended Updates:${NC}
    Flatpak, Snap, Firmware (fwupd)
    Language Managers: pip, npm, cargo, gem

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

# Logging functions (use RSR if available)
if type rsr_log_info &> /dev/null; then
    log_info() { rsr_log_info "$1"; }
    log_ok() { rsr_log_ok "$1"; }
    log_warn() { rsr_log_warn "$1"; }
    log_error() { rsr_log_error "$1"; }
    log_debug() { [[ "$VERBOSE" == "true" ]] && rsr_log_debug "$1"; }
else
    log_info() { echo -e "${BLUE}▸${NC} $1"; }
    log_ok() { echo -e "${GREEN}✓${NC} $1"; }
    log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
    log_error() { echo -e "${RED}✗${NC} $1" >&2; }
    log_debug() { [[ "$VERBOSE" == "true" ]] && echo -e "${DIM}  $1${NC}"; }
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
            -i | --interactive)
                INTERACTIVE=true
                shift
                ;;
            --no-interactive)
                INTERACTIVE=false
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
            --flatpak)
                INCLUDE_FLATPAK=true
                shift
                ;;
            --snap)
                INCLUDE_SNAP=true
                shift
                ;;
            --firmware)
                INCLUDE_FIRMWARE=true
                shift
                ;;
            --lang)
                INCLUDE_LANGUAGE_PKGS=true
                shift
                ;;
            --lang-only)
                LANGUAGE_MANAGERS+=("$2")
                shift 2
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
            while read -r pkg; do
                echo "    • $pkg"
            done < /var/run/reboot-required.pkgs
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

    # Extended updates
    if [[ "$INCLUDE_FLATPAK" == "true" ]]; then
        echo ""
        update_flatpak
    fi

    if [[ "$INCLUDE_SNAP" == "true" ]]; then
        echo ""
        update_snap
    fi

    if [[ "$INCLUDE_FIRMWARE" == "true" ]]; then
        echo ""
        update_firmware
    fi

    if [[ "$INCLUDE_LANGUAGE_PKGS" == "true" ]] || [[ ${#LANGUAGE_MANAGERS[@]} -gt 0 ]]; then
        echo ""
        update_language_managers
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

# =============================================================================
# Interactive Mode
# =============================================================================

run_interactive() {
    print_interactive_header "$SCRIPT_NAME" "$SCRIPT_VERSION"

    echo ""
    log_info "Detected package manager: $PKG_MANAGER"
    echo ""

    # Check for updates first
    local count
    count=$(count_updates)

    if [[ "$count" -eq 0 ]]; then
        log_ok "System is up to date - no updates available"
        echo ""

        # Offer to check reboot status
        if prompt_yes_no "Check if system reboot is required?" "y"; then
            check_reboot_required
        fi
        return 0
    fi

    log_warn "$count update(s) available"
    echo ""

    # Main action selection
    local action
    action=$(prompt_select "What would you like to do?" \
        "View available updates" \
        "Install all updates (comprehensive)" \
        "Install system updates only" \
        "Install security updates only" \
        "View changelogs" \
        "Check if reboot is required")

    case "$action" in
        "View available updates")
            list_available_updates
            check_security_updates
            echo ""

            # Check for additional update sources
            if command -v flatpak &> /dev/null; then
                echo ""
                local flatpak_count
                flatpak_count=$(flatpak remote-ls --updates 2> /dev/null | wc -l)
                if [[ "$flatpak_count" -gt 0 ]]; then
                    log_info "Flatpak: $flatpak_count update(s) available"
                fi
            fi

            if command -v snap &> /dev/null; then
                local snap_updates
                snap_updates=$(snap refresh --list 2> /dev/null | tail -n +2 | wc -l)
                if [[ "$snap_updates" -gt 0 ]]; then
                    log_info "Snap: $snap_updates update(s) available"
                fi
            fi

            echo ""
            if prompt_yes_no "Would you like to install updates now?" "n"; then
                interactive_install_updates
            fi
            ;;
        "Install all updates (comprehensive)")
            # Enable all update sources
            command -v flatpak &> /dev/null && INCLUDE_FLATPAK=true
            command -v snap &> /dev/null && INCLUDE_SNAP=true
            command -v fwupdmgr &> /dev/null && INCLUDE_FIRMWARE=true
            INCLUDE_LANGUAGE_PKGS=true
            interactive_install_updates
            ;;
        "Install system updates only")
            interactive_install_updates
            ;;
        "Install security updates only")
            SECURITY_ONLY=true
            interactive_install_updates
            ;;
        "View changelogs")
            show_changelog
            echo ""
            if prompt_yes_no "Would you like to install updates now?" "n"; then
                interactive_install_updates
            fi
            ;;
        "Check if reboot is required")
            check_reboot_required
            ;;
    esac
}

# =============================================================================
# Extended Update Functions
# =============================================================================

# Update Flatpak packages
update_flatpak() {
    if ! command -v flatpak &> /dev/null; then
        log_debug "Flatpak not installed, skipping"
        return 0
    fi

    log_info "Checking Flatpak updates..."

    local updates
    updates=$(flatpak remote-ls --updates 2> /dev/null | wc -l)

    if [[ "$updates" -eq 0 ]]; then
        log_ok "Flatpak: No updates available"
        return 0
    fi

    log_info "Flatpak: $updates update(s) available"

    if [[ "$DRY_RUN" == "true" ]]; then
        flatpak remote-ls --updates 2> /dev/null
        return 0
    fi

    local confirm_flag=""
    [[ "$AUTO_YES" == "true" ]] && confirm_flag="-y"

    flatpak update $confirm_flag 2>&1 || {
        log_warn "Flatpak update failed"
        return 1
    }

    log_ok "Flatpak updates completed"
}

# Update Snap packages
update_snap() {
    if ! command -v snap &> /dev/null; then
        log_debug "Snap not installed, skipping"
        return 0
    fi

    log_info "Checking Snap updates..."

    if [[ "$DRY_RUN" == "true" ]]; then
        snap refresh --list 2> /dev/null || log_ok "Snap: No updates available"
        return 0
    fi

    if [[ $EUID -ne 0 ]]; then
        sudo snap refresh 2>&1 || {
            log_warn "Snap update failed"
            return 1
        }
    else
        snap refresh 2>&1 || {
            log_warn "Snap update failed"
            return 1
        }
    fi

    log_ok "Snap updates completed"
}

# Update firmware via fwupd
update_firmware() {
    if ! command -v fwupdmgr &> /dev/null; then
        log_debug "fwupd not installed, skipping firmware updates"
        return 0
    fi

    log_info "Checking firmware updates..."

    # Refresh metadata
    if [[ $EUID -ne 0 ]]; then
        sudo fwupdmgr refresh --force > /dev/null 2>&1 || true
    else
        fwupdmgr refresh --force > /dev/null 2>&1 || true
    fi

    local updates
    updates=$(fwupdmgr get-updates 2> /dev/null | grep -c "Update Version" || echo "0")

    if [[ "$updates" -eq 0 ]]; then
        log_ok "Firmware: No updates available"
        return 0
    fi

    log_warn "Firmware: $updates update(s) available"

    if [[ "$DRY_RUN" == "true" ]]; then
        fwupdmgr get-updates 2> /dev/null
        return 0
    fi

    echo ""
    log_warn "Firmware updates may require a reboot"

    if [[ "$AUTO_YES" != "true" ]]; then
        if ! prompt_yes_no "Install firmware updates?" "n"; then
            log_info "Firmware updates skipped"
            return 0
        fi
    fi

    if [[ $EUID -ne 0 ]]; then
        sudo fwupdmgr update -y 2>&1 || {
            log_warn "Firmware update failed"
            return 1
        }
    else
        fwupdmgr update -y 2>&1 || {
            log_warn "Firmware update failed"
            return 1
        }
    fi

    log_ok "Firmware updates completed"
}

# Update Python packages (pip)
update_pip() {
    if ! command -v pip3 &> /dev/null && ! command -v pip &> /dev/null; then
        log_debug "pip not installed, skipping"
        return 0
    fi

    local pip_cmd="pip3"
    command -v pip3 &> /dev/null || pip_cmd="pip"

    log_info "Checking pip packages..."

    local outdated
    outdated=$($pip_cmd list --outdated --format=columns 2> /dev/null | tail -n +3 | wc -l)

    if [[ "$outdated" -eq 0 ]]; then
        log_ok "pip: No updates available"
        return 0
    fi

    log_info "pip: $outdated package(s) can be updated"

    if [[ "$DRY_RUN" == "true" ]]; then
        $pip_cmd list --outdated 2> /dev/null
        return 0
    fi

    # Update pip itself first
    $pip_cmd install --upgrade pip > /dev/null 2>&1 || true

    # Get list of outdated packages
    local packages
    packages=$($pip_cmd list --outdated --format=freeze 2> /dev/null | cut -d= -f1)

    if [[ -n "$packages" ]]; then
        echo "$packages" | while read -r pkg; do
            [[ -z "$pkg" ]] && continue
            log_debug "Updating $pkg..."
            $pip_cmd install --upgrade "$pkg" > /dev/null 2>&1 || log_warn "Failed to update $pkg"
        done
    fi

    log_ok "pip updates completed"
}

# Update npm packages
update_npm() {
    if ! command -v npm &> /dev/null; then
        log_debug "npm not installed, skipping"
        return 0
    fi

    log_info "Checking global npm packages..."

    local outdated
    outdated=$(npm outdated -g --depth=0 2> /dev/null | tail -n +2 | wc -l)

    if [[ "$outdated" -eq 0 ]]; then
        log_ok "npm: No updates available"
        return 0
    fi

    log_info "npm: $outdated package(s) can be updated"

    if [[ "$DRY_RUN" == "true" ]]; then
        npm outdated -g --depth=0 2> /dev/null
        return 0
    fi

    npm update -g > /dev/null 2>&1 || {
        log_warn "npm update failed"
        return 1
    }

    log_ok "npm updates completed"
}

# Update Rust packages (cargo)
update_cargo() {
    if ! command -v cargo &> /dev/null; then
        log_debug "cargo not installed, skipping"
        return 0
    fi

    # Check for cargo-install-update
    if ! command -v cargo-install-update &> /dev/null; then
        log_debug "cargo-install-update not found, skipping cargo updates"
        log_info "Hint: Install with 'cargo install cargo-update'"
        return 0
    fi

    log_info "Checking cargo packages..."

    if [[ "$DRY_RUN" == "true" ]]; then
        cargo install-update --list 2> /dev/null
        return 0
    fi

    cargo install-update --all > /dev/null 2>&1 || {
        log_warn "cargo update failed"
        return 1
    }

    log_ok "cargo updates completed"
}

# Update Ruby gems
update_gem() {
    if ! command -v gem &> /dev/null; then
        log_debug "gem not installed, skipping"
        return 0
    fi

    log_info "Checking Ruby gems..."

    local outdated
    outdated=$(gem outdated 2> /dev/null | wc -l)

    if [[ "$outdated" -eq 0 ]]; then
        log_ok "gem: No updates available"
        return 0
    fi

    log_info "gem: $outdated gem(s) can be updated"

    if [[ "$DRY_RUN" == "true" ]]; then
        gem outdated 2> /dev/null
        return 0
    fi

    gem update > /dev/null 2>&1 || {
        log_warn "gem update failed"
        return 1
    }

    log_ok "gem updates completed"
}

# Update all language package managers
update_language_managers() {
    if [[ ${#LANGUAGE_MANAGERS[@]} -gt 0 ]]; then
        # Update only specified managers
        for mgr in "${LANGUAGE_MANAGERS[@]}"; do
            case "$mgr" in
                pip) update_pip ;;
                npm) update_npm ;;
                cargo) update_cargo ;;
                gem) update_gem ;;
                *)
                    log_warn "Unknown language manager: $mgr"
                    ;;
            esac
        done
    else
        # Update all available
        update_pip
        update_npm
        update_cargo
        update_gem
    fi
}

interactive_install_updates() {
    echo ""

    # Exclusions
    if prompt_yes_no "Would you like to exclude any packages?" "n"; then
        echo ""
        log_info "Enter packages to exclude (one per line, empty line to finish):"
        while true; do
            local pkg
            read -r -p "  Package: " pkg
            [[ -z "$pkg" ]] && break
            EXCLUDE_PACKAGES+=("$pkg")
        done
    fi

    echo ""

    # Dry run option
    if prompt_yes_no "Perform a dry run first?" "y"; then
        DRY_RUN=true
        log_info "Performing dry run..."
        perform_update
        DRY_RUN=false
        echo ""
        if ! prompt_yes_no "Proceed with actual update?" "y"; then
            log_info "Update cancelled"
            return 0
        fi
    fi

    # Final confirmation
    local update_type="all"
    [[ "$SECURITY_ONLY" == "true" ]] && update_type="security"

    echo ""
    log_info "Update configuration:"
    echo -e "  ${CYAN}•${NC} Update type: $update_type updates"
    [[ ${#EXCLUDE_PACKAGES[@]} -gt 0 ]] && echo -e "  ${CYAN}•${NC} Excluding: ${EXCLUDE_PACKAGES[*]}"
    echo ""

    if confirm_destructive "This will update system packages"; then
        AUTO_YES=true
        INSTALL_ALL=true
        perform_update

        echo ""
        log_ok "Update completed!"

        # Check reboot
        if check_reboot_required; then
            echo ""
            if prompt_yes_no "Reboot now?" "n"; then
                log_warn "Rebooting system..."
                sleep 2
                reboot
            fi
        fi
    fi
}

# Main function
main() {
    local original_args=("$@")
    parse_args "$@"

    detect_pkg_manager

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
        # Refresh packages first (if we have permission)
        if [[ $EUID -eq 0 ]]; then
            refresh_packages
        fi
        run_interactive
        exit $EXIT_OK
    fi

    echo -e "${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}"
    echo ""

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
