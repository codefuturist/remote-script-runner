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

set -euo pipefail

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

# =============================================================================
# Color Codes
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# =============================================================================
# Logging Functions
# =============================================================================

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_debug() { [[ "$VERBOSE" == "true" ]] && echo -e "${CYAN}[DEBUG]${NC} $*"; }

# =============================================================================
# Usage/Help Function
# =============================================================================

usage() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION

DESCRIPTION:
    {{DESCRIPTION}}

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help      Display this help message
    -v, --verbose   Enable verbose output
    -d, --dry-run   Show what would be done

EXAMPLES:
    $0 -v
    $0 --dry-run

