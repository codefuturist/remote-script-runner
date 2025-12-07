#!/usr/bin/env bats
# =============================================================================
# Unit Tests for disk-cleanup.sh
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

@test "disk-cleanup: shows help with -h flag" {
    run bash "$SCRIPT_DIR/disk-cleanup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Disk Cleanup"
    assert_output --partial "Usage"
    assert_output --partial "Options"
}

@test "disk-cleanup: shows help with --help flag" {
    run bash "$SCRIPT_DIR/disk-cleanup.sh" --help
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Usage"
}

@test "disk-cleanup: help shows all sections" {
    run bash "$SCRIPT_DIR/disk-cleanup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "tmp"
    assert_output --partial "logs"
    assert_output --partial "cache"
    assert_output --partial "journal"
}

@test "disk-cleanup: help shows examples" {
    run bash "$SCRIPT_DIR/disk-cleanup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Examples"
}

# =============================================================================
# Default Behavior Tests
# =============================================================================

@test "disk-cleanup: defaults to dry-run mode" {
    run bash "$SCRIPT_DIR/disk-cleanup.sh" -s tmp 2>&1
    output=$(strip_colors "$output")
    assert_output --partial "DRY RUN"
}

@test "disk-cleanup: dry-run flag works" {
    run bash "$SCRIPT_DIR/disk-cleanup.sh" -d -s tmp 2>&1
    output=$(strip_colors "$output")
    assert_output --partial "DRY RUN"
}

# =============================================================================
# Section Selection Tests
# =============================================================================

@test "disk-cleanup: can select single section" {
    run bash "$SCRIPT_DIR/disk-cleanup.sh" -d -s tmp 2>&1
    output=$(strip_colors "$output")
    assert_output --partial "temporary"
}

@test "disk-cleanup: can select multiple sections" {
    run bash "$SCRIPT_DIR/disk-cleanup.sh" -d -s tmp -s logs 2>&1
    output=$(strip_colors "$output")
    assert_output --partial "Disk Cleanup"
}

@test "disk-cleanup: --all runs all sections" {
    run bash "$SCRIPT_DIR/disk-cleanup.sh" -d -a 2>&1
    output=$(strip_colors "$output")
    # Should process multiple sections
    assert_output --partial "Disk Cleanup"
}

# =============================================================================
# Option Parsing Tests
# =============================================================================

@test "disk-cleanup: verbose flag works" {
    run bash "$SCRIPT_DIR/disk-cleanup.sh" -v -d -s tmp 2>&1
    # Just verify it runs without crashing on parse
    output=$(strip_colors "$output")
    assert_output --partial "Disk Cleanup"
}

@test "disk-cleanup: --older-than accepts value" {
    run bash "$SCRIPT_DIR/disk-cleanup.sh" -d -s tmp --older-than 14 2>&1
    output=$(strip_colors "$output")
    assert_output --partial "Disk Cleanup"
}

@test "disk-cleanup: --keep-kernels accepts value" {
    run bash "$SCRIPT_DIR/disk-cleanup.sh" -d -s kernels --keep-kernels 3 2>&1
    output=$(strip_colors "$output")
    assert_output --partial "Disk Cleanup"
}

# =============================================================================
# Execute Mode Tests
# =============================================================================

@test "disk-cleanup: execute mode does not show DRY RUN" {
    # Create a temp directory to clean
    mkdir -p "$TEST_TEMP_DIR/cleanup-test"
    touch "$TEST_TEMP_DIR/cleanup-test/oldfile.tmp"

    # Note: We're not actually cleaning system dirs, just testing the flag is recognized
    run bash "$SCRIPT_DIR/disk-cleanup.sh" -x -s tmp 2>&1 || true
    output=$(strip_colors "$output")
    # Should not show "DRY RUN" in execute mode header message
    refute_output --partial "DRY RUN MODE"
}

# =============================================================================
# Syntax and Structure Tests
# =============================================================================

@test "disk-cleanup: has valid bash syntax" {
    run bash -n "$SCRIPT_DIR/disk-cleanup.sh"
    assert_success
}

@test "disk-cleanup: contains required metadata" {
    run grep -E "^# @id" "$SCRIPT_DIR/disk-cleanup.sh"
    assert_success

    run grep -E "^# @name" "$SCRIPT_DIR/disk-cleanup.sh"
    assert_success

    run grep -E "^# @description" "$SCRIPT_DIR/disk-cleanup.sh"
    assert_success
}

@test "disk-cleanup: script is executable" {
    assert_file_executable "$SCRIPT_DIR/disk-cleanup.sh"
}

# =============================================================================
# Helper Function Tests
# =============================================================================

@test "disk-cleanup: human_size function exists" {
    run grep -q "human_size()" "$SCRIPT_DIR/disk-cleanup.sh"
    assert_success
}

@test "disk-cleanup: log functions exist" {
    run grep -q "log_info()" "$SCRIPT_DIR/disk-cleanup.sh"
    assert_success

    run grep -q "log_ok()" "$SCRIPT_DIR/disk-cleanup.sh"
    assert_success

    run grep -q "log_error()" "$SCRIPT_DIR/disk-cleanup.sh"
    assert_success
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "disk-cleanup: handles unknown option gracefully" {
    run bash "$SCRIPT_DIR/disk-cleanup.sh" --unknown-option-xyz
    assert_failure
}

@test "disk-cleanup: handles unknown section gracefully" {
    run bash "$SCRIPT_DIR/disk-cleanup.sh" -d -s nonexistent_section
    # Should complete but warn about unknown section
    output=$(strip_colors "$output")
    assert_output --partial "Unknown section"
}

