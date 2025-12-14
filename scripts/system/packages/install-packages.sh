#!/usr/bin/env bash
# =============================================================================
# @name         install-packages
# @description  Install packages from predefined profiles
# @version      1.0.0
# @author       RSR Team
# @category     system/packages
# =============================================================================
#
# Usage:
#   install-packages.sh [OPTIONS] [PROFILE...]
#
# Examples:
#   install-packages.sh --list                    # List available profiles
#   install-packages.sh development               # Install development profile
#   install-packages.sh minimal security          # Install multiple profiles
#   install-packages.sh --auto development        # Auto-install without prompts
#
# =============================================================================

set -euo pipefail

# =============================================================================
# RSR Library
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RSR_LIB_DIR="${SCRIPT_DIR}/../../../lib"

if [[ -f "$RSR_LIB_DIR/rsr-lib.sh" ]]; then
    # shellcheck source=../../../lib/rsr-lib.sh
    source "$RSR_LIB_DIR/rsr-lib.sh" packages
else
    echo "ERROR: RSR library not found at $RSR_LIB_DIR/rsr-lib.sh" >&2
    exit 1
fi

# =============================================================================
# Configuration
# =============================================================================

readonly SCRIPT_NAME="install-packages"
readonly SCRIPT_VERSION="1.0.0"

# Options
SHOW_LIST=false
SHOW_INFO=false
AUTO_INSTALL=false
DRY_RUN=false
VERBOSE=false
PROFILES=()

# =============================================================================
# Functions
# =============================================================================

show_help() {
    cat << 'EOF'
Install Packages - Install packages from predefined profiles

Usage:
    install-packages.sh [OPTIONS] [PROFILE...]

Options:
    -h, --help          Show this help message
    -l, --list          List available profiles
    -i, --info PROFILE  Show profile details
    -a, --auto          Auto-install without prompts
    -d, --dry-run       Show what would be installed
    -v, --verbose       Enable verbose output
    --version           Show version information

Profiles:
    minimal         Essential packages (curl, git, vim, htop, jq)
    development     Development tools (build tools, editors, utilities)
    webserver       Web server (nginx, certbot, SSL tools)
    docker          Container platform (docker, docker-compose)
    database        Database clients (mysql, postgresql, redis, sqlite)
    monitoring      Monitoring tools (htop, iotop, iftop, sysstat)
    security        Security tools (fail2ban, ufw, clamav, lynis)
    python          Python environment (python3, pip, venv)
    nodejs          Node.js environment (nodejs, npm, yarn)
    kubernetes      Kubernetes tools (kubectl, helm, k9s)
    network         Network tools (nmap, tcpdump, mtr)
    devops          DevOps tools (ansible, terraform, vault)
    server          Complete server (includes minimal, security, monitoring)

Examples:
    # List available profiles
    install-packages.sh --list

    # Show profile details
    install-packages.sh --info development

    # Install development profile
    install-packages.sh development

    # Install multiple profiles
    install-packages.sh minimal security monitoring

    # Auto-install without prompts
    install-packages.sh --auto development

    # Dry run (show what would be installed)
    install-packages.sh --dry-run server

Environment Variables:
    RSR_PKG_AUTO_INSTALL    Set to 1 to auto-install dependencies
    RSR_PKG_CONFIRM         Set to 0 to skip confirmations
    RSR_PKG_LISTS_DIR       Override package lists directory

EOF
}

show_version() {
    echo "${SCRIPT_NAME} v${SCRIPT_VERSION}"
    echo "RSR Packages Module v${_RSR_PACKAGES_VERSION:-unknown}"
}

show_profiles() {
    rsr_print_header "Available Package Profiles"
    rsr_pkg_list_profiles
    echo ""
    rsr_log_info "Use 'install-packages.sh --info PROFILE' for details"
    rsr_log_info "Use 'install-packages.sh PROFILE' to install"
}

show_profile_info() {
    local profile="$1"
    local profile_file="${RSR_PKG_LISTS_DIR}/${profile}.yaml"

    if [[ ! -f "$profile_file" ]]; then
        profile_file="${RSR_PKG_LISTS_DIR}/${profile}.yml"
    fi

    if [[ ! -f "$profile_file" ]]; then
        rsr_log_error "Profile not found: $profile"
        return 1
    fi

    rsr_print_header "Profile: $profile"

    # Show description
    local desc
    desc=$(grep -m1 '^description:' "$profile_file" 2> /dev/null | sed 's/^description:[[:space:]]*//' | tr -d '"'"'")
    [[ -n "$desc" ]] && echo "Description: $desc"

    # Show category
    local category
    category=$(grep -m1 '^category:' "$profile_file" 2> /dev/null | sed 's/^category:[[:space:]]*//' | tr -d '"'"'")
    [[ -n "$category" ]] && echo "Category: $category"

    echo ""
    echo "Packages:"
    _rsr_parse_yaml_packages "$profile_file" "packages" | sed 's/^/  - /'

    # Show optional packages if present
    local optional
    optional=$(_rsr_parse_yaml_packages "$profile_file" "optional")
    if [[ -n "$optional" ]]; then
        echo ""
        echo "Optional packages:"
        echo "$optional" | sed 's/^/  - /'
    fi

    echo ""
}

install_profiles() {
    local profiles=("$@")

    if [[ ${#profiles[@]} -eq 0 ]]; then
        rsr_log_error "No profiles specified"
        echo ""
        show_profiles
        return 1
    fi

    for profile in "${profiles[@]}"; do
        rsr_print_header "Installing Profile: $profile"

        if [[ "$DRY_RUN" == "true" ]]; then
            rsr_log_info "DRY RUN: Would install profile '$profile'"
            show_profile_info "$profile"
        else
            if ! rsr_pkg_install_profile "$profile"; then
                rsr_log_error "Failed to install profile: $profile"
                return 1
            fi
            rsr_log_ok "Profile '$profile' installed successfully"
        fi
    done
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                show_help
                exit 0
                ;;
            --version)
                show_version
                exit 0
                ;;
            -l | --list)
                SHOW_LIST=true
                shift
                ;;
            -i | --info)
                SHOW_INFO=true
                shift
                if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
                    PROFILES+=("$1")
                    shift
                fi
                ;;
            -a | --auto)
                AUTO_INSTALL=true
                RSR_PKG_AUTO_INSTALL=1
                RSR_PKG_CONFIRM=0
                shift
                ;;
            -d | --dry-run)
                DRY_RUN=true
                shift
                ;;
            -v | --verbose)
                VERBOSE=true
                RSR_DEBUG=1
                shift
                ;;
            --)
                shift
                PROFILES+=("$@")
                break
                ;;
            -*)
                rsr_log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                PROFILES+=("$1")
                shift
                ;;
        esac
    done
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"

    # Show package manager info in verbose mode
    if [[ "$VERBOSE" == "true" ]]; then
        rsr_pkg_info
        echo ""
    fi

    # Handle different modes
    if [[ "$SHOW_LIST" == "true" ]]; then
        show_profiles
        exit 0
    fi

    if [[ "$SHOW_INFO" == "true" ]]; then
        if [[ ${#PROFILES[@]} -eq 0 ]]; then
            rsr_log_error "No profile specified for --info"
            exit 1
        fi
        for profile in "${PROFILES[@]}"; do
            show_profile_info "$profile"
        done
        exit 0
    fi

    # Install profiles
    if [[ ${#PROFILES[@]} -eq 0 ]]; then
        # Interactive mode - show menu
        show_help
        exit 0
    fi

    install_profiles "${PROFILES[@]}"
}

# =============================================================================
# Entry Point
# =============================================================================

main "$@"
