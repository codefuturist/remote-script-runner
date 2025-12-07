#!/usr/bin/env bats
# =============================================================================
# Unit Tests for firewall-setup.sh
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

@test "firewall-setup: shows help with -h flag" {
    run bash "$SCRIPT_DIR/firewall-setup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Firewall"
    assert_output --partial "Usage"
}

@test "firewall-setup: shows help with --help flag" {
    run bash "$SCRIPT_DIR/firewall-setup.sh" --help
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Options"
}

@test "firewall-setup: help shows presets" {
    run bash "$SCRIPT_DIR/firewall-setup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "minimal"
    assert_output --partial "web"
}

@test "firewall-setup: help shows examples" {
    run bash "$SCRIPT_DIR/firewall-setup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Examples"
}

# =============================================================================
# Preset Options Tests
# =============================================================================

@test "firewall-setup: supports --preset option" {
    run bash "$SCRIPT_DIR/firewall-setup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-p"
    assert_output --partial "preset"
}

@test "firewall-setup: supports minimal preset" {
    run bash "$SCRIPT_DIR/firewall-setup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "minimal"
}

@test "firewall-setup: supports web preset" {
    run bash "$SCRIPT_DIR/firewall-setup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "web"
}

@test "firewall-setup: supports database preset" {
    run bash "$SCRIPT_DIR/firewall-setup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "database"
}

# =============================================================================
# Port Management Tests
# =============================================================================

@test "firewall-setup: supports --allow option" {
    run bash "$SCRIPT_DIR/firewall-setup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-a"
    assert_output --partial "allow"
}

@test "firewall-setup: supports --deny option" {
    run bash "$SCRIPT_DIR/firewall-setup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-D"
    assert_output --partial "deny"
}

@test "firewall-setup: supports --allow-from option" {
    run bash "$SCRIPT_DIR/firewall-setup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--allow-from"
}

@test "firewall-setup: supports --rate-limit option" {
    run bash "$SCRIPT_DIR/firewall-setup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--rate-limit"
}

# =============================================================================
# Control Options Tests
# =============================================================================

@test "firewall-setup: supports --status option" {
    run bash "$SCRIPT_DIR/firewall-setup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--status"
}

@test "firewall-setup: supports --enable option" {
    run bash "$SCRIPT_DIR/firewall-setup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--enable"
}

@test "firewall-setup: supports --disable option" {
    run bash "$SCRIPT_DIR/firewall-setup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--disable"
}

@test "firewall-setup: supports --backup option" {
    run bash "$SCRIPT_DIR/firewall-setup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "--backup"
}

@test "firewall-setup: supports --dry-run option" {
    run bash "$SCRIPT_DIR/firewall-setup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-d"
    assert_output --partial "dry"
}

# =============================================================================
# Syntax and Structure Tests
# =============================================================================

@test "firewall-setup: has valid bash syntax" {
    run bash -n "$SCRIPT_DIR/firewall-setup.sh"
    assert_success
}

@test "firewall-setup: contains required metadata" {
    run grep -E "^# @id" "$SCRIPT_DIR/firewall-setup.sh"
    assert_success

    run grep -E "^# @category.*security" "$SCRIPT_DIR/firewall-setup.sh"
    assert_success
}

@test "firewall-setup: script is executable" {
    assert_file_executable "$SCRIPT_DIR/firewall-setup.sh"
}

@test "firewall-setup: detects firewall type" {
    # Should detect ufw, firewalld, or iptables
    run grep -E "ufw|firewalld|iptables|nftables" "$SCRIPT_DIR/firewall-setup.sh"
    assert_success
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "firewall-setup: handles unknown option" {
    run bash "$SCRIPT_DIR/firewall-setup.sh" --unknown-option-xyz 2>&1
    assert_failure
}

# =============================================================================
# Output Tests
# =============================================================================

@test "firewall-setup: supports verbose output" {
    run bash "$SCRIPT_DIR/firewall-setup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial -- "-v"
    assert_output --partial "verbose"
}

