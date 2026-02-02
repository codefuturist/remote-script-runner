#!/usr/bin/env bash
# =============================================================================
# lib/core/subscript.sh - RSR Subscript Execution System
# Enables scripts to call and reuse other scripts without code duplication
#
# Usage: source "${RSR_LIB_DIR:-./lib}/core/subscript.sh"
#
# Provides:
#   - Script execution with context propagation
#   - Library mode for sourcing scripts without execution
#   - Dry-run and verbose mode inheritance
#   - Script function importing
# =============================================================================

# Guard: Prevent double-sourcing
[[ -n "${_RSR_CORE_SUBSCRIPT_LOADED:-}" ]] && return 0
_RSR_CORE_SUBSCRIPT_LOADED=1

# Module version
_RSR_SUBSCRIPT_VERSION="1.0.0"

# Ensure core is loaded
if [[ -z "${_RSR_CORE_INIT_LOADED:-}" ]]; then
    _script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || _script_dir="."
    source "${_script_dir}/init.sh" 2>/dev/null || source "./lib/core/init.sh" 2>/dev/null || {
        echo "ERROR: RSR core/init.sh must be sourced first" >&2
        return 1
    }
fi

# =============================================================================
# Script Registry and Path Resolution
# =============================================================================

# Get the RSR root directory
_rsr_get_root() {
    if [[ -n "${RSR_ROOT:-}" ]]; then
        echo "$RSR_ROOT"
    elif [[ -n "${RSR_LIB_DIR:-}" ]]; then
        echo "${RSR_LIB_DIR}/.."
    else
        echo "."
    fi
}

# Resolve script path from command name
# Usage: path=$(rsr_resolve_script "ssh-harden")
rsr_resolve_script() {
    local cmd="$1"
    local root
    root="$(_rsr_get_root)"
    
    # Script path mappings (mirrors rsr main script)
    local script_path=""
    case "$cmd" in
        # Security
        audit|security-audit) script_path="scripts/security/audit/security-audit.sh" ;;
        users|user-audit) script_path="scripts/security/audit/user-audit.sh" ;;
        ssh-harden|ssh-hardening) script_path="scripts/security/hardening/ssh-hardening.sh" ;;
        firewall|firewall-setup) script_path="scripts/security/hardening/firewall-setup.sh" ;;
        ssl|ssl-check) script_path="scripts/security/certificates/ssl-checker.sh" ;;
        ssh-server) script_path="scripts/security/ssh/ssh-server.sh" ;;
        ssh-keys) script_path="scripts/security/ssh/ssh-keys.sh" ;;
        ssh-config) script_path="scripts/security/ssh/ssh-config.sh" ;;
        
        # System
        health|health-check) script_path="scripts/system/health/system-health-check.sh" ;;
        update|system-update) script_path="scripts/system/updates/system-update.sh" ;;
        cleanup|disk-cleanup) script_path="scripts/system/cleanup/disk-cleanup.sh" ;;
        detect-distro) script_path="scripts/system/info/detect-distro.sh" ;;
        install-pkgs) script_path="scripts/system/packages/install-packages.sh" ;;
        bootstrap|host-bootstrap) script_path="scripts/system/bootstrap/host-bootstrap.sh" ;;
        
        # Users
        user-mgmt|user-management) script_path="scripts/users/management/user-management.sh" ;;
        setup|server-setup) script_path="scripts/users/setup/server-setup.sh" ;;
        
        # Network
        netdiag|network-diagnostics) script_path="scripts/network/diagnostics/network-diagnostics.sh" ;;
        shares|share-management) script_path="scripts/network/shares/share-management.sh" ;;
        
        # Containers
        docker|docker-management) script_path="scripts/containers/docker/docker-management.sh" ;;
        
        # Backup
        backup) script_path="scripts/backup/tools/backup-unified.sh" ;;
        db-backup|database-backup) script_path="scripts/backup/database/database-backup.sh" ;;
        config-backup) script_path="scripts/backup/config/config-backup.sh" ;;
        
        *) script_path="" ;;
    esac
    
    if [[ -n "$script_path" ]] && [[ -f "$root/$script_path" ]]; then
        echo "$root/$script_path"
    else
        echo ""
    fi
}

# =============================================================================
# Context Management
# =============================================================================

# Current execution context (exported for subscripts)
declare -gx RSR_DRY_RUN="${RSR_DRY_RUN:-false}"
declare -gx RSR_VERBOSE="${RSR_VERBOSE:-false}"
declare -gx RSR_YES="${RSR_YES:-0}"
declare -gx RSR_INTERACTIVE="${RSR_INTERACTIVE:-auto}"
declare -gx RSR_AS_LIBRARY="${RSR_AS_LIBRARY:-0}"

# Save current context
# Usage: local saved_ctx=$(rsr_save_context)
rsr_save_context() {
    echo "RSR_DRY_RUN=$RSR_DRY_RUN;RSR_VERBOSE=$RSR_VERBOSE;RSR_YES=$RSR_YES;RSR_INTERACTIVE=$RSR_INTERACTIVE"
}

# Restore saved context
# Usage: rsr_restore_context "$saved_ctx"
rsr_restore_context() {
    local ctx="$1"
    eval "$ctx"
}

# Build arguments array from current context
# Usage: args=$(rsr_context_args)
rsr_context_args() {
    local args=""
    [[ "$RSR_DRY_RUN" == "true" ]] && args="$args --dry-run"
    [[ "$RSR_VERBOSE" == "true" ]] && args="$args --verbose"
    [[ "$RSR_YES" == "1" ]] && args="$args -y"
    [[ "$RSR_INTERACTIVE" == "false" ]] && args="$args --no-interactive"
    echo "$args"
}

# =============================================================================
# Subscript Execution
# =============================================================================

# Run a subscript with current context
# Usage: rsr_run_subscript "ssh-harden" --no-root --max-auth-tries 3
rsr_run_subscript() {
    local cmd="$1"
    shift
    local script_path
    script_path=$(rsr_resolve_script "$cmd")
    
    if [[ -z "$script_path" ]]; then
        rsr_log_error "Unknown subscript: $cmd"
        return 1
    fi
    
    if [[ ! -f "$script_path" ]]; then
        rsr_log_error "Script not found: $script_path"
        return 1
    fi
    
    # Build context arguments
    local ctx_args
    ctx_args=$(rsr_context_args)
    
    rsr_log_debug "Running subscript: $cmd ($script_path)"
    rsr_log_debug "Context args: $ctx_args"
    rsr_log_debug "Extra args: $*"
    
    # Execute subscript with context
    # shellcheck disable=SC2086
    bash "$script_path" $ctx_args "$@"
}

# Run subscript and capture output
# Usage: output=$(rsr_run_subscript_capture "health" -a)
rsr_run_subscript_capture() {
    local cmd="$1"
    shift
    local script_path
    script_path=$(rsr_resolve_script "$cmd")
    
    if [[ -z "$script_path" ]] || [[ ! -f "$script_path" ]]; then
        return 1
    fi
    
    local ctx_args
    ctx_args=$(rsr_context_args)
    
    # shellcheck disable=SC2086
    bash "$script_path" $ctx_args "$@" 2>&1
}

# Check if subscript exists
# Usage: if rsr_subscript_exists "ssh-harden"; then ...
rsr_subscript_exists() {
    local cmd="$1"
    local script_path
    script_path=$(rsr_resolve_script "$cmd")
    [[ -n "$script_path" ]] && [[ -f "$script_path" ]]
}

# =============================================================================
# Library Mode - Source Script Functions
# =============================================================================

# Source a script in library mode (functions only, no main execution)
# Usage: rsr_import_script "ssh-harden"
# 
# Scripts must support RSR_AS_LIBRARY mode by checking:
#   if [[ "${RSR_AS_LIBRARY:-0}" != "1" ]]; then main "$@"; fi
rsr_import_script() {
    local cmd="$1"
    local script_path
    script_path=$(rsr_resolve_script "$cmd")
    
    if [[ -z "$script_path" ]] || [[ ! -f "$script_path" ]]; then
        rsr_log_error "Cannot import script: $cmd"
        return 1
    fi
    
    rsr_log_debug "Importing script as library: $cmd"
    
    # Set library mode and source
    local saved_lib_mode="${RSR_AS_LIBRARY:-0}"
    export RSR_AS_LIBRARY=1
    
    # Save positional parameters
    local saved_args=("$@")
    set --
    
    # Source the script
    # shellcheck disable=SC1090
    source "$script_path"
    local result=$?
    
    # Restore
    set -- "${saved_args[@]}"
    export RSR_AS_LIBRARY="$saved_lib_mode"
    
    return $result
}

# Import specific functions from a script
# Usage: rsr_import_functions "ssh-harden" "configure_ssh" "validate_config"
rsr_import_functions() {
    local cmd="$1"
    shift
    local functions=("$@")
    
    # First import the full script
    rsr_import_script "$cmd" || return 1
    
    # Verify requested functions exist
    for func in "${functions[@]}"; do
        if ! declare -f "$func" &>/dev/null; then
            rsr_log_warn "Function '$func' not found after importing $cmd"
        fi
    done
}

# =============================================================================
# Convenience Wrappers for Common Operations
# =============================================================================

# Run with dry-run if current context is dry-run
# Usage: rsr_maybe_run command arg1 arg2
rsr_maybe_run() {
    if [[ "$RSR_DRY_RUN" == "true" ]]; then
        rsr_log_info "[DRY RUN] Would run: $*"
        return 0
    fi
    "$@"
}

# Run with sudo if needed
# Usage: rsr_sudo_run command arg1 arg2
rsr_sudo_run() {
    if [[ "$RSR_DRY_RUN" == "true" ]]; then
        rsr_log_info "[DRY RUN] Would run (as root): $*"
        return 0
    fi
    
    if [[ "$EUID" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

# Prompt for confirmation respecting RSR_YES
# Usage: if rsr_confirm "Proceed?"; then ...
rsr_confirm() {
    local prompt="$1"
    local default="${2:-n}"
    
    # Auto-yes mode
    if [[ "$RSR_YES" == "1" ]]; then
        return 0
    fi
    
    # Non-interactive mode
    if [[ "$RSR_INTERACTIVE" == "false" ]] || [[ ! -t 0 ]]; then
        [[ "$default" == "y" ]] && return 0 || return 1
    fi
    
    # Interactive prompt
    local hint="[y/N]"
    [[ "$default" == "y" ]] && hint="[Y/n]"
    
    printf "${RSR_COLOR_CYAN:-}?${RSR_COLOR_RESET:-} %s %s " "$prompt" "$hint"
    read -r response
    
    [[ -z "$response" ]] && response="$default"
    
    case "$response" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# =============================================================================
# Script Header Helper
# =============================================================================

# Standard script initialization that handles library mode
# Usage: rsr_script_init "$@"
# Returns: 0 to continue, 1 to exit (library mode)
rsr_script_init() {
    # In library mode, don't run main
    if [[ "${RSR_AS_LIBRARY:-0}" == "1" ]]; then
        rsr_log_debug "Script loaded in library mode"
        return 1
    fi
    
    # Inherit context from environment
    [[ -n "${RSR_DRY_RUN:-}" ]] && DRY_RUN="$RSR_DRY_RUN"
    [[ -n "${RSR_VERBOSE:-}" ]] && VERBOSE="$RSR_VERBOSE"
    [[ -n "${RSR_YES:-}" ]] && RSR_YES="$RSR_YES"
    
    return 0
}

# =============================================================================
# Module Registration
# =============================================================================

rsr_log_debug "RSR subscript module loaded (v${_RSR_SUBSCRIPT_VERSION})"
