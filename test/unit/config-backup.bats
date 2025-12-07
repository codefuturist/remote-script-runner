#!/usr/bin/env bats
# =============================================================================
# Unit Tests for config-backup.sh
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

@test "config-backup: shows help with -h flag" {
    run bash "$SCRIPT_DIR/config-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Backup"
    assert_output --partial "Usage"
}

@test "config-backup: shows help with --help flag" {
    run bash "$SCRIPT_DIR/config-backup.sh" --help
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Options"
}

@test "config-backup: help shows all sections" {
    run bash "$SCRIPT_DIR/config-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "etc"
    assert_output --partial "packages"
    assert_output --partial "crontab"
}

@test "config-backup: help shows examples" {
    run bash "$SCRIPT_DIR/config-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Examples"
}

# =============================================================================
# Section Selection Tests
# =============================================================================

@test "config-backup: supports --all option" {
    run bash "$SCRIPT_DIR/config-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-a"
    assert_output --partial "all"
}

@test "config-backup: supports --section option" {
    run bash "$SCRIPT_DIR/config-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-s"
    assert_output --partial "section"
}

# =============================================================================
# Output Options Tests
# =============================================================================

@test "config-backup: supports --output option" {
    run bash "$SCRIPT_DIR/config-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-o"
    assert_output --partial "output"
}

@test "config-backup: supports --compress option" {
    run bash "$SCRIPT_DIR/config-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--compress"
    assert_output --partial "gzip"
}

@test "config-backup: supports --encrypt option" {
    run bash "$SCRIPT_DIR/config-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--encrypt"
}

@test "config-backup: supports --gpg-key option" {
    run bash "$SCRIPT_DIR/config-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--gpg-key"
}

# =============================================================================
# Remote Upload Tests
# =============================================================================

@test "config-backup: supports --upload option" {
    run bash "$SCRIPT_DIR/config-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--upload"
}

# =============================================================================
# Retention and Management Tests
# =============================================================================

@test "config-backup: supports --retention option" {
    run bash "$SCRIPT_DIR/config-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--retention"
}

@test "config-backup: supports --list option" {
    run bash "$SCRIPT_DIR/config-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--list"
}

@test "config-backup: supports --restore option" {
    run bash "$SCRIPT_DIR/config-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--restore"
}

@test "config-backup: supports --dry-run option" {
    run bash "$SCRIPT_DIR/config-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-d"
    assert_output --partial "dry"
}

# =============================================================================
# Syntax and Structure Tests
# =============================================================================

@test "config-backup: has valid bash syntax" {
    run bash -n "$SCRIPT_DIR/config-backup.sh"
    assert_success
}

@test "config-backup: contains required metadata" {
    run grep -E "^# @id" "$SCRIPT_DIR/config-backup.sh"
    assert_success

    run grep -E "^# @category.*maintenance" "$SCRIPT_DIR/config-backup.sh"
    assert_success
}

@test "config-backup: script is executable" {
    assert_file_executable "$SCRIPT_DIR/config-backup.sh"
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "config-backup: handles unknown option" {
    run bash "$SCRIPT_DIR/config-backup.sh" --unknown-option-xyz 2>&1
    assert_failure
}

# =============================================================================
# Output Tests
# =============================================================================

@test "config-backup: supports verbose output" {
    run bash "$SCRIPT_DIR/config-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-v"
    assert_output --partial "verbose"
}

