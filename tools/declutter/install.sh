#!/usr/bin/env bash
#
# Declutter Installation Script v2
# Installs dependencies and sets up the modular declutter tool
#

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly VERSION="2.0.0"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

log_info() { echo -e "${BLUE}ℹ${RESET}  $*"; }
log_success() { echo -e "${GREEN}✓${RESET}  $*"; }
log_warn() { echo -e "${YELLOW}⚠${RESET}  $*"; }
log_error() { echo -e "${RED}✗${RESET}  $*" >&2; }

# Detect OS
detect_os() {
    OS="$(uname -s)"
    case "$OS" in
        Darwin)
            PACKAGE_MANAGER="brew"
            log_info "Detected: macOS (using Homebrew)"
            ;;
        Linux)
            if command -v apt &>/dev/null; then
                PACKAGE_MANAGER="apt"
            elif command -v dnf &>/dev/null; then
                PACKAGE_MANAGER="dnf"
            elif command -v pacman &>/dev/null; then
                PACKAGE_MANAGER="pacman"
            else
                log_error "Unsupported Linux distribution"
                exit 1
            fi
            log_info "Detected: Linux (using $PACKAGE_MANAGER)"
            ;;
        *)
            log_error "Unsupported operating system: $OS"
            exit 1
            ;;
    esac
}

# Install required dependencies
install_required() {
    log_info "Installing required dependencies..."

    case "$PACKAGE_MANAGER" in
        brew)
            for pkg in czkawka jq; do
                if brew list "$pkg" &>/dev/null; then
                    log_success "$pkg already installed"
                else
                    log_info "Installing $pkg..."
                    brew install "$pkg"
                fi
            done
            ;;
        apt)
            sudo apt update -qq
            sudo apt install -y jq
            if ! command -v czkawka_cli &>/dev/null; then
                log_warn "czkawka_cli needs manual installation"
                echo "  Download from: https://github.com/qarmin/czkawka/releases"
            fi
            ;;
        dnf)
            sudo dnf install -y jq
            if ! command -v czkawka_cli &>/dev/null; then
                log_warn "czkawka_cli needs manual installation"
            fi
            ;;
        pacman)
            sudo pacman -S --noconfirm czkawka jq
            ;;
    esac
}

# Install optional dependencies
install_optional() {
    log_info "Installing optional dependencies..."

    case "$PACKAGE_MANAGER" in
        brew)
            for pkg in fd fzf trash dust; do
                if brew list "$pkg" &>/dev/null; then
                    log_success "$pkg already installed"
                else
                    log_info "Installing $pkg..."
                    brew install "$pkg" || log_warn "Failed to install $pkg"
                fi
            done
            ;;
        apt)
            sudo apt install -y fzf fd-find trash-cli 2>/dev/null || true
            ;;
        dnf)
            sudo dnf install -y fzf fd-find trash-cli 2>/dev/null || true
            ;;
        pacman)
            sudo pacman -S --noconfirm fd fzf trash-cli dust 2>/dev/null || true
            ;;
    esac
}

# Create symlink
create_symlink() {
    local source="$SCRIPT_DIR/bin/declutter"
    local target="$HOME/.local/bin/declutter"

    # Ensure source exists
    if [[ ! -f "$source" ]]; then
        log_error "Source not found: $source"
        exit 1
    fi

    # Ensure target directory exists
    mkdir -p "$(dirname "$target")"

    # Remove old symlink if exists
    if [[ -L "$target" ]]; then
        rm "$target"
    elif [[ -f "$target" ]]; then
        mv "$target" "$target.bak"
        log_warn "Backed up existing file to $target.bak"
    fi

    ln -sf "$source" "$target"
    log_success "Created symlink: $target → $source"

    # Check if in PATH
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        log_warn "Add to your shell profile:"
        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
}

# Setup configuration
setup_config() {
    local config_dir="$HOME/.config/declutter"
    local data_dir="$HOME/.local/share/declutter"
    local cache_dir="$HOME/.cache/declutter"

    mkdir -p "$config_dir" "$data_dir"/{journal,reports} "$cache_dir"/{scans,hashes}

    # Copy default config if not exists
    if [[ ! -f "$config_dir/config.yaml" ]]; then
        if [[ -f "$SCRIPT_DIR/config/default.yaml" ]]; then
            cp "$SCRIPT_DIR/config/default.yaml" "$config_dir/config.yaml"
            log_success "Created config: $config_dir/config.yaml"
        fi
    else
        log_info "Config already exists: $config_dir/config.yaml"
    fi
}

# Verify installation
verify_installation() {
    echo ""
    log_info "Verifying installation..."

    local all_good=true

    # Required
    for cmd in jq; do
        if command -v "$cmd" &>/dev/null; then
            log_success "$cmd: $(command -v "$cmd")"
        else
            log_error "$cmd: NOT FOUND (required)"
            all_good=false
        fi
    done

    # Recommended
    if command -v czkawka_cli &>/dev/null; then
        log_success "czkawka_cli: $(command -v czkawka_cli)"
    else
        log_warn "czkawka_cli: not found (recommended for duplicate detection)"
    fi

    # Optional
    for cmd in fd fzf trash dust; do
        if command -v "$cmd" &>/dev/null; then
            log_success "$cmd: $(command -v "$cmd")"
        else
            log_warn "$cmd: not found (optional)"
        fi
    done

    echo ""
    if [[ "$all_good" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Main
main() {
    echo -e "\n${BOLD}${BLUE}╭─────────────────────────────────────────╮${RESET}"
    echo -e "${BOLD}${BLUE}│${RESET}  ${BOLD}🧹 Declutter Installer v${VERSION}${RESET}            ${BOLD}${BLUE}│${RESET}"
    echo -e "${BOLD}${BLUE}╰─────────────────────────────────────────╯${RESET}\n"

    detect_os

    echo -e "\n${BOLD}Installing dependencies...${RESET}\n"

    install_required
    install_optional

    echo ""
    create_symlink
    setup_config
    verify_installation

    echo -e "${BOLD}${GREEN}✓ Installation complete!${RESET}\n"
    echo "Run 'declutter --help' to get started."
    echo ""
    echo "Quick start:"
    echo "  declutter quick ~/Downloads    # Quick cleanup"
    echo "  declutter dev ~/Projects       # Developer cleanup"
    echo "  declutter duplicates ~/        # Find duplicates"
    echo ""
}

main "$@"
