#!/bin/sh
# lib/common.sh - Shared utilities for Remote Script Runner
# Source this file in scripts: . "${0%/*}/../lib/common.sh"
#
# POSIX-compatible for maximum portability
# Provides: colors, logging, download helpers, OS/shell detection

# =============================================================================
# Color Setup
# =============================================================================

setup_colors() {
    if [ -t 1 ]; then
        RSR_BLUE='\033[0;34m'
        RSR_GREEN='\033[0;32m'
        RSR_YELLOW='\033[1;33m'
        RSR_RED='\033[0;31m'
        RSR_CYAN='\033[0;36m'
        RSR_BOLD='\033[1m'
        RSR_DIM='\033[2m'
        RSR_NC='\033[0m'
    else
        RSR_BLUE=''
        RSR_GREEN=''
        RSR_YELLOW=''
        RSR_RED=''
        RSR_CYAN=''
        RSR_BOLD=''
        RSR_DIM=''
        RSR_NC=''
    fi

    # Export for compatibility with scripts expecting these names
    BLUE="$RSR_BLUE"
    GREEN="$RSR_GREEN"
    YELLOW="$RSR_YELLOW"
    RED="$RSR_RED"
    NC="$RSR_NC"
}

# =============================================================================
# Logging Functions
# =============================================================================

# Standard logging - consistent style across all scripts
log_info() {
    printf "${RSR_BLUE}▸${RSR_NC} %s\n" "$1"
}

log_ok() {
    printf "${RSR_GREEN}✓${RSR_NC} %s\n" "$1"
}

log_warn() {
    printf "${RSR_YELLOW}⚠${RSR_NC} %s\n" "$1" >&2
}

log_error() {
    printf "${RSR_RED}✗${RSR_NC} %s\n" "$1" >&2
}

log_debug() {
    if [ "${RSR_VERBOSE:-0}" = "1" ]; then
        printf "${RSR_DIM}[debug]${RSR_NC} %s\n" "$1"
    fi
}

# Legacy log function for backward compatibility
# Usage: log "LEVEL" "message"
log() {
    level="$1"
    message="$2"
    case "$level" in
        INFO) log_info "$message" ;;
        OK) log_ok "$message" ;;
        WARN) log_warn "$message" ;;
        ERROR) log_error "$message" ;;
        DEBUG) log_debug "$message" ;;
        *) printf "[%s] %s\n" "$level" "$message" ;;
    esac
}

# =============================================================================
# Download Helpers
# =============================================================================

# Download content from URL to stdout
# Usage: download "https://example.com/file"
download() {
    url="$1"
    if command -v curl > /dev/null 2>&1; then
        curl -fsSL "$url"
    elif command -v wget > /dev/null 2>&1; then
        wget -qO- "$url"
    else
        log_error "Neither curl nor wget is available"
        return 1
    fi
}

# Download content from URL to file
# Usage: download_to "https://example.com/file" "/path/to/dest"
download_to() {
    url="$1"
    dest="$2"
    if command -v curl > /dev/null 2>&1; then
        curl -fsSL "$url" -o "$dest"
    elif command -v wget > /dev/null 2>&1; then
        wget -qO "$dest" "$url"
    else
        log_error "Neither curl nor wget is available"
        return 1
    fi
}

# =============================================================================
# OS Detection
# =============================================================================

# Detect operating system
# Returns: darwin, linux, freebsd, windows, unknown
detect_os() {
    case "$(uname -s 2> /dev/null || echo unknown)" in
        Darwin*) echo "darwin" ;;
        Linux*) echo "linux" ;;
        FreeBSD*) echo "freebsd" ;;
        CYGWIN* | MINGW* | MSYS*) echo "windows" ;;
        *) echo "unknown" ;;
    esac
}

# Detect architecture
# Returns: amd64, arm64, arm, i386, unknown
detect_arch() {
    case "$(uname -m 2> /dev/null || echo unknown)" in
        x86_64 | amd64) echo "amd64" ;;
        arm64 | aarch64) echo "arm64" ;;
        armv*) echo "arm" ;;
        i386 | i686) echo "i386" ;;
        *) echo "unknown" ;;
    esac
}

# =============================================================================
# Shell Detection
# =============================================================================

# Detect best available shell for script execution
# Returns: bash, zsh, sh
detect_shell() {
    if [ -n "${RSR_SHELL:-}" ]; then
        echo "$RSR_SHELL"
        return
    fi

    # Prefer bash for widest compatibility
    if command -v bash > /dev/null 2>&1; then
        echo "bash"
    elif command -v zsh > /dev/null 2>&1; then
        echo "zsh"
    elif command -v sh > /dev/null 2>&1; then
        echo "sh"
    else
        echo "sh"
    fi
}

# =============================================================================
# Utility Functions
# =============================================================================

# Check if a command exists
# Usage: has_command "git"
has_command() {
    command -v "$1" > /dev/null 2>&1
}

# Check if running in a terminal
is_terminal() {
    [ -t 1 ]
}

# Print a horizontal line
print_line() {
    printf '%*s\n' "${1:-60}" '' | tr ' ' "${2:--}"
}

# =============================================================================
# Initialize
# =============================================================================

# Auto-setup colors when sourced
setup_colors
