#!/usr/bin/env bats
# =============================================================================
# Unit Tests for database-backup.sh
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

@test "database-backup: shows help with -h flag" {
    run bash "$SCRIPT_DIR/database-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Database Backup"
    assert_output --partial "Usage"
}

@test "database-backup: shows help with --help flag" {
    run bash "$SCRIPT_DIR/database-backup.sh" --help
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Options"
}

@test "database-backup: help shows examples" {
    run bash "$SCRIPT_DIR/database-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Examples"
}

# =============================================================================
# Database Type Tests
# =============================================================================

@test "database-backup: supports --mysql option" {
    run bash "$SCRIPT_DIR/database-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--mysql"
}

@test "database-backup: supports --postgresql option" {
    run bash "$SCRIPT_DIR/database-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--postgresql"
}

@test "database-backup: supports --mongodb option" {
    run bash "$SCRIPT_DIR/database-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--mongodb"
}

@test "database-backup: supports --auto detection" {
    run bash "$SCRIPT_DIR/database-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--auto"
}

# =============================================================================
# Database Selection Tests
# =============================================================================

@test "database-backup: supports -d database option" {
    run bash "$SCRIPT_DIR/database-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-d"
    assert_output --partial "database"
}

@test "database-backup: supports --all-databases option" {
    run bash "$SCRIPT_DIR/database-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-A"
    assert_output --partial "all"
}

@test "database-backup: supports --schema-only option" {
    run bash "$SCRIPT_DIR/database-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--schema"
}

# =============================================================================
# Output Options Tests
# =============================================================================

@test "database-backup: supports --compress option" {
    run bash "$SCRIPT_DIR/database-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--compress"
}

@test "database-backup: supports --encrypt option" {
    run bash "$SCRIPT_DIR/database-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--encrypt"
}

@test "database-backup: supports --upload option" {
    run bash "$SCRIPT_DIR/database-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--upload"
}

# =============================================================================
# Management Tests
# =============================================================================

@test "database-backup: supports --retention option" {
    run bash "$SCRIPT_DIR/database-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--retention"
}

@test "database-backup: supports --list option" {
    run bash "$SCRIPT_DIR/database-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--list"
}

@test "database-backup: supports --restore option" {
    run bash "$SCRIPT_DIR/database-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--restore"
}

@test "database-backup: supports --dry-run option" {
    run bash "$SCRIPT_DIR/database-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "dry"
}

# =============================================================================
# Syntax and Structure Tests
# =============================================================================

@test "database-backup: has valid bash syntax" {
    run bash -n "$SCRIPT_DIR/database-backup.sh"
    assert_success
}

@test "database-backup: contains required metadata" {
    run grep -E "^# @id" "$SCRIPT_DIR/database-backup.sh"
    assert_success

    run grep -E "^# @category.*maintenance" "$SCRIPT_DIR/database-backup.sh"
    assert_success
}

@test "database-backup: script is executable" {
    assert_file_executable "$SCRIPT_DIR/database-backup.sh"
}

@test "database-backup: references dump commands" {
    # Should reference mysqldump or pg_dump
    run grep -E "mysqldump|pg_dump|mongodump" "$SCRIPT_DIR/database-backup.sh"
    assert_success
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "database-backup: handles unknown option" {
    run bash "$SCRIPT_DIR/database-backup.sh" --unknown-option-xyz 2>&1
    assert_failure
}

# =============================================================================
# Output Tests
# =============================================================================

@test "database-backup: supports verbose output" {
    run bash "$SCRIPT_DIR/database-backup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-v"
    assert_output --partial "verbose"
}

