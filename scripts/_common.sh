#!/usr/bin/env bash
# =============================================================================
# scripts/_common.sh - Common initialization for all RSR scripts
# =============================================================================
#
# Source this file at the beginning of every script to:
# - Automatically locate and load the RSR library
# - Set up common variables and functions
#
# RECOMMENDED Usage (handles piped execution):
#   source <(curl -fsSL https://raw.githubusercontent.com/.../scripts/_common.sh) || \
#       source "$(dirname "${BASH_SOURCE[0]:-$0}")/../_common.sh" 2>/dev/null || \
#       { echo "ERROR: Cannot find _common.sh" >&2; exit 1; }
#
# Legacy Usage (local execution only):
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "${SCRIPT_DIR}/../../_common.sh"
#
# =============================================================================

# Prevent double-sourcing
[[ -n "${_RSR_COMMON_LOADED:-}" ]] && return 0
_RSR_COMMON_LOADED=1

# =============================================================================
# Safe BASH_SOURCE handling for piped execution
# =============================================================================

# Helper: Get script directory safely (works with piped execution)
_get_script_dir() {
    local src="${BASH_SOURCE[1]:-${BASH_SOURCE[0]:-$0}}"
    # Check if running via pipe (sh/bash are shell names, not paths)
    if [[ -n "$src" ]] && [[ "$src" != "bash" ]] && [[ "$src" != "sh" ]] && [[ "$src" != "-bash" ]] && [[ "$src" != "-sh" ]]; then
        dirname "$(cd "$(dirname "$src")" 2> /dev/null && pwd 2> /dev/null)" 2> /dev/null || echo ""
    else
        echo ""
    fi
}

export -f _get_script_dir 2> /dev/null || true

# =============================================================================
# Path Detection
# =============================================================================

# Find the scripts root directory (where _common.sh lives)
_find_scripts_root() {
    local dir="${1:-$(pwd)}"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/_common.sh" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# Determine script and root directories
if [[ -n "${BASH_SOURCE[0]:-}" ]] && [[ "${BASH_SOURCE[0]}" != "bash" ]] && [[ "${BASH_SOURCE[0]}" != "sh" ]] && [[ "${BASH_SOURCE[0]}" != "-bash" ]] && [[ "${BASH_SOURCE[0]}" != "-sh" ]]; then
    RSR_COMMON_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2> /dev/null && pwd)/$(basename "${BASH_SOURCE[0]}")"
    RSR_SCRIPTS_ROOT="$(dirname "$RSR_COMMON_FILE")"
else
    RSR_SCRIPTS_ROOT="$(_find_scripts_root)"
fi

RSR_PROJECT_ROOT="$(dirname "$RSR_SCRIPTS_ROOT")"
RSR_LIB_DIR="${RSR_PROJECT_ROOT}/lib"

# Export for use in scripts
export RSR_SCRIPTS_ROOT
export RSR_PROJECT_ROOT
export RSR_LIB_DIR

# =============================================================================
# RSR Library Loading
# =============================================================================

# Load RSR library with specified modules
# Usage: rsr_load [module1] [module2] ...
# Example: rsr_load users docker validate
rsr_load() {
    if [[ ! -f "$RSR_LIB_DIR/rsr-lib.sh" ]]; then
        echo "ERROR: RSR library not found at $RSR_LIB_DIR/rsr-lib.sh" >&2
        echo "       Project root: $RSR_PROJECT_ROOT" >&2
        return 1
    fi

    # shellcheck source=../lib/rsr-lib.sh
    source "$RSR_LIB_DIR/rsr-lib.sh" "$@"
}

# Auto-load core library
rsr_load

# =============================================================================
# Common Script Helpers
# =============================================================================

# Get path relative to scripts root
# Usage: script_path=$(rsr_script_path "security/audit/security-audit.sh")
rsr_script_path() {
    echo "${RSR_SCRIPTS_ROOT}/${1}"
}

# Check if running from correct location
rsr_check_location() {
    if [[ ! -d "$RSR_LIB_DIR" ]]; then
        rsr_log_error "Script must be run from the RSR repository"
        rsr_log_info "Current directory: $(pwd)"
        rsr_log_info "Expected lib at: $RSR_LIB_DIR"
        return 1
    fi
}

# =============================================================================
# Script Metadata Helpers
# =============================================================================

# Parse script header for metadata
# Usage: version=$(rsr_get_script_meta "version" "$script_file")
rsr_get_script_meta() {
    local key="$1"
    local file="${2:-${BASH_SOURCE[1]:-}}"

    [[ -f "$file" ]] || return 1

    grep -E "^#[[:space:]]*@${key}[[:space:]]+" "$file" 2> /dev/null \
        | sed -E "s/^#[[:space:]]*@${key}[[:space:]]+//" \
        | head -1
}

# =============================================================================
# Cross-Platform Helpers
# =============================================================================

# Get the appropriate script for current shell
# Usage: script=$(rsr_get_shell_script "system/health/system-health-check")
rsr_get_shell_script() {
    local base_path="$1"
    local shell="${2:-bash}"

    local extensions=("sh" "bash" "zsh" "fish")

    for ext in "${extensions[@]}"; do
        local script="${RSR_SCRIPTS_ROOT}/${base_path}.${ext}"
        if [[ -f "$script" ]]; then
            echo "$script"
            return 0
        fi
    done

    # Try without extension
    if [[ -f "${RSR_SCRIPTS_ROOT}/${base_path}" ]]; then
        echo "${RSR_SCRIPTS_ROOT}/${base_path}"
        return 0
    fi

    return 1
}

# =============================================================================
# Initialization Complete
# =============================================================================

rsr_log_debug "RSR common initialized (scripts: $RSR_SCRIPTS_ROOT)"
