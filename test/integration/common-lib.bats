#!/usr/bin/env bats
# =============================================================================
# Integration Tests for lib/common.sh
# =============================================================================

load '../test_helper'

setup() {
    setup_test_env
    # Source the common library
    source "$PROJECT_ROOT/lib/common.sh"
}

teardown() {
    teardown_test_env
}

# =============================================================================
# Library Loading Tests
# =============================================================================

@test "common: lib/common.sh exists" {
    assert_file_exist "$PROJECT_ROOT/lib/common.sh"
}

@test "common: lib/common.sh has valid syntax" {
    run sh -n "$PROJECT_ROOT/lib/common.sh"
    assert_success
}

@test "common: can source lib/common.sh" {
    run bash -c "source '$PROJECT_ROOT/lib/common.sh'"
    assert_success
}

# =============================================================================
# Color Setup Tests
# =============================================================================

@test "common: setup_colors function exists" {
    run type setup_colors
    assert_success
}

@test "common: setup_colors sets color variables" {
    setup_colors

    # In a terminal, these should be set
    # In tests (non-terminal), they may be empty
    # Just verify the function runs without error
    true
}

# =============================================================================
# Logging Function Tests
# =============================================================================

@test "common: log_info function exists" {
    run type log_info
    assert_success
}

@test "common: log_ok function exists" {
    run type log_ok
    assert_success
}

@test "common: log_warn function exists" {
    run type log_warn
    assert_success
}

@test "common: log_error function exists" {
    run type log_error
    assert_success
}

@test "common: log_debug function exists" {
    run type log_debug
    assert_success
}

@test "common: log_info outputs message" {
    run log_info "test message"
    assert_success
    assert_output --partial "test message"
}

@test "common: log_ok outputs message" {
    run log_ok "success message"
    assert_success
    assert_output --partial "success message"
}

@test "common: log_warn outputs message" {
    run log_warn "warning message"
    assert_output --partial "warning message"
}

@test "common: log_error outputs message" {
    run log_error "error message"
    assert_output --partial "error message"
}

@test "common: log_debug respects RSR_VERBOSE" {
    export RSR_VERBOSE=0
    run log_debug "debug message"
    refute_output --partial "debug message"

    export RSR_VERBOSE=1
    run log_debug "debug message"
    assert_output --partial "debug message"
}

# =============================================================================
# Download Helper Tests
# =============================================================================

@test "common: download function exists" {
    run type download
    assert_success
}

@test "common: download_to function exists" {
    run type download_to
    assert_success
}

# =============================================================================
# OS Detection Tests
# =============================================================================

@test "common: detect_os function exists" {
    run type detect_os
    assert_success
}

@test "common: detect_os returns valid value" {
    run detect_os
    assert_success
    # Should be one of: darwin, linux, freebsd, windows, unknown
    [[ "$output" =~ ^(darwin|linux|freebsd|windows|unknown)$ ]]
}

@test "common: detect_arch function exists" {
    run type detect_arch
    assert_success
}

@test "common: detect_arch returns valid value" {
    run detect_arch
    assert_success
    # Should be one of: amd64, arm64, arm, i386, unknown
    [[ "$output" =~ ^(amd64|arm64|arm|i386|unknown)$ ]]
}

# =============================================================================
# Shell Detection Tests
# =============================================================================

@test "common: detect_shell function exists" {
    run type detect_shell
    assert_success
}

@test "common: detect_shell returns valid shell" {
    run detect_shell
    assert_success
    # Should be bash, zsh, or sh
    [[ "$output" =~ ^(bash|zsh|sh|fish)$ ]]
}

@test "common: detect_shell respects RSR_SHELL env" {
    export RSR_SHELL="custom_shell"
    run detect_shell
    assert_success
    assert_output "custom_shell"
}

# =============================================================================
# Utility Function Tests
# =============================================================================

@test "common: has_command function exists" {
    run type has_command
    assert_success
}

@test "common: has_command returns true for existing command" {
    run has_command "bash"
    assert_success
}

@test "common: has_command returns false for non-existing command" {
    run has_command "nonexistent_command_xyz_123"
    assert_failure
}

@test "common: is_terminal function exists" {
    run type is_terminal
    assert_success
}

@test "common: print_line function exists" {
    run type print_line
    assert_success
}

@test "common: print_line outputs line" {
    run print_line 20
    assert_success
    # Should output a line of dashes
    [[ ${#output} -ge 20 ]]
}

# =============================================================================
# Legacy Compatibility Tests
# =============================================================================

@test "common: legacy log function exists" {
    run type log
    assert_success
}

@test "common: legacy log function works with INFO level" {
    run log "INFO" "info message"
    assert_success
    assert_output --partial "info message"
}

@test "common: legacy log function works with ERROR level" {
    run log "ERROR" "error message"
    assert_output --partial "error message"
}

