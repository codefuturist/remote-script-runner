#!/usr/bin/env bash
# =============================================================================
# @name         {{SCRIPT_NAME}}
# @description  {{DESCRIPTION}}
# @version      1.0.0
# @author       {{AUTHOR}}
# @license      MIT
# @requires     bash 4.0+
# =============================================================================
#
# Usage:
#   {{SCRIPT_NAME}}.sh [OPTIONS] [ARGS]
#
# Examples:
#   {{SCRIPT_NAME}}.sh --help
#   {{SCRIPT_NAME}}.sh -v
#
# =============================================================================

set -eo pipefail

# =============================================================================
# RSR Library
# =============================================================================

SCRIPT_SOURCE="${BASH_SOURCE[0]:-${0:-}}"
if [ -n "${SCRIPT_SOURCE}" ] && [ "${SCRIPT_SOURCE}" != "bash" ] && [ "${SCRIPT_SOURCE}" != "sh" ] && [ "${SCRIPT_SOURCE}" != "-bash" ] && [ "${SCRIPT_SOURCE}" != "-sh" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_SOURCE}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
else
    SCRIPT_DIR=""
fi
RSR_LIB_DIR="${SCRIPT_DIR}/../../lib"

# Load RSR library with required modules
if [[ -f "$RSR_LIB_DIR/rsr-lib.sh" ]]; then
    # shellcheck source=../../lib/rsr-lib.sh
    source "$RSR_LIB_DIR/rsr-lib.sh" validate
else
    echo "ERROR: RSR library not found at $RSR_LIB_DIR/rsr-lib.sh" >&2
    echo "       Run this script from the repository root or set RSR_LIB_DIR" >&2
    exit 1
fi

# =============================================================================
# Configuration
# =============================================================================

readonly SCRIPT_NAME="{{SCRIPT_NAME}}"
readonly SCRIPT_VERSION="1.0.0"

# Default options
VERBOSE=false
DRY_RUN=false
INTERACTIVE=auto

# =============================================================================
# Functions
# =============================================================================

show_help() {
    cat << EOF
${SCRIPT_NAME} v${SCRIPT_VERSION}

{{DESCRIPTION}}

Usage:
    ${0##*/} [OPTIONS]

Options:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    -d, --dry-run       Show what would be done without executing
    -y, --yes           Auto-confirm all prompts
    --version           Show version information

Examples:
    ${0##*/} --help
    ${0##*/} -v

EOF
}

show_version() {
    echo "${SCRIPT_NAME} v${SCRIPT_VERSION}"
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            --version)
                show_version
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                INTERACTIVE=false
                shift
                ;;
            --)
                shift
                break
                ;;
            -*)
                rsr_log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                break
                ;;
        esac
    done
}

# =============================================================================
# Main Logic
# =============================================================================

main() {
    parse_args "$@"

    rsr_log_info "Starting ${SCRIPT_NAME}..."

    if [[ "$DRY_RUN" == "true" ]]; then
        rsr_log_warn "Dry run mode - no changes will be made"
    fi

    # TODO: Implement main logic here

    rsr_log_ok "Done!"
}

# =============================================================================
# Entry Point
# =============================================================================

main "$@"

