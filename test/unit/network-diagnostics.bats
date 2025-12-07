#!/usr/bin/env bats
# =============================================================================
# Unit Tests for network-diagnostics.sh
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

@test "network-diagnostics: shows help with -h flag" {
    run bash "$SCRIPT_DIR/network-diagnostics.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Network Diagnostics"
    assert_output --partial "Usage"
}

@test "network-diagnostics: shows help with --help flag" {
    run bash "$SCRIPT_DIR/network-diagnostics.sh" --help
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Options"
}

@test "network-diagnostics: help shows all sections" {
    run bash "$SCRIPT_DIR/network-diagnostics.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "connectivity"
    assert_output --partial "dns"
    assert_output --partial "gateway"
    assert_output --partial "interfaces"
}

@test "network-diagnostics: help shows examples" {
    run bash "$SCRIPT_DIR/network-diagnostics.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Examples"
}

# =============================================================================
# Diagnostic Options Tests
# =============================================================================

@test "network-diagnostics: supports --all option" {
    run bash "$SCRIPT_DIR/network-diagnostics.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-a"
    assert_output --partial "all"
}

@test "network-diagnostics: supports --ping option" {
    run bash "$SCRIPT_DIR/network-diagnostics.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--ping"
}

@test "network-diagnostics: supports --dns option" {
    run bash "$SCRIPT_DIR/network-diagnostics.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--dns"
}

@test "network-diagnostics: supports --trace option" {
    run bash "$SCRIPT_DIR/network-diagnostics.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--trace"
}

@test "network-diagnostics: supports --port option" {
    run bash "$SCRIPT_DIR/network-diagnostics.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--port"
}

@test "network-diagnostics: supports --interfaces option" {
    run bash "$SCRIPT_DIR/network-diagnostics.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--interfaces"
}

@test "network-diagnostics: supports --public-ip option" {
    run bash "$SCRIPT_DIR/network-diagnostics.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--public-ip"
}

# =============================================================================
# Section Selection Tests
# =============================================================================

@test "network-diagnostics: can select specific section" {
    run bash "$SCRIPT_DIR/network-diagnostics.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-s"
    assert_output --partial "section"
}

# =============================================================================
# Syntax and Structure Tests
# =============================================================================

@test "network-diagnostics: has valid bash syntax" {
    run bash -n "$SCRIPT_DIR/network-diagnostics.sh"
    assert_success
}

@test "network-diagnostics: contains required metadata" {
    run grep -E "^# @id" "$SCRIPT_DIR/network-diagnostics.sh"
    assert_success

    run grep -E "^# @category.*network" "$SCRIPT_DIR/network-diagnostics.sh"
    assert_success
}

@test "network-diagnostics: script is executable" {
    assert_file_executable "$SCRIPT_DIR/network-diagnostics.sh"
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "network-diagnostics: handles unknown option" {
    run bash "$SCRIPT_DIR/network-diagnostics.sh" --unknown-option-xyz 2>&1
    assert_failure
}

# =============================================================================
# Output Format Tests
# =============================================================================

@test "network-diagnostics: supports verbose output" {
    run bash "$SCRIPT_DIR/network-diagnostics.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-v"
    assert_output --partial "verbose"
}

@test "network-diagnostics: supports timeout option" {
    run bash "$SCRIPT_DIR/network-diagnostics.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-t"
    assert_output --partial "timeout"
}

