#!/bin/sh
# Remote Script Runner - Emergency Recovery Script
# 
# This script helps recover from a broken rsr installation.
# 
# Usage:
#   curl -fsSL https://codefuturist.github.io/remote-script-runner/recover.sh | sh
#   OR
#   sh recover.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

REPO_BASE_URL="https://codefuturist.github.io/remote-script-runner"

printf "\n${BOLD}╔════════════════════════════════════════════╗${NC}\n"
printf "${BOLD}║  Remote Script Runner - Recovery Tool     ║${NC}\n"
printf "${BOLD}╚════════════════════════════════════════════╝${NC}\n\n"

# Function to print messages
log_info() { printf "${BLUE}▸${NC} %s\n" "$1"; }
log_ok() { printf "${GREEN}✓${NC} %s\n" "$1"; }
log_warn() { printf "${YELLOW}⚠${NC} %s\n" "$1"; }
log_error() { printf "${RED}✗${NC} %s\n" "$1"; }

# Detect installation path
detect_install_path() {
    local path
    
    # Check common locations
    if [ -f "$HOME/.local/bin/rsr" ]; then
        echo "$HOME/.local/bin/rsr"
    elif [ -f "/usr/local/bin/rsr" ]; then
        echo "/usr/local/bin/rsr"
    elif command -v rsr >/dev/null 2>&1; then
        command -v rsr
    else
        echo ""
    fi
}

# Main recovery logic
main() {
    log_info "Detecting rsr installation..."
    
    local install_path
    install_path=$(detect_install_path)
    
    if [ -z "$install_path" ]; then
        log_warn "Could not find rsr installation"
        printf "\n${BOLD}Options:${NC}\n"
        printf "1. Fresh install: curl -fsSL $REPO_BASE_URL/install.sh | bash\n"
        printf "2. Specify path manually\n\n"
        printf "Enter installation path (or press Enter to install fresh): "
        read -r custom_path
        
        if [ -z "$custom_path" ]; then
            log_info "Performing fresh installation..."
            if command -v curl >/dev/null 2>&1; then
                curl -fsSL "$REPO_BASE_URL/install.sh" | bash
            elif command -v wget >/dev/null 2>&1; then
                wget -qO- "$REPO_BASE_URL/install.sh" | bash
            else
                log_error "Neither curl nor wget available"
                exit 1
            fi
            exit 0
        else
            install_path="$custom_path"
        fi
    fi
    
    log_ok "Found installation at: $install_path"
    
    # Check if backup exists
    if [ -f "${install_path}.backup" ]; then
        log_ok "Backup found: ${install_path}.backup"
        printf "\n${BOLD}Recovery Options:${NC}\n"
        printf "1. Restore from backup\n"
        printf "2. Download fresh copy\n"
        printf "3. Test current installation\n"
        printf "4. Exit\n\n"
        printf "Choose option (1-4): "
        read -r choice
        
        case "$choice" in
            1)
                log_info "Restoring from backup..."
                if cp "${install_path}.backup" "$install_path"; then
                    chmod +x "$install_path"
                    log_ok "Restored successfully!"
                    log_info "Testing installation..."
                    if "$install_path" --version; then
                        log_ok "Installation working!"
                    else
                        log_warn "Installation may still have issues"
                    fi
                else
                    log_error "Failed to restore from backup"
                    exit 1
                fi
                ;;
            2)
                log_info "Downloading fresh copy..."
                local temp_file="${install_path}.recovery.$$"
                if command -v curl >/dev/null 2>&1; then
                    curl -fsSL "$REPO_BASE_URL/rsr" -o "$temp_file"
                elif command -v wget >/dev/null 2>&1; then
                    wget -qO "$temp_file" "$REPO_BASE_URL/rsr"
                else
                    log_error "Neither curl nor wget available"
                    exit 1
                fi
                
                if [ -s "$temp_file" ]; then
                    mv "$install_path" "${install_path}.broken"
                    mv "$temp_file" "$install_path"
                    chmod +x "$install_path"
                    log_ok "Fresh installation complete!"
                    log_info "Broken version saved as: ${install_path}.broken"
                else
                    log_error "Download failed"
                    rm -f "$temp_file"
                    exit 1
                fi
                ;;
            3)
                log_info "Testing current installation..."
                if "$install_path" --version; then
                    log_ok "Installation is working!"
                else
                    log_error "Installation is broken"
                    log_info "Run this script again and choose option 1 or 2"
                fi
                ;;
            4)
                log_info "Exiting without changes"
                exit 0
                ;;
            *)
                log_error "Invalid choice"
                exit 1
                ;;
        esac
    else
        log_warn "No backup found"
        printf "\n${BOLD}Recovery Options:${NC}\n"
        printf "1. Download fresh copy (replaces current)\n"
        printf "2. Test current installation\n"
        printf "3. Exit\n\n"
        printf "Choose option (1-3): "
        read -r choice
        
        case "$choice" in
            1)
                log_info "Downloading fresh copy..."
                local temp_file="${install_path}.recovery.$$"
                if command -v curl >/dev/null 2>&1; then
                    curl -fsSL "$REPO_BASE_URL/rsr" -o "$temp_file"
                elif command -v wget >/dev/null 2>&1; then
                    wget -qO "$temp_file" "$REPO_BASE_URL/rsr"
                else
                    log_error "Neither curl nor wget available"
                    exit 1
                fi
                
                if [ -s "$temp_file" ]; then
                    cp "$install_path" "${install_path}.broken" 2>/dev/null || true
                    mv "$temp_file" "$install_path"
                    chmod +x "$install_path"
                    log_ok "Fresh installation complete!"
                else
                    log_error "Download failed"
                    rm -f "$temp_file"
                    exit 1
                fi
                ;;
            2)
                log_info "Testing current installation..."
                if "$install_path" --version; then
                    log_ok "Installation is working!"
                else
                    log_error "Installation is broken"
                    log_info "Run this script again and choose option 1"
                fi
                ;;
            3)
                log_info "Exiting without changes"
                exit 0
                ;;
            *)
                log_error "Invalid choice"
                exit 1
                ;;
        esac
    fi
    
    printf "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    log_ok "Recovery complete!"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n\n"
}

main
