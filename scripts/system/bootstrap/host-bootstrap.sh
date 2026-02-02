#!/bin/bash
# =============================================================================
# @id           host-bootstrap
# @name         host-bootstrap
# @displayName  Host Bootstrap
# @description  Interactive wizard to bootstrap a new host with essential tools, SSH, and security
# @category     system
# @version      2.0.0
# @author       codefuturist
# @tags         bootstrap,setup,host,server,workstation,initialization,wizard
# @shells       bash
# =============================================================================

# Host Bootstrap Script - User-friendly wizard for new host setup
# 
# This script guides users through bootstrapping a new host with:
# - Essential system packages
# - SSH configuration and hardening
# - Basic security settings
# - Development tools (optional)
# - Docker (optional)
#
# This script uses the RSR bootstrap module for actual operations,
# providing a user-friendly CLI and wizard interface.
#
# Usage:
#   Interactive:  rsr bootstrap
#   Remote:       curl -fsSL https://scripts.pandia.io/rsr | sh -s -- bootstrap
#   Quick mode:   rsr bootstrap --quick --profile server

set -eo pipefail

# =============================================================================
# Load RSR Library with Bootstrap Module
# =============================================================================

SCRIPT_SOURCE="${BASH_SOURCE[0]:-${0:-}}"
if [ -n "${SCRIPT_SOURCE}" ] && [ "${SCRIPT_SOURCE}" != "bash" ] && [ "${SCRIPT_SOURCE}" != "sh" ] && [ "${SCRIPT_SOURCE}" != "-bash" ] && [ "${SCRIPT_SOURCE}" != "-sh" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_SOURCE}")" 2> /dev/null && pwd)" || SCRIPT_DIR=""
else
    SCRIPT_DIR=""
fi
RSR_LIB_DIR="${SCRIPT_DIR}/../../../lib"
export RSR_ROOT="${SCRIPT_DIR}/../../.."

# Load RSR library with bootstrap module
RSR_LIB_LOADED=0
BOOTSTRAP_MODULE_LOADED=0
if [[ -f "$RSR_LIB_DIR/rsr-lib.sh" ]]; then
    # Save and clear positional params to prevent rsr-lib from processing them
    _saved_args=("$@")
    set --
    # shellcheck source=../../../lib/rsr-lib.sh
    source "$RSR_LIB_DIR/rsr-lib.sh" && RSR_LIB_LOADED=1
    
    # Load bootstrap module
    if [[ "$RSR_LIB_LOADED" == 1 ]]; then
        rsr_load_module bootstrap && BOOTSTRAP_MODULE_LOADED=1
        rsr_load_module subscript 2>/dev/null || true
    fi
    
    # Restore positional params
    set -- "${_saved_args[@]}"
    unset _saved_args
fi

# =============================================================================
# Script Configuration
# =============================================================================

SCRIPT_NAME="Host Bootstrap"
SCRIPT_VERSION="2.0.0"

# Defaults (exported for bootstrap module)
# IMPORTANT: All changes default to FALSE - only do what user explicitly requests
PROFILE=""
HOSTNAME_NEW=""
TIMEZONE=""
DRY_RUN=false
VERBOSE=false
QUICK_MODE=false
INTERACTIVE=auto
RSR_YES=0
SKIP_SSH=false
SKIP_SECURITY=false
SKIP_PACKAGES=false

# What to install - ALL default to FALSE (do nothing unless requested)
INSTALL_ESSENTIALS=false
INSTALL_DEV_TOOLS=false
INSTALL_DOCKER=false
INSTALL_HOMEBREW=false
CONFIGURE_SSH=false
CONFIGURE_FIREWALL=false
CONFIGURE_FAIL2BAN=false
CREATE_USER=""
CREATE_USER_SUDO=false

# =============================================================================
# Color Setup (fallback if RSR lib not loaded)
# =============================================================================

setup_colors() {
    if [[ -t 1 ]]; then
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        CYAN='\033[0;36m'
        MAGENTA='\033[0;35m'
        DIM='\033[2m'
        BOLD='\033[1m'
        NC='\033[0m'
    else
        RED='' GREEN='' YELLOW='' BLUE='' CYAN='' MAGENTA='' DIM='' BOLD='' NC=''
    fi
}

# Use RSR colors if available AND we're in a TTY, otherwise set up our own
if [[ -z "${RSR_COLOR_RED:-}" ]] || [[ ! -t 1 ]]; then
    setup_colors
else
    RED="${RSR_COLOR_RED}" GREEN="${RSR_COLOR_GREEN}" YELLOW="${RSR_COLOR_YELLOW}"
    BLUE="${RSR_COLOR_BLUE}" CYAN="${RSR_COLOR_CYAN}" MAGENTA="${RSR_COLOR_MAGENTA:-\033[0;35m}"
    DIM="${RSR_COLOR_DIM}" BOLD="${RSR_COLOR_BOLD:-\033[1m}" NC="${RSR_COLOR_RESET}"
fi

# =============================================================================
# Logging Functions
# =============================================================================

log_info() { 
    if [[ -t 1 ]]; then
        printf "${BLUE}▸${NC} %s\n" "$1"
    else
        printf "INFO: %s\n" "$1"
    fi
}
log_ok() { 
    if [[ -t 1 ]]; then
        printf "${GREEN}✓${NC} %s\n" "$1"
    else
        printf "OK: %s\n" "$1"
    fi
}
log_warn() { 
    if [[ -t 1 ]]; then
        printf "${YELLOW}⚠${NC} %s\n" "$1" >&2
    else
        printf "WARN: %s\n" "$1" >&2
    fi
}
log_error() { 
    if [[ -t 1 ]]; then
        printf "${RED}✗${NC} %s\n" "$1" >&2
    else
        printf "ERROR: %s\n" "$1" >&2
    fi
}
log_step() { 
    if [[ -t 1 ]]; then
        printf "\n${BOLD}${CYAN}» %s${NC}\n" "$1"
    else
        printf "\n=== %s ===\n" "$1"
    fi
}
log_debug() { 
    if [[ "$VERBOSE" == true ]]; then
        printf "${DIM}[debug]${NC} %s\n" "$1"
    fi
}

# =============================================================================
# Display Functions
# =============================================================================

show_banner() {
    printf "\n"
    printf "${BOLD}${CYAN}"
    cat << 'EOF'
    ┌─────────────────────────────────────────────────────────────┐
    │                                                             │
    │   🚀  Host Bootstrap Wizard                                 │
    │                                                             │
    │   Set up a new host with essential tools and configuration  │
    │                                                             │
    └─────────────────────────────────────────────────────────────┘
EOF
    printf "${NC}\n"
}

show_help() {
    cat << EOF
${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}

Bootstrap a new host with essential tools and configuration.

${BOLD}IMPORTANT:${NC} Nothing is changed unless you explicitly request it via a profile
or individual flags. Use --dry-run to preview changes before applying.

${BOLD}Usage:${NC}
  rsr bootstrap                     # Interactive wizard
  rsr bootstrap --quick             # Quick setup with defaults
  rsr bootstrap --profile server    # Use preset profile

${BOLD}Options:${NC}
  -h, --help              Show this help
  -v, --verbose           Verbose output
  -d, --dry-run           Show what would be done (no changes made)
  -y, --yes               Auto-confirm all prompts
  --quick                 Quick mode with sensible defaults
  --profile PROFILE       Use preset profile: minimal, server, workstation, dev

${BOLD}Configuration:${NC}
  --hostname NAME         Set new hostname
  --timezone ZONE         Set timezone (e.g., UTC, America/New_York)
  --user NAME             Create admin user with sudo access
  --skip-ssh              Skip SSH configuration
  --skip-security         Skip security hardening
  --skip-packages         Skip package installation

${BOLD}Features (must be explicitly enabled):${NC}
  --essentials            Install essential packages (curl, git, vim, etc.)
  --dev-tools             Install development tools
  --docker                Install Docker
  --homebrew              Install Homebrew (macOS only)
  --firewall              Configure firewall
  --fail2ban              Install and configure fail2ban

${BOLD}Profiles:${NC}
  ${GREEN}minimal${NC}      Essential tools only (curl, git, vim)
  ${GREEN}server${NC}       Server setup (essentials + SSH hardening + firewall)
  ${GREEN}workstation${NC}  Desktop/laptop (essentials + dev tools)
  ${GREEN}dev${NC}          Full development environment (all tools + Docker)

${BOLD}Examples:${NC}
  # Interactive wizard (recommended for first-time users)
  rsr bootstrap

  # Install Homebrew on macOS
  rsr bootstrap --homebrew

  # Preview what server profile would do
  rsr bootstrap --profile server --dry-run

  # Quick server setup
  rsr bootstrap --quick --profile server

  # Only install essential packages
  rsr bootstrap --essentials -y

  # Full automated setup
  rsr bootstrap -y --profile server --hostname myserver --user admin

${BOLD}Remote Execution:${NC}
  curl -fsSL https://scripts.pandia.io/rsr | sh -s -- bootstrap
  curl -fsSL https://scripts.pandia.io/rsr | sh -s -- bootstrap --quick --profile server

EOF
}

# =============================================================================
# System Detection
# =============================================================================

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_NAME="${NAME:-Unknown}"
        OS_VERSION="${VERSION_ID:-unknown}"
        OS_FAMILY="${ID_LIKE:-$ID}"
    elif [[ "$(uname)" == "Darwin" ]]; then
        OS_ID="macos"
        OS_NAME="macOS"
        OS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo 'unknown')"
        OS_FAMILY="darwin"
    else
        OS_ID="unknown"
        OS_NAME="Unknown"
        OS_VERSION="unknown"
        OS_FAMILY="unknown"
    fi
    
    log_debug "Detected OS: $OS_NAME ($OS_ID) version $OS_VERSION"
}

detect_package_manager() {
    if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt"
        PKG_UPDATE="apt-get update -qq"
        PKG_INSTALL="apt-get install -y -qq"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
        PKG_UPDATE="dnf check-update -q || true"
        PKG_INSTALL="dnf install -y -q"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
        PKG_UPDATE="yum check-update -q || true"
        PKG_INSTALL="yum install -y -q"
    elif command -v pacman &>/dev/null; then
        PKG_MANAGER="pacman"
        PKG_UPDATE="pacman -Sy --noconfirm"
        PKG_INSTALL="pacman -S --noconfirm --needed"
    elif command -v apk &>/dev/null; then
        PKG_MANAGER="apk"
        PKG_UPDATE="apk update"
        PKG_INSTALL="apk add --no-cache"
    elif command -v brew &>/dev/null; then
        PKG_MANAGER="brew"
        PKG_UPDATE="brew update"
        PKG_INSTALL="brew install"
    else
        PKG_MANAGER="unknown"
    fi
    
    log_debug "Package manager: $PKG_MANAGER"
}

# =============================================================================
# Profile Presets
# =============================================================================

apply_profile() {
    local profile="$1"
    
    case "$profile" in
        minimal)
            INSTALL_ESSENTIALS=true
            INSTALL_DEV_TOOLS=false
            INSTALL_DOCKER=false
            CONFIGURE_SSH=false
            CONFIGURE_FIREWALL=false
            CONFIGURE_FAIL2BAN=false
            ;;
        server)
            INSTALL_ESSENTIALS=true
            INSTALL_DEV_TOOLS=false
            INSTALL_DOCKER=false
            CONFIGURE_SSH=true
            CONFIGURE_FIREWALL=true
            CONFIGURE_FAIL2BAN=true
            ;;
        workstation)
            INSTALL_ESSENTIALS=true
            INSTALL_DEV_TOOLS=true
            INSTALL_DOCKER=false
            CONFIGURE_SSH=true
            CONFIGURE_FIREWALL=false
            CONFIGURE_FAIL2BAN=false
            ;;
        dev)
            INSTALL_ESSENTIALS=true
            INSTALL_DEV_TOOLS=true
            INSTALL_DOCKER=true
            CONFIGURE_SSH=true
            CONFIGURE_FIREWALL=false
            CONFIGURE_FAIL2BAN=false
            ;;
        *)
            log_error "Unknown profile: $profile"
            log_info "Available profiles: minimal, server, workstation, dev"
            exit 1
            ;;
    esac
    
    log_debug "Applied profile: $profile"
}

# =============================================================================
# Interactive Prompts (with fallbacks)
# =============================================================================

prompt_select_fallback() {
    local prompt="$1"
    shift
    local options=("$@")
    local i=1
    
    printf "\n${CYAN}?${NC} %s\n" "$prompt"
    for opt in "${options[@]}"; do
        printf "  ${CYAN}%d)${NC} %s\n" "$i" "$opt"
        ((i++))
    done
    printf "\n  Enter choice [1-%d]: " "${#options[@]}"
    read -r choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#options[@]} ]]; then
        echo "${options[$((choice-1))]}"
    else
        echo "${options[0]}"
    fi
}

prompt_confirm_fallback() {
    local prompt="$1"
    local default="${2:-n}"
    local hint="[y/N]"
    [[ "$default" == "y" ]] && hint="[Y/n]"
    
    printf "${CYAN}?${NC} %s %s " "$prompt" "$hint"
    read -r response
    
    [[ -z "$response" ]] && response="$default"
    
    case "$response" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

prompt_input_fallback() {
    local prompt="$1"
    local default="${2:-}"
    local hint=""
    [[ -n "$default" ]] && hint=" ${DIM}(default: $default)${NC}"
    
    printf "${CYAN}?${NC} %s%b: " "$prompt" "$hint"
    read -r response
    
    echo "${response:-$default}"
}

# Use RSR functions if available, otherwise fallback
prompt_select() {
    if type rsr_prompt_select &>/dev/null; then
        rsr_prompt_select "$@"
    else
        prompt_select_fallback "$@"
    fi
}

prompt_confirm() {
    if type rsr_prompt_confirm &>/dev/null; then
        rsr_prompt_confirm "$@"
    else
        prompt_confirm_fallback "$@"
    fi
}

prompt_input() {
    if type rsr_prompt_input &>/dev/null; then
        rsr_prompt_input "$@"
    else
        prompt_input_fallback "$@"
    fi
}

# =============================================================================
# Interactive Wizard
# =============================================================================

run_wizard() {
    show_banner
    
    printf "${DIM}This wizard will help you configure a new host.${NC}\n"
    printf "${DIM}You can also use --quick for a faster setup or --help for all options.${NC}\n\n"
    
    # Step 1: Choose profile
    log_step "Step 1: Choose a setup profile"
    echo ""
    
    local profile_choice
    profile_choice=$(prompt_select "What type of system is this?" \
        "Server (production/cloud server)" \
        "Workstation (desktop/laptop)" \
        "Development (full dev environment)" \
        "Minimal (essential tools only)" \
        "Custom (choose individual options)")
    
    case "$profile_choice" in
        Server*) PROFILE="server" ;;
        Workstation*) PROFILE="workstation" ;;
        Development*) PROFILE="dev" ;;
        Minimal*) PROFILE="minimal" ;;
        Custom*) PROFILE="custom" ;;
    esac
    
    if [[ "$PROFILE" != "custom" ]]; then
        apply_profile "$PROFILE"
    fi
    
    # Step 2: System configuration
    log_step "Step 2: System Configuration"
    echo ""
    
    if prompt_confirm "Change the hostname?" "n"; then
        HOSTNAME_NEW=$(prompt_input "Enter new hostname" "$(hostname)")
    fi
    
    if prompt_confirm "Configure timezone?" "n"; then
        if command -v timedatectl &>/dev/null; then
            local current_tz
            current_tz=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "UTC")
            TIMEZONE=$(prompt_input "Enter timezone" "$current_tz")
        else
            TIMEZONE=$(prompt_input "Enter timezone" "UTC")
        fi
    fi
    
    # Step 3: User setup
    log_step "Step 3: User Setup"
    echo ""
    
    if prompt_confirm "Create a new admin user?" "n"; then
        CREATE_USER=$(prompt_input "Username for new admin")
        CREATE_USER_SUDO=true
    fi
    
    # Step 4: Package selection (if custom profile)
    if [[ "$PROFILE" == "custom" ]]; then
        log_step "Step 4: Package Selection"
        echo ""
        
        INSTALL_ESSENTIALS=$(prompt_confirm "Install essential packages (curl, git, vim, htop)?" "y" && echo true || echo false)
        INSTALL_DEV_TOOLS=$(prompt_confirm "Install development tools (build-essential, make)?" "n" && echo true || echo false)
        INSTALL_DOCKER=$(prompt_confirm "Install Docker?" "n" && echo true || echo false)
    fi
    
    # Step 5: Security configuration
    log_step "Step 5: Security Configuration"
    echo ""
    
    if [[ "$PROFILE" == "custom" ]] || prompt_confirm "Review security settings?" "n"; then
        CONFIGURE_SSH=$(prompt_confirm "Configure SSH (disable root login, etc.)?" "y" && echo true || echo false)
        
        if [[ "$OS_ID" != "macos" ]]; then
            CONFIGURE_FIREWALL=$(prompt_confirm "Configure firewall (ufw/firewalld)?" "n" && echo true || echo false)
            CONFIGURE_FAIL2BAN=$(prompt_confirm "Install fail2ban for brute-force protection?" "n" && echo true || echo false)
        fi
    fi
    
    # Step 6: Dry run option
    log_step "Step 6: Review & Confirm"
    echo ""
    
    if prompt_confirm "Perform a dry run first (recommended)?" "y"; then
        DRY_RUN=true
    fi
}

# =============================================================================
# Package Installation
# =============================================================================

get_essential_packages() {
    case "$PKG_MANAGER" in
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

get_dev_packages() {
    case "$PKG_MANAGER" in
        apt)
            echo "build-essential make gcc g++ python3 python3-pip jq unzip"
            ;;
        dnf|yum)
            echo "gcc gcc-c++ make python3 python3-pip jq unzip @development-tools"
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

install_packages() {
    local packages="$1"
    local description="$2"
    
    if [[ -z "$packages" ]]; then
        return 0
    fi
    
    log_info "Installing $description..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would install: $packages"
        return 0
    fi
    
    if [[ "$PKG_MANAGER" == "unknown" ]]; then
        log_warn "Unknown package manager, skipping package installation"
        return 1
    fi
    
    # Update package lists
    if [[ "$EUID" -eq 0 ]]; then
        eval "$PKG_UPDATE" 2>/dev/null || true
        eval "$PKG_INSTALL $packages" 2>/dev/null
    else
        sudo bash -c "$PKG_UPDATE" 2>/dev/null || true
        sudo bash -c "$PKG_INSTALL $packages" 2>/dev/null
    fi
    
    log_ok "Installed $description"
}

install_docker() {
    log_info "Installing Docker..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would install Docker"
        return 0
    fi
    
    if command -v docker &>/dev/null; then
        log_ok "Docker already installed"
        return 0
    fi
    
    case "$OS_ID" in
        ubuntu|debian)
            # Add Docker's official GPG key
            sudo install -m 0755 -d /etc/apt/keyrings
            curl -fsSL "https://download.docker.com/linux/$OS_ID/gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            sudo chmod a+r /etc/apt/keyrings/docker.gpg
            
            # Add the repository
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS_ID $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
                sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            sudo apt-get update -qq
            sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        centos|rhel|fedora)
            sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 2>/dev/null || \
                sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || \
                sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        macos)
            if command -v brew &>/dev/null; then
                brew install --cask docker
                log_info "Docker Desktop installed. Please start it from Applications."
            else
                log_warn "Install Docker Desktop from https://docker.com/products/docker-desktop"
            fi
            return 0
            ;;
        *)
            log_warn "Docker installation not supported on $OS_NAME"
            log_info "Visit https://docs.docker.com/engine/install/ for manual installation"
            return 1
            ;;
    esac
    
    # Start and enable Docker
    if command -v systemctl &>/dev/null; then
        sudo systemctl start docker
        sudo systemctl enable docker
    fi
    
    # Add current user to docker group
    if [[ -n "${SUDO_USER:-}" ]]; then
        sudo usermod -aG docker "$SUDO_USER"
        log_info "Added $SUDO_USER to docker group (log out and back in to take effect)"
    elif [[ "$EUID" -ne 0 ]]; then
        sudo usermod -aG docker "$USER"
        log_info "Added $USER to docker group (log out and back in to take effect)"
    fi
    
    log_ok "Docker installed successfully"
}

# =============================================================================
# System Configuration
# =============================================================================

configure_hostname() {
    if [[ -z "$HOSTNAME_NEW" ]]; then
        return 0
    fi
    
    log_info "Setting hostname to: $HOSTNAME_NEW"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would set hostname to: $HOSTNAME_NEW"
        return 0
    fi
    
    if command -v hostnamectl &>/dev/null; then
        sudo hostnamectl set-hostname "$HOSTNAME_NEW"
    else
        echo "$HOSTNAME_NEW" | sudo tee /etc/hostname > /dev/null
        sudo hostname "$HOSTNAME_NEW"
    fi
    
    # Update /etc/hosts
    if ! grep -q "$HOSTNAME_NEW" /etc/hosts; then
        echo "127.0.1.1 $HOSTNAME_NEW" | sudo tee -a /etc/hosts > /dev/null
    fi
    
    log_ok "Hostname set to: $HOSTNAME_NEW"
}

configure_timezone() {
    if [[ -z "$TIMEZONE" ]]; then
        return 0
    fi
    
    log_info "Setting timezone to: $TIMEZONE"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would set timezone to: $TIMEZONE"
        return 0
    fi
    
    if command -v timedatectl &>/dev/null; then
        sudo timedatectl set-timezone "$TIMEZONE"
    elif [[ -f "/usr/share/zoneinfo/$TIMEZONE" ]]; then
        sudo ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
        echo "$TIMEZONE" | sudo tee /etc/timezone > /dev/null
    fi
    
    log_ok "Timezone set to: $TIMEZONE"
}

create_admin_user() {
    if [[ -z "$CREATE_USER" ]]; then
        return 0
    fi
    
    log_info "Creating admin user: $CREATE_USER"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would create user: $CREATE_USER with sudo access"
        return 0
    fi
    
    if id "$CREATE_USER" &>/dev/null; then
        log_warn "User $CREATE_USER already exists"
    else
        if [[ "$OS_ID" == "macos" ]]; then
            log_warn "User creation on macOS requires manual steps"
            log_info "Use System Preferences > Users & Groups to create user"
        else
            sudo useradd -m -s /bin/bash "$CREATE_USER"
            log_ok "Created user: $CREATE_USER"
        fi
    fi
    
    # Add to sudo/wheel group
    if [[ "$CREATE_USER_SUDO" == true ]] && [[ "$OS_ID" != "macos" ]]; then
        if getent group sudo &>/dev/null; then
            sudo usermod -aG sudo "$CREATE_USER"
        elif getent group wheel &>/dev/null; then
            sudo usermod -aG wheel "$CREATE_USER"
        fi
        log_ok "Added $CREATE_USER to sudo group"
        
        # Prompt to set password
        log_info "Set password for $CREATE_USER:"
        sudo passwd "$CREATE_USER" || true
    fi
}

# =============================================================================
# Security Configuration
# =============================================================================

configure_ssh_security() {
    if [[ "$CONFIGURE_SSH" != true ]] || [[ "$SKIP_SSH" == true ]]; then
        return 0
    fi
    
    log_info "Configuring SSH security..."
    
    local sshd_config="/etc/ssh/sshd_config"
    
    if [[ ! -f "$sshd_config" ]]; then
        log_warn "SSH config not found, skipping SSH configuration"
        return 0
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would configure SSH:"
        log_info "  - Disable root login"
        log_info "  - Disable password authentication (if key exists)"
        log_info "  - Set MaxAuthTries to 3"
        return 0
    fi
    
    # Backup original config
    sudo cp "$sshd_config" "${sshd_config}.backup.$(date +%Y%m%d%H%M%S)"
    
    # Disable root login
    sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' "$sshd_config"
    
    # Set max auth tries
    if grep -q "^#*MaxAuthTries" "$sshd_config"; then
        sudo sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' "$sshd_config"
    else
        echo "MaxAuthTries 3" | sudo tee -a "$sshd_config" > /dev/null
    fi
    
    # Only disable password auth if user has SSH keys
    if [[ -f ~/.ssh/authorized_keys ]] && [[ -s ~/.ssh/authorized_keys ]]; then
        sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "$sshd_config"
        log_ok "Disabled password authentication (SSH keys found)"
    else
        log_warn "No SSH keys found, keeping password authentication enabled"
        log_info "Add your SSH key and run: sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config"
    fi
    
    # Restart SSH service
    if command -v systemctl &>/dev/null; then
        sudo systemctl restart sshd 2>/dev/null || sudo systemctl restart ssh 2>/dev/null
    elif command -v service &>/dev/null; then
        sudo service sshd restart 2>/dev/null || sudo service ssh restart 2>/dev/null
    fi
    
    log_ok "SSH security configured"
}

configure_firewall_rules() {
    if [[ "$CONFIGURE_FIREWALL" != true ]] || [[ "$SKIP_SECURITY" == true ]]; then
        return 0
    fi
    
    if [[ "$OS_ID" == "macos" ]]; then
        log_info "macOS firewall can be configured in System Preferences > Security & Privacy"
        return 0
    fi
    
    log_info "Configuring firewall..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would configure firewall:"
        log_info "  - Allow SSH (port 22)"
        log_info "  - Allow HTTP (port 80)"
        log_info "  - Allow HTTPS (port 443)"
        log_info "  - Enable firewall"
        return 0
    fi
    
    if command -v ufw &>/dev/null; then
        sudo ufw default deny incoming
        sudo ufw default allow outgoing
        sudo ufw allow ssh
        sudo ufw allow http
        sudo ufw allow https
        sudo ufw --force enable
        log_ok "UFW firewall configured and enabled"
    elif command -v firewall-cmd &>/dev/null; then
        sudo firewall-cmd --permanent --add-service=ssh
        sudo firewall-cmd --permanent --add-service=http
        sudo firewall-cmd --permanent --add-service=https
        sudo firewall-cmd --reload
        log_ok "Firewalld configured"
    else
        log_warn "No supported firewall found (ufw or firewalld)"
    fi
}

install_fail2ban() {
    if [[ "$CONFIGURE_FAIL2BAN" != true ]] || [[ "$SKIP_SECURITY" == true ]]; then
        return 0
    fi
    
    if [[ "$OS_ID" == "macos" ]]; then
        log_info "fail2ban is not typically used on macOS"
        return 0
    fi
    
    log_info "Installing fail2ban..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would install and configure fail2ban"
        return 0
    fi
    
    install_packages "fail2ban" "fail2ban"
    
    # Create basic jail configuration
    local jail_local="/etc/fail2ban/jail.local"
    if [[ ! -f "$jail_local" ]]; then
        cat << 'EOF' | sudo tee "$jail_local" > /dev/null
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
        sudo systemctl enable fail2ban
        sudo systemctl start fail2ban
    fi
    
    log_ok "fail2ban installed and configured"
}

# =============================================================================
# Summary
# =============================================================================

show_summary() {
    echo ""
    if [[ -t 1 ]]; then
        printf "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
        printf "${BOLD}                    Bootstrap Configuration                     ${NC}\n"
        printf "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
    else
        printf "=== Bootstrap Configuration ===\n"
    fi
    echo ""
    
    printf "  System:            %s (%s)\n" "$OS_NAME" "$OS_VERSION"
    printf "  Package Manager:   %s\n" "$PKG_MANAGER"
    [[ -n "$PROFILE" ]] && printf "  Profile:           %s\n" "$PROFILE"
    echo ""
    
    printf "  Configuration:\n"
    [[ -n "$HOSTNAME_NEW" ]] && printf "    - Hostname:      %s\n" "$HOSTNAME_NEW"
    [[ -n "$TIMEZONE" ]] && printf "    - Timezone:      %s\n" "$TIMEZONE"
    [[ -n "$CREATE_USER" ]] && printf "    - Create user:   %s (sudo: %s)\n" "$CREATE_USER" "$CREATE_USER_SUDO"
    echo ""
    
    printf "  Packages:\n"
    [[ "$INSTALL_HOMEBREW" == true ]] && printf "    [x] Homebrew (macOS)\n"
    [[ "$INSTALL_ESSENTIALS" == true ]] && printf "    [x] Essential tools\n"
    [[ "$INSTALL_DEV_TOOLS" == true ]] && printf "    [x] Development tools\n"
    [[ "$INSTALL_DOCKER" == true ]] && printf "    [x] Docker\n"
    echo ""
    
    printf "  Security:\n"
    [[ "$CONFIGURE_SSH" == true ]] && printf "    [x] SSH hardening\n"
    [[ "$CONFIGURE_FIREWALL" == true ]] && printf "    [x] Firewall configuration\n"
    [[ "$CONFIGURE_FAIL2BAN" == true ]] && printf "    [x] fail2ban\n"
    echo ""
    
    if [[ "$DRY_RUN" == true ]]; then
        printf "  Mode: DRY RUN - No changes will be made\n"
        echo ""
    fi
    
    if [[ -t 1 ]]; then
        printf "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
    else
        printf "===============================================\n"
    fi
}

show_completion() {
    echo ""
    if [[ -t 1 ]]; then
        printf "${GREEN}${BOLD}═══════════════════════════════════════════════════════════════${NC}\n"
        printf "${GREEN}${BOLD}                    Bootstrap Complete! 🎉                      ${NC}\n"
        printf "${GREEN}${BOLD}═══════════════════════════════════════════════════════════════${NC}\n"
    else
        printf "=== Bootstrap Complete! ===\n"
    fi
    echo ""
    
    if [[ "$DRY_RUN" == true ]]; then
        printf "  This was a dry run. Run without --dry-run to apply changes.\n"
        echo ""
        printf "  Example: rsr bootstrap --profile %s\n" "${PROFILE:-server}"
    else
        printf "  Host has been bootstrapped successfully!\n"
        echo ""
        
        printf "  Next steps:\n"
        [[ -n "$CREATE_USER" ]] && printf "    - Log in as %s to verify access\n" "$CREATE_USER"
        [[ "$CONFIGURE_SSH" == true ]] && printf "    - Test SSH access in a new terminal before closing this session\n"
        [[ "$INSTALL_DOCKER" == true ]] && printf "    - Log out and back in for Docker group to take effect\n"
        printf "    - Run 'rsr health -a' to verify system health\n"
    fi
    
    echo ""
    if [[ -t 1 ]]; then
        printf "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
    else
        printf "===============================================\n"
    fi
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
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                RSR_YES=1
                INTERACTIVE=false
                shift
                ;;
            --quick)
                QUICK_MODE=true
                INTERACTIVE=false
                shift
                ;;
            --profile)
                PROFILE="$2"
                shift 2
                ;;
            --hostname)
                HOSTNAME_NEW="$2"
                shift 2
                ;;
            --timezone)
                TIMEZONE="$2"
                shift 2
                ;;
            --user)
                CREATE_USER="$2"
                CREATE_USER_SUDO=true
                shift 2
                ;;
            --skip-ssh)
                SKIP_SSH=true
                shift
                ;;
            --skip-security)
                SKIP_SECURITY=true
                shift
                ;;
            --skip-packages)
                SKIP_PACKAGES=true
                shift
                ;;
            --essentials)
                INSTALL_ESSENTIALS=true
                shift
                ;;
            --dev-tools)
                INSTALL_DEV_TOOLS=true
                shift
                ;;
            --docker)
                INSTALL_DOCKER=true
                shift
                ;;
            --homebrew)
                INSTALL_HOMEBREW=true
                shift
                ;;
            --firewall)
                CONFIGURE_FIREWALL=true
                shift
                ;;
            --fail2ban)
                CONFIGURE_FAIL2BAN=true
                shift
                ;;
            --no-interactive)
                INTERACTIVE=false
                shift
                ;;
            *)
                log_error "Unknown option: $1"
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
    local original_args=("$@")
    parse_args "$@"
    
    # Detect system
    detect_os
    detect_package_manager
    
    # Apply profile if specified
    if [[ -n "$PROFILE" ]]; then
        apply_profile "$PROFILE"
    fi
    
    # Quick mode with sensible defaults
    if [[ "$QUICK_MODE" == true ]] && [[ -z "$PROFILE" ]]; then
        PROFILE="server"
        apply_profile "$PROFILE"
    fi
    
    # Determine if we should run interactive mode
    if [[ "$INTERACTIVE" == "auto" ]]; then
        if [[ ${#original_args[@]} -eq 0 ]] && [[ -t 0 ]] && [[ -t 1 ]]; then
            INTERACTIVE=true
        else
            INTERACTIVE=false
        fi
    fi
    
    # Run wizard if interactive
    if [[ "$INTERACTIVE" == true ]]; then
        run_wizard
    fi
    
    # Show configuration summary
    show_summary
    
    # Confirm before proceeding (unless -y or dry-run)
    if [[ "$RSR_YES" -ne 1 ]] && [[ "$DRY_RUN" != true ]] && [[ -t 0 ]]; then
        echo ""
        if ! prompt_confirm "Proceed with bootstrap?" "y"; then
            log_info "Bootstrap cancelled"
            exit 0
        fi
    fi
    
    echo ""
    log_step "Starting Bootstrap Process"
    
    # Export context for bootstrap module
    export RSR_DRY_RUN="$DRY_RUN"
    export RSR_VERBOSE="$VERBOSE"
    export RSR_YES="$RSR_YES"
    
    # Execute bootstrap steps - use module functions if available, else fallback
    if [[ "$BOOTSTRAP_MODULE_LOADED" == 1 ]]; then
        # Use bootstrap module (reuses existing scripts/modules)
        log_debug "Using bootstrap module for operations"
        
        # System configuration
        [[ -n "$HOSTNAME_NEW" ]] && rsr_bootstrap_hostname "$HOSTNAME_NEW"
        [[ -n "$TIMEZONE" ]] && rsr_bootstrap_timezone "$TIMEZONE"
        [[ -n "$CREATE_USER" ]] && rsr_bootstrap_user "$CREATE_USER" $([[ "$CREATE_USER_SUDO" == true ]] && echo "--sudo")
        
        # Package installation
        if [[ "$SKIP_PACKAGES" != true ]]; then
            [[ "$INSTALL_HOMEBREW" == true ]] && rsr_bootstrap_homebrew
            [[ "$INSTALL_ESSENTIALS" == true ]] && rsr_bootstrap_packages_essential
            [[ "$INSTALL_DEV_TOOLS" == true ]] && rsr_bootstrap_packages_dev
            [[ "$INSTALL_DOCKER" == true ]] && rsr_bootstrap_docker
        fi
        
        # Security configuration
        if [[ "$SKIP_SECURITY" != true ]]; then
            [[ "$CONFIGURE_SSH" == true ]] && rsr_bootstrap_ssh
            [[ "$CONFIGURE_FIREWALL" == true ]] && rsr_bootstrap_firewall
            [[ "$CONFIGURE_FAIL2BAN" == true ]] && rsr_bootstrap_fail2ban
        fi
    else
        # Fallback to local functions (for standalone execution)
        log_debug "Using local functions for operations"
        
        configure_hostname
        configure_timezone
        create_admin_user
        
        if [[ "$SKIP_PACKAGES" != true ]]; then
            # Homebrew installation (macOS only, fallback)
            if [[ "$INSTALL_HOMEBREW" == true ]] && [[ "$OS_ID" == "macos" ]]; then
                if ! command -v brew &>/dev/null; then
                    log_info "Installing Homebrew..."
                    if [[ "$DRY_RUN" == true ]]; then
                        log_info "[DRY RUN] Would install Homebrew"
                    else
                        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                    fi
                else
                    log_ok "Homebrew is already installed"
                fi
            fi
            
            if [[ "$INSTALL_ESSENTIALS" == true ]]; then
                install_packages "$(get_essential_packages)" "essential packages"
            fi
            
            if [[ "$INSTALL_DEV_TOOLS" == true ]]; then
                install_packages "$(get_dev_packages)" "development tools"
            fi
            
            if [[ "$INSTALL_DOCKER" == true ]]; then
                install_docker
            fi
        fi
        
        if [[ "$SKIP_SECURITY" != true ]]; then
            configure_ssh_security
            configure_firewall_rules
            install_fail2ban
        fi
    fi
    
    # Show completion message
    show_completion
}

# =============================================================================
# Library Mode Support
# =============================================================================

# Support being sourced as a library (RSR_AS_LIBRARY=1)
if [[ "${RSR_AS_LIBRARY:-0}" != "1" ]]; then
    main "$@"
fi
