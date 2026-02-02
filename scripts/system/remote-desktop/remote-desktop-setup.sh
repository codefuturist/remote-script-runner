#!/usr/bin/env bash
# =============================================================================
# @name         remote-desktop-setup
# @description  Setup remote desktop server (xRDP) on Linux distributions
# @version      1.0.0
# @author       RSR Team
# @license      MIT
# @requires     bash 4.0+
# =============================================================================
#
# Usage:
#   remote-desktop-setup.sh [OPTIONS] [SUBCOMMAND]
#
# Subcommands:
#   install     - Install and configure remote desktop server
#   status      - Show remote desktop service status
#   enable      - Enable remote desktop at boot
#   disable     - Disable remote desktop at boot
#   start       - Start remote desktop service
#   stop        - Stop remote desktop service
#   restart     - Restart remote desktop service
#   configure   - Interactive configuration wizard
#   firewall    - Configure firewall for RDP access
#   security    - Apply security hardening
#   uninstall   - Remove remote desktop server
#
# Examples:
#   remote-desktop-setup.sh install
#   remote-desktop-setup.sh --dry-run install
#   remote-desktop-setup.sh status
#   remote-desktop-setup.sh security
#
# Supported Distributions:
#   - Ubuntu 20.04+, 22.04+, 24.04+
#   - Debian 11+, 12+
#   - Linux Mint 20+
#   - Fedora 38+
#   - Rocky Linux 8+, 9+
#   - AlmaLinux 8+, 9+
#   - openSUSE Leap 15+
#
# =============================================================================

set -eo pipefail

# =============================================================================
# RSR Library
# =============================================================================

SCRIPT_SOURCE="${BASH_SOURCE[0]:-${0:-}}"
if [ -n "${SCRIPT_SOURCE}" ] && [ "${SCRIPT_SOURCE}" != "bash" ] && [ "${SCRIPT_SOURCE}" != "sh" ] && [ "${SCRIPT_SOURCE}" != "-bash" ] && [ "${SCRIPT_SOURCE}" != "-sh" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_SOURCE}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
else
    SCRIPT_DIR=""
fi
RSR_LIB_DIR="${SCRIPT_DIR}/../../../lib"

# Try to load RSR library, fallback to standalone mode
if [[ -f "$RSR_LIB_DIR/rsr-lib.sh" ]]; then
    # shellcheck source=../../../lib/rsr-lib.sh
    source "$RSR_LIB_DIR/rsr-lib.sh" validate
    RSR_STANDALONE=false
else
    RSR_STANDALONE=true
    # Minimal logging functions for standalone mode
    rsr_log_info() { echo "[INFO] $*"; }
    rsr_log_ok() { echo "[OK] $*"; }
    rsr_log_warn() { echo "[WARN] $*" >&2; }
    rsr_log_error() { echo "[ERROR] $*" >&2; }
    rsr_log_debug() { [[ "${VERBOSE:-false}" == "true" ]] && echo "[DEBUG] $*"; }
fi

# =============================================================================
# Configuration
# =============================================================================

readonly SCRIPT_NAME="remote-desktop-setup"
readonly SCRIPT_VERSION="1.0.0"
readonly RDP_PORT=3389
readonly XRDP_CONFIG="/etc/xrdp/xrdp.ini"
readonly SESMAN_CONFIG="/etc/xrdp/sesman.ini"

# Default options
VERBOSE=false
DRY_RUN=false
INTERACTIVE=auto
FORCE=false
SUBCOMMAND=""

# Detected system info
DISTRO=""
DISTRO_VERSION=""
DISTRO_FAMILY=""
PKG_MANAGER=""
DESKTOP_ENV=""
INIT_SYSTEM=""

# =============================================================================
# Color Support
# =============================================================================

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
fi

# =============================================================================
# Helper Functions
# =============================================================================

print_header() {
    echo -e "\n${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
}

print_step() {
    echo -e "${CYAN}▶${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

run_cmd() {
    local cmd="$*"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $cmd"
        return 0
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${CYAN}[CMD]${NC} $cmd"
    fi
    
    eval "$cmd"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# =============================================================================
# System Detection
# =============================================================================

detect_system() {
    print_step "Detecting system configuration..."
    
    # Detect init system
    if command -v systemctl &>/dev/null && systemctl --version &>/dev/null; then
        INIT_SYSTEM="systemd"
    elif [[ -f /etc/init.d/xrdp ]]; then
        INIT_SYSTEM="sysvinit"
    else
        INIT_SYSTEM="unknown"
    fi
    
    # Detect distribution
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        DISTRO="${ID:-unknown}"
        DISTRO_VERSION="${VERSION_ID:-unknown}"
        
        case "$DISTRO" in
            ubuntu|debian|linuxmint|pop)
                DISTRO_FAMILY="debian"
                PKG_MANAGER="apt"
                ;;
            fedora)
                DISTRO_FAMILY="fedora"
                PKG_MANAGER="dnf"
                ;;
            rhel|rocky|almalinux|centos)
                DISTRO_FAMILY="rhel"
                if command -v dnf &>/dev/null; then
                    PKG_MANAGER="dnf"
                else
                    PKG_MANAGER="yum"
                fi
                ;;
            opensuse*|sles)
                DISTRO_FAMILY="suse"
                PKG_MANAGER="zypper"
                ;;
            arch|manjaro)
                DISTRO_FAMILY="arch"
                PKG_MANAGER="pacman"
                ;;
            *)
                print_warning "Unknown distribution: $DISTRO"
                DISTRO_FAMILY="unknown"
                ;;
        esac
    else
        print_error "Cannot detect distribution (no /etc/os-release)"
        exit 1
    fi
    
    # Detect desktop environment
    detect_desktop_env
    
    print_success "System: $DISTRO $DISTRO_VERSION ($DISTRO_FAMILY)"
    print_success "Package Manager: $PKG_MANAGER"
    print_success "Init System: $INIT_SYSTEM"
    print_success "Desktop Environment: ${DESKTOP_ENV:-none}"
}

detect_desktop_env() {
    # Check for running desktop session
    if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
        DESKTOP_ENV="$XDG_CURRENT_DESKTOP"
    elif [[ -n "${DESKTOP_SESSION:-}" ]]; then
        DESKTOP_ENV="$DESKTOP_SESSION"
    else
        # Check installed desktops
        if command -v gnome-shell &>/dev/null; then
            DESKTOP_ENV="GNOME"
        elif command -v plasmashell &>/dev/null; then
            DESKTOP_ENV="KDE"
        elif command -v xfce4-session &>/dev/null; then
            DESKTOP_ENV="XFCE"
        elif command -v mate-session &>/dev/null; then
            DESKTOP_ENV="MATE"
        elif command -v cinnamon &>/dev/null; then
            DESKTOP_ENV="Cinnamon"
        elif command -v lxqt-session &>/dev/null; then
            DESKTOP_ENV="LXQt"
        elif dpkg -l 2>/dev/null | grep -q "xfce4-session\|xubuntu-desktop"; then
            DESKTOP_ENV="XFCE"
        else
            DESKTOP_ENV="none"
        fi
    fi
}

# =============================================================================
# Package Installation
# =============================================================================

install_packages_debian() {
    print_step "Installing xRDP packages (Debian/Ubuntu)..."
    
    run_cmd "apt-get update -qq"
    run_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y xrdp dbus-x11"
    
    # Install session broker if available
    if apt-cache show xorgxrdp &>/dev/null; then
        run_cmd "apt-get install -y xorgxrdp"
    fi
    
    # Ensure a desktop environment is installed
    if [[ "$DESKTOP_ENV" == "none" ]]; then
        print_warning "No desktop environment detected"
        echo ""
        echo "Please install a desktop environment first. Recommended options:"
        echo ""
        echo "  Lightweight (recommended for remote):"
        echo "    sudo apt install xfce4 xfce4-goodies"
        echo "    sudo apt install mate-desktop-environment-core"
        echo ""
        echo "  Full desktop:"
        echo "    sudo apt install ubuntu-desktop"
        echo "    sudo apt install kubuntu-desktop"
        echo ""
        
        if [[ "$FORCE" != "true" ]]; then
            read -rp "Install XFCE4 (lightweight, recommended)? [y/N] " install_de
            if [[ "$install_de" =~ ^[Yy] ]]; then
                run_cmd "apt-get install -y xfce4 xfce4-goodies"
                DESKTOP_ENV="XFCE"
            else
                print_warning "Continuing without desktop environment - manual configuration required"
            fi
        fi
    fi
}

install_packages_fedora() {
    print_step "Installing xRDP packages (Fedora)..."
    
    run_cmd "dnf install -y xrdp xorgxrdp"
    
    if [[ "$DESKTOP_ENV" == "none" ]]; then
        print_warning "No desktop environment detected"
        echo "Install with: sudo dnf install @xfce-desktop-environment"
    fi
}

install_packages_rhel() {
    print_step "Installing xRDP packages (RHEL/Rocky/Alma)..."
    
    # Enable EPEL repository
    if ! rpm -q epel-release &>/dev/null; then
        run_cmd "${PKG_MANAGER} install -y epel-release"
    fi
    
    run_cmd "${PKG_MANAGER} install -y xrdp"
    
    if [[ "$DESKTOP_ENV" == "none" ]]; then
        print_warning "No desktop environment detected"
        echo "Install with: sudo ${PKG_MANAGER} groupinstall 'Server with GUI'"
    fi
}

install_packages_suse() {
    print_step "Installing xRDP packages (openSUSE)..."
    
    run_cmd "zypper install -y xrdp"
    
    if [[ "$DESKTOP_ENV" == "none" ]]; then
        print_warning "No desktop environment detected"
        echo "Install with: sudo zypper install -t pattern xfce"
    fi
}

install_packages_arch() {
    print_step "Installing xRDP packages (Arch)..."
    
    run_cmd "pacman -S --noconfirm xrdp"
    
    if [[ "$DESKTOP_ENV" == "none" ]]; then
        print_warning "No desktop environment detected"
        echo "Install with: sudo pacman -S xfce4 xfce4-goodies"
    fi
}

install_packages() {
    case "$DISTRO_FAMILY" in
        debian) install_packages_debian ;;
        fedora) install_packages_fedora ;;
        rhel) install_packages_rhel ;;
        suse) install_packages_suse ;;
        arch) install_packages_arch ;;
        *)
            print_error "Unsupported distribution family: $DISTRO_FAMILY"
            exit 1
            ;;
    esac
}

# =============================================================================
# Configuration
# =============================================================================

configure_xrdp() {
    print_step "Configuring xRDP..."
    
    # Backup original config
    if [[ -f "$XRDP_CONFIG" ]] && [[ ! -f "${XRDP_CONFIG}.orig" ]]; then
        run_cmd "cp '$XRDP_CONFIG' '${XRDP_CONFIG}.orig'"
    fi
    
    # Configure session to use correct desktop
    configure_session
    
    # Add xrdp user to ssl-cert group (Debian/Ubuntu)
    if getent group ssl-cert &>/dev/null; then
        run_cmd "usermod -aG ssl-cert xrdp" || true
    fi
    
    # Polkit configuration for colord (fixes authentication dialogs)
    configure_polkit
    
    print_success "xRDP configured"
}

configure_session() {
    print_step "Configuring desktop session..."
    
    local startwm_script="/etc/xrdp/startwm.sh"
    
    if [[ ! -f "$startwm_script" ]]; then
        print_warning "startwm.sh not found, skipping session configuration"
        return
    fi
    
    # Backup
    if [[ ! -f "${startwm_script}.orig" ]]; then
        run_cmd "cp '$startwm_script' '${startwm_script}.orig'"
    fi
    
    # Determine session command based on desktop environment
    local session_cmd=""
    case "${DESKTOP_ENV,,}" in
        xfce*|xubuntu)
            session_cmd="startxfce4"
            ;;
        gnome*|ubuntu)
            session_cmd="gnome-session"
            ;;
        kde*|plasma*)
            session_cmd="startplasma-x11"
            ;;
        mate*)
            session_cmd="mate-session"
            ;;
        cinnamon*)
            session_cmd="cinnamon-session"
            ;;
        lxqt*)
            session_cmd="startlxqt"
            ;;
        lxde*)
            session_cmd="startlxde"
            ;;
        *)
            print_warning "Unknown desktop: $DESKTOP_ENV - using default session"
            return
            ;;
    esac
    
    if [[ -n "$session_cmd" ]]; then
        print_step "Setting session: $session_cmd"
        
        if [[ "$DRY_RUN" != "true" ]]; then
            # Create a modified startwm.sh
            cat > "$startwm_script" << 'STARTWM_EOF'
#!/bin/sh
# xRDP session startup script

# Source environment
if [ -r /etc/default/locale ]; then
    . /etc/default/locale
    export LANG LANGUAGE
fi

# Fix for blank screen issues
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR

STARTWM_EOF
            
            echo "exec $session_cmd" >> "$startwm_script"
            chmod +x "$startwm_script"
        else
            echo "[DRY-RUN] Would configure session: $session_cmd"
        fi
    fi
}

configure_polkit() {
    print_step "Configuring Polkit rules..."
    
    local polkit_dir="/etc/polkit-1/localauthority/50-local.d"
    local polkit_rule="${polkit_dir}/45-allow-colord.pkla"
    
    if [[ -d "$polkit_dir" ]]; then
        if [[ "$DRY_RUN" != "true" ]]; then
            cat > "$polkit_rule" << 'POLKIT_EOF'
[Allow Colord all Users]
Identity=unix-user:*
Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile
ResultAny=no
ResultInactive=no
ResultActive=yes
POLKIT_EOF
            print_success "Polkit rule created: $polkit_rule"
        else
            echo "[DRY-RUN] Would create polkit rule"
        fi
    fi
    
    # Alternative polkit rules location (newer systems)
    local polkit_rules_dir="/etc/polkit-1/rules.d"
    if [[ -d "$polkit_rules_dir" ]]; then
        local polkit_js="${polkit_rules_dir}/02-allow-colord.rules"
        if [[ "$DRY_RUN" != "true" ]]; then
            cat > "$polkit_js" << 'POLKIT_JS_EOF'
polkit.addRule(function(action, subject) {
    if ((action.id == "org.freedesktop.color-manager.create-device" ||
         action.id == "org.freedesktop.color-manager.create-profile" ||
         action.id == "org.freedesktop.color-manager.delete-device" ||
         action.id == "org.freedesktop.color-manager.delete-profile" ||
         action.id == "org.freedesktop.color-manager.modify-device" ||
         action.id == "org.freedesktop.color-manager.modify-profile") &&
        subject.isInGroup("users")) {
        return polkit.Result.YES;
    }
});
POLKIT_JS_EOF
        fi
    fi
}

# =============================================================================
# Service Management
# =============================================================================

service_start() {
    print_step "Starting xRDP service..."
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        run_cmd "systemctl start xrdp"
    else
        run_cmd "service xrdp start"
    fi
    print_success "xRDP service started"
}

service_stop() {
    print_step "Stopping xRDP service..."
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        run_cmd "systemctl stop xrdp"
    else
        run_cmd "service xrdp stop"
    fi
    print_success "xRDP service stopped"
}

service_restart() {
    print_step "Restarting xRDP service..."
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        run_cmd "systemctl restart xrdp"
    else
        run_cmd "service xrdp restart"
    fi
    print_success "xRDP service restarted"
}

service_enable() {
    print_step "Enabling xRDP at boot..."
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        run_cmd "systemctl enable xrdp"
    else
        run_cmd "update-rc.d xrdp defaults" 2>/dev/null || true
    fi
    print_success "xRDP enabled at boot"
}

service_disable() {
    print_step "Disabling xRDP at boot..."
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        run_cmd "systemctl disable xrdp"
    else
        run_cmd "update-rc.d xrdp remove" 2>/dev/null || true
    fi
    print_success "xRDP disabled at boot"
}

service_status() {
    print_header "Remote Desktop Status"
    
    echo -e "${BOLD}Service Status:${NC}"
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        systemctl status xrdp --no-pager 2>/dev/null || echo "  xrdp: not running"
    else
        service xrdp status 2>/dev/null || echo "  xrdp: not running"
    fi
    
    echo ""
    echo -e "${BOLD}Listening Ports:${NC}"
    ss -tlnp 2>/dev/null | grep -E ":(3389|3350)" || netstat -tlnp 2>/dev/null | grep -E ":(3389|3350)" || echo "  No RDP ports listening"
    
    echo ""
    echo -e "${BOLD}Active Sessions:${NC}"
    if command -v xrdp-seslist &>/dev/null; then
        xrdp-seslist 2>/dev/null || echo "  No active sessions"
    else
        who | grep -v "tty" | grep -v "pts/0" || echo "  No active sessions"
    fi
    
    echo ""
    echo -e "${BOLD}Connection Info:${NC}"
    local ip_addr
    ip_addr=$(ip route get 1 2>/dev/null | awk '{print $7; exit}' || hostname -I 2>/dev/null | awk '{print $1}')
    echo "  Connect using RDP client to: ${BOLD}${ip_addr}:${RDP_PORT}${NC}"
}

# =============================================================================
# Firewall Configuration
# =============================================================================

configure_firewall() {
    print_header "Firewall Configuration"
    
    # Detect firewall
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "active"; then
        print_step "Configuring UFW firewall..."
        run_cmd "ufw allow ${RDP_PORT}/tcp comment 'Remote Desktop (RDP)'"
        run_cmd "ufw reload"
        print_success "UFW configured for RDP"
        
    elif command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
        print_step "Configuring firewalld..."
        run_cmd "firewall-cmd --permanent --add-port=${RDP_PORT}/tcp"
        run_cmd "firewall-cmd --reload"
        print_success "firewalld configured for RDP"
        
    elif command -v iptables &>/dev/null; then
        print_step "Configuring iptables..."
        run_cmd "iptables -I INPUT -p tcp --dport ${RDP_PORT} -j ACCEPT"
        
        # Try to save rules
        if [[ -f /etc/iptables/rules.v4 ]]; then
            run_cmd "iptables-save > /etc/iptables/rules.v4"
        elif command -v netfilter-persistent &>/dev/null; then
            run_cmd "netfilter-persistent save"
        fi
        print_success "iptables configured for RDP"
        
    else
        print_warning "No supported firewall detected"
        echo "Manually allow port ${RDP_PORT}/tcp for RDP access"
    fi
}

# =============================================================================
# Security Hardening
# =============================================================================

apply_security() {
    print_header "Security Hardening"
    
    if [[ ! -f "$XRDP_CONFIG" ]]; then
        print_error "xRDP not installed. Run 'install' first."
        return 1
    fi
    
    # Backup config
    run_cmd "cp '$XRDP_CONFIG' '${XRDP_CONFIG}.bak.$(date +%Y%m%d%H%M%S)'"
    
    print_step "Applying security settings..."
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Use TLS security layer
        sed -i 's/^security_layer=.*/security_layer=tls/' "$XRDP_CONFIG"
        
        # Require TLS encryption
        sed -i 's/^crypt_level=.*/crypt_level=high/' "$XRDP_CONFIG"
        
        # Enable bitmap compression
        sed -i 's/^bitmap_compression=.*/bitmap_compression=true/' "$XRDP_CONFIG"
        
        # Set reasonable limits
        sed -i 's/^max_bpp=.*/max_bpp=24/' "$XRDP_CONFIG"
        
        print_success "Security layer: TLS"
        print_success "Encryption level: High"
    else
        echo "[DRY-RUN] Would apply security hardening to xrdp.ini"
    fi
    
    # Certificate configuration
    print_step "Checking TLS certificates..."
    local cert_dir="/etc/xrdp"
    if [[ ! -f "${cert_dir}/cert.pem" ]] || [[ ! -f "${cert_dir}/key.pem" ]]; then
        print_step "Generating self-signed certificate..."
        if [[ "$DRY_RUN" != "true" ]]; then
            openssl req -x509 -newkey rsa:2048 \
                -keyout "${cert_dir}/key.pem" \
                -out "${cert_dir}/cert.pem" \
                -days 365 -nodes \
                -subj "/CN=$(hostname)" 2>/dev/null
            chmod 600 "${cert_dir}/key.pem"
            chown xrdp:xrdp "${cert_dir}/key.pem" "${cert_dir}/cert.pem"
            print_success "TLS certificate generated"
        fi
    else
        print_success "TLS certificate exists"
    fi
    
    # Fail2ban integration
    configure_fail2ban
    
    # Session security
    print_step "Configuring session security..."
    if [[ "$DRY_RUN" != "true" ]] && [[ -f "$SESMAN_CONFIG" ]]; then
        # Limit max sessions per user
        sed -i 's/^MaxSessions=.*/MaxSessions=5/' "$SESMAN_CONFIG" 2>/dev/null || true
        print_success "Session limits configured"
    fi
    
    echo ""
    print_success "Security hardening complete"
    echo ""
    echo -e "${BOLD}Recommendations:${NC}"
    echo "  1. Use strong passwords for all user accounts"
    echo "  2. Consider using VPN for remote access"
    echo "  3. Restrict access to trusted IP ranges using firewall"
    echo "  4. Enable audit logging for RDP sessions"
    echo "  5. Keep system updated regularly"
}

configure_fail2ban() {
    if ! command -v fail2ban-client &>/dev/null; then
        print_warning "fail2ban not installed (recommended for brute-force protection)"
        echo "  Install with: sudo apt install fail2ban"
        return
    fi
    
    print_step "Configuring fail2ban for xRDP..."
    
    local fail2ban_config="/etc/fail2ban/jail.d/xrdp.conf"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        cat > "$fail2ban_config" << 'F2B_EOF'
[xrdp]
enabled = true
port = 3389
filter = xrdp
logpath = /var/log/xrdp-sesman.log
maxretry = 5
bantime = 3600
findtime = 600
F2B_EOF
        
        # Create filter if not exists
        local filter_file="/etc/fail2ban/filter.d/xrdp.conf"
        if [[ ! -f "$filter_file" ]]; then
            cat > "$filter_file" << 'FILTER_EOF'
[Definition]
failregex = .*\[<HOST>\].* login failed.*
            .*connection from <HOST>.*login failure.*
ignoreregex =
FILTER_EOF
        fi
        
        systemctl restart fail2ban 2>/dev/null || service fail2ban restart 2>/dev/null || true
        print_success "fail2ban configured for xRDP"
    fi
}

# =============================================================================
# Installation
# =============================================================================

do_install() {
    print_header "Installing Remote Desktop Server"
    
    check_root
    detect_system
    
    # Check if already installed
    if command -v xrdp &>/dev/null; then
        print_warning "xRDP is already installed"
        if [[ "$FORCE" != "true" ]]; then
            read -rp "Reinstall/update? [y/N] " reinstall
            if [[ ! "$reinstall" =~ ^[Yy] ]]; then
                return 0
            fi
        fi
    fi
    
    # Install packages
    install_packages
    
    # Configure
    configure_xrdp
    
    # Enable and start service
    service_enable
    service_start
    
    # Configure firewall
    configure_firewall
    
    echo ""
    print_header "Installation Complete!"
    
    local ip_addr
    ip_addr=$(ip route get 1 2>/dev/null | awk '{print $7; exit}' || hostname -I 2>/dev/null | awk '{print $1}')
    
    echo -e "${BOLD}Next Steps:${NC}"
    echo ""
    echo "  1. Connect using any RDP client (Windows Remote Desktop, Remmina, etc.)"
    echo "     Host: ${BOLD}${ip_addr}${NC}"
    echo "     Port: ${BOLD}${RDP_PORT}${NC}"
    echo ""
    echo "  2. Login with your Linux username and password"
    echo ""
    echo "  3. For better security, run:"
    echo "     ${0##*/} security"
    echo ""
    echo -e "${BOLD}Useful Commands:${NC}"
    echo "  ${0##*/} status    - Check service status"
    echo "  ${0##*/} restart   - Restart service"
    echo "  ${0##*/} security  - Apply security hardening"
}

# =============================================================================
# Uninstall
# =============================================================================

do_uninstall() {
    print_header "Uninstalling Remote Desktop Server"
    
    check_root
    detect_system
    
    if ! command -v xrdp &>/dev/null; then
        print_warning "xRDP is not installed"
        return 0
    fi
    
    if [[ "$FORCE" != "true" ]]; then
        read -rp "Are you sure you want to uninstall xRDP? [y/N] " confirm
        if [[ ! "$confirm" =~ ^[Yy] ]]; then
            echo "Cancelled"
            return 0
        fi
    fi
    
    # Stop and disable service
    service_stop || true
    service_disable || true
    
    # Remove packages
    print_step "Removing packages..."
    case "$PKG_MANAGER" in
        apt)
            run_cmd "apt-get remove --purge -y xrdp xorgxrdp"
            run_cmd "apt-get autoremove -y"
            ;;
        dnf|yum)
            run_cmd "${PKG_MANAGER} remove -y xrdp xorgxrdp"
            ;;
        zypper)
            run_cmd "zypper remove -y xrdp"
            ;;
        pacman)
            run_cmd "pacman -Rs --noconfirm xrdp"
            ;;
    esac
    
    # Remove configuration (optional)
    if [[ "$FORCE" == "true" ]]; then
        run_cmd "rm -rf /etc/xrdp"
    else
        print_warning "Configuration kept at /etc/xrdp (use --force to remove)"
    fi
    
    print_success "xRDP uninstalled"
}

# =============================================================================
# Interactive Menu
# =============================================================================

show_interactive_menu() {
    local choice
    
    while true; do
        clear
        echo -e "${BOLD}${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BOLD}${BLUE}║         Remote Desktop Setup - Interactive Mode               ║${NC}"
        echo -e "${BOLD}${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        # Show current status summary
        local rdp_status="Not installed"
        local rdp_color="$YELLOW"
        if command -v xrdp &>/dev/null; then
            if systemctl is-active xrdp &>/dev/null 2>&1 || service xrdp status &>/dev/null 2>&1; then
                rdp_status="Running"
                rdp_color="$GREEN"
            else
                rdp_status="Installed (stopped)"
                rdp_color="$YELLOW"
            fi
        fi
        echo -e "  Current Status: ${rdp_color}${rdp_status}${NC}"
        echo ""
        
        echo -e "${BOLD}  Installation & Setup${NC}"
        echo -e "    ${CYAN}1${NC}) Install Remote Desktop (xRDP)"
        echo -e "    ${CYAN}2${NC}) Uninstall Remote Desktop"
        echo ""
        echo -e "${BOLD}  Service Management${NC}"
        echo -e "    ${CYAN}3${NC}) Start service"
        echo -e "    ${CYAN}4${NC}) Stop service"
        echo -e "    ${CYAN}5${NC}) Restart service"
        echo -e "    ${CYAN}6${NC}) Enable at boot"
        echo -e "    ${CYAN}7${NC}) Disable at boot"
        echo ""
        echo -e "${BOLD}  Configuration & Security${NC}"
        echo -e "    ${CYAN}8${NC}) Configure firewall"
        echo -e "    ${CYAN}9${NC}) Apply security hardening"
        echo ""
        echo -e "${BOLD}  Information${NC}"
        echo -e "    ${CYAN}s${NC}) Show detailed status"
        echo -e "    ${CYAN}h${NC}) Show help"
        echo ""
        echo -e "    ${CYAN}q${NC}) Quit"
        echo ""
        echo -n "  Select an option: "
        
        read -r choice
        
        case "$choice" in
            1)
                echo ""
                do_install
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            2)
                echo ""
                do_uninstall
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            3)
                echo ""
                check_root || { read -rp "Press Enter to continue..."; continue; }
                service_start
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            4)
                echo ""
                check_root || { read -rp "Press Enter to continue..."; continue; }
                service_stop
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            5)
                echo ""
                check_root || { read -rp "Press Enter to continue..."; continue; }
                service_restart
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            6)
                echo ""
                check_root || { read -rp "Press Enter to continue..."; continue; }
                service_enable
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            7)
                echo ""
                check_root || { read -rp "Press Enter to continue..."; continue; }
                service_disable
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            8)
                echo ""
                check_root || { read -rp "Press Enter to continue..."; continue; }
                detect_system
                configure_firewall
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            9)
                echo ""
                check_root || { read -rp "Press Enter to continue..."; continue; }
                detect_system
                apply_security
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            s|S)
                echo ""
                detect_system
                service_status
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            h|H)
                echo ""
                show_help
                read -rp "Press Enter to continue..."
                ;;
            q|Q|exit|quit)
                echo ""
                echo "Goodbye!"
                exit 0
                ;;
            *)
                echo ""
                print_error "Invalid option: $choice"
                sleep 1
                ;;
        esac
    done
}

# =============================================================================
# Help
# =============================================================================

show_help() {
    cat << EOF
${BOLD}${SCRIPT_NAME}${NC} v${SCRIPT_VERSION}

Setup remote desktop server (xRDP) on Linux distributions.

${BOLD}USAGE:${NC}
    ${0##*/}                      # Launch interactive menu
    ${0##*/} [OPTIONS] <SUBCOMMAND>

${BOLD}SUBCOMMANDS:${NC}
    install     Install and configure remote desktop server
    status      Show remote desktop service status
    enable      Enable remote desktop at boot
    disable     Disable remote desktop at boot
    start       Start remote desktop service
    stop        Stop remote desktop service
    restart     Restart remote desktop service
    firewall    Configure firewall for RDP access
    security    Apply security hardening
    uninstall   Remove remote desktop server
    menu        Launch interactive menu

${BOLD}OPTIONS:${NC}
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    -d, --dry-run       Show what would be done without executing
    -f, --force         Force operation (skip confirmations)
    -y, --yes           Auto-confirm all prompts
    --version           Show version information

${BOLD}INTERACTIVE MODE:${NC}
    Run without arguments to launch the interactive menu.
    The menu provides a user-friendly interface to all features.

${BOLD}EXAMPLES:${NC}
    ${0##*/}                      # Interactive menu
    ${0##*/} install              # Install xRDP
    ${0##*/} --dry-run install    # Preview installation
    ${0##*/} status               # Check service status
    ${0##*/} security             # Apply security hardening
    ${0##*/} restart              # Restart service

${BOLD}SUPPORTED DISTRIBUTIONS:${NC}
    Ubuntu 20.04+, 22.04+, 24.04+
    Debian 11+, 12+
    Linux Mint 20+
    Fedora 38+
    Rocky Linux 8+, 9+
    AlmaLinux 8+, 9+
    openSUSE Leap 15+

${BOLD}CONNECTING:${NC}
    After installation, connect using any RDP client:
    - Windows: Remote Desktop Connection (mstsc.exe)
    - macOS: Microsoft Remote Desktop
    - Linux: Remmina, Vinagre, or xfreerdp

EOF
}

show_version() {
    echo "${SCRIPT_NAME} v${SCRIPT_VERSION}"
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
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE=true
                INTERACTIVE=false
                shift
                ;;
            -y|--yes)
                INTERACTIVE=false
                shift
                ;;
            --)
                shift
                break
                ;;
            -*)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                SUBCOMMAND="$1"
                shift
                break
                ;;
        esac
    done
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"
    
    # Launch interactive mode if no subcommand and running in a terminal
    if [[ -z "$SUBCOMMAND" ]]; then
        if [[ -t 0 && -t 1 ]]; then
            # Interactive terminal - show menu
            show_interactive_menu
        else
            # Non-interactive (piped) - show help
            show_help
            exit 0
        fi
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "Dry run mode - no changes will be made"
        echo ""
    fi
    
    case "$SUBCOMMAND" in
        install)
            do_install
            ;;
        status)
            detect_system
            service_status
            ;;
        start)
            check_root
            service_start
            ;;
        stop)
            check_root
            service_stop
            ;;
        restart)
            check_root
            service_restart
            ;;
        enable)
            check_root
            service_enable
            ;;
        disable)
            check_root
            service_disable
            ;;
        firewall)
            check_root
            detect_system
            configure_firewall
            ;;
        security)
            check_root
            detect_system
            apply_security
            ;;
        uninstall)
            do_uninstall
            ;;
        menu|interactive)
            show_interactive_menu
            ;;
        *)
            print_error "Unknown subcommand: $SUBCOMMAND"
            show_help
            exit 1
            ;;
    esac
}

# =============================================================================
# Entry Point
# =============================================================================

main "$@"
