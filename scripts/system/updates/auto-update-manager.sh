#!/bin/bash
# =============================================================================
# @id           auto-update-manager
# @name         auto-update-manager
# @displayName  Auto Update Manager
# @description  Install, configure, and manage automated system updates
# @category     maintenance
# @version      1.0.0
# @author       codefuturist
# @tags         update,automatic,unattended,scheduled,cron,systemd,launchd
# @shells       bash
# @platforms    linux,darwin
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
    # shellcheck source=../../../lib/rsr-lib.sh
    source "$RSR_LIB_DIR/rsr-lib.sh" validate
fi

# Script metadata
SCRIPT_NAME="Auto Update Manager"
SCRIPT_VERSION="1.0.0"

# =============================================================================
# Configuration
# =============================================================================

# Paths
CONFIG_DIR="/etc/rsr"
CONFIG_FILE="$CONFIG_DIR/auto-update.conf"
LOG_DIR="/var/log/rsr"
LOG_FILE="$LOG_DIR/auto-update.log"
SYSTEMD_DIR="/etc/systemd/system"
LAUNCHD_SYSTEM_DIR="/Library/LaunchDaemons"
LAUNCHD_USER_DIR="$HOME/Library/LaunchAgents"

# User-level paths (non-root)
USER_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/rsr"
USER_LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/rsr/logs"

# Service names
SERVICE_NAME="rsr-auto-update"
LAUNCHD_LABEL="com.rsr.auto-update"

# Default settings
DEFAULT_SCHEDULE="daily"
DEFAULT_TIME="02:00"
DEFAULT_DAY="0"  # Sunday
DEFAULT_REBOOT="never"
DEFAULT_SECURITY_ONLY=false
DEFAULT_INCLUDE_LANG=false

# Color codes (from RSR library or fallback)
RED="${RSR_COLOR_RED:-\033[0;31m}"
GREEN="${RSR_COLOR_GREEN:-\033[0;32m}"
YELLOW="${RSR_COLOR_YELLOW:-\033[1;33m}"
BLUE="${RSR_COLOR_BLUE:-\033[0;34m}"
CYAN="${RSR_COLOR_CYAN:-\033[0;36m}"
MAGENTA="${RSR_COLOR_MAGENTA:-\033[0;35m}"
DIM="${RSR_COLOR_DIM:-\033[2m}"
BOLD="${RSR_COLOR_BOLD:-\033[1m}"
NC="${RSR_COLOR_RESET:-\033[0m}"

# Exit codes
EXIT_OK=0
EXIT_ERROR=1
EXIT_INVALID_ARGS=2
EXIT_PERMISSION=3
EXIT_NOT_INSTALLED=4
EXIT_ALREADY_INSTALLED=5

# Interactive mode flag
INTERACTIVE_MODE=false

# =============================================================================
# Utility Functions
# =============================================================================

log_info() { echo -e "${BLUE}ℹ${NC}  $*"; }
log_success() { echo -e "${GREEN}✓${NC}  $*"; }
log_warn() { echo -e "${YELLOW}⚠${NC}  $*"; }
log_error() { echo -e "${RED}✗${NC}  $*" >&2; }
log_step() { echo -e "${CYAN}→${NC}  $*"; }
log_dim() { echo -e "${DIM}   $*${NC}"; }

is_root() { [[ $EUID -eq 0 ]]; }

is_macos() { [[ "$(uname -s)" == "Darwin" ]]; }

is_linux() { [[ "$(uname -s)" == "Linux" ]]; }

has_systemd() { command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; }

detect_distro() {
    if is_macos; then
        echo "macos"
    elif [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        case "$ID" in
            debian|ubuntu|linuxmint|pop) echo "debian" ;;
            rhel|centos|fedora|rocky|alma|ol) echo "rhel" ;;
            arch|manjaro|endeavouros) echo "arch" ;;
            opensuse*|sles) echo "suse" ;;
            alpine) echo "alpine" ;;
            *) echo "unknown" ;;
        esac
    else
        echo "unknown"
    fi
}

detect_pkg_manager() {
    if command -v apt-get &>/dev/null; then echo "apt"
    elif command -v dnf &>/dev/null; then echo "dnf"
    elif command -v yum &>/dev/null; then echo "yum"
    elif command -v pacman &>/dev/null; then echo "pacman"
    elif command -v zypper &>/dev/null; then echo "zypper"
    elif command -v apk &>/dev/null; then echo "apk"
    elif command -v brew &>/dev/null; then echo "brew"
    else echo "unknown"
    fi
}

require_root() {
    if ! is_root; then
        log_error "This operation requires root privileges"
        log_dim "Run with: sudo $0 $*"
        exit $EXIT_PERMISSION
    fi
}

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup="${file}.bak.$(date +%Y%m%d%H%M%S)"
        cp "$file" "$backup"
        log_dim "Backed up: $file → $backup"
    fi
}

ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        log_dim "Created directory: $dir"
    fi
}

get_update_script_path() {
    local distro
    distro=$(detect_distro)
    
    if [[ "$distro" == "macos" ]]; then
        echo "$SCRIPT_DIR/system-update-macos.sh"
    else
        echo "$SCRIPT_DIR/system-update.sh"
    fi
}

# =============================================================================
# Usage / Help
# =============================================================================

usage() {
    cat << EOF
${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}

Install, configure, and manage automated system updates across platforms.

${YELLOW}Usage:${NC}
    $0 [command] [options]
    $0                          ${DIM}# Interactive mode (when run without arguments)${NC}
    $0 -i                       ${DIM}# Force interactive mode${NC}

${BOLD}Commands:${NC}
    install             Install and configure automatic updates
    remove              Remove automatic update configuration
    status              Show current configuration and status
    enable              Enable scheduled updates
    disable             Disable updates (keep configuration)
    run-now             Trigger an immediate update
    logs                Show update history and logs
    config              Show or modify configuration

${BOLD}Options:${NC}
    -h, --help                  Show this help message
    -i, --interactive           Run in interactive mode with guided setup
    -v, --verbose               Enable verbose output
    -y, --yes                   Skip confirmation prompts
    -n, --dry-run               Show what would be done

${BOLD}Install Options:${NC}
    --schedule <schedule>       Update frequency: daily, weekly, monthly
                                (default: daily)
    --time <HH:MM>              Time to run updates (default: 02:00)
    --day <0-6|sun-sat>         Day for weekly schedule (default: sun/0)
    --security-only             Only install security updates
    --reboot <mode>             Reboot behavior: never, if-needed, always
                                (default: never)
    --include-lang              Include language package managers
    --notify <method>           Notification: email, webhook, none
    --email <address>           Email address for notifications
    --use-native                Use native tools (unattended-upgrades/dnf-automatic)
    --user                      Install for current user only (no root)

${BOLD}Platforms & Methods:${NC}
    ${DIM}Debian/Ubuntu${NC}    unattended-upgrades (native) or systemd timer
    ${DIM}RHEL/Fedora${NC}      dnf-automatic (native) or systemd timer
    ${DIM}Arch Linux${NC}       systemd timer with system-update.sh
    ${DIM}openSUSE${NC}         systemd timer with system-update.sh
    ${DIM}Alpine${NC}           cron with system-update.sh
    ${DIM}macOS${NC}            launchd with system-update-macos.sh

${BOLD}Examples:${NC}
    ${DIM}# Interactive setup wizard${NC}
    sudo $0
    
    ${DIM}# Interactive mode explicitly${NC}
    sudo $0 -i install

    ${DIM}# Install with defaults (daily at 2am)${NC}
    sudo $0 install

    ${DIM}# Install weekly updates on Sunday at 3am${NC}
    sudo $0 install --schedule weekly --time 03:00 --day sun

    ${DIM}# Install using native unattended-upgrades${NC}
    sudo $0 install --use-native --security-only

    ${DIM}# Check current status${NC}
    $0 status

    ${DIM}# View recent logs${NC}
    $0 logs --tail 50

    ${DIM}# Disable temporarily${NC}
    sudo $0 disable

    ${DIM}# Run update now${NC}
    sudo $0 run-now

${BOLD}Exit Codes:${NC}
    0   Success
    1   General error
    2   Invalid arguments
    3   Permission denied
    4   Auto-updates not installed
    5   Already installed

EOF
}

# =============================================================================
# Configuration Management
# =============================================================================

load_config() {
    # Set defaults
    SCHEDULE="${DEFAULT_SCHEDULE}"
    UPDATE_TIME="${DEFAULT_TIME}"
    UPDATE_DAY="${DEFAULT_DAY}"
    REBOOT_MODE="${DEFAULT_REBOOT}"
    SECURITY_ONLY="${DEFAULT_SECURITY_ONLY}"
    INCLUDE_LANG="${DEFAULT_INCLUDE_LANG}"
    NOTIFY_METHOD="none"
    NOTIFY_EMAIL=""
    USE_NATIVE=false
    USER_INSTALL=false
    
    # Load from config file if exists
    local config_file="$CONFIG_FILE"
    if ! is_root && [[ -f "$USER_CONFIG_DIR/auto-update.conf" ]]; then
        config_file="$USER_CONFIG_DIR/auto-update.conf"
    fi
    
    if [[ -f "$config_file" ]]; then
        # shellcheck source=/dev/null
        source "$config_file"
    fi
}

save_config() {
    local config_file="$CONFIG_FILE"
    local config_dir="$CONFIG_DIR"
    
    if [[ "$USER_INSTALL" == "true" ]] || ! is_root; then
        config_dir="$USER_CONFIG_DIR"
        config_file="$USER_CONFIG_DIR/auto-update.conf"
    fi
    
    ensure_dir "$config_dir"
    
    cat > "$config_file" << EOF
# RSR Auto Update Configuration
# Generated: $(date -Iseconds)

# Schedule: daily, weekly, monthly
SCHEDULE="$SCHEDULE"

# Time to run updates (HH:MM in 24h format)
UPDATE_TIME="$UPDATE_TIME"

# Day of week for weekly schedule (0=Sunday, 6=Saturday)
UPDATE_DAY="$UPDATE_DAY"

# Reboot behavior: never, if-needed, always
REBOOT_MODE="$REBOOT_MODE"

# Only install security updates
SECURITY_ONLY=$SECURITY_ONLY

# Include language package managers (pip, npm, cargo, gem)
INCLUDE_LANG=$INCLUDE_LANG

# Notification method: none, email, webhook
NOTIFY_METHOD="$NOTIFY_METHOD"

# Email address for notifications
NOTIFY_EMAIL="$NOTIFY_EMAIL"

# Use native auto-update tools (unattended-upgrades, dnf-automatic)
USE_NATIVE=$USE_NATIVE

# User-level installation
USER_INSTALL=$USER_INSTALL

# Installation timestamp
INSTALLED_AT="$(date -Iseconds)"

# Distro at install time
DISTRO="$(detect_distro)"

# Package manager
PKG_MANAGER="$(detect_pkg_manager)"
EOF
    
    log_success "Configuration saved to $config_file"
}

show_config() {
    echo -e "\n${BOLD}Current Configuration${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    load_config
    
    printf "  %-20s %s\n" "Schedule:" "${CYAN}$SCHEDULE${NC}"
    printf "  %-20s %s\n" "Time:" "${CYAN}$UPDATE_TIME${NC}"
    if [[ "$SCHEDULE" == "weekly" ]]; then
        local day_name
        case "$UPDATE_DAY" in
            0|sun) day_name="Sunday" ;;
            1|mon) day_name="Monday" ;;
            2|tue) day_name="Tuesday" ;;
            3|wed) day_name="Wednesday" ;;
            4|thu) day_name="Thursday" ;;
            5|fri) day_name="Friday" ;;
            6|sat) day_name="Saturday" ;;
        esac
        printf "  %-20s %s\n" "Day:" "${CYAN}$day_name${NC}"
    fi
    printf "  %-20s %s\n" "Security Only:" "${CYAN}$SECURITY_ONLY${NC}"
    printf "  %-20s %s\n" "Include Languages:" "${CYAN}$INCLUDE_LANG${NC}"
    printf "  %-20s %s\n" "Reboot Mode:" "${CYAN}$REBOOT_MODE${NC}"
    printf "  %-20s %s\n" "Notifications:" "${CYAN}$NOTIFY_METHOD${NC}"
    printf "  %-20s %s\n" "Use Native:" "${CYAN}$USE_NATIVE${NC}"
    echo ""
}

# =============================================================================
# Native Tool Installers (Debian: unattended-upgrades)
# =============================================================================

install_unattended_upgrades() {
    log_step "Installing unattended-upgrades..."
    
    # Install package
    apt-get update -qq
    apt-get install -y unattended-upgrades apt-listchanges
    
    # Configure 50unattended-upgrades
    local config_50="/etc/apt/apt.conf.d/50unattended-upgrades"
    backup_file "$config_50"
    
    cat > "$config_50" << 'EOF'
// RSR Auto Update Manager Configuration
// Automatically generated - manual edits may be overwritten

Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
EOF

    if [[ "$SECURITY_ONLY" != "true" ]]; then
        cat >> "$config_50" << 'EOF'
    "${distro_id}:${distro_codename}-updates";
EOF
    fi
    
    cat >> "$config_50" << 'EOF'
};

// Remove unused kernel packages
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";

// Remove unused dependencies
Unattended-Upgrade::Remove-Unused-Dependencies "true";

// Automatic reboot configuration
EOF

    case "$REBOOT_MODE" in
        never)
            echo 'Unattended-Upgrade::Automatic-Reboot "false";' >> "$config_50"
            ;;
        if-needed)
            echo 'Unattended-Upgrade::Automatic-Reboot "true";' >> "$config_50"
            echo "Unattended-Upgrade::Automatic-Reboot-Time \"$UPDATE_TIME\";" >> "$config_50"
            ;;
        always)
            echo 'Unattended-Upgrade::Automatic-Reboot "true";' >> "$config_50"
            echo 'Unattended-Upgrade::Automatic-Reboot-WithUsers "true";' >> "$config_50"
            echo "Unattended-Upgrade::Automatic-Reboot-Time \"$UPDATE_TIME\";" >> "$config_50"
            ;;
    esac
    
    # Email notifications
    if [[ "$NOTIFY_METHOD" == "email" && -n "$NOTIFY_EMAIL" ]]; then
        cat >> "$config_50" << EOF

// Email notifications
Unattended-Upgrade::Mail "$NOTIFY_EMAIL";
Unattended-Upgrade::MailReport "only-on-error";
EOF
    fi
    
    echo "" >> "$config_50"
    
    # Configure 20auto-upgrades
    local config_20="/etc/apt/apt.conf.d/20auto-upgrades"
    backup_file "$config_20"
    
    local update_interval=1
    local upgrade_interval=1
    
    case "$SCHEDULE" in
        daily) update_interval=1; upgrade_interval=1 ;;
        weekly) update_interval=1; upgrade_interval=7 ;;
        monthly) update_interval=1; upgrade_interval=30 ;;
    esac
    
    cat > "$config_20" << EOF
// RSR Auto Update Manager Configuration
APT::Periodic::Update-Package-Lists "$update_interval";
APT::Periodic::Unattended-Upgrade "$upgrade_interval";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
EOF
    
    # Enable and start the timer
    systemctl enable apt-daily.timer apt-daily-upgrade.timer
    systemctl start apt-daily.timer apt-daily-upgrade.timer
    
    log_success "unattended-upgrades configured and enabled"
}

remove_unattended_upgrades() {
    log_step "Removing unattended-upgrades configuration..."
    
    # Disable timers
    systemctl disable apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
    systemctl stop apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
    
    # Restore backups or remove configs
    local config_50="/etc/apt/apt.conf.d/50unattended-upgrades"
    local config_20="/etc/apt/apt.conf.d/20auto-upgrades"
    
    for config in "$config_50" "$config_20"; do
        # Find most recent backup
        local latest_backup
        latest_backup=$(ls -t "${config}.bak."* 2>/dev/null | head -1)
        if [[ -n "$latest_backup" ]]; then
            mv "$latest_backup" "$config"
            log_dim "Restored: $config"
        fi
    done
    
    log_success "unattended-upgrades disabled"
}

# =============================================================================
# Native Tool Installers (RHEL/Fedora: dnf-automatic)
# =============================================================================

install_dnf_automatic() {
    log_step "Installing dnf-automatic..."
    
    # Install package
    dnf install -y dnf-automatic
    
    # Configure dnf-automatic
    local config="/etc/dnf/automatic.conf"
    backup_file "$config"
    
    cat > "$config" << EOF
[commands]
# What kind of upgrade to perform
# security = only security updates
# default = all available updates
upgrade_type = $([ "$SECURITY_ONLY" == "true" ] && echo "security" || echo "default")

# Whether updates should be downloaded
download_updates = yes

# Whether updates should be applied
apply_updates = yes

# Reboot after updates if needed
EOF

    case "$REBOOT_MODE" in
        never)
            echo "reboot = never" >> "$config"
            ;;
        if-needed)
            echo "reboot = when-needed" >> "$config"
            echo "reboot_command = \"shutdown -r +5 'System rebooting for updates'\"" >> "$config"
            ;;
        always)
            echo "reboot = when-needed" >> "$config"
            ;;
    esac
    
    cat >> "$config" << EOF

[emitters]
# How to notify about updates
emit_via = $([ "$NOTIFY_METHOD" == "email" ] && echo "email" || echo "stdio")

[email]
email_from = root@$(hostname -f 2>/dev/null || hostname)
email_to = ${NOTIFY_EMAIL:-root}
email_host = localhost

[base]
debuglevel = 1
EOF
    
    # Enable the appropriate timer
    local timer_name="dnf-automatic.timer"
    if [[ "$SECURITY_ONLY" == "true" ]]; then
        timer_name="dnf-automatic-install.timer"
    fi
    
    systemctl enable "$timer_name"
    systemctl start "$timer_name"
    
    log_success "dnf-automatic configured and enabled"
}

remove_dnf_automatic() {
    log_step "Removing dnf-automatic configuration..."
    
    # Disable all possible timers
    for timer in dnf-automatic.timer dnf-automatic-install.timer dnf-automatic-download.timer; do
        systemctl disable "$timer" 2>/dev/null || true
        systemctl stop "$timer" 2>/dev/null || true
    done
    
    # Restore config backup
    local config="/etc/dnf/automatic.conf"
    local latest_backup
    latest_backup=$(ls -t "${config}.bak."* 2>/dev/null | head -1)
    if [[ -n "$latest_backup" ]]; then
        mv "$latest_backup" "$config"
        log_dim "Restored: $config"
    fi
    
    log_success "dnf-automatic disabled"
}

# =============================================================================
# systemd Timer Installation
# =============================================================================

install_systemd_timer() {
    log_step "Installing systemd timer..."
    
    local update_script
    update_script=$(get_update_script_path)
    
    if [[ ! -f "$update_script" ]]; then
        log_error "Update script not found: $update_script"
        exit $EXIT_ERROR
    fi
    
    ensure_dir "$LOG_DIR"
    
    # Create service file
    cat > "$SYSTEMD_DIR/${SERVICE_NAME}.service" << EOF
[Unit]
Description=RSR Automatic System Updates
Documentation=https://github.com/codefuturist/remote-script-runner
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$update_script --all $([ "$SECURITY_ONLY" == "true" ] && echo "--security") $([ "$INCLUDE_LANG" == "true" ] && echo "--lang") -y
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE

# Security hardening
NoNewPrivileges=yes
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF
    
    # Create timer file
    local on_calendar
    case "$SCHEDULE" in
        daily)
            on_calendar="*-*-* $UPDATE_TIME:00"
            ;;
        weekly)
            local day_name
            case "$UPDATE_DAY" in
                0|sun) day_name="Sun" ;;
                1|mon) day_name="Mon" ;;
                2|tue) day_name="Tue" ;;
                3|wed) day_name="Wed" ;;
                4|thu) day_name="Thu" ;;
                5|fri) day_name="Fri" ;;
                6|sat) day_name="Sat" ;;
            esac
            on_calendar="$day_name *-*-* $UPDATE_TIME:00"
            ;;
        monthly)
            on_calendar="*-*-01 $UPDATE_TIME:00"
            ;;
    esac
    
    cat > "$SYSTEMD_DIR/${SERVICE_NAME}.timer" << EOF
[Unit]
Description=RSR Automatic System Updates Timer
Documentation=https://github.com/codefuturist/remote-script-runner

[Timer]
OnCalendar=$on_calendar
RandomizedDelaySec=15min
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # Reload and enable
    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}.timer"
    systemctl start "${SERVICE_NAME}.timer"
    
    log_success "systemd timer installed and enabled"
    log_dim "Service: ${SERVICE_NAME}.service"
    log_dim "Timer: ${SERVICE_NAME}.timer"
    log_dim "Schedule: $on_calendar"
}

remove_systemd_timer() {
    log_step "Removing systemd timer..."
    
    systemctl disable "${SERVICE_NAME}.timer" 2>/dev/null || true
    systemctl stop "${SERVICE_NAME}.timer" 2>/dev/null || true
    
    rm -f "$SYSTEMD_DIR/${SERVICE_NAME}.service"
    rm -f "$SYSTEMD_DIR/${SERVICE_NAME}.timer"
    
    systemctl daemon-reload
    
    log_success "systemd timer removed"
}

# =============================================================================
# launchd Installation (macOS)
# =============================================================================

install_launchd() {
    log_step "Installing launchd agent..."
    
    local update_script
    update_script=$(get_update_script_path)
    
    if [[ ! -f "$update_script" ]]; then
        log_error "Update script not found: $update_script"
        exit $EXIT_ERROR
    fi
    
    local plist_dir="$LAUNCHD_SYSTEM_DIR"
    local run_at_load="true"
    
    if [[ "$USER_INSTALL" == "true" ]] || ! is_root; then
        plist_dir="$LAUNCHD_USER_DIR"
        USER_INSTALL=true
    fi
    
    ensure_dir "$plist_dir"
    
    local log_path="$LOG_DIR"
    if [[ "$USER_INSTALL" == "true" ]]; then
        log_path="$USER_LOG_DIR"
        ensure_dir "$log_path"
    else
        ensure_dir "$LOG_DIR"
    fi
    
    # Parse time
    local hour minute
    hour=$(echo "$UPDATE_TIME" | cut -d: -f1)
    minute=$(echo "$UPDATE_TIME" | cut -d: -f2)
    
    # Build arguments
    local args_xml="        <string>$update_script</string>
        <string>--all</string>"
    
    if [[ "$SECURITY_ONLY" == "true" ]]; then
        # macOS doesn't have security-only, but we can skip certain updates
        args_xml="$args_xml
        <string>--no-system</string>"
    fi
    
    if [[ "$INCLUDE_LANG" == "true" ]]; then
        args_xml="$args_xml
        <string>--lang</string>"
    fi
    
    args_xml="$args_xml
        <string>-y</string>"
    
    # Build calendar interval
    local calendar_xml=""
    case "$SCHEDULE" in
        daily)
            calendar_xml="    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>$((10#$hour))</integer>
        <key>Minute</key>
        <integer>$((10#$minute))</integer>
    </dict>"
            ;;
        weekly)
            local weekday
            case "$UPDATE_DAY" in
                0|sun) weekday=0 ;;
                1|mon) weekday=1 ;;
                2|tue) weekday=2 ;;
                3|wed) weekday=3 ;;
                4|thu) weekday=4 ;;
                5|fri) weekday=5 ;;
                6|sat) weekday=6 ;;
            esac
            calendar_xml="    <key>StartCalendarInterval</key>
    <dict>
        <key>Weekday</key>
        <integer>$weekday</integer>
        <key>Hour</key>
        <integer>$((10#$hour))</integer>
        <key>Minute</key>
        <integer>$((10#$minute))</integer>
    </dict>"
            ;;
        monthly)
            calendar_xml="    <key>StartCalendarInterval</key>
    <dict>
        <key>Day</key>
        <integer>1</integer>
        <key>Hour</key>
        <integer>$((10#$hour))</integer>
        <key>Minute</key>
        <integer>$((10#$minute))</integer>
    </dict>"
            ;;
    esac
    
    local plist_file="$plist_dir/${LAUNCHD_LABEL}.plist"
    
    cat > "$plist_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LAUNCHD_LABEL</string>
    
    <key>ProgramArguments</key>
    <array>
$args_xml
    </array>
    
$calendar_xml
    
    <key>StandardOutPath</key>
    <string>$log_path/auto-update.log</string>
    
    <key>StandardErrorPath</key>
    <string>$log_path/auto-update.err</string>
    
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    
    <key>RunAtLoad</key>
    <false/>
    
    <key>ProcessType</key>
    <string>Background</string>
    
    <key>LowPriorityIO</key>
    <true/>
    
    <key>Nice</key>
    <integer>10</integer>
</dict>
</plist>
EOF
    
    # Load the agent
    if [[ "$USER_INSTALL" == "true" ]]; then
        launchctl load -w "$plist_file" 2>/dev/null || true
    else
        launchctl load -w "$plist_file" 2>/dev/null || true
    fi
    
    log_success "launchd agent installed"
    log_dim "Plist: $plist_file"
}

remove_launchd() {
    log_step "Removing launchd agent..."
    
    local plist_file="$LAUNCHD_SYSTEM_DIR/${LAUNCHD_LABEL}.plist"
    local user_plist="$LAUNCHD_USER_DIR/${LAUNCHD_LABEL}.plist"
    
    # Unload and remove system plist
    if [[ -f "$plist_file" ]]; then
        launchctl unload "$plist_file" 2>/dev/null || true
        rm -f "$plist_file"
        log_dim "Removed: $plist_file"
    fi
    
    # Unload and remove user plist
    if [[ -f "$user_plist" ]]; then
        launchctl unload "$user_plist" 2>/dev/null || true
        rm -f "$user_plist"
        log_dim "Removed: $user_plist"
    fi
    
    log_success "launchd agent removed"
}

# =============================================================================
# Cron Installation (Alpine fallback)
# =============================================================================

install_cron() {
    log_step "Installing cron job..."
    
    local update_script
    update_script=$(get_update_script_path)
    
    if [[ ! -f "$update_script" ]]; then
        log_error "Update script not found: $update_script"
        exit $EXIT_ERROR
    fi
    
    ensure_dir "$LOG_DIR"
    
    local cron_file="/etc/cron.d/rsr-auto-update"
    
    local hour minute
    hour=$(echo "$UPDATE_TIME" | cut -d: -f1)
    minute=$(echo "$UPDATE_TIME" | cut -d: -f2)
    
    local cron_schedule
    case "$SCHEDULE" in
        daily)
            cron_schedule="$minute $hour * * *"
            ;;
        weekly)
            cron_schedule="$minute $hour * * $UPDATE_DAY"
            ;;
        monthly)
            cron_schedule="$minute $hour 1 * *"
            ;;
    esac
    
    local args="--all -y"
    [[ "$SECURITY_ONLY" == "true" ]] && args="$args --security"
    [[ "$INCLUDE_LANG" == "true" ]] && args="$args --lang"
    
    cat > "$cron_file" << EOF
# RSR Auto Update Manager
# Generated: $(date -Iseconds)
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

$cron_schedule root $update_script $args >> $LOG_FILE 2>&1
EOF
    
    chmod 644 "$cron_file"
    
    # Ensure cron is running
    if command -v rc-service &>/dev/null; then
        rc-service crond restart 2>/dev/null || true
    elif command -v service &>/dev/null; then
        service cron restart 2>/dev/null || true
    fi
    
    log_success "cron job installed"
    log_dim "File: $cron_file"
    log_dim "Schedule: $cron_schedule"
}

remove_cron() {
    log_step "Removing cron job..."
    
    rm -f /etc/cron.d/rsr-auto-update
    
    log_success "cron job removed"
}

# =============================================================================
# Main Installation Logic
# =============================================================================

do_install() {
    local distro pkg_manager
    distro=$(detect_distro)
    pkg_manager=$(detect_pkg_manager)
    
    echo ""
    echo -e "${BOLD}Installing Auto-Updates${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_info "Distro: $distro"
    log_info "Package Manager: $pkg_manager"
    echo ""
    
    # Check if already installed
    if is_installed; then
        if [[ "$FORCE" != "true" ]]; then
            log_warn "Auto-updates already configured"
            log_dim "Use --force to reconfigure, or run 'remove' first"
            exit $EXIT_ALREADY_INSTALLED
        fi
        log_warn "Reconfiguring existing installation..."
        do_remove --quiet
    fi
    
    # Save configuration first
    save_config
    
    # Install based on platform and preferences
    if is_macos; then
        install_launchd
    elif [[ "$USE_NATIVE" == "true" ]]; then
        case "$distro" in
            debian)
                install_unattended_upgrades
                ;;
            rhel)
                if [[ "$pkg_manager" == "dnf" ]]; then
                    install_dnf_automatic
                else
                    log_warn "yum doesn't have native auto-updates, using systemd timer"
                    install_systemd_timer
                fi
                ;;
            *)
                log_warn "No native auto-update tool for $distro, using systemd timer"
                install_systemd_timer
                ;;
        esac
    elif has_systemd; then
        install_systemd_timer
    else
        # Alpine or other non-systemd
        install_cron
    fi
    
    echo ""
    log_success "Auto-updates installed successfully!"
    echo ""
    show_config
    show_status
}

do_remove() {
    local quiet=false
    [[ "$1" == "--quiet" ]] && quiet=true
    
    if [[ "$quiet" != "true" ]]; then
        echo ""
        echo -e "${BOLD}Removing Auto-Updates${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
    fi
    
    local distro
    distro=$(detect_distro)
    
    # Remove all possible installations
    if is_macos; then
        remove_launchd
    else
        # Try removing all types
        remove_systemd_timer 2>/dev/null || true
        remove_cron 2>/dev/null || true
        
        if [[ -f /etc/apt/apt.conf.d/50unattended-upgrades ]]; then
            remove_unattended_upgrades 2>/dev/null || true
        fi
        
        if [[ -f /etc/dnf/automatic.conf ]]; then
            remove_dnf_automatic 2>/dev/null || true
        fi
    fi
    
    # Remove config
    rm -f "$CONFIG_FILE" 2>/dev/null || true
    rm -f "$USER_CONFIG_DIR/auto-update.conf" 2>/dev/null || true
    
    if [[ "$quiet" != "true" ]]; then
        echo ""
        log_success "Auto-updates removed"
    fi
}

# =============================================================================
# Status and Control
# =============================================================================

is_installed() {
    if is_macos; then
        [[ -f "$LAUNCHD_SYSTEM_DIR/${LAUNCHD_LABEL}.plist" ]] || \
        [[ -f "$LAUNCHD_USER_DIR/${LAUNCHD_LABEL}.plist" ]]
    else
        systemctl is-enabled "${SERVICE_NAME}.timer" &>/dev/null || \
        [[ -f /etc/cron.d/rsr-auto-update ]] || \
        systemctl is-enabled apt-daily-upgrade.timer &>/dev/null || \
        systemctl is-enabled dnf-automatic.timer &>/dev/null || \
        systemctl is-enabled dnf-automatic-install.timer &>/dev/null
    fi
}

is_enabled() {
    if is_macos; then
        local plist=""
        if [[ -f "$LAUNCHD_SYSTEM_DIR/${LAUNCHD_LABEL}.plist" ]]; then
            plist="$LAUNCHD_SYSTEM_DIR/${LAUNCHD_LABEL}.plist"
        elif [[ -f "$LAUNCHD_USER_DIR/${LAUNCHD_LABEL}.plist" ]]; then
            plist="$LAUNCHD_USER_DIR/${LAUNCHD_LABEL}.plist"
        fi
        
        if [[ -n "$plist" ]]; then
            launchctl list 2>/dev/null | grep -q "$LAUNCHD_LABEL"
        else
            return 1
        fi
    else
        systemctl is-active "${SERVICE_NAME}.timer" &>/dev/null || \
        systemctl is-active apt-daily-upgrade.timer &>/dev/null || \
        systemctl is-active dnf-automatic.timer &>/dev/null || \
        systemctl is-active dnf-automatic-install.timer &>/dev/null
    fi
}

show_status() {
    echo -e "\n${BOLD}Status${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local installed=false
    local enabled=false
    local method="none"
    local next_run="unknown"
    
    if is_installed; then
        installed=true
        is_enabled && enabled=true
    fi
    
    # Detect method and get next run time
    if is_macos; then
        if [[ -f "$LAUNCHD_SYSTEM_DIR/${LAUNCHD_LABEL}.plist" ]] || \
           [[ -f "$LAUNCHD_USER_DIR/${LAUNCHD_LABEL}.plist" ]]; then
            method="launchd"
            # launchd doesn't easily show next run time
            next_run="(see configuration)"
        fi
    else
        if systemctl is-enabled "${SERVICE_NAME}.timer" &>/dev/null; then
            method="systemd timer"
            next_run=$(systemctl show "${SERVICE_NAME}.timer" --property=NextElapseUSecRealtime 2>/dev/null | cut -d= -f2 || echo "unknown")
        elif systemctl is-enabled apt-daily-upgrade.timer &>/dev/null; then
            method="unattended-upgrades"
            next_run=$(systemctl show apt-daily-upgrade.timer --property=NextElapseUSecRealtime 2>/dev/null | cut -d= -f2 || echo "unknown")
        elif systemctl is-enabled dnf-automatic.timer &>/dev/null 2>/dev/null || \
             systemctl is-enabled dnf-automatic-install.timer &>/dev/null 2>/dev/null; then
            method="dnf-automatic"
            next_run=$(systemctl show dnf-automatic.timer --property=NextElapseUSecRealtime 2>/dev/null | cut -d= -f2 || echo "unknown")
        elif [[ -f /etc/cron.d/rsr-auto-update ]]; then
            method="cron"
            next_run="(see cron schedule)"
        fi
    fi
    
    # Display status
    if [[ "$installed" == "true" ]]; then
        printf "  %-20s ${GREEN}●${NC} %s\n" "Installed:" "Yes"
    else
        printf "  %-20s ${RED}○${NC} %s\n" "Installed:" "No"
        echo ""
        log_dim "Run '$0 install' to set up automatic updates"
        return
    fi
    
    if [[ "$enabled" == "true" ]]; then
        printf "  %-20s ${GREEN}●${NC} %s\n" "Enabled:" "Yes"
    else
        printf "  %-20s ${YELLOW}○${NC} %s\n" "Enabled:" "No (disabled)"
    fi
    
    printf "  %-20s %s\n" "Method:" "${CYAN}$method${NC}"
    printf "  %-20s %s\n" "Next Run:" "${CYAN}$next_run${NC}"
    
    # Show last run info
    local last_log=""
    if [[ -f "$LOG_FILE" ]]; then
        last_log="$LOG_FILE"
    elif [[ -f "$USER_LOG_DIR/auto-update.log" ]]; then
        last_log="$USER_LOG_DIR/auto-update.log"
    fi
    
    if [[ -n "$last_log" && -f "$last_log" ]]; then
        local last_run
        last_run=$(stat -c %y "$last_log" 2>/dev/null || stat -f %Sm "$last_log" 2>/dev/null || echo "unknown")
        printf "  %-20s %s\n" "Last Log Update:" "${DIM}$last_run${NC}"
    fi
    
    echo ""
}

do_enable() {
    if ! is_installed; then
        log_error "Auto-updates not installed"
        log_dim "Run '$0 install' first"
        exit $EXIT_NOT_INSTALLED
    fi
    
    log_step "Enabling auto-updates..."
    
    if is_macos; then
        local plist=""
        if [[ -f "$LAUNCHD_SYSTEM_DIR/${LAUNCHD_LABEL}.plist" ]]; then
            plist="$LAUNCHD_SYSTEM_DIR/${LAUNCHD_LABEL}.plist"
        elif [[ -f "$LAUNCHD_USER_DIR/${LAUNCHD_LABEL}.plist" ]]; then
            plist="$LAUNCHD_USER_DIR/${LAUNCHD_LABEL}.plist"
        fi
        
        if [[ -n "$plist" ]]; then
            launchctl load -w "$plist"
        fi
    else
        if systemctl list-unit-files "${SERVICE_NAME}.timer" &>/dev/null; then
            systemctl enable "${SERVICE_NAME}.timer"
            systemctl start "${SERVICE_NAME}.timer"
        elif systemctl list-unit-files apt-daily-upgrade.timer &>/dev/null; then
            systemctl enable apt-daily.timer apt-daily-upgrade.timer
            systemctl start apt-daily.timer apt-daily-upgrade.timer
        elif systemctl list-unit-files dnf-automatic.timer &>/dev/null; then
            systemctl enable dnf-automatic.timer
            systemctl start dnf-automatic.timer
        fi
    fi
    
    log_success "Auto-updates enabled"
}

do_disable() {
    if ! is_installed; then
        log_error "Auto-updates not installed"
        exit $EXIT_NOT_INSTALLED
    fi
    
    log_step "Disabling auto-updates..."
    
    if is_macos; then
        launchctl unload "$LAUNCHD_SYSTEM_DIR/${LAUNCHD_LABEL}.plist" 2>/dev/null || true
        launchctl unload "$LAUNCHD_USER_DIR/${LAUNCHD_LABEL}.plist" 2>/dev/null || true
    else
        systemctl stop "${SERVICE_NAME}.timer" 2>/dev/null || true
        systemctl disable "${SERVICE_NAME}.timer" 2>/dev/null || true
        
        systemctl stop apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
        systemctl disable apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
        
        systemctl stop dnf-automatic.timer 2>/dev/null || true
        systemctl disable dnf-automatic.timer 2>/dev/null || true
    fi
    
    log_success "Auto-updates disabled (configuration preserved)"
    log_dim "Run '$0 enable' to re-enable"
}

do_run_now() {
    log_step "Running system update now..."
    echo ""
    
    local update_script
    update_script=$(get_update_script_path)
    
    if [[ ! -f "$update_script" ]]; then
        log_error "Update script not found: $update_script"
        exit $EXIT_ERROR
    fi
    
    load_config
    
    local args=("--all" "-y")
    [[ "$SECURITY_ONLY" == "true" ]] && args+=("--security")
    [[ "$INCLUDE_LANG" == "true" ]] && args+=("--lang")
    [[ "$VERBOSE" == "true" ]] && args+=("-v")
    
    exec "$update_script" "${args[@]}"
}

do_logs() {
    local tail_lines=50
    local follow=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tail|-n) tail_lines="$2"; shift 2 ;;
            --follow|-f) follow=true; shift ;;
            *) shift ;;
        esac
    done
    
    local log_file=""
    
    # Find log file
    for f in "$LOG_FILE" "$USER_LOG_DIR/auto-update.log" /var/log/unattended-upgrades/unattended-upgrades.log /var/log/dnf.log; do
        if [[ -f "$f" ]]; then
            log_file="$f"
            break
        fi
    done
    
    if [[ -z "$log_file" ]]; then
        log_warn "No log file found"
        log_dim "Logs will appear after the first scheduled update run"
        exit 0
    fi
    
    echo -e "${BOLD}Update Logs${NC} (${DIM}$log_file${NC})"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    if [[ "$follow" == "true" ]]; then
        tail -f "$log_file"
    else
        tail -n "$tail_lines" "$log_file"
    fi
}

# =============================================================================
# Interactive Mode Functions
# =============================================================================

# Print a boxed header
print_header() {
    local title="$1"
    local width=60
    local padding=$(( (width - ${#title} - 2) / 2 ))
    
    echo ""
    echo -e "${CYAN}╭$(printf '─%.0s' $(seq 1 $width))╮${NC}"
    echo -e "${CYAN}│${NC}$(printf ' %.0s' $(seq 1 $padding))${BOLD}$title${NC}$(printf ' %.0s' $(seq 1 $((width - padding - ${#title}))))${CYAN}│${NC}"
    echo -e "${CYAN}╰$(printf '─%.0s' $(seq 1 $width))╯${NC}"
    echo ""
}

# Print a section header
print_section() {
    local title="$1"
    echo ""
    echo -e "${BOLD}${title}${NC}"
    echo -e "${DIM}$(printf '─%.0s' $(seq 1 ${#title}))${NC}"
}

# Prompt for yes/no with default
prompt_yn() {
    local prompt="$1"
    local default="${2:-y}"
    local result
    
    if [[ "$default" == "y" ]]; then
        echo -en "${CYAN}?${NC} $prompt ${DIM}[Y/n]${NC} "
    else
        echo -en "${CYAN}?${NC} $prompt ${DIM}[y/N]${NC} "
    fi
    
    read -r result
    result="${result:-$default}"
    
    [[ "${result,,}" == "y" || "${result,,}" == "yes" ]]
}

# Prompt for a value with default
prompt_value() {
    local prompt="$1"
    local default="$2"
    local result
    
    echo -en "${CYAN}?${NC} $prompt ${DIM}[$default]${NC} "
    read -r result
    echo "${result:-$default}"
}

# Interactive menu selection
# Usage: menu_select "prompt" "option1" "option2" "option3"
# Returns: selected index (0-based)
menu_select() {
    local prompt="$1"
    shift
    local options=("$@")
    local selected=0
    local key
    
    # Hide cursor
    tput civis 2>/dev/null || true
    
    # Cleanup on exit
    trap 'tput cnorm 2>/dev/null || true' RETURN
    
    while true; do
        # Clear previous menu
        for ((i = 0; i < ${#options[@]} + 2; i++)); do
            tput cuu1 2>/dev/null || echo -en "\033[1A"
            tput el 2>/dev/null || echo -en "\033[2K"
        done 2>/dev/null || true
        
        # Print prompt
        echo -e "${CYAN}?${NC} $prompt ${DIM}(↑/↓ to select, Enter to confirm)${NC}"
        echo ""
        
        # Print options
        for i in "${!options[@]}"; do
            if [[ $i -eq $selected ]]; then
                echo -e "  ${GREEN}❯${NC} ${BOLD}${options[$i]}${NC}"
            else
                echo -e "    ${DIM}${options[$i]}${NC}"
            fi
        done
        
        # Read key
        read -rsn1 key
        
        case "$key" in
            $'\x1b')  # Escape sequence
                read -rsn2 -t 0.1 key
                case "$key" in
                    '[A') # Up
                        ((selected--))
                        [[ $selected -lt 0 ]] && selected=$((${#options[@]} - 1))
                        ;;
                    '[B') # Down
                        ((selected++))
                        [[ $selected -ge ${#options[@]} ]] && selected=0
                        ;;
                esac
                ;;
            '') # Enter
                tput cnorm 2>/dev/null || true
                return $selected
                ;;
        esac
    done
}

# Simple numbered menu (fallback for non-interactive terminals)
menu_numbered() {
    local prompt="$1"
    shift
    local options=("$@")
    local choice
    
    echo -e "${CYAN}?${NC} $prompt"
    echo ""
    
    for i in "${!options[@]}"; do
        echo -e "  ${CYAN}$((i + 1))${NC}) ${options[$i]}"
    done
    
    echo ""
    while true; do
        echo -en "  ${DIM}Enter choice [1-${#options[@]}]:${NC} "
        read -r choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#options[@]} ]]; then
            return $((choice - 1))
        fi
        echo -e "  ${RED}Invalid choice${NC}"
    done
}

# Smart menu - uses arrow keys if terminal supports it, otherwise numbered
smart_menu() {
    local prompt="$1"
    shift
    local options=("$@")
    
    # Check if we have a proper terminal
    if [[ -t 0 ]] && [[ -t 1 ]] && command -v tput &>/dev/null; then
        # Add spacing for menu redraw
        echo ""
        for ((i = 0; i < ${#options[@]} + 2; i++)); do
            echo ""
        done
        menu_select "$prompt" "${options[@]}"
    else
        menu_numbered "$prompt" "${options[@]}"
    fi
}

# Time picker
prompt_time() {
    local prompt="$1"
    local default="$2"
    local result
    
    while true; do
        result=$(prompt_value "$prompt (HH:MM)" "$default")
        if [[ "$result" =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9]$ ]]; then
            # Normalize to HH:MM
            printf "%02d:%02d\n" "${result%%:*}" "${result##*:}"
            return 0
        fi
        log_error "Invalid time format. Use HH:MM (e.g., 02:00, 14:30)"
    done
}

# Day picker for weekly schedule
prompt_day() {
    local days=("Sunday" "Monday" "Tuesday" "Wednesday" "Thursday" "Friday" "Saturday")
    
    echo ""  # Initial spacing
    smart_menu "Which day of the week?" "${days[@]}"
    local selected=$?
    echo "$selected"
}

# Interactive install wizard
interactive_install() {
    print_header "Auto Update Manager Setup"
    
    local distro pkg_manager
    distro=$(detect_distro)
    pkg_manager=$(detect_pkg_manager)
    
    echo -e "  ${DIM}Platform:${NC}        $(uname -s)"
    echo -e "  ${DIM}Distribution:${NC}    $distro"
    echo -e "  ${DIM}Package Manager:${NC} $pkg_manager"
    echo ""
    
    # Check existing installation
    if is_installed; then
        echo -e "  ${YELLOW}⚠${NC}  Auto-updates are already configured"
        echo ""
        if ! prompt_yn "Do you want to reconfigure?" "n"; then
            echo ""
            log_info "Keeping existing configuration"
            exit 0
        fi
        FORCE=true
    fi
    
    print_section "Update Schedule"
    
    # Schedule selection
    local schedules=("Daily - Run updates every day" "Weekly - Run updates once a week" "Monthly - Run updates once a month")
    smart_menu "How often should updates run?" "${schedules[@]}"
    local sched_idx=$?
    
    case $sched_idx in
        0) SCHEDULE="daily" ;;
        1) SCHEDULE="weekly" ;;
        2) SCHEDULE="monthly" ;;
    esac
    echo -e "  ${GREEN}✓${NC} Schedule: ${CYAN}$SCHEDULE${NC}"
    
    # Time selection
    echo ""
    UPDATE_TIME=$(prompt_time "What time should updates run?" "02:00")
    echo -e "  ${GREEN}✓${NC} Time: ${CYAN}$UPDATE_TIME${NC}"
    
    # Day selection for weekly
    if [[ "$SCHEDULE" == "weekly" ]]; then
        echo ""
        UPDATE_DAY=$(prompt_day)
        local day_names=("Sunday" "Monday" "Tuesday" "Wednesday" "Thursday" "Friday" "Saturday")
        echo -e "  ${GREEN}✓${NC} Day: ${CYAN}${day_names[$UPDATE_DAY]}${NC}"
    fi
    
    print_section "Update Options"
    
    # Security only
    echo ""
    if prompt_yn "Install security updates only? (recommended for servers)" "n"; then
        SECURITY_ONLY=true
        echo -e "  ${GREEN}✓${NC} Security only: ${CYAN}Yes${NC}"
    else
        SECURITY_ONLY=false
        echo -e "  ${GREEN}✓${NC} Security only: ${CYAN}No (all updates)${NC}"
    fi
    
    # Language packages
    echo ""
    if prompt_yn "Include language packages (pip, npm, cargo, gem)?" "n"; then
        INCLUDE_LANG=true
        echo -e "  ${GREEN}✓${NC} Language packages: ${CYAN}Yes${NC}"
    else
        INCLUDE_LANG=false
        echo -e "  ${GREEN}✓${NC} Language packages: ${CYAN}No${NC}"
    fi
    
    # Reboot behavior
    echo ""
    local reboot_options=("Never - Never automatically reboot" "If needed - Reboot only when required" "Always - Always reboot after updates")
    smart_menu "Automatic reboot after updates?" "${reboot_options[@]}"
    local reboot_idx=$?
    
    case $reboot_idx in
        0) REBOOT_MODE="never" ;;
        1) REBOOT_MODE="if-needed" ;;
        2) REBOOT_MODE="always" ;;
    esac
    echo -e "  ${GREEN}✓${NC} Reboot: ${CYAN}$REBOOT_MODE${NC}"
    
    # Native tools (Debian/RHEL only)
    if [[ "$distro" == "debian" ]] || [[ "$distro" == "rhel" && "$pkg_manager" == "dnf" ]]; then
        print_section "Installation Method"
        echo ""
        
        local native_name
        if [[ "$distro" == "debian" ]]; then
            native_name="unattended-upgrades"
        else
            native_name="dnf-automatic"
        fi
        
        local methods=("Use $native_name (native, well-tested)" "Use RSR timer (more control, cross-platform)")
        smart_menu "Which method do you prefer?" "${methods[@]}"
        local method_idx=$?
        
        if [[ $method_idx -eq 0 ]]; then
            USE_NATIVE=true
            echo -e "  ${GREEN}✓${NC} Method: ${CYAN}$native_name${NC}"
        else
            USE_NATIVE=false
            echo -e "  ${GREEN}✓${NC} Method: ${CYAN}RSR systemd timer${NC}"
        fi
    fi
    
    # Email notifications
    print_section "Notifications"
    echo ""
    if prompt_yn "Enable email notifications on failure?" "n"; then
        NOTIFY_METHOD="email"
        NOTIFY_EMAIL=$(prompt_value "Email address" "root@localhost")
        echo -e "  ${GREEN}✓${NC} Notifications: ${CYAN}$NOTIFY_EMAIL${NC}"
    else
        NOTIFY_METHOD="none"
        echo -e "  ${GREEN}✓${NC} Notifications: ${CYAN}Disabled${NC}"
    fi
    
    # User install option (macOS or non-root)
    if is_macos || ! is_root; then
        print_section "Installation Scope"
        echo ""
        
        if is_root; then
            local scopes=("System-wide - All users (requires root)" "Current user only")
            smart_menu "Installation scope?" "${scopes[@]}"
            if [[ $? -eq 1 ]]; then
                USER_INSTALL=true
            fi
        else
            log_info "Installing for current user (run with sudo for system-wide)"
            USER_INSTALL=true
        fi
    fi
    
    # Confirmation
    print_section "Summary"
    echo ""
    echo -e "  ${DIM}Schedule:${NC}      $SCHEDULE at $UPDATE_TIME"
    [[ "$SCHEDULE" == "weekly" ]] && echo -e "  ${DIM}Day:${NC}           ${day_names[$UPDATE_DAY]}"
    echo -e "  ${DIM}Security only:${NC} $SECURITY_ONLY"
    echo -e "  ${DIM}Languages:${NC}     $INCLUDE_LANG"
    echo -e "  ${DIM}Reboot:${NC}        $REBOOT_MODE"
    echo -e "  ${DIM}Notifications:${NC} ${NOTIFY_EMAIL:-none}"
    [[ -n "$USE_NATIVE" ]] && echo -e "  ${DIM}Method:${NC}        $([ "$USE_NATIVE" == "true" ] && echo "Native" || echo "RSR timer")"
    echo ""
    
    if ! prompt_yn "Proceed with installation?" "y"; then
        echo ""
        log_warn "Installation cancelled"
        exit 0
    fi
    
    echo ""
}

# Interactive main menu
interactive_menu() {
    print_header "Auto Update Manager"
    
    local installed=false
    local enabled=false
    is_installed && installed=true
    is_enabled && enabled=true
    
    # Show current status
    if [[ "$installed" == "true" ]]; then
        echo -e "  ${GREEN}●${NC} Auto-updates are ${GREEN}installed${NC}"
        if [[ "$enabled" == "true" ]]; then
            echo -e "  ${GREEN}●${NC} Status: ${GREEN}Enabled${NC}"
        else
            echo -e "  ${YELLOW}○${NC} Status: ${YELLOW}Disabled${NC}"
        fi
    else
        echo -e "  ${DIM}○${NC} Auto-updates are ${DIM}not installed${NC}"
    fi
    echo ""
    
    # Build menu options based on state
    local options=()
    local actions=()
    
    if [[ "$installed" != "true" ]]; then
        options+=("Install auto-updates")
        actions+=("install")
    else
        options+=("Reconfigure auto-updates")
        actions+=("install")
        
        if [[ "$enabled" == "true" ]]; then
            options+=("Disable auto-updates")
            actions+=("disable")
        else
            options+=("Enable auto-updates")
            actions+=("enable")
        fi
        
        options+=("Run update now")
        actions+=("run-now")
        
        options+=("View logs")
        actions+=("logs")
        
        options+=("Show configuration")
        actions+=("config")
        
        options+=("Remove auto-updates")
        actions+=("remove")
    fi
    
    options+=("Exit")
    actions+=("exit")
    
    smart_menu "What would you like to do?" "${options[@]}"
    local choice=$?
    
    COMMAND="${actions[$choice]}"
    
    if [[ "$COMMAND" == "exit" ]]; then
        echo ""
        log_info "Goodbye!"
        exit 0
    fi
    
    if [[ "$COMMAND" == "install" ]]; then
        INTERACTIVE_MODE=true
    fi
}

# Interactive remove confirmation
interactive_remove() {
    print_header "Remove Auto-Updates"
    
    if ! is_installed; then
        log_warn "Auto-updates are not installed"
        exit 0
    fi
    
    echo -e "  ${YELLOW}⚠${NC}  This will remove all auto-update configuration"
    echo ""
    
    if ! prompt_yn "Are you sure you want to remove auto-updates?" "n"; then
        echo ""
        log_info "Removal cancelled"
        exit 0
    fi
    echo ""
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_args() {
    COMMAND=""
    VERBOSE=false
    AUTO_YES=false
    DRY_RUN=false
    FORCE=false
    
    # Load defaults
    load_config
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            install|remove|status|enable|disable|run-now|logs|config)
                COMMAND="$1"
                shift
                ;;
            -i|--interactive)
                INTERACTIVE_MODE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -y|--yes)
                AUTO_YES=true
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --schedule)
                SCHEDULE="$2"
                if [[ ! "$SCHEDULE" =~ ^(daily|weekly|monthly)$ ]]; then
                    log_error "Invalid schedule: $SCHEDULE (use daily, weekly, or monthly)"
                    exit $EXIT_INVALID_ARGS
                fi
                shift 2
                ;;
            --time)
                UPDATE_TIME="$2"
                if [[ ! "$UPDATE_TIME" =~ ^[0-2][0-9]:[0-5][0-9]$ ]]; then
                    log_error "Invalid time format: $UPDATE_TIME (use HH:MM)"
                    exit $EXIT_INVALID_ARGS
                fi
                shift 2
                ;;
            --day)
                UPDATE_DAY="$2"
                case "$UPDATE_DAY" in
                    0|1|2|3|4|5|6|sun|mon|tue|wed|thu|fri|sat) ;;
                    *)
                        log_error "Invalid day: $UPDATE_DAY (use 0-6 or sun-sat)"
                        exit $EXIT_INVALID_ARGS
                        ;;
                esac
                shift 2
                ;;
            --security-only)
                SECURITY_ONLY=true
                shift
                ;;
            --reboot)
                REBOOT_MODE="$2"
                if [[ ! "$REBOOT_MODE" =~ ^(never|if-needed|always)$ ]]; then
                    log_error "Invalid reboot mode: $REBOOT_MODE"
                    exit $EXIT_INVALID_ARGS
                fi
                shift 2
                ;;
            --include-lang)
                INCLUDE_LANG=true
                shift
                ;;
            --notify)
                NOTIFY_METHOD="$2"
                shift 2
                ;;
            --email)
                NOTIFY_EMAIL="$2"
                NOTIFY_METHOD="email"
                shift 2
                ;;
            --use-native)
                USE_NATIVE=true
                shift
                ;;
            --user)
                USER_INSTALL=true
                shift
                ;;
            --tail|-n)
                shift 2
                ;;
            --follow|-f)
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit $EXIT_INVALID_ARGS
                ;;
        esac
    done
    
    # Default to interactive mode if no command given and terminal is interactive
    if [[ -z "$COMMAND" ]]; then
        if [[ -t 0 ]] && [[ -t 1 ]]; then
            INTERACTIVE_MODE=true
        else
            usage
            exit 0
        fi
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"
    
    # Interactive mode - show menu if no command
    if [[ "$INTERACTIVE_MODE" == "true" ]] && [[ -z "$COMMAND" ]]; then
        interactive_menu
    fi
    
    # Interactive install wizard
    if [[ "$INTERACTIVE_MODE" == "true" ]] && [[ "$COMMAND" == "install" ]]; then
        interactive_install
    fi
    
    # Interactive remove confirmation
    if [[ "$INTERACTIVE_MODE" == "true" ]] && [[ "$COMMAND" == "remove" ]] && [[ "$AUTO_YES" != "true" ]]; then
        interactive_remove
    fi
    
    case "$COMMAND" in
        install)
            if [[ "$USER_INSTALL" != "true" ]] && ! is_macos; then
                require_root "$@"
            fi
            do_install
            ;;
        remove)
            if ! is_macos; then
                require_root "$@"
            fi
            do_remove
            ;;
        status)
            load_config
            show_config
            show_status
            ;;
        enable)
            if ! is_macos; then
                require_root "$@"
            fi
            do_enable
            ;;
        disable)
            if ! is_macos; then
                require_root "$@"
            fi
            do_disable
            ;;
        run-now)
            require_root "$@"
            do_run_now
            ;;
        logs)
            do_logs "$@"
            ;;
        config)
            show_config
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            exit $EXIT_INVALID_ARGS
            ;;
    esac
}

main "$@"
