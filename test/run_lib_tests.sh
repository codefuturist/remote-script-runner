#!/bin/bash
# test/run_lib_tests.sh - Run all RSR library tests
#
# Usage: ./test/run_lib_tests.sh [--shell] [--powershell] [--all]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0

log_header() {
    echo ""
    echo -e "${BLUE}═══ $1 ═══${NC}"
    echo ""
}

log_ok() {
    echo -e "${GREEN}✓${NC} $1"
}

log_fail() {
    echo -e "${RED}✗${NC} $1"
}

log_skip() {
    echo -e "${YELLOW}○${NC} $1"
}

# Check if bats is installed
check_bats() {
    if ! command -v bats &> /dev/null; then
        echo -e "${YELLOW}⚠ bats not installed. Install with: brew install bats-core${NC}"
        return 1
    fi
    return 0
}

# Check if PowerShell is installed
check_pwsh() {
    if ! command -v pwsh &> /dev/null; then
        echo -e "${YELLOW}⚠ PowerShell not installed. Install with: brew install --cask powershell${NC}"
        return 1
    fi
    return 0
}

# Run shell tests with bats
run_shell_tests() {
    log_header "Shell Library Tests (bats)"

    if ! check_bats; then
        log_skip "Skipping shell tests - bats not installed"
        return 0
    fi

    cd "$ROOT_DIR"

    # Find all bats test files
    local test_files=(test/lib/*.bats)

    if [ ${#test_files[@]} -eq 0 ]; then
        log_skip "No shell test files found"
        return 0
    fi

    echo "Running: bats ${test_files[*]}"
    echo ""

    if bats "${test_files[@]}"; then
        log_ok "All shell tests passed"
        return 0
    else
        log_fail "Some shell tests failed"
        return 1
    fi
}

# Run PowerShell tests with Pester
run_powershell_tests() {
    log_header "PowerShell Library Tests (Pester)"

    if ! check_pwsh; then
        log_skip "Skipping PowerShell tests - pwsh not installed"
        return 0
    fi

    cd "$ROOT_DIR"

    # Run Pester tests
    echo "Running: pwsh -c 'Invoke-Pester test/lib/Test-RSR.ps1'"
    echo ""

    if pwsh -NoProfile -Command "
        \$ErrorActionPreference = 'Stop'

        # Install Pester if not available
        if (-not (Get-Module -ListAvailable -Name Pester)) {
            Write-Host 'Installing Pester...'
            Install-Module Pester -Force -SkipPublisherCheck -Scope CurrentUser
        }

        Import-Module Pester -PassThru

        \$config = New-PesterConfiguration
        \$config.TestResult.Enabled = \$true
        \$config.Output.Verbosity = 'Detailed'
        \$config.Run.Path = 'test/lib/Test-RSR.ps1'
        \$config.Run.Exit = \$true

        Invoke-Pester -Configuration \$config
    "; then
        log_ok "All PowerShell tests passed"
        return 0
    else
        log_fail "Some PowerShell tests failed"
        return 1
    fi
}

# Quick library validation
validate_library() {
    log_header "Library Validation"

    cd "$ROOT_DIR"

    # Check shell library loads
    echo "Validating shell library..."
    local version
    version=$(bash -c "cd '$ROOT_DIR' && source lib/rsr-lib.sh && echo \$RSR_LIB_VERSION" 2>/dev/null)
    if [[ "$version" =~ ^2\. ]]; then
        log_ok "Shell library loads correctly (v$version)"
    else
        log_fail "Shell library failed to load"
        return 1
    fi

    # Check PowerShell module loads
    if check_pwsh; then
        echo "Validating PowerShell module..."
        if pwsh -NoProfile -Command "Set-Location '$ROOT_DIR'; Import-Module lib/powershell/RSR.psd1 -ErrorAction Stop; Write-Output 'OK'" 2>/dev/null | grep -q "OK"; then
            log_ok "PowerShell module loads correctly"
        else
            log_fail "PowerShell module failed to load"
            return 1
        fi
    else
        log_skip "Skipping PowerShell validation"
    fi

    return 0
}

# Main
main() {
    local run_shell=false
    local run_powershell=false
    local run_validation=true

    # Parse arguments
    if [ $# -eq 0 ]; then
        # Run all by default
        run_shell=true
        run_powershell=true
    else
        for arg in "$@"; do
            case "$arg" in
                --shell) run_shell=true ;;
                --powershell|--pwsh) run_powershell=true ;;
                --all) run_shell=true; run_powershell=true ;;
                --validate) run_validation=true; run_shell=false; run_powershell=false ;;
                --help|-h)
                    echo "Usage: $0 [--shell] [--powershell] [--all] [--validate]"
                    echo ""
                    echo "Options:"
                    echo "  --shell       Run shell/bash tests (bats)"
                    echo "  --powershell  Run PowerShell tests (Pester)"
                    echo "  --all         Run all tests (default)"
                    echo "  --validate    Quick library validation only"
                    exit 0
                    ;;
                *)
                    echo "Unknown option: $arg"
                    exit 1
                    ;;
            esac
        done
    fi

    log_header "RSR Library Test Suite"
    echo "Root: $ROOT_DIR"
    echo "Date: $(date)"

    local exit_code=0

    # Run validation
    if $run_validation; then
        if ! validate_library; then
            exit_code=1
        fi
    fi

    # Run shell tests
    if $run_shell; then
        if ! run_shell_tests; then
            exit_code=1
        fi
    fi

    # Run PowerShell tests
    if $run_powershell; then
        if ! run_powershell_tests; then
            exit_code=1
        fi
    fi

    # Summary
    log_header "Test Summary"

    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}All tests completed successfully!${NC}"
    else
        echo -e "${RED}Some tests failed!${NC}"
    fi

    exit $exit_code
}

main "$@"

