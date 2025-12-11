#!/usr/bin/env bash
# =============================================================================
# @name         setup-powershell-repo
# @description  Setup Microsoft repository for PowerShell 7 installation on Linux
# @version      1.0.0
# @author       RSR Team
# @category     packages
# =============================================================================
#
# This script configures the Microsoft package repository on Linux systems,
# enabling PowerShell 7 installation via the native package manager.
#
# Supported distributions:
#   - Ubuntu 20.04, 22.04, 24.04
#   - Debian 10, 11, 12
#   - RHEL/CentOS 7, 8, 9
#   - Fedora 38, 39, 40
#   - Alpine Linux 3.17+
#
# Usage:
#   ./setup-powershell-repo.sh [OPTIONS]
#
# Examples:
#   ./setup-powershell-repo.sh                  # Auto-detect and setup
#   ./setup-powershell-repo.sh --check          # Check if repo is configured
#   ./setup-powershell-repo.sh --remove         # Remove Microsoft repository
#
# =============================================================================

set -euo pipefail

# =============================================================================
# RSR Library (optional - works standalone too)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RSR_LIB_DIR="${SCRIPT_DIR}/../../lib"

# Try to load RSR library, but work standalone if not available
if [[ -f "$RSR_LIB_DIR/rsr-lib.sh" ]]; then
    # shellcheck source=../../lib/rsr-lib.sh
    source "$RSR_LIB_DIR/rsr-lib.sh" 2>/dev/null || true
fi

# Fallback logging functions if RSR library not loaded
if ! declare -f rsr_log_info &>/dev/null; then
    rsr_log_info()    { echo "[INFO]    $*"; }
    rsr_log_success() { echo "[SUCCESS] $*"; }
    rsr_log_warn()    { echo "[WARN]    $*"; }
    rsr_log_error()   { echo "[ERROR]   $*" >&2; }
    rsr_log_debug()   { [[ "${DEBUG:-0}" == "1" ]] && echo "[DEBUG]   $*"; }
fi

# =============================================================================
# Configuration
# =============================================================================

readonly SCRIPT_NAME="setup-powershell-repo"
readonly SCRIPT_VERSION="1.0.0"

# Microsoft GPG key URL
readonly MS_GPG_KEY_URL="https://packages.microsoft.com/keys/microsoft.asc"

# Options
CHECK_ONLY=false
REMOVE_REPO=false
FORCE=false
VERBOSE=false

# =============================================================================
# Helper Functions
# =============================================================================

show_help() {
    cat << 'EOF'
Setup PowerShell Repository - Configure Microsoft repository for PowerShell 7

This script adds the Microsoft package repository to your Linux system,
enabling installation of PowerShell 7 via your native package manager.

Usage:
    setup-powershell-repo.sh [OPTIONS]

Options:
    -h, --help      Show this help message
    -c, --check     Check if repository is already configured
    -r, --remove    Remove Microsoft repository
    -f, --force     Force reconfiguration even if already set up
    -v, --verbose   Enable verbose output
    --version       Show version information

Supported Distributions:
    Ubuntu      20.04, 22.04, 24.04 (Focal, Jammy, Noble)
    Debian      10, 11, 12 (Buster, Bullseye, Bookworm)
    RHEL/CentOS 7, 8, 9
    Fedora      38, 39, 40+
    Alpine      3.17+ (manual installation)

Examples:
    # Setup repository (auto-detect distribution)
    sudo ./setup-powershell-repo.sh

    # Check if repository is configured
    ./setup-powershell-repo.sh --check

    # Remove Microsoft repository
    sudo ./setup-powershell-repo.sh --remove

    # Force reconfiguration
    sudo ./setup-powershell-repo.sh --force

After Setup:
    # Debian/Ubuntu
    sudo apt-get update && sudo apt-get install -y powershell

    # RHEL/Fedora
    sudo dnf install -y powershell

    # Or use RSR
    rsr pkg install core.runtimes.powershell

EOF
}

show_version() {
    echo "${SCRIPT_NAME} v${SCRIPT_VERSION}"
}

# Detect Linux distribution
detect_distro() {
    local distro=""
    local version=""
    local codename=""

    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        distro="${ID:-unknown}"
        version="${VERSION_ID:-}"
        codename="${VERSION_CODENAME:-}"
    elif [[ -f /etc/redhat-release ]]; then
        distro="rhel"
        version=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release | head -1)
    elif [[ -f /etc/debian_version ]]; then
        distro="debian"
        version=$(cat /etc/debian_version)
    fi

    echo "${distro}|${version}|${codename}"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        rsr_log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Check if repository is already configured
is_repo_configured() {
    local distro_info
    distro_info=$(detect_distro)
    local distro="${distro_info%%|*}"

    case "$distro" in
        ubuntu|debian)
            [[ -f /etc/apt/sources.list.d/microsoft-prod.list ]] || \
            [[ -f /etc/apt/sources.list.d/microsoft.list ]]
            ;;
        rhel|centos|fedora|rocky|almalinux)
            [[ -f /etc/yum.repos.d/microsoft-prod.repo ]] || \
            rpm -q packages-microsoft-prod &>/dev/null
            ;;
        alpine)
            command -v pwsh &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# Repository Setup Functions
# =============================================================================

setup_debian_ubuntu() {
    local version="$1"
    local codename="$2"
    local distro="$3"

    rsr_log_info "Setting up Microsoft repository for ${distro^} ${version} (${codename})..."

    # Install prerequisites
    apt-get update -qq
    apt-get install -y -qq wget apt-transport-https software-properties-common

    # Download and install Microsoft GPG key
    rsr_log_info "Importing Microsoft GPG key..."
    wget -q "$MS_GPG_KEY_URL" -O /tmp/microsoft.asc
    
    # Convert to GPG format and install
    if command -v gpg &>/dev/null; then
        gpg --dearmor -o /usr/share/keyrings/microsoft-archive-keyring.gpg /tmp/microsoft.asc 2>/dev/null || \
        cat /tmp/microsoft.asc | gpg --dearmor > /usr/share/keyrings/microsoft-archive-keyring.gpg
    else
        # Fallback for systems without gpg
        cat /tmp/microsoft.asc > /usr/share/keyrings/microsoft.asc
    fi
    rm -f /tmp/microsoft.asc

    # Determine the correct repository URL
    local repo_url
    case "$distro" in
        ubuntu)
            repo_url="https://packages.microsoft.com/repos/microsoft-ubuntu-${codename}-prod"
            ;;
        debian)
            repo_url="https://packages.microsoft.com/repos/microsoft-debian-${codename}-prod"
            ;;
    esac

    # Add repository
    rsr_log_info "Adding Microsoft repository..."
    if [[ -f /usr/share/keyrings/microsoft-archive-keyring.gpg ]]; then
        echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] ${repo_url} ${codename} main" \
            > /etc/apt/sources.list.d/microsoft-prod.list
    else
        echo "deb [arch=amd64,arm64,armhf] ${repo_url} ${codename} main" \
            > /etc/apt/sources.list.d/microsoft-prod.list
    fi

    # Update package cache
    rsr_log_info "Updating package cache..."
    apt-get update -qq

    rsr_log_success "Microsoft repository configured successfully"
    rsr_log_info "Install PowerShell with: sudo apt-get install -y powershell"
}

setup_rhel_fedora() {
    local version="$1"
    local distro="$2"

    rsr_log_info "Setting up Microsoft repository for ${distro^} ${version}..."

    # Determine major version
    local major_version="${version%%.*}"

    # Download and install Microsoft repository package
    local repo_url
    case "$distro" in
        fedora)
            repo_url="https://packages.microsoft.com/config/fedora/${major_version}/packages-microsoft-prod.rpm"
            ;;
        rhel|centos|rocky|almalinux)
            # RHEL-based distros
            repo_url="https://packages.microsoft.com/config/rhel/${major_version}/packages-microsoft-prod.rpm"
            ;;
    esac

    rsr_log_info "Installing Microsoft repository package..."
    
    # Install the repo package
    if command -v dnf &>/dev/null; then
        dnf install -y "$repo_url"
    else
        yum install -y "$repo_url"
    fi

    rsr_log_success "Microsoft repository configured successfully"
    
    if command -v dnf &>/dev/null; then
        rsr_log_info "Install PowerShell with: sudo dnf install -y powershell"
    else
        rsr_log_info "Install PowerShell with: sudo yum install -y powershell"
    fi
}

setup_alpine() {
    local version="$1"

    rsr_log_info "Setting up PowerShell for Alpine Linux ${version}..."
    rsr_log_warn "Alpine Linux requires manual PowerShell installation"
    
    # Install prerequisites
    apk add --no-cache \
        ca-certificates \
        less \
        ncurses-terminfo-base \
        krb5-libs \
        libgcc \
        libintl \
        libssl3 \
        libstdc++ \
        tzdata \
        userspace-rcu \
        zlib \
        icu-libs \
        curl

    # Download and install PowerShell
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64) arch="x64" ;;
        aarch64) arch="arm64" ;;
        *) 
            rsr_log_error "Unsupported architecture: $arch"
            return 1
            ;;
    esac

    rsr_log_info "Downloading PowerShell for Alpine (${arch})..."
    
    # Get latest stable version
    local ps_version
    ps_version=$(curl -s "https://api.github.com/repos/PowerShell/PowerShell/releases/latest" | \
        grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
    
    if [[ -z "$ps_version" ]]; then
        ps_version="7.5.0"  # Fallback version
    fi

    local download_url="https://github.com/PowerShell/PowerShell/releases/download/v${ps_version}/powershell-${ps_version}-linux-musl-${arch}.tar.gz"
    
    # Create installation directory
    mkdir -p /opt/microsoft/powershell/7
    
    # Download and extract
    curl -L "$download_url" | tar -xz -C /opt/microsoft/powershell/7
    
    # Create symlink
    ln -sf /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh
    
    # Set executable permission
    chmod +x /opt/microsoft/powershell/7/pwsh

    rsr_log_success "PowerShell ${ps_version} installed successfully"
    rsr_log_info "Run PowerShell with: pwsh"
}

# =============================================================================
# Repository Removal Functions
# =============================================================================

remove_repo() {
    local distro_info
    distro_info=$(detect_distro)
    local distro="${distro_info%%|*}"

    rsr_log_info "Removing Microsoft repository..."

    case "$distro" in
        ubuntu|debian)
            rm -f /etc/apt/sources.list.d/microsoft-prod.list
            rm -f /etc/apt/sources.list.d/microsoft.list
            rm -f /usr/share/keyrings/microsoft-archive-keyring.gpg
            rm -f /usr/share/keyrings/microsoft.asc
            apt-get update -qq
            ;;
        rhel|centos|fedora|rocky|almalinux)
            rm -f /etc/yum.repos.d/microsoft-prod.repo
            if rpm -q packages-microsoft-prod &>/dev/null; then
                if command -v dnf &>/dev/null; then
                    dnf remove -y packages-microsoft-prod
                else
                    yum remove -y packages-microsoft-prod
                fi
            fi
            ;;
        alpine)
            rm -rf /opt/microsoft/powershell
            rm -f /usr/bin/pwsh
            ;;
        *)
            rsr_log_error "Unsupported distribution: $distro"
            return 1
            ;;
    esac

    rsr_log_success "Microsoft repository removed"
}

# =============================================================================
# Main Setup Logic
# =============================================================================

setup_repo() {
    local distro_info
    distro_info=$(detect_distro)
    
    local distro="${distro_info%%|*}"
    local rest="${distro_info#*|}"
    local version="${rest%%|*}"
    local codename="${rest#*|}"

    rsr_log_info "Detected: ${distro^} ${version} (${codename:-N/A})"

    # Check if already configured
    if [[ "$FORCE" != "true" ]] && is_repo_configured; then
        rsr_log_success "Microsoft repository is already configured"
        rsr_log_info "Use --force to reconfigure"
        return 0
    fi

    case "$distro" in
        ubuntu|debian)
            setup_debian_ubuntu "$version" "$codename" "$distro"
            ;;
        rhel|centos|rocky|almalinux|fedora)
            setup_rhel_fedora "$version" "$distro"
            ;;
        alpine)
            setup_alpine "$version"
            ;;
        *)
            rsr_log_error "Unsupported distribution: $distro"
            rsr_log_info "Supported: Ubuntu, Debian, RHEL, CentOS, Fedora, Rocky, AlmaLinux, Alpine"
            rsr_log_info "For other distributions, see: https://docs.microsoft.com/powershell/scripting/install/installing-powershell-on-linux"
            return 1
            ;;
    esac
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            --version)
                show_version
                exit 0
                ;;
            -c|--check)
                CHECK_ONLY=true
                shift
                ;;
            -r|--remove)
                REMOVE_REPO=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                export DEBUG=1
                shift
                ;;
            *)
                rsr_log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"

    # Check-only mode
    if [[ "$CHECK_ONLY" == "true" ]]; then
        if is_repo_configured; then
            rsr_log_success "Microsoft repository is configured"
            exit 0
        else
            rsr_log_warn "Microsoft repository is NOT configured"
            rsr_log_info "Run: sudo $0 to configure"
            exit 1
        fi
    fi

    # Need root for setup/remove
    check_root

    # Remove mode
    if [[ "$REMOVE_REPO" == "true" ]]; then
        remove_repo
        exit $?
    fi

    # Setup mode
    setup_repo
}

main "$@"
