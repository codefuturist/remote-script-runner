#!/usr/bin/env bash
# DNS GitOps Installation Script
# Installs and configures DNS GitOps sync system for Pi-hole + Unbound
# Compatible with Pi-hole v6 and standard BIND zone files

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

VERSION="1.0.0"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_REPO_URL="https://github.com/codefuturist/iac-catalog.git"
DEFAULT_REPO_BRANCH="develop"
DEFAULT_INSTALL_PATH="/opt/gitops"
DEFAULT_SERVICE_TYPE="standalone"  # standalone or integrated

# =============================================================================
# Helper Functions
# =============================================================================

print_header() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                                                                  ║"
    echo "║          DNS GitOps Installation Script v${VERSION}                ║"
    echo "║                                                                  ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*"
}

log_step() {
    echo -e "${BLUE}▶${NC} $*"
}

prompt_yes_no() {
    local question="$1"
    local default="${2:-y}"
    
    if [[ "$default" == "y" ]]; then
        local prompt="[Y/n]"
    else
        local prompt="[y/N]"
    fi
    
    while true; do
        read -rp "$question $prompt: " answer
        answer=${answer:-$default}
        case "$answer" in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

check_command() {
    if command -v "$1" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# Pre-flight Checks
# =============================================================================

check_prerequisites() {
    log_step "Checking prerequisites..."
    
    local missing=()
    
    # Check for required commands
    for cmd in git python3 systemctl sudo; do
        if ! check_command "$cmd"; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing[*]}"
        log_error "Please install them and try again"
        exit 1
    fi
    
    # Check Python version
    local python_version
    python_version=$(python3 --version | awk '{print $2}' | cut -d. -f1-2)
    if [[ $(echo "$python_version < 3.6" | bc -l) -eq 1 ]]; then
        log_error "Python 3.6 or higher required (found $python_version)"
        exit 1
    fi
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        log_warn "Running as root. This is not recommended."
        if ! prompt_yes_no "Continue anyway?" "n"; then
            exit 1
        fi
    fi
    
    # Check for sudo access
    if ! sudo -n true 2>/dev/null; then
        log_warn "Sudo password will be required"
    fi
    
    log_info "Prerequisites check passed"
}

detect_environment() {
    log_step "Detecting environment..."
    
    # Check if Pi-hole is installed
    if ! check_command pihole; then
        log_error "Pi-hole not detected"
        log_error "This script requires Pi-hole to be installed"
        exit 1
    fi
    
    # Check Pi-hole version
    local pihole_version
    pihole_version=$(pihole -v | grep "Pi-hole" | awk '{print $3}' | cut -d'v' -f2 || echo "unknown")
    log_info "Pi-hole version: $pihole_version"
    
    # Check for Pi-hole TOML config (v6)
    if [[ ! -f /etc/pihole/pihole.toml ]]; then
        log_error "Pi-hole v6 configuration not found"
        log_error "This script requires Pi-hole v6+ with TOML configuration"
        exit 1
    fi
    
    log_info "Pi-hole v6+ detected"
    
    # Check if Docker is installed
    if check_command docker; then
        log_info "Docker detected"
        DOCKER_AVAILABLE=true
    else
        log_info "Docker not detected (DNS-only mode)"
        DOCKER_AVAILABLE=false
    fi
    
    # Check if gitops-sync already exists
    if [[ -f /opt/gitops/gitops-sync.sh ]]; then
        log_warn "Existing gitops-sync installation detected"
        GITOPS_SYNC_EXISTS=true
    else
        GITOPS_SYNC_EXISTS=false
    fi
}

# =============================================================================
# Configuration
# =============================================================================

configure_installation() {
    log_step "Configuration"
    echo ""
    
    # Repository URL
    echo -e "${CYAN}DNS Zone Repository Configuration:${NC}"
    read -rp "Repository URL [$DEFAULT_REPO_URL]: " REPO_URL
    REPO_URL=${REPO_URL:-$DEFAULT_REPO_URL}
    
    read -rp "Repository branch [$DEFAULT_REPO_BRANCH]: " REPO_BRANCH
    REPO_BRANCH=${REPO_BRANCH:-$DEFAULT_REPO_BRANCH}
    
    # Installation path
    read -rp "Installation path [$DEFAULT_INSTALL_PATH]: " INSTALL_PATH
    INSTALL_PATH=${INSTALL_PATH:-$DEFAULT_INSTALL_PATH}
    
    echo ""
    echo -e "${CYAN}Service Type:${NC}"
    echo "  1) Standalone (DNS sync only, recommended for DNS-only servers)"
    echo "  2) Integrated (Part of full GitOps, for infrastructure servers)"
    
    if [[ "$GITOPS_SYNC_EXISTS" == true ]]; then
        echo ""
        log_warn "Existing gitops-sync detected"
        echo "  - Choose 'Standalone' to run DNS sync independently"
        echo "  - Choose 'Integrated' to use existing gitops-sync (includes DNS)"
    fi
    
    read -rp "Choice [1-2]: " service_choice
    case "$service_choice" in
        2)
            SERVICE_TYPE="integrated"
            log_info "Selected: Integrated mode"
            ;;
        *)
            SERVICE_TYPE="standalone"
            log_info "Selected: Standalone mode"
            ;;
    esac
    
    # Sync interval
    echo ""
    read -rp "Sync interval in minutes [3]: " SYNC_INTERVAL
    SYNC_INTERVAL=${SYNC_INTERVAL:-3}
    
    # Summary
    echo ""
    echo -e "${CYAN}Installation Summary:${NC}"
    echo "  Repository: $REPO_URL"
    echo "  Branch: $REPO_BRANCH"
    echo "  Install path: $INSTALL_PATH"
    echo "  Service type: $SERVICE_TYPE"
    echo "  Sync interval: ${SYNC_INTERVAL} minutes"
    echo ""
    
    if ! prompt_yes_no "Proceed with installation?"; then
        log_warn "Installation cancelled"
        exit 0
    fi
}

# =============================================================================
# Installation Functions
# =============================================================================

create_directories() {
    log_step "Creating directories..."
    
    sudo mkdir -p "$INSTALL_PATH"
    sudo mkdir -p /var/cache/gitops-dns
    sudo mkdir -p /var/log
    
    # Set permissions
    if [[ $EUID -ne 0 ]]; then
        sudo chown -R "$USER:$USER" "$INSTALL_PATH" 2>/dev/null || true
    fi
    
    log_info "Directories created"
}

download_scripts() {
    log_step "Downloading DNS GitOps scripts..."
    
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Download sync-dns-zones.py
    log_info "Downloading zone parser..."
    curl -fsSL "https://raw.githubusercontent.com/codefuturist/remote-script-runner/main/scripts/bash/sync-dns-zones.py" \
        -o "$temp_dir/sync-dns-zones.py" || {
        log_error "Failed to download sync-dns-zones.py"
        exit 1
    }
    
    # Download dns-sync.sh (standalone service script)
    log_info "Downloading DNS sync script..."
    curl -fsSL "https://raw.githubusercontent.com/codefuturist/remote-script-runner/main/scripts/bash/dns-sync.sh" \
        -o "$temp_dir/dns-sync.sh" || {
        log_error "Failed to download dns-sync.sh"
        exit 1
    }
    
    # Download health check script
    log_info "Downloading health check script..."
    curl -fsSL "https://raw.githubusercontent.com/codefuturist/remote-script-runner/main/scripts/bash/check-dns-sync-health.sh" \
        -o "$temp_dir/check-dns-sync-health.sh" || {
        log_error "Failed to download health check script"
        exit 1
    }
    
    # Copy to installation directory
    sudo cp "$temp_dir/sync-dns-zones.py" "$INSTALL_PATH/"
    sudo cp "$temp_dir/dns-sync.sh" "$INSTALL_PATH/"
    sudo cp "$temp_dir/check-dns-sync-health.sh" "$INSTALL_PATH/"
    
    # Make executable
    sudo chmod +x "$INSTALL_PATH/dns-sync.sh"
    sudo chmod +x "$INSTALL_PATH/check-dns-sync-health.sh"
    sudo chmod +x "$INSTALL_PATH/sync-dns-zones.py"
    
    # Cleanup
    rm -rf "$temp_dir"
    
    log_info "Scripts downloaded and installed"
}

configure_sudoers() {
    log_step "Configuring sudo permissions..."
    
    sudo tee /etc/sudoers.d/dns-sync > /dev/null << 'EOF'
# DNS Sync Service - Minimal sudo permissions
root ALL=(ALL) NOPASSWD: /usr/bin/python3 /opt/gitops/sync-dns-zones.py *
root ALL=(ALL) NOPASSWD: /bin/cp /etc/pihole/pihole.toml /etc/pihole/pihole.toml.backup-*
root ALL=(ALL) NOPASSWD: /bin/systemctl restart pihole-FTL
root ALL=(ALL) NOPASSWD: /bin/systemctl status pihole-FTL
root ALL=(ALL) NOPASSWD: /bin/systemctl start pihole-FTL
root ALL=(ALL) NOPASSWD: /bin/systemctl stop pihole-FTL
EOF
    
    sudo chmod 440 /etc/sudoers.d/dns-sync
    
    # Validate sudoers file
    if ! sudo visudo -c -f /etc/sudoers.d/dns-sync; then
        log_error "Invalid sudoers configuration"
        exit 1
    fi
    
    log_info "Sudo permissions configured"
}

create_systemd_service() {
    log_step "Creating systemd service..."
    
    # Create service file
    sudo tee /etc/systemd/system/dns-sync.service > /dev/null << EOF
[Unit]
Description=DNS GitOps Sync Service
Documentation=https://github.com/codefuturist/iac-catalog
After=network-online.target pihole-FTL.service
Wants=network-online.target

[Service]
Type=oneshot
User=root
Group=root

# Environment
Environment="DNS_REPO_URL=$REPO_URL"
Environment="DNS_REPO_BRANCH=$REPO_BRANCH"
Environment="DNS_REPO_PATH=$INSTALL_PATH/iac-catalog"
Environment="DNS_ZONES_PATH=environments/global/configurations/dns-zones"
Environment="PIHOLE_TOML_PATH=/etc/pihole/pihole.toml"
Environment="DNS_CACHE_DIR=/var/cache/gitops-dns"
Environment="DNS_LOG_FILE=/var/log/dns-sync.log"
Environment="DNS_LOG_LEVEL=INFO"

# Execution
ExecStart=$INSTALL_PATH/dns-sync.sh sync

# Security
NoNewPrivileges=false
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$INSTALL_PATH /var/log /var/run /var/cache/gitops-dns /etc/pihole /tmp

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=dns-sync

# Resource limits
CPUQuota=50%
MemoryMax=512M

[Install]
WantedBy=multi-user.target
EOF
    
    # Create timer file
    sudo tee /etc/systemd/system/dns-sync.timer > /dev/null << EOF
[Unit]
Description=DNS GitOps Sync Timer
Documentation=https://github.com/codefuturist/iac-catalog
Requires=dns-sync.service

[Timer]
# Run every $SYNC_INTERVAL minutes
OnBootSec=2min
OnUnitActiveSec=${SYNC_INTERVAL}min
AccuracySec=30s

# Persistent timer (catch up if system was off)
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # Reload systemd
    sudo systemctl daemon-reload
    
    log_info "Systemd service created"
}

configure_git() {
    log_step "Configuring Git..."
    
    # Set safe directory for root
    sudo git config --global --add safe.directory "$INSTALL_PATH/iac-catalog"
    
    log_info "Git configured"
}

initialize_repository() {
    log_step "Initializing DNS repository..."
    
    # Run init command
    if sudo "$INSTALL_PATH/dns-sync.sh" init; then
        log_info "Repository initialized successfully"
    else
        log_error "Failed to initialize repository"
        exit 1
    fi
}

# =============================================================================
# Post-Installation
# =============================================================================

enable_service() {
    log_step "Enabling service..."
    
    sudo systemctl enable dns-sync.timer
    sudo systemctl start dns-sync.timer
    
    log_info "Service enabled and started"
}

run_initial_sync() {
    log_step "Running initial sync..."
    
    if sudo systemctl start dns-sync.service; then
        sleep 5
        log_info "Initial sync triggered"
    else
        log_warn "Initial sync failed (check logs)"
    fi
}

show_status() {
    echo ""
    log_step "Installation complete!"
    echo ""
    
    echo -e "${CYAN}Service Status:${NC}"
    sudo systemctl status dns-sync.timer --no-pager | head -10
    
    echo ""
    echo -e "${CYAN}Next Steps:${NC}"
    echo "  1. Check service status:"
    echo "     sudo systemctl status dns-sync.timer"
    echo ""
    echo "  2. View logs:"
    echo "     sudo tail -f /var/log/dns-sync.log"
    echo ""
    echo "  3. Test DNS resolution:"
    echo "     dig your-hostname.your-zone.com @127.0.0.1"
    echo ""
    echo "  4. Run health check:"
    echo "     sudo $INSTALL_PATH/check-dns-sync-health.sh"
    echo ""
    echo "  5. Manual sync:"
    echo "     sudo systemctl start dns-sync.service"
    echo ""
    echo -e "${CYAN}Configuration:${NC}"
    echo "  Zone files: $INSTALL_PATH/iac-catalog/environments/global/configurations/dns-zones/"
    echo "  Logs: /var/log/dns-sync.log"
    echo "  Cache: /var/cache/gitops-dns/"
    echo ""
    echo -e "${GREEN}DNS GitOps is now active and syncing every $SYNC_INTERVAL minutes!${NC}"
    echo ""
}

print_documentation() {
    echo -e "${CYAN}Documentation:${NC}"
    echo "  Quick Start: https://github.com/codefuturist/remote-script-runner"
    echo "  Zone file format: Standard BIND zone files"
    echo "  Supported records: A, AAAA, CNAME, wildcards"
    echo ""
}

# =============================================================================
# Uninstall Function
# =============================================================================

uninstall() {
    log_step "Uninstalling DNS GitOps..."
    
    # Stop and disable service
    sudo systemctl stop dns-sync.timer 2>/dev/null || true
    sudo systemctl disable dns-sync.timer 2>/dev/null || true
    sudo systemctl stop dns-sync.service 2>/dev/null || true
    
    # Remove systemd files
    sudo rm -f /etc/systemd/system/dns-sync.service
    sudo rm -f /etc/systemd/system/dns-sync.timer
    sudo systemctl daemon-reload
    
    # Remove scripts (but keep repository)
    sudo rm -f "$INSTALL_PATH/dns-sync.sh"
    sudo rm -f "$INSTALL_PATH/sync-dns-zones.py"
    sudo rm -f "$INSTALL_PATH/check-dns-sync-health.sh"
    
    # Remove sudoers
    sudo rm -f /etc/sudoers.d/dns-sync
    
    # Keep logs and cache for debugging
    log_warn "Logs and cache kept for reference:"
    log_warn "  /var/log/dns-sync.log"
    log_warn "  /var/cache/gitops-dns/"
    
    log_info "DNS GitOps uninstalled"
}

# =============================================================================
# Main Function
# =============================================================================

main() {
    local mode="${1:-install}"
    
    case "$mode" in
        install)
            print_header
            check_prerequisites
            detect_environment
            configure_installation
            
            echo ""
            log_step "Starting installation..."
            
            create_directories
            download_scripts
            configure_sudoers
            create_systemd_service
            configure_git
            initialize_repository
            
            if [[ "$SERVICE_TYPE" == "standalone" ]]; then
                enable_service
                run_initial_sync
            fi
            
            show_status
            print_documentation
            ;;
            
        uninstall)
            print_header
            if prompt_yes_no "Are you sure you want to uninstall DNS GitOps?"; then
                uninstall
            else
                log_info "Uninstall cancelled"
            fi
            ;;
            
        *)
            echo "Usage: $SCRIPT_NAME {install|uninstall}"
            echo ""
            echo "Commands:"
            echo "  install   - Install DNS GitOps system (default)"
            echo "  uninstall - Remove DNS GitOps system"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
