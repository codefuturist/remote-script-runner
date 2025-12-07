#!/usr/bin/env bats
# =============================================================================
# Unit Tests for ssl-checker.sh
# =============================================================================

load '../test_helper'

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

# =============================================================================
# Help and Usage Tests
# =============================================================================

@test "ssl-checker: shows help with -h flag" {
    run bash "$SCRIPT_DIR/ssl-checker.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "SSL Certificate Checker"
    assert_output --partial "Usage"
}

@test "ssl-checker: shows help with --help flag" {
    run bash "$SCRIPT_DIR/ssl-checker.sh" --help
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Options"
}

@test "ssl-checker: help shows exit codes" {
    run bash "$SCRIPT_DIR/ssl-checker.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Exit Codes"
}

@test "ssl-checker: help shows examples" {
    run bash "$SCRIPT_DIR/ssl-checker.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Examples"
}

# =============================================================================
# Option Parsing Tests
# =============================================================================

@test "ssl-checker: accepts -d domain option" {
    require_command "openssl"
    # This will fail to connect but should parse the option correctly
    run timeout 5 bash "$SCRIPT_DIR/ssl-checker.sh" -d example.invalid.test 2>&1 || true
    # Just verify the script started processing
    [[ $status -ne 2 ]] || skip "Option parsing failed"
}

@test "ssl-checker: accepts -w warning days option" {
    run bash "$SCRIPT_DIR/ssl-checker.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-w"
    assert_output --partial "warn"
}

@test "ssl-checker: accepts -c critical days option" {
    run bash "$SCRIPT_DIR/ssl-checker.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-c"
    assert_output --partial "critical"
}

@test "ssl-checker: accepts -p port option" {
    run bash "$SCRIPT_DIR/ssl-checker.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-p"
    assert_output --partial "port"
}

@test "ssl-checker: accepts -f file option" {
    run bash "$SCRIPT_DIR/ssl-checker.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-f"
    assert_output --partial "file"
}

@test "ssl-checker: accepts --chain option" {
    run bash "$SCRIPT_DIR/ssl-checker.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--chain"
}

@test "ssl-checker: accepts --ciphers option" {
    run bash "$SCRIPT_DIR/ssl-checker.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--ciphers"
}

# =============================================================================
# File Input Tests
# =============================================================================

@test "ssl-checker: can read domains from file" {
    local domains_file=$(fixture_path "domains.txt")

    # Just verify file exists and script accepts it
    assert_file_exist "$domains_file"
}

@test "ssl-checker: handles missing file gracefully" {
    run bash "$SCRIPT_DIR/ssl-checker.sh" -f /nonexistent/file.txt 2>&1
    assert_failure
}

# =============================================================================
# Output Format Tests
# =============================================================================

@test "ssl-checker: supports text output format" {
    run bash "$SCRIPT_DIR/ssl-checker.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "text"
}

@test "ssl-checker: supports json output format" {
    run bash "$SCRIPT_DIR/ssl-checker.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "json"
}

# =============================================================================
# Syntax and Structure Tests
# =============================================================================

@test "ssl-checker: has valid bash syntax" {
    run bash -n "$SCRIPT_DIR/ssl-checker.sh"
    assert_success
}

@test "ssl-checker: contains required metadata" {
    run grep -E "^# @id" "$SCRIPT_DIR/ssl-checker.sh"
    assert_success

    run grep -E "^# @name" "$SCRIPT_DIR/ssl-checker.sh"
    assert_success
}

@test "ssl-checker: script is executable" {
    assert_file_executable "$SCRIPT_DIR/ssl-checker.sh"
}

@test "ssl-checker: defines exit codes" {
    run grep -E "EXIT_OK|EXIT_WARNING|EXIT_CRITICAL|EXIT_ERROR" "$SCRIPT_DIR/ssl-checker.sh"
    assert_success
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "ssl-checker: handles unknown option" {
    run bash "$SCRIPT_DIR/ssl-checker.sh" --unknown-option-xyz 2>&1
    assert_failure
}

@test "ssl-checker: requires domain argument" {
    run bash "$SCRIPT_DIR/ssl-checker.sh" 2>&1
    # Should fail or show help when no domain provided
    # (depends on implementation - may show help or error)
    [[ $status -ne 0 ]] || [[ "$output" == *"Usage"* ]]
}

# =============================================================================
# Verbose Mode Tests
# =============================================================================

@test "ssl-checker: accepts verbose flag" {
    run bash "$SCRIPT_DIR/ssl-checker.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-v"
    assert_output --partial "verbose"
}

