#!/bin/bash
# =============================================================================
# PowerShell Testing Script - Cross-platform Pester test runner
# =============================================================================
#
# This script runs Pester tests for PowerShell scripts.
# Works on macOS, Linux, and Windows (with PowerShell Core installed).
#
# Usage: ./tools/test-powershell.sh [--verbose]
#
# Options:
#   --verbose    Show detailed test output
#
# Requirements:
#   - PowerShell Core (pwsh) installed
#   - Pester module (auto-installed if missing)
#
# Exit codes:
#   0 - All tests passed
#   1 - Test failures
#   2 - PowerShell not available

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TEST_DIR="$ROOT_DIR/test/powershell"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose | -v)
            VERBOSE=true
            shift
            ;;
        -h | --help)
            echo "Usage: $0 [--verbose]"
            echo ""
            echo "Options:"
            echo "  --verbose, -v    Show detailed test output"
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option: $1${NC}" >&2
            exit 1
            ;;
    esac
done

log_info() { printf "${BLUE}▸${NC} %s\n" "$1"; }
log_ok() { printf "${GREEN}✓${NC} %s\n" "$1"; }
log_warn() { printf "${YELLOW}⚠${NC} %s\n" "$1"; }
log_error() { printf "${RED}✗${NC} %s\n" "$1"; }

# Check if PowerShell Core is installed
check_pwsh() {
    if ! command -v pwsh >/dev/null 2>&1; then
        log_error "PowerShell Core (pwsh) is not installed"
        echo ""
        echo "Install PowerShell Core:"
        echo "  macOS:   brew install --cask powershell"
        echo "  Linux:   See https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux"
        echo "  Windows: winget install Microsoft.PowerShell"
        echo ""
        return 1
    fi
    return 0
}

# Main script
main() {
    log_info "Checking PowerShell environment..."

    if ! check_pwsh; then
        exit 2
    fi

    log_ok "PowerShell Core is available"

    # Check if test directory exists
    if [ ! -d "$TEST_DIR" ]; then
        log_warn "No PowerShell tests found at: $TEST_DIR"
        log_info "Skipping PowerShell tests"
        exit 0
    fi

    # Check if Pester is installed, install if needed
    log_info "Checking Pester module..."

    pwsh -NoProfile -Command "
        if (-not (Get-Module -ListAvailable -Name Pester)) {
            Write-Host '${YELLOW}▸${NC} Installing Pester module...' -NoNewline
            Install-Module -Name Pester -Force -Scope CurrentUser -Repository PSGallery -SkipPublisherCheck
            Write-Host ' ${GREEN}Done${NC}'
        }
    " || {
        log_error "Failed to install Pester"
        exit 1
    }

    log_ok "Pester module is ready"

    # Run Pester tests
    log_info "Running PowerShell tests with Pester..."
    echo ""

    OUTPUT_DETAIL="Normal"
    if [ "$VERBOSE" = true ]; then
        OUTPUT_DETAIL="Detailed"
    fi

    # Run the tests
    pwsh -NoProfile -Command "
        \$ErrorActionPreference = 'Stop'

        # Import Pester
        Import-Module Pester

        # Configure Pester
        \$config = New-PesterConfiguration
        \$config.Run.Path = '$TEST_DIR'
        \$config.Output.Verbosity = '$OUTPUT_DETAIL'
        \$config.TestResult.Enabled = \$false
        \$config.CodeCoverage.Enabled = \$false

        # Run tests
        \$result = Invoke-Pester -Configuration \$config

        # Exit with test result
        exit \$result.FailedCount
    "

    exit_code=$?

    echo ""
    if [ $exit_code -eq 0 ]; then
        log_ok "All PowerShell tests passed"
    else
        log_error "PowerShell tests failed"
    fi

    exit $exit_code
}

main

