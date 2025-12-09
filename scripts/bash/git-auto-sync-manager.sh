#!/bin/bash
# git-auto-sync-manager.sh - Interactive installer and manager for git-auto-sync
# Part of Remote Script Runner collection
# Usage: curl -fsSL https://example.com/git-auto-sync-manager.sh | bash

set -euo pipefail

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../../lib"

# Source libraries if available
if [[ -f "$LIB_DIR/common.sh" ]]; then
    source "$LIB_DIR/common.sh"
    setup_colors
fi

if [[ -f "$LIB_DIR/interactive.sh" ]]; then
    source "$LIB_DIR/interactive.sh"
fi

# =============================================================================
# Configuration
# =============================================================================

GIT_SYNC_SCRIPT="${SCRIPT_DIR}/git-auto-sync.sh"

# Detect OS
if [[ "$(uname)" == "Darwin" ]]; then
    OS="macos"
else
    OS="linux"
fi

# Detect install mode (system vs user)
if [[ $EUID -eq 0 ]] || [[ "${GIT_SYNC_SYSTEM_INSTALL:-}" == "true" ]]; then
    # System-wide installation
    INSTALL_MODE="system"
    INSTALL_DIR="/usr/local/bin"
    if [[ "$OS" == "macos" ]]; then
        CONFIG_DIR="/etc/git-auto-sync"
        SYSTEMD_DIR=""
        LAUNCHD_DIR="/Library/LaunchDaemons"
    else
        CONFIG_DIR="/etc/git-auto-sync"
        SYSTEMD_DIR="/etc/systemd/system"
        LAUNCHD_DIR=""
    fi
else
    # User-level installation
    INSTALL_MODE="user"
    INSTALL_DIR="$HOME/.local/bin"
    CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/git-auto-sync"
    if [[ "$OS" == "macos" ]]; then
        LAUNCHD_DIR="$HOME/Library/LaunchAgents"
        SYSTEMD_DIR=""
    else
        SYSTEMD_DIR="$HOME/.config/systemd/user"
        LAUNCHD_DIR=""
    fi
fi

# Ensure directories exist
mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" 2>/dev/null || true
if [[ -n "$SYSTEMD_DIR" ]]; then
    mkdir -p "$SYSTEMD_DIR" 2>/dev/null || true
fi
if [[ -n "$LAUNCHD_DIR" ]]; then
    mkdir -p "$LAUNCHD_DIR" 2>/dev/null || true
fi

# =============================================================================
# Color Setup (fallback if common.sh not available)
# =============================================================================

if [[ ! -f "$LIB_DIR/common.sh" ]]; then
    setup_colors() {
        if [ -t 1 ]; then
            BLUE='\033[0;34m'
            GREEN='\033[0;32m'
            YELLOW='\033[1;33m'
            RED='\033[0;31m'
            CYAN='\033[0;36m'
            BOLD='\033[1m'
            DIM='\033[2m'
            NC='\033[0m'
        else
            BLUE='' GREEN='' YELLOW='' RED='' CYAN='' BOLD='' DIM='' NC=''
        fi
    }
    setup_colors
    
    log_info() { printf "${BLUE}▸${NC} %s\n" "$1"; }
    log_ok() { printf "${GREEN}✓${NC} %s\n" "$1"; }
    log_warn() { printf "${YELLOW}⚠${NC} %s\n" "$1" >&2; }
    log_error() { printf "${RED}✗${NC} %s\n" "$1" >&2; }
fi

# =============================================================================
# UI Utilities
# =============================================================================

print_header() {
    local title="$1"
    echo ""
    printf "${BOLD}${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${BOLD}${BLUE}║${NC}  %-60s${BOLD}${BLUE}║${NC}\n" "$title"
    printf "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    echo ""
}

print_separator() {
    printf "${DIM}────────────────────────────────────────────────────────────────${NC}\n"
}

print_menu_option() {
    local num="$1"
    local text="$2"
    local status="${3:-}"
    
    if [[ -n "$status" ]]; then
        printf "  ${BOLD}${CYAN}%s)${NC} %-40s ${GREEN}%s${NC}\n" "$num" "$text" "$status"
    else
        printf "  ${BOLD}${CYAN}%s)${NC} %s\n" "$num" "$text"
    fi
}

prompt_continue() {
    echo ""
    read -p "Press Enter to continue..." -r
    clear
}

prompt_input() {
    local prompt="$1"
    local default="${2:-}"
    local result
    
    if [[ -n "$default" ]]; then
        read -p "${CYAN}${prompt}${NC} [${default}]: " -r result
        echo "${result:-$default}"
    else
        read -p "${CYAN}${prompt}${NC}: " -r result
        echo "$result"
    fi
}

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local response
    
    if [[ "$default" == "y" ]]; then
        read -p "${CYAN}${prompt}${NC} [Y/n]: " -r response
        response="${response:-y}"
    else
        read -p "${CYAN}${prompt}${NC} [y/N]: " -r response
        response="${response:-n}"
    fi
    
    [[ "$response" =~ ^[Yy] ]]
}

# =============================================================================
# System Checks
# =============================================================================

check_root() {
    [[ $EUID -eq 0 ]]
}

check_git_installed() {
    command -v git >/dev/null 2>&1
}

check_jq_installed() {
    command -v jq >/dev/null 2>&1
}

check_git_lfs_installed() {
    command -v git-lfs >/dev/null 2>&1
}

check_script_installed() {
    [[ -f "$INSTALL_DIR/git-auto-sync.sh" ]]
}

check_systemd_service() {
    [[ -f "$SYSTEMD_DIR/git-auto-sync.service" ]] && systemctl is-enabled git-auto-sync.service >/dev/null 2>&1
}

check_launchd_service() {
    [[ -f "$LAUNCHD_DIR/com.user.git-auto-sync.plist" ]]
}

get_installation_status() {
    if check_script_installed; then
        echo "✓ Installed"
    else
        echo "✗ Not installed"
    fi
}

get_service_status() {
    if [[ "$OS" == "linux" ]]; then
        if check_systemd_service; then
            if systemctl is-active git-auto-sync.service >/dev/null 2>&1; then
                echo "✓ Running"
            else
                echo "⚠ Installed but not running"
            fi
        else
            echo "✗ Not configured"
        fi
    else
        if check_launchd_service; then
            if launchctl list | grep -q "com.user.git-auto-sync"; then
                echo "✓ Running"
            else
                echo "⚠ Installed but not running"
            fi
        else
            echo "✗ Not configured"
        fi
    fi
}

# =============================================================================
# Installation Functions
# =============================================================================

install_dependencies() {
    print_header "Installing Dependencies"
    
    if ! check_git_installed; then
        log_error "Git is not installed!"
        if [[ "$OS" == "linux" ]]; then
            if [[ "$INSTALL_MODE" == "system" ]]; then
                log_info "Install with: sudo apt install git  # or: sudo yum install git"
            else
                log_info "Install with: apt install git  # or: yum install git"
                log_info "Or download from: https://git-scm.com/downloads"
            fi
        else
            log_info "Install with: brew install git"
        fi
        return 1
    else
        log_ok "Git is installed"
    fi
    
    if ! check_jq_installed; then
        log_warn "jq is not installed (required for JSON config files)"
        if prompt_yes_no "Install jq now?" "y"; then
            if [[ "$INSTALL_MODE" == "system" ]]; then
                # System mode - use sudo
                if [[ "$OS" == "linux" ]]; then
                    if command -v apt-get >/dev/null 2>&1; then
                        sudo apt-get install -y jq
                    elif command -v yum >/dev/null 2>&1; then
                        sudo yum install -y jq
                    fi
                else
                    brew install jq
                fi
            else
                # User mode - suggest manual installation
                log_warn "Package installation requires root access"
                if [[ "$OS" == "linux" ]]; then
                    log_info "Please install manually: sudo apt install jq  # or: sudo yum install jq"
                else
                    log_info "Install with: brew install jq"
                fi
            fi
        fi
    else
        log_ok "jq is installed"
    fi
    
    if ! check_git_lfs_installed; then
        log_warn "Git LFS is not installed (optional, for large files)"
        if prompt_yes_no "Install Git LFS?" "n"; then
            if [[ "$INSTALL_MODE" == "system" ]]; then
                # System mode - use sudo
                if [[ "$OS" == "linux" ]]; then
                    if command -v apt-get >/dev/null 2>&1; then
                        sudo apt-get install -y git-lfs
                    elif command -v yum >/dev/null 2>&1; then
                        sudo yum install -y git-lfs
                    fi
                else
                    brew install git-lfs
                fi
                git lfs install
            else
                # User mode - suggest manual installation
                log_warn "Package installation requires root access"
                if [[ "$OS" == "linux" ]]; then
                    log_info "Please install manually: sudo apt install git-lfs  # or: sudo yum install git-lfs"
                else
                    log_info "Install with: brew install git-lfs"
                fi
            fi
        fi
    else
        log_ok "Git LFS is installed"
    fi
    
    prompt_continue
}

install_script() {
    print_header "Installing Git Auto-Sync Script"
    
    log_info "Install mode: $INSTALL_MODE"
    log_info "Target directory: $INSTALL_DIR"
    
    if [[ ! -f "$GIT_SYNC_SCRIPT" ]]; then
        log_error "Script not found: $GIT_SYNC_SCRIPT"
        log_info "Downloading from remote repository..."
        
        local download_url="https://codefuturist.github.io/remote-script-runner/scripts/bash/git-auto-sync.sh"
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL "$download_url" -o "/tmp/git-auto-sync.sh"
            GIT_SYNC_SCRIPT="/tmp/git-auto-sync.sh"
        else
            log_error "curl is required to download the script"
            return 1
        fi
    fi
    
    # Ensure install directory exists and is in PATH
    if [[ ! -d "$INSTALL_DIR" ]]; then
        mkdir -p "$INSTALL_DIR" 2>/dev/null || {
            log_error "Cannot create $INSTALL_DIR"
            return 1
        }
    fi
    
    log_info "Installing to $INSTALL_DIR/git-auto-sync.sh"
    
    # Copy script based on install mode
    if [[ "$INSTALL_MODE" == "system" ]]; then
        if check_root; then
            cp "$GIT_SYNC_SCRIPT" "$INSTALL_DIR/git-auto-sync.sh"
            chmod +x "$INSTALL_DIR/git-auto-sync.sh"
        else
            sudo cp "$GIT_SYNC_SCRIPT" "$INSTALL_DIR/git-auto-sync.sh"
            sudo chmod +x "$INSTALL_DIR/git-auto-sync.sh"
        fi
    else
        # User installation - no sudo needed
        cp "$GIT_SYNC_SCRIPT" "$INSTALL_DIR/git-auto-sync.sh"
        chmod +x "$INSTALL_DIR/git-auto-sync.sh"
        
        # Check if install dir is in PATH
        if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
            log_warn "$INSTALL_DIR is not in your PATH"
            log_info "Add to your shell profile (~/.bashrc or ~/.zshrc):"
            echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
        fi
    fi
    
    log_ok "Script installed successfully"
    log_info "You can now run: git-auto-sync.sh --help"
    
    prompt_continue
}

create_configuration() {
    print_header "Creating Configuration"
    
    log_info "Configuration directory: $CONFIG_DIR"
    
    # Create config directory
    if [[ ! -d "$CONFIG_DIR" ]]; then
        if [[ "$INSTALL_MODE" == "user" ]]; then
            mkdir -p "$CONFIG_DIR" || {
                log_error "Cannot create config directory: $CONFIG_DIR"
                return 1
            }
        else
            if check_root; then
                mkdir -p "$CONFIG_DIR"
            else
                sudo mkdir -p "$CONFIG_DIR"
            fi
        fi
        log_ok "Created configuration directory"
    fi
    
    local config_file="$CONFIG_DIR/repos.json"
    
    if [[ -f "$config_file" ]]; then
        log_warn "Configuration file already exists: $config_file"
        if ! prompt_yes_no "Overwrite existing configuration?" "n"; then
            return 0
        fi
    fi
    
    # Interactive configuration builder
    echo ""
    log_info "Let's configure your repositories..."
    echo ""
    
    local repos='[]'
    local add_more=true
    
    while $add_more; do
        echo ""
        print_separator
        log_info "Repository Configuration"
        print_separator
        
        local name=$(prompt_input "Repository name (e.g., 'my-project')")
        local path=$(prompt_input "Repository path (e.g., '/var/www/mysite')")
        local branch=$(prompt_input "Branch to sync" "main")
        local remote=$(prompt_input "Remote name" "origin")
        
        echo ""
        log_info "Sync mode:"
        echo "  1) safe   - Fast-forward merge, stash changes (recommended)"
        echo "  2) force  - Hard reset, discard local changes"
        echo "  3) pull   - Standard git pull"
        echo ""
        local mode_choice=$(prompt_input "Choose sync mode [1-3]" "1")
        
        local mode="safe"
        case "$mode_choice" in
            2) mode="force" ;;
            3) mode="pull" ;;
        esac
        
        local use_lfs="false"
        if prompt_yes_no "Enable Git LFS?" "n"; then
            use_lfs="true"
        fi
        
        local post_hook=""
        if prompt_yes_no "Configure post-sync hook?" "n"; then
            post_hook=$(prompt_input "Path to hook script")
        fi
        
        # Build JSON object
        local repo_json=$(cat <<EOF
{
  "name": "$name",
  "path": "$path",
  "branch": "$branch",
  "remote": "$remote",
  "mode": "$mode",
  "use_lfs": $use_lfs$([ -n "$post_hook" ] && echo ",
  \"post_hook\": \"$post_hook\"" || echo "")
}
EOF
)
        
        # Add to array
        if command -v jq >/dev/null 2>&1; then
            repos=$(echo "$repos" | jq ". += [$repo_json]")
        else
            # Fallback without jq (basic)
            if [[ "$repos" == "[]" ]]; then
                repos="[$repo_json]"
            else
                repos="${repos%]}, $repo_json]"
            fi
        fi
        
        echo ""
        log_ok "Repository added: $name"
        echo ""
        
        if ! prompt_yes_no "Add another repository?" "n"; then
            add_more=false
        fi
    done
    
    # Save configuration
    if [[ "$INSTALL_MODE" == "user" ]]; then
        # User mode - direct write
        echo "$repos" | jq '.' > "$config_file" 2>/dev/null || echo "$repos" > "$config_file"
    else
        # System mode - may need sudo
        if check_root; then
            echo "$repos" | jq '.' > "$config_file" 2>/dev/null || echo "$repos" > "$config_file"
        else
            echo "$repos" | jq '.' | sudo tee "$config_file" > /dev/null 2>/dev/null || echo "$repos" | sudo tee "$config_file" > /dev/null
        fi
    fi
    
    log_ok "Configuration saved: $config_file"
    
    echo ""
    log_info "Configuration preview:"
    echo "$repos" | jq '.' 2>/dev/null || cat "$config_file"
    
    prompt_continue
}

setup_systemd_service() {
    print_header "Setting Up SystemD Service"
    
    if [[ "$OS" != "linux" ]]; then
        log_error "SystemD is only available on Linux"
        prompt_continue
        return 1
    fi
    
    if [[ -z "$SYSTEMD_DIR" ]]; then
        log_error "SystemD directory not configured"
        prompt_continue
        return 1
    fi
    
    local service_file="$SYSTEMD_DIR/git-auto-sync.service"
    local config_file="$CONFIG_DIR/repos.json"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        log_info "Please create a configuration first (option 3)"
        prompt_continue
        return 1
    fi
    
    local interval=$(prompt_input "Sync interval in seconds" "300")
    local user=$(prompt_input "Run as user" "$(whoami)")
    
    log_info "Creating SystemD service..."
    
    local service_content="[Unit]
Description=Git Auto-Sync Service
Documentation=https://github.com/codefuturist/remote-script-runner
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$user
Group=$user
WorkingDirectory=/home/$user

ExecStart=$INSTALL_DIR/git-auto-sync.sh --daemon --config $config_file --interval $interval

Restart=always
RestartSec=10

Environment=\"LOG_LEVEL=INFO\"
Environment=\"PATH=/usr/local/bin:/usr/bin:/bin\"

StandardOutput=journal
StandardError=journal
SyslogIdentifier=git-auto-sync

[Install]
WantedBy=multi-user.target"
    
    # Write service file based on mode
    if [[ "$INSTALL_MODE" == "system" ]]; then
        echo "$service_content" | sudo tee "$service_file" > /dev/null
    else
        echo "$service_content" > "$service_file"
    fi
    
    log_ok "Service file created: $service_file"
    
    if prompt_yes_no "Enable and start service now?" "y"; then
        if [[ "$INSTALL_MODE" == "system" ]]; then
            sudo systemctl daemon-reload
            sudo systemctl enable git-auto-sync.service
            sudo systemctl start git-auto-sync.service
            log_info "Check status with: sudo systemctl status git-auto-sync"
            log_info "View logs with: sudo journalctl -u git-auto-sync -f"
        else
            systemctl --user daemon-reload
            systemctl --user enable git-auto-sync.service
            systemctl --user start git-auto-sync.service
            log_info "Check status with: systemctl --user status git-auto-sync"
            log_info "View logs with: journalctl --user -u git-auto-sync -f"
        fi
        
        log_ok "Service enabled and started"
    fi
    
    prompt_continue
}

setup_launchd_service() {
    print_header "Setting Up LaunchAgent (macOS)"
    
    if [[ "$OS" != "macos" ]]; then
        log_error "LaunchAgent is only available on macOS"
        prompt_continue
        return 1
    fi
    
    local plist_file="$LAUNCHD_DIR/com.user.git-auto-sync.plist"
    local config_file="$CONFIG_DIR/repos.json"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        log_info "Please create a configuration first (option 3)"
        prompt_continue
        return 1
    fi
    
    mkdir -p "$LAUNCHD_DIR"
    
    local interval=$(prompt_input "Sync interval in seconds" "300")
    
    log_info "Creating LaunchAgent..."
    
    cat > "$plist_file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.git-auto-sync</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/git-auto-sync.sh</string>
        <string>--daemon</string>
        <string>--config</string>
        <string>$config_file</string>
        <string>--interval</string>
        <string>$interval</string>
    </array>
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
        <key>Crashed</key>
        <true/>
    </dict>
    
    <key>StandardOutPath</key>
    <string>/tmp/git-auto-sync.log</string>
    
    <key>StandardErrorPath</key>
    <string>/tmp/git-auto-sync.err</string>
    
    <key>EnvironmentVariables</key>
    <dict>
        <key>LOG_LEVEL</key>
        <string>INFO</string>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
EOF
    
    log_ok "LaunchAgent created: $plist_file"
    
    if prompt_yes_no "Load and start agent now?" "y"; then
        launchctl load "$plist_file"
        launchctl start com.user.git-auto-sync
        
        log_ok "Agent loaded and started"
        
        echo ""
        log_info "Check status with: launchctl list | grep git-auto-sync"
        log_info "View logs with: tail -f /tmp/git-auto-sync.log"
    fi
    
    prompt_continue
}

# =============================================================================
# Management Functions
# =============================================================================

view_configuration() {
    print_header "Current Configuration"
    
    local config_file="$CONFIG_DIR/repos.json"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "No configuration file found: $config_file"
    else
        log_info "Configuration file: $config_file"
        echo ""
        if command -v jq >/dev/null 2>&1; then
            cat "$config_file" | jq '.'
        else
            cat "$config_file"
        fi
    fi
    
    prompt_continue
}

test_sync() {
    print_header "Test Sync (Dry Run)"
    
    if ! check_script_installed; then
        log_error "Script not installed. Please install first (option 1)"
        prompt_continue
        return 1
    fi
    
    local config_file="$CONFIG_DIR/repos.json"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "No configuration file found: $config_file"
        prompt_continue
        return 1
    fi
    
    log_info "Running sync with configuration: $config_file"
    echo ""
    
    if prompt_yes_no "Run with verbose output?" "y"; then
        "$INSTALL_DIR/git-auto-sync.sh" --config "$config_file" -v
    else
        "$INSTALL_DIR/git-auto-sync.sh" --config "$config_file"
    fi
    
    prompt_continue
}

check_service_status() {
    print_header "Service Status"
    
    if [[ "$OS" == "linux" ]]; then
        if check_systemd_service; then
            log_ok "SystemD service is installed"
            echo ""
            if [[ "$INSTALL_MODE" == "system" ]]; then
                sudo systemctl status git-auto-sync.service --no-pager
                echo ""
                log_info "Recent logs:"
                sudo journalctl -u git-auto-sync -n 20 --no-pager
            else
                systemctl --user status git-auto-sync.service --no-pager
                echo ""
                log_info "Recent logs:"
                journalctl --user -u git-auto-sync -n 20 --no-pager
            fi
        else
            log_error "SystemD service is not installed"
        fi
    else
        if check_launchd_service; then
            log_ok "LaunchAgent is installed"
            echo ""
            launchctl list | grep git-auto-sync || log_warn "Agent not running"
            echo ""
            log_info "Recent logs:"
            if [[ -f "$LOG_DIR/sync.log" ]]; then
                tail -20 "$LOG_DIR/sync.log"
            else
                tail -20 /tmp/git-auto-sync.log 2>/dev/null || log_warn "No logs found"
            fi
        else
            log_error "LaunchAgent is not installed"
        fi
    fi
    
    prompt_continue
}

uninstall_everything() {
    print_header "Uninstall Git Auto-Sync"
    
    log_warn "This will remove:"
    echo "  • Script from $INSTALL_DIR"
    echo "  • Configuration from $CONFIG_DIR"
    echo "  • Service/Agent configuration"
    echo ""
    
    if ! prompt_yes_no "Are you sure you want to uninstall?" "n"; then
        return 0
    fi
    
    # Stop service
    if [[ "$OS" == "linux" ]]; then
        if check_systemd_service; then
            log_info "Stopping SystemD service..."
            if [[ "$INSTALL_MODE" == "system" ]]; then
                sudo systemctl stop git-auto-sync.service 2>/dev/null || true
                sudo systemctl disable git-auto-sync.service 2>/dev/null || true
                sudo rm -f "$SYSTEMD_DIR/git-auto-sync.service"
                sudo systemctl daemon-reload
            else
                systemctl --user stop git-auto-sync.service 2>/dev/null || true
                systemctl --user disable git-auto-sync.service 2>/dev/null || true
                rm -f "$SYSTEMD_DIR/git-auto-sync.service"
                systemctl --user daemon-reload
            fi
        fi
    else
        if check_launchd_service; then
            log_info "Stopping LaunchAgent..."
            launchctl unload "$LAUNCHD_DIR/com.user.git-auto-sync.plist" 2>/dev/null || true
            rm -f "$LAUNCHD_DIR/com.user.git-auto-sync.plist"
        fi
    fi
    
    # Remove script
    if check_script_installed; then
        log_info "Removing script..."
        if [[ "$INSTALL_MODE" == "system" ]]; then
            if check_root; then
                rm -f "$INSTALL_DIR/git-auto-sync.sh"
            else
                sudo rm -f "$INSTALL_DIR/git-auto-sync.sh"
            fi
        else
            # User mode - no sudo
            rm -f "$INSTALL_DIR/git-auto-sync.sh" 2>/dev/null || {
                log_warn "Cannot remove $INSTALL_DIR/git-auto-sync.sh (permission denied)"
            }
        fi
    fi
    
    # Remove configuration
    if [[ -d "$CONFIG_DIR" ]]; then
        if prompt_yes_no "Remove configuration directory?" "n"; then
            log_info "Removing configuration..."
            if [[ "$INSTALL_MODE" == "system" ]]; then
                if check_root; then
                    rm -rf "$CONFIG_DIR"
                else
                    sudo rm -rf "$CONFIG_DIR"
                fi
            else
                # User mode - no sudo
                rm -rf "$CONFIG_DIR" 2>/dev/null || {
                    log_warn "Cannot remove $CONFIG_DIR (permission denied)"
                }
            fi
        fi
    fi
    
    log_ok "Uninstall complete"
    prompt_continue
}

# =============================================================================
# Main Menu
# =============================================================================

show_main_menu() {
    while true; do
        clear
        print_header "Git Auto-Sync - Interactive Manager v$VERSION"
        
        # System status
        log_info "System Information:"
        printf "  ${DIM}Mode:${NC} %s\n" "$INSTALL_MODE"
        printf "  ${DIM}OS:${NC} %s\n" "$OS"
        printf "  ${DIM}Install Dir:${NC} %s\n" "$INSTALL_DIR"
        printf "  ${DIM}Config Dir:${NC} %s\n" "$CONFIG_DIR"
        echo ""
        
        log_info "Current Status:"
        printf "  ${DIM}Script:${NC} %s\n" "$(get_installation_status)"
        printf "  ${DIM}Service:${NC} %s\n" "$(get_service_status)"
        echo ""
        
        print_separator
        log_info "Installation & Setup:"
        print_menu_option "1" "Install dependencies"
        print_menu_option "2" "Install git-auto-sync script"
        print_menu_option "3" "Create/edit configuration"
        
        if [[ "$OS" == "linux" ]]; then
            print_menu_option "4" "Setup SystemD service"
        else
            print_menu_option "4" "Setup LaunchAgent (macOS)"
        fi
        
        echo ""
        print_separator
        log_info "Management:"
        print_menu_option "5" "View configuration"
        print_menu_option "6" "Test sync (dry run)"
        print_menu_option "7" "Check service status"
        print_menu_option "8" "Uninstall everything"
        
        echo ""
        print_separator
        print_menu_option "h" "Show help"
        print_menu_option "q" "Quit"
        print_separator
        echo ""
        
        read -p "$(printf "${BOLD}${CYAN}Select an option:${NC} ")" -r choice
        
        case "$choice" in
            1) install_dependencies ;;
            2) install_script ;;
            3) create_configuration ;;
            4) 
                if [[ "$OS" == "linux" ]]; then
                    setup_systemd_service
                else
                    setup_launchd_service
                fi
                ;;
            5) view_configuration ;;
            6) test_sync ;;
            7) check_service_status ;;
            8) uninstall_everything ;;
            h|H)
                clear
                print_header "Git Auto-Sync Help"
                cat <<'EOF'
This interactive manager helps you install and configure git-auto-sync.

Quick Start:
1. Install dependencies (option 1)
2. Install the script (option 2)
3. Create configuration (option 3)
4. Setup service (option 4)
5. Test sync (option 6)

Configuration File:
The configuration is stored as JSON in:
  Linux: /etc/git-auto-sync/repos.json
  macOS: ~/.config/git-auto-sync/repos.json

Manual Usage:
Once installed, you can run manually:
  git-auto-sync.sh -r /path/to/repo
  git-auto-sync.sh --config /path/to/config.json
  git-auto-sync.sh --daemon --config /path/to/config.json

Documentation:
  https://codefuturist.github.io/remote-script-runner/

EOF
                prompt_continue
                ;;
            q|Q)
                echo ""
                log_info "Thank you for using Git Auto-Sync Manager!"
                exit 0
                ;;
            *)
                log_error "Invalid option: $choice"
                sleep 1
                ;;
        esac
    done
}

# =============================================================================
# Entry Point
# =============================================================================

main() {
    # Check if running in interactive mode
    if [[ ! -t 0 || ! -t 1 ]]; then
        log_error "This script requires an interactive terminal"
        log_info "Run directly: bash $0"
        exit 1
    fi
    
    # Welcome message
    clear
    print_header "Welcome to Git Auto-Sync Interactive Manager!"
    
    echo "This tool will help you install and configure git-auto-sync"
    echo "for automatic Git repository synchronization."
    echo ""
    
    if ! check_git_installed; then
        log_warn "Git is not installed. You'll need to install it first."
    fi
    
    prompt_continue
    
    # Show main menu
    show_main_menu
}

main "$@"
