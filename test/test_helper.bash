#!/usr/bin/env bash
# =============================================================================
# Test Helper for Remote Script Runner
# =============================================================================
#
# This file provides shared utilities for all BATS tests:
# - Load BATS libraries (support, assert, file)
# - Setup/teardown helpers
# - Mock command utilities
# - Common assertions
# - Fixture management
#
# Usage in test files:
#   load 'test_helper'

# =============================================================================
# Load BATS Libraries
# =============================================================================

# Get the directory containing this helper
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$TEST_DIR")"
SCRIPT_DIR="$PROJECT_ROOT/scripts/bash"
LIB_DIR="$PROJECT_ROOT/lib"
FIXTURES_DIR="$TEST_DIR/fixtures"
MOCKS_DIR="$TEST_DIR/mocks"

# Load BATS libraries
load "${TEST_DIR}/libs/bats-support/load"
load "${TEST_DIR}/libs/bats-assert/load"
load "${TEST_DIR}/libs/bats-file/load"

# =============================================================================
# Test Environment Setup/Teardown
# =============================================================================

# Setup test environment - call this in setup()
setup_test_env() {
    # Create temporary directory for test artifacts
    TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_TEMP_DIR

    # Add mocks to PATH (mocks take precedence)
    export ORIGINAL_PATH="$PATH"
    export PATH="$MOCKS_DIR:$PATH"

    # Disable colors in test output for easier assertions
    export NO_COLOR=1
    export TERM=dumb

    # Set non-interactive mode
    export DEBIAN_FRONTEND=noninteractive

    # Create mock home directory
    export TEST_HOME="$TEST_TEMP_DIR/home"
    mkdir -p "$TEST_HOME"

    # Create mock /etc structure
    export TEST_ETC="$TEST_TEMP_DIR/etc"
    mkdir -p "$TEST_ETC"
}

# Teardown test environment - call this in teardown()
teardown_test_env() {
    # Restore original PATH
    if [[ -n "${ORIGINAL_PATH:-}" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi

    # Remove temporary directory
    if [[ -n "${TEST_TEMP_DIR:-}" && -d "${TEST_TEMP_DIR}" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# =============================================================================
# Mock Command Utilities
# =============================================================================

# Create a mock command that returns specific output
# Usage: mock_command "apt-get" "mock output" [exit_code]
mock_command() {
    local cmd_name="$1"
    local output="${2:-}"
    local exit_code="${3:-0}"

    local mock_file="$TEST_TEMP_DIR/mocks/$cmd_name"
    mkdir -p "$TEST_TEMP_DIR/mocks"

    cat > "$mock_file" << EOF
#!/bin/bash
echo "$output"
exit $exit_code
EOF
    chmod +x "$mock_file"

    # Prepend mock directory to PATH
    export PATH="$TEST_TEMP_DIR/mocks:$PATH"
}

# Create a mock command that captures its arguments
# Usage: mock_command_capture "mysqldump"
# Later: cat "$TEST_TEMP_DIR/mocks/mysqldump.args"
mock_command_capture() {
    local cmd_name="$1"
    local output="${2:-}"
    local exit_code="${3:-0}"

    local mock_file="$TEST_TEMP_DIR/mocks/$cmd_name"
    mkdir -p "$TEST_TEMP_DIR/mocks"

    cat > "$mock_file" << EOF
#!/bin/bash
echo "\$@" >> "$TEST_TEMP_DIR/mocks/${cmd_name}.args"
echo "$output"
exit $exit_code
EOF
    chmod +x "$mock_file"
    export PATH="$TEST_TEMP_DIR/mocks:$PATH"
}

# Check if mock command was called with specific arguments
# Usage: assert_mock_called_with "mysqldump" "--all-databases"
assert_mock_called_with() {
    local cmd_name="$1"
    local expected_arg="$2"
    local args_file="$TEST_TEMP_DIR/mocks/${cmd_name}.args"

    assert_file_exist "$args_file"
    assert_file_contains "$args_file" "$expected_arg"
}

# =============================================================================
# Strip ANSI Color Codes
# =============================================================================

# Remove ANSI color codes from string
# Usage: result=$(strip_colors "$output")
strip_colors() {
    echo "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

# =============================================================================
# Script Execution Helpers
# =============================================================================

# Run a script and strip colors from output
# Usage: run_script "disk-cleanup.sh" "-h"
run_script() {
    local script="$1"
    shift
    run bash "$SCRIPT_DIR/$script" "$@"
    output=$(strip_colors "$output")
}

# Run the main rsr command
# Usage: run_rsr "health" "-a"
run_rsr() {
    run "$PROJECT_ROOT/rsr" "$@"
    output=$(strip_colors "$output")
}

# =============================================================================
# Platform Detection
# =============================================================================

# Check if running on macOS
is_macos() {
    [[ "$(uname -s)" == "Darwin" ]]
}

# Check if running on Linux
is_linux() {
    [[ "$(uname -s)" == "Linux" ]]
}

# Skip test if not on specified platform
# Usage: require_linux
require_linux() {
    if ! is_linux; then
        skip "Test requires Linux"
    fi
}

require_macos() {
    if ! is_macos; then
        skip "Test requires macOS"
    fi
}

# Skip test if root is required but not available
require_root() {
    if [[ $EUID -ne 0 ]]; then
        skip "Test requires root privileges"
    fi
}

# Skip test if a command is not available
# Usage: require_command "openssl"
require_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        skip "Test requires '$cmd' command"
    fi
}

# =============================================================================
# Fixture Helpers
# =============================================================================

# Get path to a fixture file
# Usage: fixture_path "domains.txt"
fixture_path() {
    echo "$FIXTURES_DIR/$1"
}

# Copy fixture to temp directory
# Usage: use_fixture "sample-config" "$TEST_TEMP_DIR/config"
use_fixture() {
    local fixture="$1"
    local dest="$2"
    cp -r "$FIXTURES_DIR/$fixture" "$dest"
}

# Create a temporary file with content
# Usage: temp_file "content here"
temp_file() {
    local content="$1"
    local file="$TEST_TEMP_DIR/tempfile_$$_$RANDOM"
    echo "$content" > "$file"
    echo "$file"
}

# =============================================================================
# Assertion Helpers
# =============================================================================

# Assert that output contains all specified strings
# Usage: assert_output_contains "string1" "string2" "string3"
assert_output_contains() {
    for pattern in "$@"; do
        assert_output --partial "$pattern"
    done
}

# Assert exit code matches expected value
# Usage: assert_exit_code 0
assert_exit_code() {
    local expected="$1"
    assert_equal "$status" "$expected" "Expected exit code $expected, got $status"
}

# Assert output matches help format (has Usage, Options sections)
assert_valid_help_output() {
    assert_success
    assert_output --partial "Usage"
    assert_output --partial "Options"
}

# Assert script has valid bash syntax
# Usage: assert_valid_syntax "disk-cleanup.sh"
assert_valid_syntax() {
    local script="$1"
    run bash -n "$SCRIPT_DIR/$script"
    assert_success
}

# =============================================================================
# Common Test Patterns
# =============================================================================

# Test that a script shows help with -h flag
# Usage: test_help_flag "disk-cleanup.sh"
test_help_flag() {
    local script="$1"
    run bash "$SCRIPT_DIR/$script" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Usage"
}

# Test that a script shows help with --help flag
test_help_long_flag() {
    local script="$1"
    run bash "$SCRIPT_DIR/$script" --help
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Usage"
}

# Test that script fails with unknown option
test_unknown_option() {
    local script="$1"
    run bash "$SCRIPT_DIR/$script" --this-option-does-not-exist-xyz
    assert_failure
}

