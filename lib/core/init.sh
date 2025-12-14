#!/bin/sh
# lib/core/init.sh - RSR Library Initialization & Core Utilities
# POSIX-compliant foundation for all RSR libraries
#
# Usage: . "${RSR_LIB_DIR:-./lib}/core/init.sh"
#
# Provides:
#   - Library initialization and dependency management
#   - OS/shell/architecture detection
#   - Logging framework with consistent formatting
#   - Error handling and exit codes
#   - Download helpers (curl/wget abstraction)
#   - Command existence checking

# =============================================================================
# Guard: Prevent double-sourcing
# =============================================================================

[ -n "${_RSR_CORE_INIT_LOADED:-}" ] && return 0
_RSR_CORE_INIT_LOADED=1

# =============================================================================
# Library Metadata
# =============================================================================

RSR_LIB_VERSION="2.0.0"
RSR_LIB_NAME="RSR Core Library"

# =============================================================================
# Exit Codes (consistent across all RSR tools)
# =============================================================================

RSR_EXIT_SUCCESS=0
RSR_EXIT_ERROR=1
RSR_EXIT_USAGE=2
RSR_EXIT_DEPENDENCY=3
RSR_EXIT_PERMISSION=4
RSR_EXIT_NOT_FOUND=5
RSR_EXIT_ALREADY_EXISTS=6
RSR_EXIT_TIMEOUT=7
RSR_EXIT_CANCELLED=8

# =============================================================================
# Color Setup
# =============================================================================

rsr_setup_colors() {
    if [ -t 1 ] && [ "${RSR_NO_COLOR:-0}" != "1" ]; then
        RSR_COLOR_BLUE='\033[0;34m'
        RSR_COLOR_GREEN='\033[0;32m'
        RSR_COLOR_YELLOW='\033[1;33m'
        RSR_COLOR_RED='\033[0;31m'
        RSR_COLOR_CYAN='\033[0;36m'
        RSR_COLOR_MAGENTA='\033[0;35m'
        RSR_COLOR_BOLD='\033[1m'
        RSR_COLOR_DIM='\033[2m'
        RSR_COLOR_RESET='\033[0m'
    else
        RSR_COLOR_BLUE=''
        RSR_COLOR_GREEN=''
        RSR_COLOR_YELLOW=''
        RSR_COLOR_RED=''
        RSR_COLOR_CYAN=''
        RSR_COLOR_MAGENTA=''
        RSR_COLOR_BOLD=''
        RSR_COLOR_DIM=''
        RSR_COLOR_RESET=''
    fi
}

# Initialize colors on load
rsr_setup_colors

# =============================================================================
# Logging Framework
# =============================================================================

# Log info message
# Usage: rsr_log_info "message"
rsr_log_info() {
    printf "${RSR_COLOR_BLUE}▸${RSR_COLOR_RESET} %s\n" "$1"
}

# Log success message
# Usage: rsr_log_ok "message"
rsr_log_ok() {
    printf "${RSR_COLOR_GREEN}✓${RSR_COLOR_RESET} %s\n" "$1"
}

# Log warning message (to stderr)
# Usage: rsr_log_warn "message"
rsr_log_warn() {
    printf "${RSR_COLOR_YELLOW}⚠${RSR_COLOR_RESET} %s\n" "$1" >&2
}

# Log error message (to stderr)
# Usage: rsr_log_error "message"
rsr_log_error() {
    printf "${RSR_COLOR_RED}✗${RSR_COLOR_RESET} %s\n" "$1" >&2
}

# Log debug message (only when RSR_DEBUG=1)
# Usage: rsr_log_debug "message"
rsr_log_debug() {
    [ "${RSR_DEBUG:-0}" = "1" ] || return 0
    printf "${RSR_COLOR_DIM}[debug]${RSR_COLOR_RESET} %s\n" "$1"
}

# Log verbose message (only when RSR_VERBOSE=1)
# Usage: rsr_log_verbose "message"
rsr_log_verbose() {
    [ "${RSR_VERBOSE:-0}" = "1" ] || return 0
    printf "${RSR_COLOR_DIM}[verbose]${RSR_COLOR_RESET} %s\n" "$1"
}

# Log step in a process
# Usage: rsr_log_step 1 5 "Installing dependencies"
rsr_log_step() {
    _step="$1"
    _total="$2"
    _message="$3"
    printf "${RSR_COLOR_CYAN}[%d/%d]${RSR_COLOR_RESET} %s\n" "$_step" "$_total" "$_message"
}

# Print header
# Usage: rsr_print_header "Section Title"
rsr_print_header() {
    printf "\n${RSR_COLOR_BOLD}═══ %s ═══${RSR_COLOR_RESET}\n\n" "$1"
}

# Print separator line
# Usage: rsr_print_separator [width] [char]
rsr_print_separator() {
    _width="${1:-60}"
    _char="${2:--}"
    printf '%*s\n' "$_width" '' | tr ' ' "$_char"
}

# =============================================================================
# Error Handling
# =============================================================================

# Die with error message and exit code
# Usage: rsr_die "message" [exit_code]
rsr_die() {
    rsr_log_error "$1"
    exit "${2:-$RSR_EXIT_ERROR}"
}

# Die if previous command failed
# Usage: some_command || rsr_die_on_error "Failed to run command"
rsr_die_on_error() {
    _exit_code=$?
    [ $_exit_code -eq 0 ] && return 0
    rsr_die "$1" "$_exit_code"
}

# Assert condition or die
# Usage: rsr_assert "test -f /etc/passwd" "passwd file not found"
rsr_assert() {
    eval "$1" || rsr_die "${2:-Assertion failed: $1}"
}

# =============================================================================
# OS Detection (cached)
# =============================================================================

# Detect operating system
# Returns: darwin, linux, freebsd, windows, unknown
rsr_detect_os() {
    if [ -z "${_RSR_CACHED_OS:-}" ]; then
        case "$(uname -s 2> /dev/null || echo unknown)" in
            Darwin*) _RSR_CACHED_OS="darwin" ;;
            Linux*) _RSR_CACHED_OS="linux" ;;
            FreeBSD*) _RSR_CACHED_OS="freebsd" ;;
            CYGWIN* | MINGW* | MSYS*) _RSR_CACHED_OS="windows" ;;
            *) _RSR_CACHED_OS="unknown" ;;
        esac
    fi
    echo "$_RSR_CACHED_OS"
}

# Detect CPU architecture
# Returns: amd64, arm64, arm, i386, unknown
rsr_detect_arch() {
    if [ -z "${_RSR_CACHED_ARCH:-}" ]; then
        case "$(uname -m 2> /dev/null || echo unknown)" in
            x86_64 | amd64) _RSR_CACHED_ARCH="amd64" ;;
            arm64 | aarch64) _RSR_CACHED_ARCH="arm64" ;;
            armv*) _RSR_CACHED_ARCH="arm" ;;
            i386 | i686) _RSR_CACHED_ARCH="i386" ;;
            *) _RSR_CACHED_ARCH="unknown" ;;
        esac
    fi
    echo "$_RSR_CACHED_ARCH"
}

# Detect Linux distribution
# Returns: debian, ubuntu, fedora, centos, rhel, arch, alpine, unknown
rsr_detect_distro() {
    if [ -z "${_RSR_CACHED_DISTRO:-}" ]; then
        _RSR_CACHED_DISTRO="unknown"
        if [ -f /etc/os-release ]; then
            # shellcheck disable=SC1091
            . /etc/os-release
            case "${ID:-}" in
                debian) _RSR_CACHED_DISTRO="debian" ;;
                ubuntu) _RSR_CACHED_DISTRO="ubuntu" ;;
                fedora) _RSR_CACHED_DISTRO="fedora" ;;
                centos) _RSR_CACHED_DISTRO="centos" ;;
                rhel) _RSR_CACHED_DISTRO="rhel" ;;
                arch) _RSR_CACHED_DISTRO="arch" ;;
                alpine) _RSR_CACHED_DISTRO="alpine" ;;
                *) _RSR_CACHED_DISTRO="${ID:-unknown}" ;;
            esac
        elif [ -f /etc/debian_version ]; then
            _RSR_CACHED_DISTRO="debian"
        elif [ -f /etc/redhat-release ]; then
            _RSR_CACHED_DISTRO="rhel"
        fi
    fi
    echo "$_RSR_CACHED_DISTRO"
}

# Detect current shell
# Returns: bash, zsh, sh, dash, fish, unknown
rsr_detect_shell() {
    if [ -z "${_RSR_CACHED_SHELL:-}" ]; then
        if [ -n "${BASH_VERSION:-}" ]; then
            _RSR_CACHED_SHELL="bash"
        elif [ -n "${ZSH_VERSION:-}" ]; then
            _RSR_CACHED_SHELL="zsh"
        elif [ -n "${FISH_VERSION:-}" ]; then
            _RSR_CACHED_SHELL="fish"
        else
            # Try to detect from $0 or $SHELL
            _shell_name="$(basename "${SHELL:-sh}" 2> /dev/null || echo sh)"
            case "$_shell_name" in
                bash | zsh | dash | fish | ksh) _RSR_CACHED_SHELL="$_shell_name" ;;
                *) _RSR_CACHED_SHELL="sh" ;;
            esac
        fi
    fi
    echo "$_RSR_CACHED_SHELL"
}

# Get package manager for current system
# Returns: apt, yum, dnf, pacman, zypper, brew, apk, winget, choco, unknown
rsr_detect_package_manager() {
    if [ -z "${_RSR_CACHED_PKG_MGR:-}" ]; then
        if rsr_has_command apt-get; then
            _RSR_CACHED_PKG_MGR="apt"
        elif rsr_has_command dnf; then
            _RSR_CACHED_PKG_MGR="dnf"
        elif rsr_has_command yum; then
            _RSR_CACHED_PKG_MGR="yum"
        elif rsr_has_command pacman; then
            _RSR_CACHED_PKG_MGR="pacman"
        elif rsr_has_command zypper; then
            _RSR_CACHED_PKG_MGR="zypper"
        elif rsr_has_command apk; then
            _RSR_CACHED_PKG_MGR="apk"
        elif rsr_has_command brew; then
            _RSR_CACHED_PKG_MGR="brew"
        elif rsr_has_command winget; then
            _RSR_CACHED_PKG_MGR="winget"
        elif rsr_has_command choco; then
            _RSR_CACHED_PKG_MGR="choco"
        else
            _RSR_CACHED_PKG_MGR="unknown"
        fi
    fi
    echo "$_RSR_CACHED_PKG_MGR"
}

# =============================================================================
# Command Utilities
# =============================================================================

# Check if a command exists
# Usage: rsr_has_command "git"
rsr_has_command() {
    command -v "$1" > /dev/null 2>&1
}

# Require a command or die
# Usage: rsr_require_command "git" "Git is required for this operation"
rsr_require_command() {
    _cmd="$1"
    _msg="${2:-Command '$_cmd' is required but not installed}"
    rsr_has_command "$_cmd" || rsr_die "$_msg" "$RSR_EXIT_DEPENDENCY"
}

# Require root/sudo or die
# Usage: rsr_require_root "This operation requires root privileges"
rsr_require_root() {
    _msg="${1:-This operation requires root privileges}"
    [ "$(id -u)" -eq 0 ] || rsr_die "$_msg" "$RSR_EXIT_PERMISSION"
}

# Check if running as root
# Usage: if rsr_is_root; then ...
rsr_is_root() {
    [ "$(id -u)" -eq 0 ]
}

# =============================================================================
# Download Helpers
# =============================================================================

# Download URL to stdout
# Usage: rsr_download "https://example.com/file"
rsr_download() {
    _url="$1"
    if rsr_has_command curl; then
        curl -fsSL "$_url"
    elif rsr_has_command wget; then
        wget -qO- "$_url"
    else
        rsr_die "Neither curl nor wget is available" "$RSR_EXIT_DEPENDENCY"
    fi
}

# Download URL to file
# Usage: rsr_download_to "https://example.com/file" "/path/to/dest"
rsr_download_to() {
    _url="$1"
    _dest="$2"
    if rsr_has_command curl; then
        curl -fsSL "$_url" -o "$_dest"
    elif rsr_has_command wget; then
        wget -qO "$_dest" "$_url"
    else
        rsr_die "Neither curl nor wget is available" "$RSR_EXIT_DEPENDENCY"
    fi
}

# =============================================================================
# Terminal Utilities
# =============================================================================

# Check if running in a terminal
# Usage: if rsr_is_terminal; then ...
rsr_is_terminal() {
    [ -t 1 ]
}

# Check if interactive mode is appropriate
# Usage: if rsr_is_interactive; then ...
rsr_is_interactive() {
    # Explicitly disabled
    [ "${RSR_NO_INTERACTIVE:-0}" = "1" ] && return 1
    # Explicitly enabled
    [ "${RSR_INTERACTIVE:-0}" = "1" ] && return 0
    # Auto-detect: both stdin and stdout are terminals
    [ -t 0 ] && [ -t 1 ]
}

# =============================================================================
# String Utilities
# =============================================================================

# Check if string is empty or whitespace only
# Usage: if rsr_is_blank "$var"; then ...
rsr_is_blank() {
    [ -z "$(echo "$1" | tr -d '[:space:]')" ]
}

# Trim whitespace from string
# Usage: trimmed=$(rsr_trim "  hello  ")
rsr_trim() {
    echo "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Convert string to lowercase
# Usage: lower=$(rsr_lowercase "HELLO")
rsr_lowercase() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

# Convert string to uppercase
# Usage: upper=$(rsr_uppercase "hello")
rsr_uppercase() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

# =============================================================================
# Path Utilities
# =============================================================================

# Get absolute path (POSIX-compatible realpath alternative)
# Usage: abs_path=$(rsr_realpath "./relative/path")
rsr_realpath() {
    if rsr_has_command realpath; then
        realpath "$1" 2> /dev/null
    elif rsr_has_command readlink; then
        readlink -f "$1" 2> /dev/null
    else
        # Fallback: cd and pwd
        if [ -d "$1" ]; then
            (cd "$1" && pwd)
        elif [ -f "$1" ]; then
            _dir="$(dirname "$1")"
            _base="$(basename "$1")"
            echo "$(cd "$_dir" && pwd)/$_base"
        else
            echo "$1"
        fi
    fi
}

# =============================================================================
# Version Comparison
# =============================================================================

# Compare version strings
# Usage: rsr_version_compare "1.2.3" "1.2.4"
# Returns: 0 if equal, 1 if first > second, 2 if first < second
rsr_version_compare() {
    [ "$1" = "$2" ] && return 0

    _v1="$1"
    _v2="$2"

    # Compare each part
    _IFS="$IFS"
    IFS='.'
    set -- $_v1
    _v1_major="${1:-0}"
    _v1_minor="${2:-0}"
    _v1_patch="${3:-0}"

    set -- $_v2
    _v2_major="${1:-0}"
    _v2_minor="${2:-0}"
    _v2_patch="${3:-0}"
    IFS="$_IFS"

    # Compare major
    [ "$_v1_major" -gt "$_v2_major" ] 2> /dev/null && return 1
    [ "$_v1_major" -lt "$_v2_major" ] 2> /dev/null && return 2

    # Compare minor
    [ "$_v1_minor" -gt "$_v2_minor" ] 2> /dev/null && return 1
    [ "$_v1_minor" -lt "$_v2_minor" ] 2> /dev/null && return 2

    # Compare patch
    [ "$_v1_patch" -gt "$_v2_patch" ] 2> /dev/null && return 1
    [ "$_v1_patch" -lt "$_v2_patch" ] 2> /dev/null && return 2

    return 0
}

# =============================================================================
# Initialization Complete
# =============================================================================

rsr_log_debug "RSR Core Library v${RSR_LIB_VERSION} loaded"
