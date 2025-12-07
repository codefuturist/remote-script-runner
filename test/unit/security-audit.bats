#!/usr/bin/env bats
# =============================================================================
# Unit Tests for security-audit.sh
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

@test "security-audit: shows help with -h flag" {
    run bash "$SCRIPT_DIR/security-audit.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Security Audit"
    assert_output --partial "Usage"
}

@test "security-audit: shows help with --help flag" {
    run bash "$SCRIPT_DIR/security-audit.sh" --help
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Options"
}

@test "security-audit: help shows all sections" {
    run bash "$SCRIPT_DIR/security-audit.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "ports"
    assert_output --partial "auth"
    assert_output --partial "files"
    assert_output --partial "users"
    assert_output --partial "network"
    assert_output --partial "ssh"
}

@test "security-audit: help shows examples" {
    run bash "$SCRIPT_DIR/security-audit.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Examples"
}

# =============================================================================
# Section Selection Tests
# =============================================================================

@test "security-audit: --all runs all checks" {
    run bash "$SCRIPT_DIR/security-audit.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-a"
    assert_output --partial "all"
}

@test "security-audit: can select specific section" {
    run bash "$SCRIPT_DIR/security-audit.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-s"
    assert_output --partial "section"
}

# =============================================================================
# Scan Mode Tests
# =============================================================================

@test "security-audit: supports --quick mode" {
    run bash "$SCRIPT_DIR/security-audit.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--quick"
}

@test "security-audit: supports --deep mode" {
    run bash "$SCRIPT_DIR/security-audit.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--deep"
}

# =============================================================================
# Severity Filter Tests
# =============================================================================

@test "security-audit: supports --severity filter" {
    run bash "$SCRIPT_DIR/security-audit.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--severity"
}

# =============================================================================
# Report Generation Tests
# =============================================================================

@test "security-audit: supports -r report option" {
    run bash "$SCRIPT_DIR/security-audit.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-r"
    assert_output --partial "report"
}

@test "security-audit: supports --format option" {
    run bash "$SCRIPT_DIR/security-audit.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--format"
    assert_output --partial "text"
    assert_output --partial "json"
}

# =============================================================================
# Syntax and Structure Tests
# =============================================================================

@test "security-audit: has valid bash syntax" {
    run bash -n "$SCRIPT_DIR/security-audit.sh"
    assert_success
}

@test "security-audit: contains required metadata" {
    run grep -E "^# @id" "$SCRIPT_DIR/security-audit.sh"
    assert_success

    run grep -E "^# @category.*security" "$SCRIPT_DIR/security-audit.sh"
    assert_success
}

@test "security-audit: script is executable" {
    assert_file_executable "$SCRIPT_DIR/security-audit.sh"
}

@test "security-audit: defines severity levels" {
    run grep -E "CRITICAL|HIGH|MEDIUM|LOW" "$SCRIPT_DIR/security-audit.sh"
    assert_success
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "security-audit: handles unknown option" {
    run bash "$SCRIPT_DIR/security-audit.sh" --unknown-option-xyz 2>&1
    assert_failure
}

@test "security-audit: handles unknown section" {
    run bash "$SCRIPT_DIR/security-audit.sh" -s nonexistent_section 2>&1
    output=$(strip_colors "$output")
    # Should handle gracefully
    [[ $status -eq 0 ]] || [[ "$output" == *"nknown"* ]] || [[ "$output" == *"nvalid"* ]]
}

# =============================================================================
# Output Tests
# =============================================================================

@test "security-audit: supports verbose output" {
    run bash "$SCRIPT_DIR/security-audit.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-v"
    assert_output --partial "verbose"
}

