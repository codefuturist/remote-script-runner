A#!/usr/bin/env bats
# =============================================================================
# Unit Tests for system-update.sh
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

@test "system-update: shows help with -h flag" {
    run bash "$SCRIPT_DIR/system-update.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "System Update"
    assert_output --partial "Usage"
}

@test "system-update: shows help with --help flag" {
    run bash "$SCRIPT_DIR/system-update.sh" --help
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Options"
}

@test "system-update: help shows examples" {
    run bash "$SCRIPT_DIR/system-update.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Examples"
}

# =============================================================================
# Check Mode Tests
# =============================================================================

@test "system-update: supports --check option" {
    run bash "$SCRIPT_DIR/system-update.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-c"
    assert_output --partial "check"
}

@test "system-update: supports --list option" {
    run bash "$SCRIPT_DIR/system-update.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-l"
    assert_output --partial "list"
}

# =============================================================================
# Update Options Tests
# =============================================================================

@test "system-update: supports --all option" {
    run bash "$SCRIPT_DIR/system-update.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-a"
    assert_output --partial "all"
}

@test "system-update: supports --security option" {
    run bash "$SCRIPT_DIR/system-update.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--security"
}

@test "system-update: supports --exclude option" {
    run bash "$SCRIPT_DIR/system-update.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-e"
    assert_output --partial "exclude"
}

@test "system-update: supports --yes non-interactive option" {
    run bash "$SCRIPT_DIR/system-update.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-y"
}

@test "system-update: supports --dry-run option" {
    run bash "$SCRIPT_DIR/system-update.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-d"
    assert_output --partial "dry"
}

# =============================================================================
# Reboot Check Tests
# =============================================================================

@test "system-update: supports --reboot-required option" {
    run bash "$SCRIPT_DIR/system-update.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--reboot"
}

# =============================================================================
# Syntax and Structure Tests
# =============================================================================

@test "system-update: has valid bash syntax" {
    run bash -n "$SCRIPT_DIR/system-update.sh"
    assert_success
}

@test "system-update: contains required metadata" {
    run grep -E "^# @id" "$SCRIPT_DIR/system-update.sh"
    assert_success

    run grep -E "^# @category.*maintenance" "$SCRIPT_DIR/system-update.sh"
    assert_success
}

@test "system-update: script is executable" {
    assert_file_executable "$SCRIPT_DIR/system-update.sh"
}

# =============================================================================
# Package Manager Detection Tests
# =============================================================================

@test "system-update: detects package manager" {
    # The script should have package manager detection logic
    run grep -E "apt|yum|dnf|pacman|zypper|apk" "$SCRIPT_DIR/system-update.sh"
    assert_success
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "system-update: handles unknown option" {
    run bash "$SCRIPT_DIR/system-update.sh" --unknown-option-xyz 2>&1
    assert_failure
}

# =============================================================================
# Output Format Tests
# =============================================================================

@test "system-update: supports verbose output" {
    run bash "$SCRIPT_DIR/system-update.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-v"
    assert_output --partial "verbose"
}

