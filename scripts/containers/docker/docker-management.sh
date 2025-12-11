#!/bin/sh
set -e
set -o noglob
#
# Docker Management Script
# Remote Script Runner - Docker Operations
#
# A comprehensive Docker management tool for installation, container management,
# image operations, and system maintenance. Designed to be run remotely via curl.
#
# Usage:
#   Remote:  curl -fsSL https://scripts.pandia.io/rsr | sh -s -- docker [OPTIONS]
#   Local:   ./docker-management.sh [OPTIONS]
#
# Examples:
#   # Install Docker Engine
#   curl -fsSL https://scripts.pandia.io/rsr | sh -s -- docker install engine
#
#   # Check Docker status
#   curl -fsSL https://scripts.pandia.io/rsr | sh -s -- docker status
#
#   # List containers
#   curl -fsSL https://scripts.pandia.io/rsr | sh -s -- docker ps
#
#   # System cleanup
#   curl -fsSL https://scripts.pandia.io/rsr | sh -s -- docker cleanup
#

set -euo pipefail

# ============================================================================
# Load RSR Library
# ============================================================================

SCRIPT_NAME="docker-management"
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RSR_LIB_DIR="${SCRIPT_DIR}/../../../lib"

# Load the RSR library with required modules
if [[ -f "$RSR_LIB_DIR/rsr-lib.sh" ]]; then
    source "$RSR_LIB_DIR/rsr-lib.sh" docker validate
else
    echo "ERROR: RSR library not found at $RSR_LIB_DIR/rsr-lib.sh" >&2
    exit 1
fi

# ============================================================================
# Logging Functions (using RSR library)
# ============================================================================

log_info() { rsr_log_info "$*"; }
log_success() { rsr_log_ok "$*"; }
log_warn() { rsr_log_warn "$*"; }
log_error() { rsr_log_error "$*"; }

# ============================================================================
# Utility Functions (using RSR library)
# ============================================================================

# Detect operating system
detect_os() {
    rsr_detect_distro
}

# Detect architecture
detect_arch() {
    rsr_detect_arch
}

# Check if running as root
is_root() {
    rsr_is_root
}

# Ensure sudo/root access
ensure_sudo() {
    if ! is_root; then
        if ! rsr_has_command sudo; then
            log_error "This operation requires root access and sudo is not available"
            exit 1
        fi
        if ! sudo -n true 2>/dev/null; then
            log_info "This operation requires sudo access"
            sudo -v
        fi
    fi
}

# ============================================================================
# Docker Detection Functions (using RSR library)
# ============================================================================

# Check if Docker is installed
is_docker_installed() {
    rsr_docker_is_installed
}

# Check if Docker daemon is running
is_docker_running() {
    rsr_docker_is_running
}

# Get Docker version
get_docker_version() {
    rsr_docker_version
}

# ============================================================================
# Docker Installation Functions
# ============================================================================

# Install Docker Engine on Ubuntu/Debian
install_docker_ubuntu_debian() {
    log_info "Installing Docker Engine on Ubuntu/Debian..."

    ensure_sudo

    # Remove old versions
    sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    # Update package index
    sudo apt-get update

    # Install dependencies
    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # Add Docker's official GPG key
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$(detect_os)/gpg | \
        sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    # Set up repository
    echo \
      "deb [arch=$(detect_arch) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(detect_os) \
      $(lsb_release -cs) stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker Engine
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker

    # Add current user to docker group
    if [[ -n "${SUDO_USER:-}" ]]; then
        sudo usermod -aG docker "$SUDO_USER"
    elif [[ -n "${USER:-}" ]]; then
        sudo usermod -aG docker "$USER"
    fi

    log_success "Docker Engine installed successfully"
}

# Install Docker Engine on RHEL/Rocky/AlmaLinux/Fedora
install_docker_rhel_fedora() {
    log_info "Installing Docker Engine on RHEL/Fedora..."

    ensure_sudo

    # Remove old versions
    sudo dnf remove -y docker docker-client docker-client-latest docker-common docker-latest \
                       docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true

    # Install dnf-plugins-core
    sudo dnf install -y dnf-plugins-core

    # Set up repository
    local os_id
    os_id=$(detect_os)
    case "$os_id" in
        rhel|rocky|almalinux)
            sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
            ;;
        fedora)
            sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            ;;
    esac

    # Install Docker Engine
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker

    # Add current user to docker group
    if [[ -n "${SUDO_USER:-}" ]]; then
        sudo usermod -aG docker "$SUDO_USER"
    elif [[ -n "${USER:-}" ]]; then
        sudo usermod -aG docker "$USER"
    fi

    log_success "Docker Engine installed successfully"
}

# Install Docker Engine on Arch Linux
install_docker_arch() {
    log_info "Installing Docker Engine on Arch Linux..."

    ensure_sudo

    # Install Docker
    sudo pacman -S --noconfirm docker docker-compose

    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker

    # Add current user to docker group
    if [[ -n "${SUDO_USER:-}" ]]; then
        sudo usermod -aG docker "$SUDO_USER"
    elif [[ -n "${USER:-}" ]]; then
        sudo usermod -aG docker "$USER"
    fi

    log_success "Docker Engine installed successfully"
}

# Install Docker Engine (dispatch to OS-specific installer)
install_docker_engine() {
    local os
    os=$(detect_os)

    log_info "Detected OS: $os"

    case "$os" in
        ubuntu|debian)
            install_docker_ubuntu_debian
            ;;
        rhel|rocky|almalinux|fedora)
            install_docker_rhel_fedora
            ;;
        arch)
            install_docker_arch
            ;;
        macos)
            log_error "On macOS, please install Docker Desktop manually from:"
            log_info "https://www.docker.com/products/docker-desktop"
            exit 1
            ;;
        *)
            log_error "Unsupported operating system: $os"
            exit 1
            ;;
    esac
}

# ============================================================================
# Docker Operations Functions
# ============================================================================

# Show Docker status
show_docker_status() {
    log_info "Docker Status"
    echo

    if ! is_docker_installed; then
        log_error "Docker is not installed"
        return 1
    fi

    echo "Version: $(get_docker_version)"

    if is_docker_running; then
        log_success "Docker daemon is running"
    else
        log_error "Docker daemon is not running"
        return 1
    fi

    echo
    echo "System Information:"
    docker info 2>/dev/null | grep -E "Server Version|Operating System|Architecture|CPUs|Total Memory|Docker Root Dir" || true
}

# List Docker containers
list_containers() {
    local all_flag=""
    [[ "${1:-}" == "all" ]] && all_flag="-a"

    if ! is_docker_installed; then
        log_error "Docker is not installed"
        return 1
    fi

    log_info "Docker Containers"
    docker ps $all_flag
}

# List Docker images
list_images() {
    if ! is_docker_installed; then
        log_error "Docker is not installed"
        return 1
    fi

    log_info "Docker Images"
    docker images
}

# Show Docker disk usage
show_disk_usage() {
    if ! is_docker_installed; then
        log_error "Docker is not installed"
        return 1
    fi

    log_info "Docker Disk Usage"
    docker system df -v
}

# Cleanup Docker system
cleanup_docker() {
    if ! is_docker_installed; then
        log_error "Docker is not installed"
        return 1
    fi

    log_warn "This will remove:"
    echo "  - All stopped containers"
    echo "  - All networks not used by at least one container"
    echo "  - All dangling images"
    echo "  - All dangling build cache"
    echo

    read -p "Continue? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cancelled"
        return 0
    fi

    log_info "Cleaning up Docker system..."
    docker system prune -f
    log_success "Docker system cleaned"
}

# Cleanup Docker system (aggressive)
cleanup_docker_all() {
    if ! is_docker_installed; then
        log_error "Docker is not installed"
        return 1
    fi

    log_warn "This will remove:"
    echo "  - All stopped containers"
    echo "  - All networks not used by at least one container"
    echo "  - All images without at least one container"
    echo "  - All build cache"
    echo "  - All volumes not used by at least one container"
    echo

    read -p "Continue? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cancelled"
        return 0
    fi

    log_info "Cleaning up Docker system (all unused resources)..."
    docker system prune -a --volumes -f
    log_success "Docker system cleaned"
}

# Start Docker daemon
start_docker() {
    ensure_sudo

    local os
    os=$(detect_os)

    if [[ "$os" == "macos" ]]; then
        log_info "On macOS, Docker is managed by Docker Desktop"
        log_info "Please start Docker Desktop application"
        return 0
    fi

    log_info "Starting Docker daemon..."
    sudo systemctl start docker
    log_success "Docker daemon started"
}

# Stop Docker daemon
stop_docker() {
    ensure_sudo

    local os
    os=$(detect_os)

    if [[ "$os" == "macos" ]]; then
        log_info "On macOS, Docker is managed by Docker Desktop"
        log_info "Please quit Docker Desktop application"
        return 0
    fi

    log_info "Stopping Docker daemon..."
    sudo systemctl stop docker
    log_success "Docker daemon stopped"
}

# ============================================================================
# Help Function
# ============================================================================

show_help() {
    cat <<EOF
Docker Management Script v${SCRIPT_VERSION}

A comprehensive Docker management tool for installation and operations.

Usage: $0 [COMMAND] [OPTIONS]

Commands:
  install engine     Install Docker Engine
  status             Show Docker status
  ps, list           List running containers
  ps all, list all   List all containers (including stopped)
  images             List Docker images
  df, disk           Show disk usage
  cleanup            Clean up unused resources
  cleanup all        Clean up all unused resources (aggressive)
  start              Start Docker daemon
  stop               Stop Docker daemon
  version            Show Docker version
  help               Show this help message

Examples:
  # Install Docker Engine
  $0 install engine

  # Check Docker status
  $0 status

  # List all containers
  $0 ps all

  # Show disk usage
  $0 df

  # Clean up unused resources
  $0 cleanup

Remote Usage:
  # Install Docker remotely
  curl -fsSL https://scripts.pandia.io/rsr | sh -s -- docker install engine

  # Check Docker status remotely
  curl -fsSL https://scripts.pandia.io/rsr | sh -s -- docker status

  # List containers remotely
  curl -fsSL https://scripts.pandia.io/rsr | sh -s -- docker ps

Notes:
  - Installation requires sudo/root access
  - After installation, log out and back in for group changes
  - On macOS, Docker Desktop must be installed manually

EOF
}

# ============================================================================
# Main Function
# ============================================================================

main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        install)
            local install_type="${1:-engine}"
            case "$install_type" in
                engine)
                    install_docker_engine
                    ;;
                *)
                    log_error "Unknown install type: $install_type"
                    log_info "Available: engine"
                    exit 1
                    ;;
            esac
            ;;

        status)
            show_docker_status
            ;;

        ps|list)
            local show_all="${1:-}"
            list_containers "$show_all"
            ;;

        images)
            list_images
            ;;

        df|disk)
            show_disk_usage
            ;;

        cleanup)
            local cleanup_all="${1:-}"
            if [[ "$cleanup_all" == "all" ]]; then
                cleanup_docker_all
            else
                cleanup_docker
            fi
            ;;

        start)
            start_docker
            ;;

        stop)
            stop_docker
            ;;

        version)
            echo "Script Version: $SCRIPT_VERSION"
            echo "Docker Version: $(get_docker_version)"
            ;;

        help|--help|-h)
            show_help
            ;;

        *)
            log_error "Unknown command: $command"
            echo
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
