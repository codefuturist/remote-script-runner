#!/usr/bin/env bash
# lib/rsr-lib.sh - RSR Library Loader
# Single entry point to load all RSR library components
#
# Usage:
#   . /path/to/lib/rsr-lib.sh           # Load core only
#   . /path/to/lib/rsr-lib.sh --all     # Load all modules
#   . /path/to/lib/rsr-lib.sh users docker  # Load specific modules
#
# Available modules:
#   core        - Core utilities (always loaded)
#   validate    - Input validation
#   interactive - Interactive prompts (bash only)
#   users       - User/group management
#   docker      - Docker operations
#   ssh         - SSH server management

# =============================================================================
# Library Path Detection
# =============================================================================

# Determine library root directory
if [ -n "${RSR_LIB_DIR:-}" ]; then
    _RSR_LIB_ROOT="$RSR_LIB_DIR"
else
    _script_source="${BASH_SOURCE[0]:-${0:-}}"
    if [ -n "${_script_source}" ] && [ "${_script_source}" != "sh" ] && [ "${_script_source}" != "bash" ] && [ "${_script_source}" != "-sh" ] && [ "${_script_source}" != "-bash" ]; then
        _RSR_LIB_ROOT="$(cd "$(dirname "${_script_source}")" 2> /dev/null && pwd)" || _RSR_LIB_ROOT="./lib"
    else
        _RSR_LIB_ROOT="$(cd "$(dirname "$0")" 2> /dev/null && pwd)" || _RSR_LIB_ROOT="./lib"
    fi
fi

# Export for modules (only if not already set)
if [ -z "${RSR_LIB_DIR:-}" ]; then
    export RSR_LIB_DIR="$_RSR_LIB_ROOT"
fi

# =============================================================================
# Core Loading (Always)
# =============================================================================

# shellcheck source=core/init.sh
. "${_RSR_LIB_ROOT}/core/init.sh" || {
    echo "ERROR: Failed to load RSR core library" >&2
    return 1
}

# =============================================================================
# Module Loading Functions
# =============================================================================

# Load a specific module
# Usage: rsr_load_module "users"
rsr_load_module() {
    _module="$1"

    case "$_module" in
        core)
            # Already loaded
            return 0
            ;;
        validate | validation)
            # shellcheck source=core/validate.sh
            . "${_RSR_LIB_ROOT}/core/validate.sh"
            ;;
        interactive)
            # Requires bash
            if [ -n "${BASH_VERSION:-}" ]; then
                # shellcheck source=core/interactive.sh
                . "${_RSR_LIB_ROOT}/core/interactive.sh"
            else
                rsr_log_warn "Interactive module requires bash"
                return 1
            fi
            ;;
        users | user)
            # shellcheck source=modules/users.sh
            . "${_RSR_LIB_ROOT}/modules/users.sh"
            ;;
        docker)
            # shellcheck source=modules/docker.sh
            . "${_RSR_LIB_ROOT}/modules/docker.sh"
            ;;
        ssh)
            # shellcheck source=modules/ssh.sh
            . "${_RSR_LIB_ROOT}/modules/ssh.sh"
            ;;
        packages | pkg)
            # shellcheck source=modules/packages.sh
            . "${_RSR_LIB_ROOT}/modules/packages.sh"
            ;;
        backup | bkp)
            # shellcheck source=modules/backup.sh
            . "${_RSR_LIB_ROOT}/modules/backup.sh"
            ;;
        shares | share)
            # shellcheck source=modules/shares.sh
            . "${_RSR_LIB_ROOT}/modules/shares.sh"
            ;;
    esac
}

# Load all modules
# Usage: rsr_load_all
rsr_load_all() {
    rsr_load_module validate
    rsr_load_module users
    rsr_load_module docker
    rsr_load_module ssh
    rsr_load_module packages
    rsr_load_module shares

    # Interactive only if bash
    [ -n "${BASH_VERSION:-}" ] && rsr_load_module interactive

    rsr_load_module backup
}

# =============================================================================
# Process Arguments
# =============================================================================

_rsr_lib_process_args() {
    # If no args, just load core (already done)
    [ $# -eq 0 ] && return 0

    for _arg in "$@"; do
        case "$_arg" in
            --all | -a)
                rsr_load_all
                return 0
                ;;
            --help | -h)
                cat << 'EOF'
RSR Library Loader

Usage:
  . lib/rsr-lib.sh              # Load core only
  . lib/rsr-lib.sh --all        # Load all modules
  . lib/rsr-lib.sh users docker # Load specific modules

Available modules:
  core        Core utilities (logging, detection, etc.)
  validate    Input validation functions
  interactive Interactive prompts and menus (bash only)
  users       User and group management
  docker      Docker container operations
  ssh         SSH server management

Environment variables:
  RSR_DEBUG=1       Enable debug output
  RSR_VERBOSE=1     Enable verbose output
  RSR_NO_COLOR=1    Disable colored output
  RSR_LIB_DIR       Override library directory

EOF
                return 0
                ;;
            -*)
                rsr_log_warn "Unknown option: $_arg"
                ;;
            *)
                rsr_load_module "$_arg"
                ;;
        esac
    done
}

# Process args if provided
_rsr_lib_process_args "$@"

# =============================================================================
# Library Version Info
# =============================================================================

# Print library version info
# Usage: rsr_lib_version
rsr_lib_version() {
    echo "RSR Library v${RSR_LIB_VERSION}"
    echo "Location: ${RSR_LIB_DIR}"
    echo ""
    echo "Loaded modules:"
    [ -n "${_RSR_CORE_INIT_LOADED:-}" ] && echo "  ✓ core (v${RSR_LIB_VERSION})"
    [ -n "${_RSR_CORE_VALIDATE_LOADED:-}" ] && echo "  ✓ validate"
    [ -n "${_RSR_CORE_INTERACTIVE_LOADED:-}" ] && echo "  ✓ interactive"
    [ -n "${_RSR_MODULE_USERS_LOADED:-}" ] && echo "  ✓ users (v${_RSR_USERS_VERSION:-})"
    [ -n "${_RSR_MODULE_DOCKER_LOADED:-}" ] && echo "  ✓ docker (v${_RSR_DOCKER_VERSION:-})"
    [ -n "${_RSR_MODULE_SSH_LOADED:-}" ] && echo "  ✓ ssh (v${_RSR_SSH_VERSION:-})"
}

# =============================================================================
# Initialization Complete
# =============================================================================

rsr_log_debug "RSR Library loader initialized (${RSR_LIB_DIR})"
