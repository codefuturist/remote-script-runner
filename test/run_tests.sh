#!/usr/bin/env bash
# =============================================================================
# Test Runner for Remote Script Runner
# =============================================================================
#
# Run all tests or specific test files with BATS.
#
# Usage:
#   ./test/run_tests.sh                    # Run all tests
#   ./test/run_tests.sh --unit             # Run only unit tests
#   ./test/run_tests.sh --integration      # Run only integration tests
#   ./test/run_tests.sh --verbose          # Verbose output
#   ./test/run_tests.sh test/unit/ssl.bats # Run specific test file
#
# Environment Variables:
#   BATS_JOBS=4         # Run tests in parallel (default: auto)
#   BATS_NO_PARALLELIZE # Disable parallel execution

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BATS_CORE="$SCRIPT_DIR/libs/bats-core/bin/bats"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Default options
VERBOSE=false
RUN_UNIT=true
RUN_INTEGRATION=true
SPECIFIC_FILES=()
# Disable parallel by default since GNU parallel may not be installed
PARALLEL_JOBS="${BATS_JOBS:-1}"

# =============================================================================
# Helper Functions
# =============================================================================

log_info() { echo -e "${BLUE}▸${NC} $1"; }
log_ok() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1" >&2; }

print_header() {
    echo
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║         Remote Script Runner - Test Suite                  ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
}

show_help() {
    cat << EOF
${BOLD}Remote Script Runner - Test Suite${NC}

${YELLOW}Usage:${NC}
    $0 [OPTIONS] [TEST_FILES...]

${BOLD}Options:${NC}
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output (show each test)
    -u, --unit          Run only unit tests
    -i, --integration   Run only integration tests
    -l, --list          List all available tests
    -j, --jobs N        Run N tests in parallel (default: auto)
    --no-parallel       Disable parallel execution
    --filter PATTERN    Run only tests matching pattern
    --tap               Output in TAP format
    --junit FILE        Output JUnit XML to file

${BOLD}Examples:${NC}
    ${DIM}# Run all tests${NC}
    $0

    ${DIM}# Run only unit tests with verbose output${NC}
    $0 -v --unit

    ${DIM}# Run specific test file${NC}
    $0 test/unit/disk-cleanup.bats

    ${DIM}# Run tests matching pattern${NC}
    $0 --filter "ssl"

${BOLD}Environment Variables:${NC}
    BATS_JOBS=N         Set parallel job count
    NO_COLOR=1          Disable colored output

EOF
    exit 0
}

# Check if BATS is available
check_bats() {
    if [[ -x "$BATS_CORE" ]]; then
        return 0
    fi

    # Try system bats
    if command -v bats &>/dev/null; then
        BATS_CORE="bats"
        return 0
    fi

    log_error "BATS not found!"
    echo
    echo "Install BATS using one of these methods:"
    echo
    echo "  ${BOLD}1. Initialize git submodules:${NC}"
    echo "     git submodule update --init --recursive"
    echo
    echo "  ${BOLD}2. Install via package manager:${NC}"
    echo "     brew install bats-core     # macOS"
    echo "     apt install bats           # Ubuntu/Debian"
    echo
    exit 1
}

# Check if submodules are initialized
check_submodules() {
    local missing=false

    for lib in bats-core bats-support bats-assert bats-file; do
        if [[ ! -d "$SCRIPT_DIR/libs/$lib" ]] || [[ -z "$(ls -A "$SCRIPT_DIR/libs/$lib" 2>/dev/null)" ]]; then
            missing=true
            break
        fi
    done

    if $missing; then
        log_warn "BATS submodules not initialized"
        log_info "Initializing git submodules..."
        (cd "$PROJECT_ROOT" && git submodule update --init --recursive)
    fi
}

# List all available tests
list_tests() {
    echo -e "${BOLD}Available Tests:${NC}"
    echo

    echo -e "${CYAN}Unit Tests:${NC}"
    if [[ -d "$SCRIPT_DIR/unit" ]]; then
        find "$SCRIPT_DIR/unit" -name "*.bats" -type f | sort | while read -r file; do
            local name=$(basename "$file" .bats)
            local count=$(grep -c "^@test" "$file" 2>/dev/null || echo 0)
            echo "  $name ($count tests)"
        done
    else
        echo "  (none found)"
    fi
    echo

    echo -e "${CYAN}Integration Tests:${NC}"
    if [[ -d "$SCRIPT_DIR/integration" ]]; then
        find "$SCRIPT_DIR/integration" -name "*.bats" -type f | sort | while read -r file; do
            local name=$(basename "$file" .bats)
            local count=$(grep -c "^@test" "$file" 2>/dev/null || echo 0)
            echo "  $name ($count tests)"
        done
    else
        echo "  (none found)"
    fi
    echo

    exit 0
}

# =============================================================================
# Parse Arguments
# =============================================================================

BATS_ARGS=()
FILTER_PATTERN=""
TAP_OUTPUT=false
JUNIT_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        -v|--verbose)
            VERBOSE=true
            BATS_ARGS+=("--verbose-run")
            shift
            ;;
        -u|--unit)
            RUN_UNIT=true
            RUN_INTEGRATION=false
            shift
            ;;
        -i|--integration)
            RUN_UNIT=false
            RUN_INTEGRATION=true
            shift
            ;;
        -l|--list)
            list_tests
            ;;
        -j|--jobs)
            PARALLEL_JOBS="$2"
            shift 2
            ;;
        --no-parallel)
            PARALLEL_JOBS=1
            shift
            ;;
        --filter)
            FILTER_PATTERN="$2"
            BATS_ARGS+=("--filter" "$2")
            shift 2
            ;;
        --tap)
            TAP_OUTPUT=true
            BATS_ARGS+=("--tap")
            shift
            ;;
        --junit)
            JUNIT_FILE="$2"
            BATS_ARGS+=("--report-formatter" "junit" "--output" "$(dirname "$2")")
            shift 2
            ;;
        -*)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 2
            ;;
        *)
            SPECIFIC_FILES+=("$1")
            shift
            ;;
    esac
done

# =============================================================================
# Main
# =============================================================================

main() {
    print_header

    # Check dependencies
    check_submodules
    check_bats

    # Determine which tests to run
    local test_files=()

    if [[ ${#SPECIFIC_FILES[@]} -gt 0 ]]; then
        # Run specific files
        test_files=("${SPECIFIC_FILES[@]}")
    else
        # Collect test files based on options
        if $RUN_UNIT && [[ -d "$SCRIPT_DIR/unit" ]]; then
            while IFS= read -r -d '' file; do
                test_files+=("$file")
            done < <(find "$SCRIPT_DIR/unit" -name "*.bats" -type f -print0 | sort -z)
        fi

        if $RUN_INTEGRATION && [[ -d "$SCRIPT_DIR/integration" ]]; then
            while IFS= read -r -d '' file; do
                test_files+=("$file")
            done < <(find "$SCRIPT_DIR/integration" -name "*.bats" -type f -print0 | sort -z)
        fi
    fi

    if [[ ${#test_files[@]} -eq 0 ]]; then
        log_warn "No test files found"
        exit 0
    fi

    # Show test summary
    local total_tests=0
    for file in "${test_files[@]}"; do
        if [[ -f "$file" ]]; then
            local count=$(grep -c "^@test" "$file" 2>/dev/null || echo 0)
            total_tests=$((total_tests + count))
        fi
    done

    log_info "Running ${#test_files[@]} test file(s) with $total_tests test(s)"
    if [[ $PARALLEL_JOBS -gt 1 ]]; then
        log_info "Using $PARALLEL_JOBS parallel jobs"
    fi
    echo

    # Build BATS command
    local bats_cmd=("$BATS_CORE")

    if [[ $PARALLEL_JOBS -gt 1 ]]; then
        bats_cmd+=("--jobs" "$PARALLEL_JOBS")
    fi

    if $VERBOSE; then
        bats_cmd+=("--print-output-on-failure")
    fi

    bats_cmd+=("${BATS_ARGS[@]}")
    bats_cmd+=("${test_files[@]}")

    # Run tests
    local start_time=$(date +%s)

    if "${bats_cmd[@]}"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo
        log_ok "All tests passed in ${duration}s"
        exit 0
    else
        local exit_code=$?
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo
        log_error "Some tests failed (${duration}s)"
        exit $exit_code
    fi
}

main

