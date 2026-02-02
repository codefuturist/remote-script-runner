#!/usr/bin/env bash
# =============================================================================
# lib/modules/bootstrap.sh - RSR Bootstrap Module
# Orchestrates host bootstrapping using existing scripts and modules
#
# Usage: source "${RSR_LIB_DIR:-./lib}/modules/bootstrap.sh"
#
# Provides:
#   - rsr_bootstrap_packages     - Install essential/dev packages
#   - rsr_bootstrap_docker       - Install Docker using docker module
#   - rsr_bootstrap_ssh          - Configure SSH using ssh module
#   - rsr_bootstrap_firewall     - Configure firewall
#   - rsr_bootstrap_fail2ban     - Install and configure fail2ban
#   - rsr_bootstrap_user         - Create admin user
#   - rsr_bootstrap_hostname     - Set system hostname
#   - rsr_bootstrap_timezone     - Configure timezone
#   - rsr_bootstrap_full         - Complete bootstrap workflow
# =============================================================================

# Guard: Prevent double-sourcing
[[ -n "${_RSR_MODULE_BOOTSTRAP_LOADED:-}" ]] && return 0
_RSR_MODULE_BOOTSTRAP_LOADED=1

# Module version
_RSR_BOOTSTRAP_VERSION="1.0.0"

# =============================================================================
# Dependencies
# =============================================================================

# Ensure core and subscript modules are loaded
if [[ -z "${_RSR_CORE_INIT_LOADED:-}" ]]; then
    _bootstrap_lib_dir="${RSR_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)}"
    # shellcheck source=../core/init.sh
    source "${_bootstrap_lib_dir}/core/init.sh" 2>/dev/null || {
        echo "ERROR: RSR core/init.sh must be sourced first" >&2
        return 1
    }
fi

# Load subscript module
if [[ -z "${_RSR_CORE_SUBSCRIPT_LOADED:-}" ]]; then
    # shellcheck source=../core/subscript.sh
    source "${RSR_LIB_DIR}/core/subscript.sh" 2>/dev/null || {
        rsr_log_warn "Subscript module not available, some features disabled"
    }
fi

# Load packages module
if [[ -z "${_RSR_MODULE_PACKAGES_LOADED:-}" ]]; then
    # shellcheck source=packages.sh
    source "${RSR_LIB_DIR}/modules/packages.sh" 2>/dev/null || true
fi

# Load docker module
if [[ -z "${_RSR_MODULE_DOCKER_LOADED:-}" ]]; then
    # shellcheck source=docker.sh
    source "${RSR_LIB_DIR}/modules/docker.sh" 2>/dev/null || true
fi

# Load ssh module
if [[ -z "${_RSR_MODULE_SSH_LOADED:-}" ]]; then
    # shellcheck source=ssh.sh
    source "${RSR_LIB_DIR}/modules/ssh.sh" 2>/dev/null || true
fi

# Load users module
if [[ -z "${_RSR_MODULE_USERS_LOADED:-}" ]]; then
    # shellcheck source=users.sh
    source "${RSR_LIB_DIR}/modules/users.sh" 2>/dev/null || true
fi

# =============================================================================
# Configuration
# =============================================================================

# Bootstrap profiles
declare -gA RSR_BOOTSTRAP_PROFILES=(
    [minimal]="packages_essential"
    [server]="packages_essential ssh_harden firewall fail2ban"
    [workstation]="packages_essential packages_dev ssh_harden"
    [dev]="packages_essential packages_dev docker ssh_harden"
)

# Package lists by category
declare -ga RSR_BOOTSTRAP_PACKAGES_ESSENTIAL=(
    curl wget git vim htop
)

declare -ga RSR_BOOTSTRAP_PACKAGES_DEV=(
    jq unzip make
)

# =============================================================================
# Homebrew Installation (macOS)
# =============================================================================

# Check if Homebrew is installed
rsr_homebrew_installed() {
    command -v brew &>/dev/null
}

# Install Homebrew on macOS
# Usage: rsr_bootstrap_homebrew [--dry-run]
rsr_bootstrap_homebrew() {
    local dry_run="${RSR_DRY_RUN:-false}"
    [[ "$1" == "--dry-run" ]] && dry_run=true
    
    local os_id
    os_id="$(rsr_detect_os)"
    
    # Only for macOS
    if [[ "$os_id" != "darwin" ]]; then
        rsr_log_debug "Homebrew installation skipped (not macOS)"
        return 0
    fi
    
    # Check if already installed
    if rsr_homebrew_installed; then
        rsr_log_ok "Homebrew is already installed"
        return 0
    fi
    
    rsr_log_info "Installing Homebrew..."
    
    if [[ "$dry_run" == "true" ]]; then
        rsr_log_info "[DRY RUN] Would install Homebrew using official installer"
        rsr_log_info "[DRY RUN] Command: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        return 0
    fi
    
    # Install Homebrew using the official command
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    if [[ $? -eq 0 ]]; then
        rsr_log_ok "Homebrew installed successfully"
        
        # Add Homebrew to PATH for Apple Silicon Macs
        if [[ -f /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
            rsr_log_info "Added Homebrew to PATH (Apple Silicon)"
            rsr_log_info "Add this to your shell profile: eval \"\$(/opt/homebrew/bin/brew shellenv)\""
        elif [[ -f /usr/local/bin/brew ]]; then
            eval "$(/usr/local/bin/brew shellenv)"
            rsr_log_info "Added Homebrew to PATH (Intel Mac)"
        fi
    else
        rsr_log_error "Failed to install Homebrew"
        return 1
    fi
}

# =============================================================================
# Package Installation
# =============================================================================

# Get essential packages for current OS
_rsr_bootstrap_get_essential_packages() {
    local mgr
    mgr="$(rsr_pkg_manager 2>/dev/null || rsr_detect_package_manager)"
    
    case "$mgr" in
        apt)
            echo "curl wget git vim htop net-tools dnsutils sudo ca-certificates gnupg lsb-release"
            ;;
        dnf|yum)
            echo "curl wget git vim htop net-tools bind-utils sudo ca-certificates gnupg"
            ;;
        pacman)
            echo "curl wget git vim htop net-tools bind-tools sudo ca-certificates gnupg"
            ;;
        apk)
            echo "curl wget git vim htop net-tools bind-tools sudo ca-certificates gnupg"
            ;;
        brew)
            echo "curl wget git vim htop"
            ;;
        *)
            echo "curl wget git vim"
            ;;
    esac
}

# Get development packages for current OS
_rsr_bootstrap_get_dev_packages() {
    local mgr
    mgr="$(rsr_pkg_manager 2>/dev/null || rsr_detect_package_manager)"
    
    case "$mgr" in
        apt)
            echo "build-essential make gcc g++ python3 python3-pip jq unzip"
            ;;
        dnf|yum)
            echo "gcc gcc-c++ make python3 python3-pip jq unzip"
            ;;
        pacman)
            echo "base-devel python python-pip jq unzip"
            ;;
        apk)
            echo "build-base python3 py3-pip jq unzip"
            ;;
        brew)
            echo "python3 jq"
            ;;
        *)
            echo "make gcc python3 jq"
            ;;
    esac
}

# Install essential packages
# Usage: rsr_bootstrap_packages_essential [--dry-run]
rsr_bootstrap_packages_essential() {
    local dry_run="${RSR_DRY_RUN:-false}"
    [[ "$1" == "--dry-run" ]] && dry_run=true
    
    local os_id
    os_id="$(rsr_detect_os)"
    
    # On macOS, ensure Homebrew is installed first
    if [[ "$os_id" == "darwin" ]]; then
        if ! rsr_homebrew_installed; then
            if [[ "$dry_run" == "true" ]]; then
                rsr_log_info "[DRY RUN] Would install Homebrew first (required for macOS packages)"
            else
                rsr_log_info "Homebrew is required for package installation on macOS"
                rsr_bootstrap_homebrew
            fi
        fi
    fi
    
    local packages
    packages="$(_rsr_bootstrap_get_essential_packages)"
    
    rsr_log_info "Installing essential packages..."
    
    if [[ "$dry_run" == "true" ]]; then
        rsr_log_info "[DRY RUN] Would install: $packages"
        return 0
    fi
    
    # Use packages module if available
    if declare -f rsr_pkg_install_many &>/dev/null; then
        rsr_pkg_update_cache
        # shellcheck disable=SC2086
        rsr_pkg_install_many $packages
    else
        # Fallback to direct installation
        _rsr_bootstrap_install_packages "$packages"
    fi
}

# Install development packages
# Usage: rsr_bootstrap_packages_dev [--dry-run]
rsr_bootstrap_packages_dev() {
    local dry_run="${RSR_DRY_RUN:-false}"
    [[ "$1" == "--dry-run" ]] && dry_run=true
    
    local packages
    packages="$(_rsr_bootstrap_get_dev_packages)"
    
    rsr_log_info "Installing development packages..."
    
    if [[ "$dry_run" == "true" ]]; then
        rsr_log_info "[DRY RUN] Would install: $packages"
        return 0
    fi
    
    if declare -f rsr_pkg_install_many &>/dev/null; then
        # shellcheck disable=SC2086
        rsr_pkg_install_many $packages
    else
        _rsr_bootstrap_install_packages "$packages"
    fi
}

# Fallback package installation
_rsr_bootstrap_install_packages() {
    local packages="$1"
    local mgr
    mgr="$(rsr_detect_package_manager)"
    
    local sudo_cmd=""
    [[ "$EUID" -ne 0 ]] && sudo_cmd="sudo"
    
    case "$mgr" in
        apt)
            $sudo_cmd apt-get update -qq
            # shellcheck disable=SC2086
            $sudo_cmd apt-get install -y -qq $packages
            ;;
        dnf)
            # shellcheck disable=SC2086
            $sudo_cmd dnf install -y -q $packages
            ;;
        yum)
            # shellcheck disable=SC2086
            $sudo_cmd yum install -y -q $packages
            ;;
        pacman)
            # shellcheck disable=SC2086
            $sudo_cmd pacman -Sy --noconfirm --needed $packages
            ;;
        apk)
            $sudo_cmd apk update
            # shellcheck disable=SC2086
            $sudo_cmd apk add -q $packages
            ;;
        brew)
            brew update --quiet
            # shellcheck disable=SC2086
            brew install -q $packages
            ;;
        *)
            rsr_log_warn "Unknown package manager: $mgr"
            return 1
            ;;
    esac
}

# =============================================================================
# Docker Installation
# =============================================================================

# Install Docker
# Usage: rsr_bootstrap_docker [--dry-run]
rsr_bootstrap_docker() {
    local dry_run="${RSR_DRY_RUN:-false}"
    [[ "$1" == "--dry-run" ]] && dry_run=true
    
    rsr_log_info "Installing Docker..."
    
    if [[ "$dry_run" == "true" ]]; then
        rsr_log_info "[DRY RUN] Would install Docker"
        return 0
    fi
    
    # Check if already installed
    if command -v docker &>/dev/null; then
        rsr_log_ok "Docker is already installed"
        return 0
    fi
    
    # Try using docker-management subscript if available
    if rsr_subscript_exists "docker" 2>/dev/null; then
        rsr_log_debug "Using docker-management subscript"
        rsr_run_subscript "docker" install engine
        return $?
    fi
    
    # Try using docker module
    if declare -f rsr_docker_install &>/dev/null; then
        rsr_log_debug "Using docker module"
        rsr_docker_install
        return $?
    fi
    
    # Fallback: direct installation
    _rsr_bootstrap_install_docker_direct
}

# Direct Docker installation (fallback)
_rsr_bootstrap_install_docker_direct() {
    local os_id
    os_id="$(rsr_detect_os)"
    local distro
    distro="$(rsr_detect_distro)"
    
    local sudo_cmd=""
    [[ "$EUID" -ne 0 ]] && sudo_cmd="sudo"
    
    case "$distro" in
        ubuntu|debian)
            # Add Docker's official GPG key
            $sudo_cmd install -m 0755 -d /etc/apt/keyrings
            curl -fsSL "https://download.docker.com/linux/$distro/gpg" | $sudo_cmd gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            $sudo_cmd chmod a+r /etc/apt/keyrings/docker.gpg
            
            # Add the repository
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$distro $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
                $sudo_cmd tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            $sudo_cmd apt-get update -qq
            $sudo_cmd apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        centos|rhel|fedora|rocky|alma)
            $sudo_cmd dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 2>/dev/null || \
                $sudo_cmd yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            $sudo_cmd dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || \
                $sudo_cmd yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        *)
            case "$os_id" in
                darwin)
                    if command -v brew &>/dev/null; then
                        brew install --cask docker
                        rsr_log_info "Docker Desktop installed. Please start it from Applications."
                    else
                        rsr_log_warn "Install Docker Desktop from https://docker.com/products/docker-desktop"
                    fi
                    return 0
                    ;;
                *)
                    rsr_log_error "Docker installation not supported on $distro"
                    rsr_log_info "Visit https://docs.docker.com/engine/install/ for manual installation"
                    return 1
                    ;;
            esac
            ;;
    esac
    
    # Start and enable Docker
    if command -v systemctl &>/dev/null; then
        $sudo_cmd systemctl start docker
        $sudo_cmd systemctl enable docker
    fi
    
    # Add current user to docker group
    local target_user="${SUDO_USER:-$USER}"
    if [[ -n "$target_user" ]] && [[ "$target_user" != "root" ]]; then
        $sudo_cmd usermod -aG docker "$target_user"
        rsr_log_info "Added $target_user to docker group (log out and back in to take effect)"
    fi
    
    rsr_log_ok "Docker installed successfully"
}

# =============================================================================
# SSH Configuration
# =============================================================================

# Configure SSH security
# Usage: rsr_bootstrap_ssh [--dry-run]
# NOTE: Only makes changes that are explicitly safe and reversible
rsr_bootstrap_ssh() {
    local dry_run="${RSR_DRY_RUN:-false}"
    [[ "$1" == "--dry-run" ]] && dry_run=true
    
    rsr_log_info "Configuring SSH security..."
    
    local sshd_config="/etc/ssh/sshd_config"
    
    if [[ ! -f "$sshd_config" ]]; then
        rsr_log_warn "SSH config not found, skipping SSH configuration"
        return 0
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        rsr_log_info "[DRY RUN] Would configure SSH:"
        rsr_log_info "  - Disable root login (PermitRootLogin no)"
        rsr_log_info "  - Set MaxAuthTries to 3"
        rsr_log_info "  - Note: Password auth unchanged unless SSH keys exist"
        return 0
    fi
    
    # Try using ssh-hardening subscript if available
    if rsr_subscript_exists "ssh-harden" 2>/dev/null; then
        rsr_log_debug "Using ssh-hardening subscript"
        # Only apply explicit, safe changes - disable root login
        rsr_run_subscript "ssh-harden" --no-root -y
        return $?
    fi
    
    # Try using ssh module
    if declare -f rsr_ssh_config_set &>/dev/null; then
        rsr_log_debug "Using ssh module"
        
        # Backup before any changes
        local backup_file="${sshd_config}.backup.$(date +%Y%m%d%H%M%S)"
        cp "$sshd_config" "$backup_file" 2>/dev/null || sudo cp "$sshd_config" "$backup_file"
        rsr_log_info "Backup created: $backup_file"
        
        # Safe change: disable root login
        rsr_ssh_config_set "PermitRootLogin" "no"
        rsr_log_ok "Disabled root SSH login"
        
        # Safe change: limit auth tries
        rsr_ssh_config_set "MaxAuthTries" "3"
        rsr_log_ok "Set MaxAuthTries to 3"
        
        # CONSERVATIVE: Only disable password auth if user has SSH keys
        # This prevents lockout
        if [[ -f ~/.ssh/authorized_keys ]] && [[ -s ~/.ssh/authorized_keys ]]; then
            rsr_log_info "SSH keys found in ~/.ssh/authorized_keys"
            rsr_log_warn "Password authentication NOT disabled (manual action required)"
            rsr_log_info "To disable password auth: sudo sed -i 's/.*PasswordAuthentication.*/PasswordAuthentication no/' $sshd_config"
        else
            rsr_log_warn "No SSH keys found - keeping password authentication enabled"
        fi
        
        # Restart SSH to apply changes
        rsr_ssh_server_restart 2>/dev/null || true
        return 0
    fi
    
    # Fallback: direct configuration
    _rsr_bootstrap_configure_ssh_direct
}

# Direct SSH configuration (fallback)
# NOTE: Conservative - does NOT auto-disable password auth
_rsr_bootstrap_configure_ssh_direct() {
    local sshd_config="/etc/ssh/sshd_config"
    local sudo_cmd=""
    [[ "$EUID" -ne 0 ]] && sudo_cmd="sudo"
    
    # Backup original config FIRST
    local backup_file="${sshd_config}.backup.$(date +%Y%m%d%H%M%S)"
    $sudo_cmd cp "$sshd_config" "$backup_file"
    rsr_log_info "Backup created: $backup_file"
    
    # Safe change: Disable root login
    if grep -q "^#*PermitRootLogin" "$sshd_config"; then
        $sudo_cmd sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' "$sshd_config"
    else
        echo "PermitRootLogin no" | $sudo_cmd tee -a "$sshd_config" > /dev/null
    fi
    rsr_log_ok "Disabled root SSH login"
    
    # Safe change: Set max auth tries
    if grep -q "^#*MaxAuthTries" "$sshd_config"; then
        $sudo_cmd sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' "$sshd_config"
    else
        echo "MaxAuthTries 3" | $sudo_cmd tee -a "$sshd_config" > /dev/null
    fi
    rsr_log_ok "Set MaxAuthTries to 3"
    
    # CONSERVATIVE: Do NOT auto-disable password auth (risk of lockout)
    if [[ -f ~/.ssh/authorized_keys ]] && [[ -s ~/.ssh/authorized_keys ]]; then
        rsr_log_info "SSH keys found in ~/.ssh/authorized_keys"
        rsr_log_warn "Password authentication NOT auto-disabled (manual action required for security)"
        rsr_log_info "To disable: sudo sed -i 's/.*PasswordAuthentication.*/PasswordAuthentication no/' $sshd_config && sudo systemctl restart sshd"
    else
        rsr_log_warn "No SSH keys found - password authentication remains enabled"
    fi
    
    # Restart SSH service
    if command -v systemctl &>/dev/null; then
        $sudo_cmd systemctl restart sshd 2>/dev/null || $sudo_cmd systemctl restart ssh 2>/dev/null
    elif command -v service &>/dev/null; then
        $sudo_cmd service sshd restart 2>/dev/null || $sudo_cmd service ssh restart 2>/dev/null
    fi
    
    rsr_log_ok "SSH security configured (backup: $backup_file)"
}

# =============================================================================
# Firewall Configuration
# =============================================================================

# Configure firewall
# Usage: rsr_bootstrap_firewall [--dry-run]
rsr_bootstrap_firewall() {
    local dry_run="${RSR_DRY_RUN:-false}"
    [[ "$1" == "--dry-run" ]] && dry_run=true
    
    local os_id
    os_id="$(rsr_detect_os)"
    
    if [[ "$os_id" == "darwin" ]]; then
        rsr_log_info "macOS firewall can be configured in System Preferences > Security & Privacy"
        return 0
    fi
    
    rsr_log_info "Configuring firewall..."
    
    if [[ "$dry_run" == "true" ]]; then
        rsr_log_info "[DRY RUN] Would configure firewall:"
        rsr_log_info "  - Allow SSH (port 22)"
        rsr_log_info "  - Allow HTTP (port 80)"
        rsr_log_info "  - Allow HTTPS (port 443)"
        rsr_log_info "  - Enable firewall"
        return 0
    fi
    
    # Try using firewall subscript if available
    if rsr_subscript_exists "firewall" 2>/dev/null; then
        rsr_log_debug "Using firewall subscript"
        rsr_run_subscript "firewall" --preset web -y
        return $?
    fi
    
    # Fallback: direct configuration
    _rsr_bootstrap_configure_firewall_direct
}

# Direct firewall configuration (fallback)
_rsr_bootstrap_configure_firewall_direct() {
    local sudo_cmd=""
    [[ "$EUID" -ne 0 ]] && sudo_cmd="sudo"
    
    if command -v ufw &>/dev/null; then
        $sudo_cmd ufw default deny incoming
        $sudo_cmd ufw default allow outgoing
        $sudo_cmd ufw allow ssh
        $sudo_cmd ufw allow http
        $sudo_cmd ufw allow https
        $sudo_cmd ufw --force enable
        rsr_log_ok "UFW firewall configured and enabled"
    elif command -v firewall-cmd &>/dev/null; then
        $sudo_cmd firewall-cmd --permanent --add-service=ssh
        $sudo_cmd firewall-cmd --permanent --add-service=http
        $sudo_cmd firewall-cmd --permanent --add-service=https
        $sudo_cmd firewall-cmd --reload
        rsr_log_ok "Firewalld configured"
    else
        rsr_log_warn "No supported firewall found (ufw or firewalld)"
        return 1
    fi
}

# =============================================================================
# Fail2ban Installation
# =============================================================================

# Install and configure fail2ban
# Usage: rsr_bootstrap_fail2ban [--dry-run]
rsr_bootstrap_fail2ban() {
    local dry_run="${RSR_DRY_RUN:-false}"
    [[ "$1" == "--dry-run" ]] && dry_run=true
    
    local os_id
    os_id="$(rsr_detect_os)"
    
    if [[ "$os_id" == "darwin" ]]; then
        rsr_log_info "fail2ban is not typically used on macOS"
        return 0
    fi
    
    rsr_log_info "Installing fail2ban..."
    
    if [[ "$dry_run" == "true" ]]; then
        rsr_log_info "[DRY RUN] Would install and configure fail2ban"
        return 0
    fi
    
    local sudo_cmd=""
    [[ "$EUID" -ne 0 ]] && sudo_cmd="sudo"
    
    # Install fail2ban
    if declare -f rsr_pkg_install &>/dev/null; then
        rsr_pkg_install fail2ban
    else
        _rsr_bootstrap_install_packages "fail2ban"
    fi
    
    # Create basic jail configuration
    local jail_local="/etc/fail2ban/jail.local"
    if [[ ! -f "$jail_local" ]]; then
        cat << 'EOF' | $sudo_cmd tee "$jail_local" > /dev/null
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
EOF
    fi
    
    # Start and enable fail2ban
    if command -v systemctl &>/dev/null; then
        $sudo_cmd systemctl enable fail2ban
        $sudo_cmd systemctl start fail2ban
    fi
    
    rsr_log_ok "fail2ban installed and configured"
}

# =============================================================================
# User Management
# =============================================================================

# Create admin user
# Usage: rsr_bootstrap_user "username" [--sudo] [--dry-run]
rsr_bootstrap_user() {
    local username="$1"
    shift
    
    local with_sudo=false
    local dry_run="${RSR_DRY_RUN:-false}"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sudo) with_sudo=true ;;
            --dry-run) dry_run=true ;;
        esac
        shift
    done
    
    [[ -z "$username" ]] && return 0
    
    rsr_log_info "Creating admin user: $username"
    
    if [[ "$dry_run" == "true" ]]; then
        rsr_log_info "[DRY RUN] Would create user: $username (sudo: $with_sudo)"
        return 0
    fi
    
    local os_id
    os_id="$(rsr_detect_os)"
    
    local sudo_cmd=""
    [[ "$EUID" -ne 0 ]] && sudo_cmd="sudo"
    
    # Check if user exists
    if id "$username" &>/dev/null; then
        rsr_log_warn "User $username already exists"
    else
        if [[ "$os_id" == "darwin" ]]; then
            rsr_log_warn "User creation on macOS requires manual steps"
            rsr_log_info "Use System Preferences > Users & Groups to create user"
        else
            # Try using users module
            if declare -f rsr_user_create &>/dev/null; then
                rsr_user_create "$username"
            else
                $sudo_cmd useradd -m -s /bin/bash "$username"
            fi
            rsr_log_ok "Created user: $username"
        fi
    fi
    
    # Add to sudo/wheel group
    if [[ "$with_sudo" == true ]] && [[ "$os_id" != "darwin" ]]; then
        if getent group sudo &>/dev/null; then
            $sudo_cmd usermod -aG sudo "$username"
        elif getent group wheel &>/dev/null; then
            $sudo_cmd usermod -aG wheel "$username"
        fi
        rsr_log_ok "Added $username to sudo group"
    fi
}

# =============================================================================
# System Configuration
# =============================================================================

# Set hostname
# Usage: rsr_bootstrap_hostname "newhostname" [--dry-run]
rsr_bootstrap_hostname() {
    local hostname="$1"
    local dry_run="${RSR_DRY_RUN:-false}"
    [[ "$2" == "--dry-run" ]] && dry_run=true
    
    [[ -z "$hostname" ]] && return 0
    
    rsr_log_info "Setting hostname to: $hostname"
    
    if [[ "$dry_run" == "true" ]]; then
        rsr_log_info "[DRY RUN] Would set hostname to: $hostname"
        return 0
    fi
    
    local sudo_cmd=""
    [[ "$EUID" -ne 0 ]] && sudo_cmd="sudo"
    
    if command -v hostnamectl &>/dev/null; then
        $sudo_cmd hostnamectl set-hostname "$hostname"
    else
        echo "$hostname" | $sudo_cmd tee /etc/hostname > /dev/null
        $sudo_cmd hostname "$hostname"
    fi
    
    # Update /etc/hosts
    if ! grep -q "$hostname" /etc/hosts; then
        echo "127.0.1.1 $hostname" | $sudo_cmd tee -a /etc/hosts > /dev/null
    fi
    
    rsr_log_ok "Hostname set to: $hostname"
}

# Set timezone
# Usage: rsr_bootstrap_timezone "America/New_York" [--dry-run]
rsr_bootstrap_timezone() {
    local timezone="$1"
    local dry_run="${RSR_DRY_RUN:-false}"
    [[ "$2" == "--dry-run" ]] && dry_run=true
    
    [[ -z "$timezone" ]] && return 0
    
    rsr_log_info "Setting timezone to: $timezone"
    
    if [[ "$dry_run" == "true" ]]; then
        rsr_log_info "[DRY RUN] Would set timezone to: $timezone"
        return 0
    fi
    
    local sudo_cmd=""
    [[ "$EUID" -ne 0 ]] && sudo_cmd="sudo"
    
    if command -v timedatectl &>/dev/null; then
        $sudo_cmd timedatectl set-timezone "$timezone"
    elif [[ -f "/usr/share/zoneinfo/$timezone" ]]; then
        $sudo_cmd ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
        echo "$timezone" | $sudo_cmd tee /etc/timezone > /dev/null
    fi
    
    rsr_log_ok "Timezone set to: $timezone"
}

# =============================================================================
# Full Bootstrap Workflow
# =============================================================================

# Apply a bootstrap profile
# Usage: rsr_bootstrap_profile "server" [--dry-run]
rsr_bootstrap_profile() {
    local profile="$1"
    local dry_run="${RSR_DRY_RUN:-false}"
    [[ "$2" == "--dry-run" ]] && dry_run=true
    
    local profile_steps="${RSR_BOOTSTRAP_PROFILES[$profile]:-}"
    
    if [[ -z "$profile_steps" ]]; then
        rsr_log_error "Unknown bootstrap profile: $profile"
        rsr_log_info "Available profiles: ${!RSR_BOOTSTRAP_PROFILES[*]}"
        return 1
    fi
    
    rsr_log_info "Applying bootstrap profile: $profile"
    rsr_log_debug "Steps: $profile_steps"
    
    local dry_arg=""
    [[ "$dry_run" == "true" ]] && dry_arg="--dry-run"
    
    for step in $profile_steps; do
        case "$step" in
            packages_essential) rsr_bootstrap_packages_essential $dry_arg ;;
            packages_dev) rsr_bootstrap_packages_dev $dry_arg ;;
            docker) rsr_bootstrap_docker $dry_arg ;;
            ssh_harden) rsr_bootstrap_ssh $dry_arg ;;
            firewall) rsr_bootstrap_firewall $dry_arg ;;
            fail2ban) rsr_bootstrap_fail2ban $dry_arg ;;
            *)
                rsr_log_warn "Unknown bootstrap step: $step"
                ;;
        esac
    done
    
    rsr_log_ok "Bootstrap profile '$profile' applied"
}

# Full bootstrap with all options
# Usage: rsr_bootstrap_full [options]
rsr_bootstrap_full() {
    local profile="server"
    local hostname=""
    local timezone=""
    local admin_user=""
    local dry_run="${RSR_DRY_RUN:-false}"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --profile) profile="$2"; shift ;;
            --hostname) hostname="$2"; shift ;;
            --timezone) timezone="$2"; shift ;;
            --user) admin_user="$2"; shift ;;
            --dry-run) dry_run=true ;;
            *) ;;
        esac
        shift
    done
    
    local dry_arg=""
    [[ "$dry_run" == "true" ]] && dry_arg="--dry-run"
    
    rsr_log_info "Starting full bootstrap (profile: $profile)"
    
    # System configuration
    [[ -n "$hostname" ]] && rsr_bootstrap_hostname "$hostname" $dry_arg
    [[ -n "$timezone" ]] && rsr_bootstrap_timezone "$timezone" $dry_arg
    [[ -n "$admin_user" ]] && rsr_bootstrap_user "$admin_user" --sudo $dry_arg
    
    # Apply profile
    rsr_bootstrap_profile "$profile" $dry_arg
    
    rsr_log_ok "Full bootstrap complete"
}

# =============================================================================
# Module Registration
# =============================================================================

rsr_log_debug "RSR bootstrap module loaded (v${_RSR_BOOTSTRAP_VERSION})"
