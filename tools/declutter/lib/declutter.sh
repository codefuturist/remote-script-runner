#!/usr/bin/env bash
# ============================================================================
# declutter-lib - Reusable File Organization Library
# ============================================================================
#
# A modular, cross-platform library for file organization, cleanup, and
# duplicate detection. Designed for reuse in other scripts.
#
# Usage in scripts:
#   source /path/to/declutter/lib/declutter.sh
#   declutter_init
#   find_duplicates ~/Documents
#
# ============================================================================

# Don't use set -e in library - let caller decide error handling
set -uo pipefail

# Library metadata
DECLUTTER_LIB_VERSION="2.0.0"
DECLUTTER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prevent double-sourcing
if [[ "${_DECLUTTER_LIB_LOADED:-}" == "true" ]]; then
    return 0
fi
_DECLUTTER_LIB_LOADED="true"

# =============================================================================
# Library Configuration
# =============================================================================

# Default paths (can be overridden before calling declutter_init)
DECLUTTER_CONFIG_DIR="${DECLUTTER_CONFIG_DIR:-$HOME/.declutter}"
DECLUTTER_CACHE_DIR="${DECLUTTER_CACHE_DIR:-$HOME/.cache/declutter}"
DECLUTTER_LOG_DIR="${DECLUTTER_LOG_DIR:-$DECLUTTER_CONFIG_DIR/logs}"
DECLUTTER_UNDO_DIR="${DECLUTTER_UNDO_DIR:-$DECLUTTER_CONFIG_DIR/undo}"

# Runtime flags
DECLUTTER_DRY_RUN="${DECLUTTER_DRY_RUN:-false}"
DECLUTTER_VERBOSE="${DECLUTTER_VERBOSE:-false}"
DECLUTTER_INTERACTIVE="${DECLUTTER_INTERACTIVE:-true}"
DECLUTTER_USE_TRASH="${DECLUTTER_USE_TRASH:-true}"
DECLUTTER_CONFIRM="${DECLUTTER_CONFIRM:-true}"

# =============================================================================
# Core Library Loading
# =============================================================================

# Source core modules in correct order
_load_core_modules() {
    local core_dir="$DECLUTTER_LIB_DIR/core"

    # Try to source modules, suppressing errors from incompatible files
    # We define our own fallbacks for essential functions
    for module in "$core_dir"/*.sh; do
        if [[ -f "$module" ]]; then
            (source "$module" 2>/dev/null) && source "$module" 2>/dev/null || true
        fi
    done

    # Ensure essential functions exist with fallbacks
    if ! declare -f log_info &>/dev/null; then
        log_info() { echo -e "\033[0;34mℹ\033[0m  $1"; }
        log_success() { echo -e "\033[0;32m✓\033[0m  $1"; }
        log_warn() { echo -e "\033[0;33m⚠\033[0m  $1"; }
        log_error() { echo -e "\033[0;31m✗\033[0m  $1" >&2; }
        log_step() { echo -e "\033[0;35m▶\033[0m  \033[1m$1\033[0m"; }
        log_debug() { [[ "${DECLUTTER_VERBOSE:-false}" == "true" ]] && echo -e "\033[0;90m🔍\033[0m  $1"; }
        export -f log_info log_success log_warn log_error log_step log_debug
    fi

    if ! declare -f print_header &>/dev/null; then
        print_header() { echo -e "\n\033[1m\033[0;34m═══ $1 ═══\033[0m\n"; }
        print_divider() { echo -e "\033[2m─────────────────────────────────────────────\033[0m"; }
        print_section() { echo -e "\n\033[1m$1\033[0m"; print_divider; }
        export -f print_header print_divider print_section
    fi

    if ! declare -f format_bytes &>/dev/null; then
        format_bytes() {
            local bytes=$1
            if ((bytes >= 1073741824)); then
                printf "%.2f GB" "$(echo "scale=2; $bytes / 1073741824" | bc 2>/dev/null || echo "0")"
            elif ((bytes >= 1048576)); then
                printf "%.2f MB" "$(echo "scale=2; $bytes / 1048576" | bc 2>/dev/null || echo "0")"
            elif ((bytes >= 1024)); then
                printf "%.2f KB" "$(echo "scale=2; $bytes / 1024" | bc 2>/dev/null || echo "0")"
            else
                printf "%d B" "$bytes"
            fi
        }
        export -f format_bytes
    fi

    if ! declare -f config_show &>/dev/null; then
        config_show() {
            echo "Declutter Configuration"
            echo "======================="
            echo "  Platform:     $PLATFORM"
            echo "  Dry Run:      $DECLUTTER_DRY_RUN"
            echo "  Interactive:  $DECLUTTER_INTERACTIVE"
            echo "  Use Trash:    $DECLUTTER_USE_TRASH"
            echo "  Verbose:      $DECLUTTER_VERBOSE"
            echo "  Config Dir:   $DECLUTTER_CONFIG_DIR"
            echo "  Cache Dir:    $DECLUTTER_CACHE_DIR"
        }
        export -f config_show
    fi
}

# Source optional feature modules
_load_feature_modules() {
    local scanners_dir="$DECLUTTER_LIB_DIR/scanners"
    local actions_dir="$DECLUTTER_LIB_DIR/actions"
    local undo_dir="$DECLUTTER_LIB_DIR/undo"
    local presets_dir="$DECLUTTER_LIB_DIR/presets"

    # Temporarily disable errexit for loading
    local errexit_was_set=false
    if [[ $- == *e* ]]; then
        errexit_was_set=true
        set +e
    fi

    # Load all modules
    for dir in "$scanners_dir" "$actions_dir" "$undo_dir" "$presets_dir"; do
        if [[ -d "$dir" ]]; then
            for module in "$dir"/*.sh; do
                [[ -f "$module" ]] && source "$module" 2>/dev/null
            done
        fi
    done

    # Restore errexit if it was set
    if $errexit_was_set; then
        set -e
    fi

    return 0
}

# Source platform adapters
_load_platform_adapters() {
    local adapters_dir="$DECLUTTER_LIB_DIR/../adapters"
    local platform
    platform=$(_detect_platform)

    # Load base adapter
    local base_adapter="$adapters_dir/base.sh"
    [[ -f "$base_adapter" ]] && source "$base_adapter"

    # Load platform-specific adapter
    local platform_adapter="$adapters_dir/${platform}.sh"
    [[ -f "$platform_adapter" ]] && source "$platform_adapter"
}

# =============================================================================
# Platform Detection (must be early)
# =============================================================================

_detect_platform() {
    case "$(uname -s)" in
        Darwin*)  echo "macos" ;;
        Linux*)   echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *)        echo "unix" ;;
    esac
}

# Set PLATFORM immediately
PLATFORM="${PLATFORM:-$(_detect_platform)}"
export PLATFORM

# =============================================================================
# Initialization
# =============================================================================

# Initialize the library (call this before using any functions)
declutter_init() {
    local config_file="${1:-}"

    # Create required directories
    mkdir -p "$DECLUTTER_CONFIG_DIR" \
             "$DECLUTTER_CACHE_DIR" \
             "$DECLUTTER_LOG_DIR" \
             "$DECLUTTER_UNDO_DIR"

    # Load core modules
    _load_core_modules

    # Load platform adapters
    _load_platform_adapters

    # Load feature modules
    _load_feature_modules

    # Load user config if specified
    if [[ -n "$config_file" && -f "$config_file" ]]; then
        # shellcheck source=/dev/null
        source "$config_file"
    elif [[ -f "$DECLUTTER_CONFIG_DIR/config.sh" ]]; then
        # shellcheck source=/dev/null
        source "$DECLUTTER_CONFIG_DIR/config.sh"
    fi

    # Initialize logging
    if declare -f log_init &>/dev/null; then
        log_init
    fi

    # Initialize undo system
    if declare -f undo_init &>/dev/null; then
        undo_init
    fi

    return 0
}

# =============================================================================
# Runtime Flag Helpers
# =============================================================================

is_dry_run() {
    [[ "$DECLUTTER_DRY_RUN" == "true" ]]
}

is_verbose() {
    [[ "$DECLUTTER_VERBOSE" == "true" ]]
}

is_interactive() {
    [[ "$DECLUTTER_INTERACTIVE" == "true" ]]
}

use_trash() {
    [[ "$DECLUTTER_USE_TRASH" == "true" ]]
}

should_confirm() {
    [[ "$DECLUTTER_CONFIRM" == "true" ]] && is_interactive
}

# =============================================================================
# Public API - Core Functions
# =============================================================================

# Get library version
declutter_version() {
    echo "$DECLUTTER_LIB_VERSION"
}

# Get library directory
declutter_lib_dir() {
    echo "$DECLUTTER_LIB_DIR"
}

# Check if required dependencies are available
declutter_check_deps() {
    local missing=()
    local deps=("jq")

    # Add optional but recommended deps
    local recommended=("czkawka_cli" "fd" "fzf" "trash")

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Missing required dependencies: ${missing[*]}" >&2
        return 1
    fi

    return 0
}

# =============================================================================
# Export Functions and Variables
# =============================================================================

export DECLUTTER_LIB_VERSION DECLUTTER_LIB_DIR
export DECLUTTER_CONFIG_DIR DECLUTTER_CACHE_DIR DECLUTTER_LOG_DIR DECLUTTER_UNDO_DIR
export DECLUTTER_DRY_RUN DECLUTTER_VERBOSE DECLUTTER_INTERACTIVE
export DECLUTTER_USE_TRASH DECLUTTER_CONFIRM

export -f declutter_init declutter_version declutter_lib_dir declutter_check_deps
export -f is_dry_run is_verbose is_interactive use_trash should_confirm
