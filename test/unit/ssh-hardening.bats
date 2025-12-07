#!/usr/bin/env bats
# =============================================================================
# Unit Tests for ssh-hardening.sh
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

@test "ssh-hardening: shows help with -h flag" {
    run bash "$SCRIPT_DIR/ssh-hardening.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "SSH Hardening"
    assert_output --partial "Usage"
}

@test "ssh-hardening: shows help with --help flag" {
    run bash "$SCRIPT_DIR/ssh-hardening.sh" --help
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Options"
}

@test "ssh-hardening: help shows examples" {
    run bash "$SCRIPT_DIR/ssh-hardening.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Examples"
}

# =============================================================================
# Status and Dry-run Tests
# =============================================================================

@test "ssh-hardening: supports --status option" {
    run bash "$SCRIPT_DIR/ssh-hardening.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--status"
}

@test "ssh-hardening: supports --dry-run option" {
    run bash "$SCRIPT_DIR/ssh-hardening.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-d"
    assert_output --partial "dry"
}

# =============================================================================
# Hardening Options Tests
# =============================================================================

@test "ssh-hardening: supports --all option" {
    run bash "$SCRIPT_DIR/ssh-hardening.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-a"
    assert_output --partial "all"
}

@test "ssh-hardening: supports --no-root option" {
    run bash "$SCRIPT_DIR/ssh-hardening.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--no-root"
}

@test "ssh-hardening: supports --key-only option" {
    run bash "$SCRIPT_DIR/ssh-hardening.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--key-only"
}

@test "ssh-hardening: supports -p port option" {
    run bash "$SCRIPT_DIR/ssh-hardening.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-p"
    assert_output --partial "port"
}

@test "ssh-hardening: supports --fail2ban option" {
    run bash "$SCRIPT_DIR/ssh-hardening.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--fail2ban"
}

@test "ssh-hardening: supports --strong-crypto option" {
    run bash "$SCRIPT_DIR/ssh-hardening.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--strong-crypto"
}

@test "ssh-hardening: supports --allow-users option" {
    run bash "$SCRIPT_DIR/ssh-hardening.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--allow-users"
}

# =============================================================================
# Backup and Rollback Tests
# =============================================================================

@test "ssh-hardening: supports --rollback option" {
    run bash "$SCRIPT_DIR/ssh-hardening.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--rollback"
}

# =============================================================================
# Syntax and Structure Tests
# =============================================================================

@test "ssh-hardening: has valid bash syntax" {
    run bash -n "$SCRIPT_DIR/ssh-hardening.sh"
    assert_success
}

@test "ssh-hardening: contains required metadata" {
    run grep -E "^# @id" "$SCRIPT_DIR/ssh-hardening.sh"
    assert_success

    run grep -E "^# @category.*security" "$SCRIPT_DIR/ssh-hardening.sh"
    assert_success
}

@test "ssh-hardening: script is executable" {
    assert_file_executable "$SCRIPT_DIR/ssh-hardening.sh"
}

# =============================================================================
# Safety Tests
# =============================================================================

@test "ssh-hardening: references sshd_config" {
    run grep -E "sshd_config|SSHD" "$SCRIPT_DIR/ssh-hardening.sh"
    assert_success
}

@test "ssh-hardening: has config validation" {
    # Should validate config with sshd -t before applying
    run grep -E "sshd.*-t|validate|syntax" "$SCRIPT_DIR/ssh-hardening.sh"
    assert_success
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "ssh-hardening: handles unknown option" {
    run bash "$SCRIPT_DIR/ssh-hardening.sh" --unknown-option-xyz 2>&1
    assert_failure
}

# =============================================================================
# Output Tests
# =============================================================================

@test "ssh-hardening: supports verbose output" {
    run bash "$SCRIPT_DIR/ssh-hardening.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-v"
    assert_output --partial "verbose"
}

