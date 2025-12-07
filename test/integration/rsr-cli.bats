#!/usr/bin/env bats
# =============================================================================
# Integration Tests for rsr CLI
# =============================================================================

load '../test_helper'

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

# =============================================================================
# Basic CLI Tests
# =============================================================================

@test "rsr: shows help with no arguments" {
    run "$PROJECT_ROOT/rsr"
    # Should show help or list of commands
    output=$(strip_colors "$output")
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"Commands"* ]] || [[ "$output" == *"rsr"* ]]
}

@test "rsr: shows help with -h flag" {
    run "$PROJECT_ROOT/rsr" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Usage"
}

@test "rsr: shows help with --help flag" {
    run "$PROJECT_ROOT/rsr" --help
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Usage"
}

@test "rsr: shows version with -V flag" {
    run "$PROJECT_ROOT/rsr" -V
    assert_success
    output=$(strip_colors "$output")
    # Should contain version number
    [[ "$output" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "rsr: shows version with --version flag" {
    run "$PROJECT_ROOT/rsr" --version
    assert_success
    output=$(strip_colors "$output")
    [[ "$output" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

# =============================================================================
# Command Discovery Tests
# =============================================================================

@test "rsr: lists available commands with list" {
    run "$PROJECT_ROOT/rsr" list
    assert_success
    output=$(strip_colors "$output")
    # Should list at least some known commands
    assert_output --partial "health"
}

@test "rsr: recognizes health command" {
    run "$PROJECT_ROOT/rsr" health -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Health"
}

@test "rsr: recognizes cleanup command" {
    run "$PROJECT_ROOT/rsr" cleanup -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Cleanup"
}

@test "rsr: recognizes ssl command" {
    run "$PROJECT_ROOT/rsr" ssl -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "SSL"
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "rsr: handles unknown command gracefully" {
    run "$PROJECT_ROOT/rsr" nonexistent-command-xyz 2>&1
    assert_failure
    output=$(strip_colors "$output")
    # Should show error message
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"Unknown"* ]] || [[ "$output" == *"unknown"* ]]
}

# =============================================================================
# Script Syntax Tests
# =============================================================================

@test "rsr: main script has valid syntax" {
    run sh -n "$PROJECT_ROOT/rsr"
    assert_success
}

@test "rsr: main script is executable" {
    assert_file_executable "$PROJECT_ROOT/rsr"
}

# =============================================================================
# Environment Tests
# =============================================================================

@test "rsr: respects RSR_VERBOSE environment variable" {
    export RSR_VERBOSE=1
    run "$PROJECT_ROOT/rsr" -h
    assert_success
}

@test "rsr: respects NO_COLOR environment variable" {
    export NO_COLOR=1
    run "$PROJECT_ROOT/rsr" -h
    assert_success
}

