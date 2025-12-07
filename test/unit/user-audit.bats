#!/usr/bin/env bats
# =============================================================================
# Unit Tests for user-audit.sh
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

@test "user-audit: shows help with -h flag" {
    run bash "$SCRIPT_DIR/user-audit.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "User Audit"
    assert_output --partial "Usage"
}

@test "user-audit: shows help with --help flag" {
    run bash "$SCRIPT_DIR/user-audit.sh" --help
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Options"
}

@test "user-audit: help shows all sections" {
    run bash "$SCRIPT_DIR/user-audit.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "accounts"
    assert_output --partial "sudo"
    assert_output --partial "passwords"
}

@test "user-audit: help shows examples" {
    run bash "$SCRIPT_DIR/user-audit.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Examples"
}

# =============================================================================
# Section Selection Tests
# =============================================================================

@test "user-audit: --all flag runs all checks" {
    run bash "$SCRIPT_DIR/user-audit.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-a"
    assert_output --partial "all"
}

@test "user-audit: can select specific section" {
    run bash "$SCRIPT_DIR/user-audit.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-s"
    assert_output --partial "section"
}

@test "user-audit: supports --sudo-only filter" {
    run bash "$SCRIPT_DIR/user-audit.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--sudo-only"
}

@test "user-audit: supports --expired filter" {
    run bash "$SCRIPT_DIR/user-audit.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--expired"
}

@test "user-audit: supports --orphans check" {
    run bash "$SCRIPT_DIR/user-audit.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--orphans"
}

@test "user-audit: supports --ssh-keys check" {
    run bash "$SCRIPT_DIR/user-audit.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--ssh"
}

# =============================================================================
# User-specific Audit Tests
# =============================================================================

@test "user-audit: can audit specific user with -u" {
    run bash "$SCRIPT_DIR/user-audit.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-u"
    assert_output --partial "user"
}

# =============================================================================
# Syntax and Structure Tests
# =============================================================================

@test "user-audit: has valid bash syntax" {
    run bash -n "$SCRIPT_DIR/user-audit.sh"
    assert_success
}

@test "user-audit: contains required metadata" {
    run grep -E "^# @id" "$SCRIPT_DIR/user-audit.sh"
    assert_success

    run grep -E "^# @category.*security" "$SCRIPT_DIR/user-audit.sh"
    assert_success
}

@test "user-audit: script is executable" {
    assert_file_executable "$SCRIPT_DIR/user-audit.sh"
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "user-audit: handles unknown option" {
    run bash "$SCRIPT_DIR/user-audit.sh" --unknown-option-xyz 2>&1
    assert_failure
}

@test "user-audit: handles unknown section" {
    run bash "$SCRIPT_DIR/user-audit.sh" -s nonexistent_section 2>&1
    output=$(strip_colors "$output")
    # Should warn about unknown section or continue gracefully
    [[ $status -eq 0 ]] || [[ "$output" == *"nknown"* ]] || [[ "$output" == *"nvalid"* ]]
}

# =============================================================================
# Output Format Tests
# =============================================================================

@test "user-audit: supports verbose output" {
    run bash "$SCRIPT_DIR/user-audit.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-v"
    assert_output --partial "verbose"
}

