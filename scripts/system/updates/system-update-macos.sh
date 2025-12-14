#!/bin/bash
# =============================================================================
# @id           update-macos
# @name         system-update-macos
# @displayName  macOS System Update
# @description  Update Homebrew, Mac App Store, and macOS system
# @category     maintenance
# @version      1.0.0
# @author       codefuturist
# @tags         update,macos,homebrew,mas,app-store,maintenance
# @shells       bash
# @platform     darwin
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
SCRIPT_NAME="macOS System Update"
SCRIPT_VERSION="1.0.0"

# Default values
VERBOSE=false
INTERACTIVE=auto
CHECK_ONLY=false
LIST_UPDATES=false
UPDATE_ALL=false
DRY_RUN=false
AUTO_YES=false
INCLUDE_BREW=true
INCLUDE_BREW_CASK=true
INCLUDE_MAS=true
INCLUDE_SOFTWAREUPDATE=false
INCLUDE_LANGUAGE_PKGS=false
LANGUAGE_MANAGERS=()

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
EXIT_OK=0
EXIT_ERROR=1
EXIT_INVALID_ARGS=2
EXIT_NO_UPDATES=100

usage() {
    cat << EOF
${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}

Update Homebrew packages, Mac App Store apps, and macOS system.

${YELLOW}Usage:${NC}
    $0 [OPTIONS]

${BOLD}Options:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -i, --interactive       Run in interactive mode (default when no args)
    --no-interactive        Disable interactive mode
    -c, --check             Check for available updates only
    -l, --list              List available updates with details
    -a, --all               Update everything (brew, casks, MAS, system)
    -y, --yes               Automatic yes to prompts
    -d, --dry-run           Show what would be updated
    --no-brew               Skip Homebrew formulae updates
    --no-cask               Skip Homebrew Cask updates
    --no-mas                Skip Mac App Store updates
    --system                Include macOS system updates
    --lang                  Include language package managers
    --lang-manager MGR      Specify language manager (pip, npm, cargo, gem)

${BOLD}Update Sources:${NC}
    Homebrew:               brew upgrade
    Homebrew Cask:          brew upgrade --cask
    Mac App Store:          mas upgrade (requires mas-cli)
    macOS System:           softwareupdate (requires sudo)
    Language Managers:      pip, npm, cargo, gem

${BOLD}Examples:${NC}
    ${DIM}# Check for updates${NC}
    $0 -c

    ${DIM}# List available updates${NC}
    $0 -l

    ${DIM}# Update everything (interactive)${NC}
    $0 -a

    ${DIM}# Update only Homebrew formulae${NC}
    $0 --no-cask --no-mas

    ${DIM}# Update Homebrew and App Store${NC}
    $0 --no-cask -y

    ${DIM}# Include system updates${NC}
    $0 -a --system -y

${BOLD}Requirements:${NC}
    - Homebrew (brew)
    - mas-cli for App Store updates (optional): brew install mas
    - sudo access for system updates (optional)

EOF
    exit 0
}

# Logging functions
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
                UPDATE_ALL=true
                shift
                ;;
            -y | --yes)
                AUTO_YES=true
                shift
                ;;
            -d | --dry-run)
                DRY_RUN=true
                shift
                ;;
            --no-brew)
                INCLUDE_BREW=false
                shift
                ;;
            --no-cask)
                INCLUDE_BREW_CASK=false
                shift
                ;;
            --no-mas)
                INCLUDE_MAS=false
                shift
                ;;
            --system)
                INCLUDE_SOFTWAREUPDATE=true
                shift
                ;;
            --lang)
                INCLUDE_LANGUAGE_PKGS=true
                shift
                ;;
            --lang-manager)
                LANGUAGE_MANAGERS+=("$2")
                INCLUDE_LANGUAGE_PKGS=true
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

# Check Homebrew updates
check_brew_updates() {
    if ! command -v brew &> /dev/null; then
        log_error "Homebrew not installed"
        return 1
    fi

    log_info "Checking Homebrew updates..."

    # Update Homebrew itself first
    if [[ "$DRY_RUN" != "true" ]]; then
        brew update &> /dev/null || log_warn "Failed to update Homebrew"
    fi

    local outdated
    outdated=$(brew outdated --quiet 2> /dev/null | wc -l | tr -d ' ')

    if [[ "$outdated" -eq 0 ]]; then
        log_ok "Homebrew: All formulae up to date"
    else
        log_warn "Homebrew: $outdated formula(e) can be upgraded"
    fi

    echo "$outdated"
}

# List Homebrew updates
list_brew_updates() {
    if ! command -v brew &> /dev/null; then
        return 0
    fi

    local outdated
    outdated=$(brew outdated --quiet 2> /dev/null)

    if [[ -z "$outdated" ]]; then
        return 0
    fi

    echo ""
    echo -e "${BOLD}Homebrew Formulae:${NC}"
    echo "$outdated" | while read -r formula; do
        local current
        local latest
        current=$(brew list --versions "$formula" 2> /dev/null | awk '{print $NF}')
        latest=$(brew info "$formula" 2> /dev/null | head -1 | awk '{print $3}' | sed 's/,$//')
        printf "  ${CYAN}%-30s${NC} %s → ${GREEN}%s${NC}\n" "$formula" "$current" "$latest"
    done
}

# Update Homebrew formulae
update_brew() {
    if ! command -v brew &> /dev/null; then
        log_debug "Homebrew not installed, skipping"
        return 0
    fi

    local count
    count=$(brew outdated --quiet 2> /dev/null | wc -l | tr -d ' ')

    if [[ "$count" -eq 0 ]]; then
        log_ok "Homebrew: Already up to date"
        return 0
    fi

    log_info "Upgrading $count Homebrew formula(e)..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Would upgrade: $(brew outdated --quiet | tr '\n' ' ')"
        return 0
    fi

    brew upgrade 2>&1 || {
        log_error "Homebrew upgrade failed"
        return 1
    }

    log_ok "Homebrew upgrade completed"
}

# Check Homebrew Cask updates
check_cask_updates() {
    if ! command -v brew &> /dev/null; then
        return 0
    fi

    log_info "Checking Homebrew Cask updates..."

    local outdated
    outdated=$(brew outdated --cask --quiet 2> /dev/null | wc -l | tr -d ' ')

    if [[ "$outdated" -eq 0 ]]; then
        log_ok "Homebrew Cask: All casks up to date"
    else
        log_warn "Homebrew Cask: $outdated cask(s) can be upgraded"
    fi

    echo "$outdated"
}

# List Homebrew Cask updates
list_cask_updates() {
    if ! command -v brew &> /dev/null; then
        return 0
    fi

    local outdated
    outdated=$(brew outdated --cask --quiet 2> /dev/null)

    if [[ -z "$outdated" ]]; then
        return 0
    fi

    echo ""
    echo -e "${BOLD}Homebrew Casks:${NC}"
    echo "$outdated" | while read -r cask; do
        printf "  ${CYAN}%-30s${NC} (update available)\n" "$cask"
    done
}

# Update Homebrew Casks
update_cask() {
    if ! command -v brew &> /dev/null; then
        log_debug "Homebrew not installed, skipping casks"
        return 0
    fi

    local count
    count=$(brew outdated --cask --quiet 2> /dev/null | wc -l | tr -d ' ')

    if [[ "$count" -eq 0 ]]; then
        log_ok "Homebrew Cask: Already up to date"
        return 0
    fi

    log_info "Upgrading $count Homebrew cask(s)..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Would upgrade: $(brew outdated --cask --quiet | tr '\n' ' ')"
        return 0
    fi

    # Greedy upgrade to get latest versions even for auto-update apps
    brew upgrade --cask --greedy 2>&1 || {
        log_error "Homebrew Cask upgrade failed"
        return 1
    }

    log_ok "Homebrew Cask upgrade completed"
}

# Check Mac App Store updates
check_mas_updates() {
    if ! command -v mas &> /dev/null; then
        log_debug "mas-cli not installed (brew install mas)"
        return 0
    fi

    log_info "Checking Mac App Store updates..."

    local outdated
    outdated=$(mas outdated 2> /dev/null | wc -l | tr -d ' ')

    if [[ "$outdated" -eq 0 ]]; then
        log_ok "Mac App Store: All apps up to date"
    else
        log_warn "Mac App Store: $outdated app(s) can be updated"
    fi

    echo "$outdated"
}

# List Mac App Store updates
list_mas_updates() {
    if ! command -v mas &> /dev/null; then
        return 0
    fi

    local outdated
    outdated=$(mas outdated 2> /dev/null)

    if [[ -z "$outdated" ]]; then
        return 0
    fi

    echo ""
    echo -e "${BOLD}Mac App Store:${NC}"
    echo "$outdated" | while read -r line; do
        local id name version latest
        id=$(echo "$line" | awk '{print $1}')
        version=$(echo "$line" | awk '{print $2}')
        latest=$(echo "$line" | awk '{print $4}')
        name=$(echo "$line" | cut -d' ' -f5-)
        printf "  ${CYAN}%-30s${NC} %s → ${GREEN}%s${NC}\n" "$name" "$version" "$latest"
    done
}

# Update Mac App Store apps
update_mas() {
    if ! command -v mas &> /dev/null; then
        log_debug "mas-cli not installed, skipping App Store updates"
        return 0
    fi

    local count
    count=$(mas outdated 2> /dev/null | wc -l | tr -d ' ')

    if [[ "$count" -eq 0 ]]; then
        log_ok "Mac App Store: Already up to date"
        return 0
    fi

    log_info "Updating $count Mac App Store app(s)..."

    if [[ "$DRY_RUN" == "true" ]]; then
        mas outdated 2> /dev/null | while read -r line; do
            log_info "Would update: $(echo "$line" | cut -d' ' -f5-)"
        done
        return 0
    fi

    mas upgrade 2>&1 || {
        log_error "Mac App Store upgrade failed"
        return 1
    }

    log_ok "Mac App Store updates completed"
}

# Check macOS system updates
check_system_updates() {
    log_info "Checking macOS system updates..."

    local updates
    updates=$(softwareupdate --list 2>&1)

    if echo "$updates" | grep -q "No new software available"; then
        log_ok "macOS: System is up to date"
        echo "0"
        return 0
    fi

    local count
    count=$(echo "$updates" | grep -c "^\* " || echo "0")

    if [[ "$count" -gt 0 ]]; then
        log_warn "macOS: $count system update(s) available"
    fi

    echo "$count"
}

# List macOS system updates
list_system_updates() {
    local updates
    updates=$(softwareupdate --list 2>&1)

    if echo "$updates" | grep -q "No new software available"; then
        return 0
    fi

    echo ""
    echo -e "${BOLD}macOS System Updates:${NC}"
    echo "$updates" | grep "^\* " | sed 's/^\* //' | while read -r line; do
        printf "  ${CYAN}%s${NC}\n" "$line"
    done
}

# Update macOS system
update_system() {
    log_info "Checking for macOS system updates..."

    local count
    count=$(softwareupdate --list 2>&1 | grep -c "^\* " || echo "0")

    if [[ "$count" -eq 0 ]]; then
        log_ok "macOS: System is up to date"
        return 0
    fi

    log_warn "macOS: $count system update(s) available"

    if [[ "$DRY_RUN" == "true" ]]; then
        softwareupdate --list 2>&1 | grep "^\* "
        return 0
    fi

    log_warn "Installing macOS system updates (this may take a while)..."
    log_warn "System may require a restart after updates"

    if [[ "$AUTO_YES" != "true" ]]; then
        if ! prompt_yes_no "Install macOS system updates?" "n"; then
            log_info "System updates skipped"
            return 0
        fi
    fi

    if [[ $EUID -ne 0 ]]; then
        sudo softwareupdate --install --all 2>&1 || {
            log_error "System update failed"
            return 1
        }
    else
        softwareupdate --install --all 2>&1 || {
            log_error "System update failed"
            return 1
        }
    fi

    log_ok "System updates completed"
}

# Update language package managers (same as Linux version)
update_language_managers() {
    local managers=("${LANGUAGE_MANAGERS[@]}")

    if [[ ${#managers[@]} -eq 0 ]]; then
        command -v pip3 &> /dev/null && managers+=("pip")
        command -v npm &> /dev/null && managers+=("npm")
        command -v cargo &> /dev/null && managers+=("cargo")
        command -v gem &> /dev/null && managers+=("gem")
    fi

    [[ ${#managers[@]} -eq 0 ]] && {
        log_debug "No language package managers found"
        return 0
    }

    log_info "Updating language package managers: ${managers[*]}"

    for mgr in "${managers[@]}"; do
        case "$mgr" in
            pip) update_pip ;;
            npm) update_npm ;;
            cargo) update_cargo ;;
            gem) update_gem ;;
            *) log_warn "Unknown language manager: $mgr" ;;
        esac
    done
}

update_pip() {
    if ! command -v pip3 &> /dev/null && ! command -v pip &> /dev/null; then
        log_debug "pip not installed, skipping"
        return 0
    fi

    local pip_cmd="pip3"
    command -v pip3 &> /dev/null || pip_cmd="pip"

    log_info "Updating pip packages..."

    if [[ "$DRY_RUN" == "true" ]]; then
        $pip_cmd list --outdated 2> /dev/null
        return 0
    fi

    local outdated
    outdated=$($pip_cmd list --outdated --format=freeze 2> /dev/null | cut -d= -f1)

    if [[ -z "$outdated" ]]; then
        log_ok "pip: All packages up to date"
        return 0
    fi

    echo "$outdated" | while read -r pkg; do
        [[ -z "$pkg" ]] && continue
        $pip_cmd install --upgrade "$pkg" &> /dev/null || true
    done

    log_ok "pip updates completed"
}

update_npm() {
    if ! command -v npm &> /dev/null; then
        log_debug "npm not installed, skipping"
        return 0
    fi

    log_info "Updating global npm packages..."

    if [[ "$DRY_RUN" == "true" ]]; then
        npm outdated -g 2> /dev/null
        return 0
    fi

    npm update -g &> /dev/null || log_ok "npm: All packages up to date"
}

update_cargo() {
    if ! command -v cargo &> /dev/null; then
        log_debug "cargo not installed, skipping"
        return 0
    fi

    if ! cargo install --list 2> /dev/null | grep -q "cargo-update"; then
        log_warn "cargo-update not installed. Install with: cargo install cargo-update"
        return 0
    fi

    log_info "Updating cargo packages..."

    if [[ "$DRY_RUN" == "true" ]]; then
        cargo install-update -l 2>&1
        return 0
    fi

    cargo install-update -a &> /dev/null || log_warn "cargo-update encountered issues"
    log_ok "cargo updates completed"
}

update_gem() {
    if ! command -v gem &> /dev/null; then
        log_debug "gem not installed, skipping"
        return 0
    fi

    log_info "Updating Ruby gems..."

    if [[ "$DRY_RUN" == "true" ]]; then
        gem outdated 2> /dev/null
        return 0
    fi

    gem update &> /dev/null || log_ok "gem: All packages up to date"
}

# Interactive mode
run_interactive() {
    if type print_interactive_header &> /dev/null; then
        print_interactive_header "$SCRIPT_NAME" "$SCRIPT_VERSION"
    else
        echo ""
        echo -e "${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}"
        echo ""
    fi

    # Check what's available
    local brew_count=0 cask_count=0 mas_count=0 system_count=0

    if [[ "$INCLUDE_BREW" == "true" ]]; then
        brew_count=$(check_brew_updates)
    fi

    if [[ "$INCLUDE_BREW_CASK" == "true" ]]; then
        cask_count=$(check_cask_updates)
    fi

    if [[ "$INCLUDE_MAS" == "true" ]]; then
        mas_count=$(check_mas_updates)
    fi

    local total=$((brew_count + cask_count + mas_count))

    if [[ "$total" -eq 0 ]]; then
        log_ok "All software is up to date!"
        echo ""

        if [[ "$INCLUDE_SOFTWAREUPDATE" == "true" ]] || prompt_yes_no "Check for macOS system updates?" "n"; then
            check_system_updates
        fi
        return 0
    fi

    echo ""
    log_info "Total updates available: $total"
    echo ""

    # Show what would be updated
    if [[ "$brew_count" -gt 0 ]]; then
        list_brew_updates
    fi

    if [[ "$cask_count" -gt 0 ]]; then
        list_cask_updates
    fi

    if [[ "$mas_count" -gt 0 ]]; then
        list_mas_updates
    fi

    echo ""

    # Main action selection
    local action
    if type prompt_select &> /dev/null; then
        action=$(prompt_select "What would you like to do?" \
            "Update all available" \
            "Update Homebrew only" \
            "Update Homebrew Casks only" \
            "Update Mac App Store only" \
            "Update with system updates" \
            "Skip updates")
    else
        log_info "Select an option:"
        echo "  1) Update all available"
        echo "  2) Update Homebrew only"
        echo "  3) Update Homebrew Casks only"
        echo "  4) Update Mac App Store only"
        echo "  5) Update with system updates"
        echo "  6) Skip updates"
        read -r -p "Choice [1-6]: " choice
        case "$choice" in
            1) action="Update all available" ;;
            2) action="Update Homebrew only" ;;
            3) action="Update Homebrew Casks only" ;;
            4) action="Update Mac App Store only" ;;
            5) action="Update with system updates" ;;
            *) action="Skip updates" ;;
        esac
    fi

    case "$action" in
        "Update all available")
            [[ "$brew_count" -gt 0 ]] && update_brew
            [[ "$cask_count" -gt 0 ]] && update_cask
            [[ "$mas_count" -gt 0 ]] && update_mas
            [[ "$INCLUDE_LANGUAGE_PKGS" == "true" ]] && update_language_managers
            ;;
        "Update Homebrew only")
            update_brew
            ;;
        "Update Homebrew Casks only")
            update_cask
            ;;
        "Update Mac App Store only")
            update_mas
            ;;
        "Update with system updates")
            [[ "$brew_count" -gt 0 ]] && update_brew
            [[ "$cask_count" -gt 0 ]] && update_cask
            [[ "$mas_count" -gt 0 ]] && update_mas
            update_system
            [[ "$INCLUDE_LANGUAGE_PKGS" == "true" ]] && update_language_managers
            ;;
        "Skip updates")
            log_info "Updates skipped"
            return 0
            ;;
    esac

    echo ""
    log_ok "Update process completed!"
}

# Main function
main() {
    local original_args=("$@")
    parse_args "$@"

    # Check if running on macOS
    if [[ "$(uname -s)" != "Darwin" ]]; then
        log_error "This script is for macOS only"
        exit $EXIT_ERROR
    fi

    # Determine if interactive mode should be enabled
    if [[ "$INTERACTIVE" == "auto" ]]; then
        if [[ ${#original_args[@]} -eq 0 ]] && [[ -t 0 ]] && [[ -t 1 ]]; then
            INTERACTIVE=true
        else
            INTERACTIVE=false
        fi
    fi

    # Run interactive mode if enabled
    if [[ "$INTERACTIVE" == "true" ]]; then
        run_interactive
        exit $EXIT_OK
    fi

    echo -e "${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}"
    echo ""

    # Handle check-only mode
    if [[ "$CHECK_ONLY" == "true" ]]; then
        local total=0
        [[ "$INCLUDE_BREW" == "true" ]] && total=$((total + $(check_brew_updates)))
        [[ "$INCLUDE_BREW_CASK" == "true" ]] && total=$((total + $(check_cask_updates)))
        [[ "$INCLUDE_MAS" == "true" ]] && total=$((total + $(check_mas_updates)))
        [[ "$INCLUDE_SOFTWAREUPDATE" == "true" ]] && total=$((total + $(check_system_updates)))

        if [[ "$total" -eq 0 ]]; then
            log_ok "All software is up to date"
            exit $EXIT_NO_UPDATES
        else
            log_info "Total updates available: $total"
            exit $EXIT_OK
        fi
    fi

    # Handle list mode
    if [[ "$LIST_UPDATES" == "true" ]]; then
        [[ "$INCLUDE_BREW" == "true" ]] && list_brew_updates
        [[ "$INCLUDE_BREW_CASK" == "true" ]] && list_cask_updates
        [[ "$INCLUDE_MAS" == "true" ]] && list_mas_updates
        [[ "$INCLUDE_SOFTWAREUPDATE" == "true" ]] && list_system_updates
        exit $EXIT_OK
    fi

    # Perform updates
    if [[ "$UPDATE_ALL" == "true" ]] || [[ "$INCLUDE_BREW" == "true" ]]; then
        update_brew
        echo ""
    fi

    if [[ "$UPDATE_ALL" == "true" ]] || [[ "$INCLUDE_BREW_CASK" == "true" ]]; then
        update_cask
        echo ""
    fi

    if [[ "$UPDATE_ALL" == "true" ]] || [[ "$INCLUDE_MAS" == "true" ]]; then
        update_mas
        echo ""
    fi

    if [[ "$INCLUDE_SOFTWAREUPDATE" == "true" ]]; then
        update_system
        echo ""
    fi

    if [[ "$INCLUDE_LANGUAGE_PKGS" == "true" ]] || [[ ${#LANGUAGE_MANAGERS[@]} -gt 0 ]]; then
        update_language_managers
        echo ""
    fi

    log_ok "Update process completed!"
}

# Helper functions if RSR library not available
if ! type prompt_yes_no &> /dev/null; then
    prompt_yes_no() {
        local question="$1"
        local default="${2:-n}"
        local prompt="[y/N]"
        [[ "$default" == "y" ]] && prompt="[Y/n]"

        read -r -p "$question $prompt " answer
        answer="${answer:-$default}"

        case "$answer" in
            [Yy] | [Yy][Ee][Ss]) return 0 ;;
            *) return 1 ;;
        esac
    }
fi

# Run main function
main "$@"
