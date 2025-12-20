#!/usr/bin/env bash
# ============================================================================
# Declutter Test Suite
# Basic tests for core functionality
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DECLUTTER_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_DIR=$(mktemp -d)
PASSED=0
FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

log_test() {
    echo -e "${YELLOW}TEST:${NC} $1"
}

log_pass() {
    echo -e "${GREEN}PASS:${NC} $1"
    ((PASSED++))
}

log_fail() {
    echo -e "${RED}FAIL:${NC} $1"
    ((FAILED++))
}

# Create test files
setup_test_files() {
    mkdir -p "$TEST_DIR"/{docs,images,code,empty_dir}

    # Create various file types
    echo "test document" > "$TEST_DIR/docs/test.txt"
    echo "test document" > "$TEST_DIR/docs/test_copy.txt"  # Duplicate
    echo "pdf content" > "$TEST_DIR/docs/sample.pdf"
    echo "image data" > "$TEST_DIR/images/photo.jpg"
    echo "console.log('test')" > "$TEST_DIR/code/app.js"

    # Create temp files
    touch "$TEST_DIR/test.tmp"
    touch "$TEST_DIR/backup.bak"

    # Create junk files
    touch "$TEST_DIR/.DS_Store"
    touch "$TEST_DIR/Thumbs.db"

    # Create large file (1MB)
    dd if=/dev/zero of="$TEST_DIR/large_file.bin" bs=1024 count=1024 2>/dev/null
}

# Test: Platform detection
test_platform_detection() {
    log_test "Platform detection"

    source "$DECLUTTER_ROOT/core/platform.sh"

    local platform
    platform=$(detect_platform)

    if [[ "$platform" =~ ^(macos|linux|windows|unknown)$ ]]; then
        log_pass "Platform detected: $platform"
    else
        log_fail "Invalid platform: $platform"
    fi
}

# Test: Human readable size
test_human_size() {
    log_test "Human readable size formatting"

    source "$DECLUTTER_ROOT/core/platform.sh"

    local result
    result=$(human_size 1073741824)
    if [[ "$result" == "1.00 GB" ]]; then
        log_pass "1 GB formatted correctly"
    else
        log_fail "Expected '1.00 GB', got '$result'"
    fi

    result=$(human_size 1048576)
    if [[ "$result" == "1.00 MB" ]]; then
        log_pass "1 MB formatted correctly"
    else
        log_fail "Expected '1.00 MB', got '$result'"
    fi
}

# Test: Configuration initialization
test_config_init() {
    log_test "Configuration initialization"

    export DECLUTTER_CONFIG_DIR="$TEST_DIR/.declutter"
    source "$DECLUTTER_ROOT/core/config.sh"

    init_config

    if [[ -f "$TEST_DIR/.declutter/config.yaml" ]]; then
        log_pass "Config file created"
    else
        log_fail "Config file not created"
    fi

    if [[ -f "$TEST_DIR/.declutter/rules.yaml" ]]; then
        log_pass "Rules file created"
    else
        log_fail "Rules file not created"
    fi
}

# Test: Safety layer - undo session
test_undo_session() {
    log_test "Undo session creation"

    export DECLUTTER_CONFIG_DIR="$TEST_DIR/.declutter"
    source "$DECLUTTER_ROOT/core/platform.sh"
    source "$DECLUTTER_ROOT/core/logger.sh"
    source "$DECLUTTER_ROOT/core/config.sh"
    source "$DECLUTTER_ROOT/core/safety.sh"

    init_config
    init_logging
    init_undo

    local session_id
    session_id=$(create_undo_session "Test session")

    if [[ -d "$TEST_DIR/.declutter/undo/$session_id" ]]; then
        log_pass "Undo session created: $session_id"
    else
        log_fail "Undo session not created"
    fi
}

# Test: Categorization
test_categorization() {
    log_test "File categorization"

    source "$DECLUTTER_ROOT/core/platform.sh"
    source "$DECLUTTER_ROOT/modules/categorize.sh" 2>/dev/null || {
        log_fail "Could not source categorize module"
        return
    }

    local cat

    cat=$(get_file_category "test.pdf")
    if [[ "$cat" == "documents" ]]; then
        log_pass "PDF categorized as documents"
    else
        log_fail "PDF category incorrect: $cat"
    fi

    cat=$(get_file_category "photo.jpg")
    if [[ "$cat" == "images" ]]; then
        log_pass "JPG categorized as images"
    else
        log_fail "JPG category incorrect: $cat"
    fi

    cat=$(get_file_category "app.js")
    if [[ "$cat" == "code" ]]; then
        log_pass "JS categorized as code"
    else
        log_fail "JS category incorrect: $cat"
    fi
}

# Test: CLI help
test_cli_help() {
    log_test "CLI help output"

    local output
    output=$("$DECLUTTER_ROOT/declutter" --help 2>&1) || true

    if echo "$output" | grep -q "Usage:"; then
        log_pass "Help shows usage"
    else
        log_fail "Help missing usage"
    fi

    if echo "$output" | grep -q "duplicates"; then
        log_pass "Help shows duplicates command"
    else
        log_fail "Help missing duplicates command"
    fi
}

# Test: CLI version
test_cli_version() {
    log_test "CLI version output"

    local output
    output=$("$DECLUTTER_ROOT/declutter" --version 2>&1) || true

    if echo "$output" | grep -qE "version [0-9]+\.[0-9]+"; then
        log_pass "Version format correct: $output"
    else
        log_fail "Invalid version format: $output"
    fi
}

# Test: Dry run mode
test_dry_run() {
    log_test "Dry run mode"

    setup_test_files

    local output
    output=$("$DECLUTTER_ROOT/declutter" --dry-run dev "$TEST_DIR" 2>&1) || true

    if echo "$output" | grep -qi "dry.run"; then
        log_pass "Dry run notice shown"
    else
        log_fail "Dry run notice not shown"
    fi

    # Files should still exist
    if [[ -f "$TEST_DIR/test.tmp" ]]; then
        log_pass "Files preserved in dry run"
    else
        log_fail "Files deleted in dry run mode"
    fi
}

# Run all tests
main() {
    echo ""
    echo "============================================"
    echo "  Declutter Test Suite"
    echo "============================================"
    echo ""
    echo "Test directory: $TEST_DIR"
    echo ""

    setup_test_files

    test_platform_detection
    test_human_size
    test_config_init
    test_undo_session
    test_categorization
    test_cli_help
    test_cli_version
    test_dry_run

    echo ""
    echo "============================================"
    echo "  Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}"
    echo "============================================"
    echo ""

    if [[ $FAILED -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
