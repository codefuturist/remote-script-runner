#!/bin/bash
# =============================================================================
# @id           {{SCRIPT_ID}}
# @name         {{SCRIPT_NAME}}
# @displayName  {{DISPLAY_NAME}}
# @description  {{DESCRIPTION}}
# @category     {{CATEGORY}}
# @version      1.0.0
# @author       {{AUTHOR}}
# @tags         {{TAGS}}
# @shells       bash
# @requires     {{REQUIREMENTS}}
# @os           linux,macos
# @sudo         {{SUDO_REQUIRED}}
# =============================================================================

# This script can be run remotely with curl and accepts arguments
# Example: /bin/bash -c "$(curl -fsSL https://codefuturist.github.io/remote-script-runner/scripts/bash/{{SCRIPT_NAME}}.sh)" -- {{EXAMPLE_ARGS}}

set -eo pipefail

# Source interactive utilities if available
SCRIPT_SOURCE="${BASH_SOURCE[0]:-${0:-}}"
if [ -n "${SCRIPT_SOURCE}" ] && [ "${SCRIPT_SOURCE}" != "bash" ] && [ "${SCRIPT_SOURCE}" != "sh" ] && [ "${SCRIPT_SOURCE}" != "-bash" ] && [ "${SCRIPT_SOURCE}" != "-sh" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_SOURCE}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
else
    SCRIPT_DIR=""
fi
[[ -f "$SCRIPT_DIR/../../lib/interactive.sh" ]] && source "$SCRIPT_DIR/../../lib/interactive.sh"

# =============================================================================
# Script Metadata
# =============================================================================

SCRIPT_NAME="{{DISPLAY_NAME}}"
SCRIPT_VERSION="1.0.0"
SCRIPT_URL="https://github.com/codefuturist/remote-script-runner"

# =============================================================================
# Default Configuration
# =============================================================================

VERBOSE=false
DRY_RUN=false
INTERACTIVE=auto
RSR_YES=0

# =============================================================================
# Color Codes
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# =============================================================================
# Exit Codes
# =============================================================================

EXIT_OK=0
EXIT_ERROR=1
EXIT_INVALID_ARGS=2

# =============================================================================
# Logging Functions
# =============================================================================

log_info() { echo -e "${BLUE}▸${NC} $*"; }
log_ok() { echo -e "${GREEN}✓${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $*"; }
log_error() { echo -e "${RED}✗${NC} $*" >&2; }
log_debug() { [[ "$VERBOSE" == "true" ]] && echo -e "${DIM}  $*${NC}"; }

print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}═══ $1 ═══${NC}"
    echo ""
}

# =============================================================================
# Usage/Help Function
# =============================================================================

usage() {
    cat << EOF
${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}

{{DESCRIPTION}}

${YELLOW}Usage:${NC}
    $0 [OPTIONS]

${BOLD}Options:${NC}
    -h, --help          Display this help message
    -v, --verbose       Enable verbose output
    -i, --interactive   Run in interactive mode (default when no args)
    --no-interactive    Disable interactive mode
    -y, --yes           Auto-confirm all prompts
    -d, --dry-run       Show what would be done

${BOLD}Examples:${NC}
    ${DIM}# Run in interactive mode${NC}
    $0

    ${DIM}# Run with verbose output${NC}
    $0 -v

    ${DIM}# Dry run${NC}
    $0 --dry-run

EOF
    exit 0
}

# =============================================================================
# Parse Arguments
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help) usage ;;
            -v | --verbose)
                VERBOSE=true
                shift
                ;;
            -i | --interactive)
                INTERACTIVE=true
                shift
                ;;
            --no-interactive)
                INTERACTIVE=false
                shift
                ;;
            -y | --yes)
                RSR_YES=1
                INTERACTIVE=false
                shift
                ;;
            -d | --dry-run)
                DRY_RUN=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                exit $EXIT_INVALID_ARGS
                ;;
            *)
                # Handle positional arguments
                shift
                ;;
        esac
    done
}

# =============================================================================
# Core Functions
# =============================================================================

# TODO: Implement your core functionality here

# =============================================================================
# Interactive Mode
# =============================================================================

run_interactive() {
    print_interactive_header "$SCRIPT_NAME" "$SCRIPT_VERSION"
    
    echo ""
    
    # TODO: Implement interactive prompts using:
    # - prompt_select "Question" "Option 1" "Option 2" "Option 3"
    # - prompt_multiselect "Question" "Option 1" "Option 2" "Option 3"
    # - prompt_input "Question" "default_value"
    # - prompt_yes_no "Question" "y" or "n"
    # - confirm_destructive "This will do something dangerous"
    
    # Example:
    # local action
    # action=$(prompt_select "What would you like to do?" \
    #     "Option 1" \
    #     "Option 2" \
    #     "Option 3")
    # 
    # case "$action" in
    #     "Option 1") # handle option 1 ;;
    #     "Option 2") # handle option 2 ;;
    #     "Option 3") # handle option 3 ;;
    # esac
    
    # Summary before execution
    echo ""
    log_info "Configuration summary:"
    # echo -e "  ${CYAN}•${NC} Setting: value"
    echo ""
    
    if prompt_yes_no "Proceed with execution?" "y"; then
        return 0
    else
        log_info "Operation cancelled"
        exit 0
    fi
}

# =============================================================================
# Main Function
# =============================================================================

main() {
    local original_args=("$@")
    parse_args "$@"

    # Determine if interactive mode should be enabled
    # Auto-enable when: no arguments given AND running in a terminal
    if [[ "$INTERACTIVE" == "auto" ]]; then
        if [[ ${#original_args[@]} -eq 0 ]] && [[ -t 0 ]] && [[ -t 1 ]]; then
            INTERACTIVE=true
        else
            INTERACTIVE=false
        fi
    fi

    # Run interactive mode if enabled and interactive utilities available
    if [[ "$INTERACTIVE" == "true" ]] && type -t rsr_is_interactive &>/dev/null && rsr_is_interactive; then
        run_interactive
    fi

    # Main script header
    echo -e "${BOLD}$SCRIPT_NAME v$SCRIPT_VERSION${NC}"
    echo ""

    # TODO: Implement main script logic here
    
    log_ok "Operation completed successfully"
    exit $EXIT_OK
}

main "$@"

