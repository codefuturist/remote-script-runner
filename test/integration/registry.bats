#!/usr/bin/env bats
# =============================================================================
# Integration Tests for Registry
# =============================================================================

load '../test_helper'

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

# =============================================================================
# Registry File Tests
# =============================================================================

@test "registry: registry.json exists" {
    assert_file_exist "$PROJECT_ROOT/scripts/registry.json"
}

@test "registry: registry.json is valid JSON" {
    require_command "jq"
    run jq '.' "$PROJECT_ROOT/scripts/registry.json"
    assert_success
}

@test "registry: registry.json has scripts array" {
    require_command "jq"
    run jq '.scripts' "$PROJECT_ROOT/scripts/registry.json"
    assert_success
    refute_output "null"
}

@test "registry: registry.json has version field" {
    require_command "jq"
    run jq -r '.version' "$PROJECT_ROOT/scripts/registry.json"
    assert_success
    refute_output "null"
}

# =============================================================================
# Script Entry Tests
# =============================================================================

@test "registry: health script is registered" {
    require_command "jq"
    run jq -r '.scripts[] | select(.id == "health") | .name' "$PROJECT_ROOT/scripts/registry.json"
    assert_success
    assert_output "system-health-check"
}

@test "registry: cleanup script is registered" {
    require_command "jq"
    run jq -r '.scripts[] | select(.id == "cleanup") | .name' "$PROJECT_ROOT/scripts/registry.json"
    assert_success
    assert_output "disk-cleanup"
}

@test "registry: ssl script is registered" {
    require_command "jq"
    run jq -r '.scripts[] | select(.id == "ssl") | .name' "$PROJECT_ROOT/scripts/registry.json"
    assert_success
    assert_output "ssl-checker"
}

# =============================================================================
# Script File Existence Tests
# =============================================================================

@test "registry: system-health-check.sh exists" {
    assert_file_exist "$PROJECT_ROOT/scripts/bash/system-health-check.sh"
}

@test "registry: disk-cleanup.sh exists" {
    assert_file_exist "$PROJECT_ROOT/scripts/bash/disk-cleanup.sh"
}

@test "registry: ssl-checker.sh exists" {
    assert_file_exist "$PROJECT_ROOT/scripts/bash/ssl-checker.sh"
}

@test "registry: user-audit.sh exists" {
    assert_file_exist "$PROJECT_ROOT/scripts/bash/user-audit.sh"
}

@test "registry: system-update.sh exists" {
    assert_file_exist "$PROJECT_ROOT/scripts/bash/system-update.sh"
}

@test "registry: security-audit.sh exists" {
    assert_file_exist "$PROJECT_ROOT/scripts/bash/security-audit.sh"
}

@test "registry: network-diagnostics.sh exists" {
    assert_file_exist "$PROJECT_ROOT/scripts/bash/network-diagnostics.sh"
}

@test "registry: ssh-hardening.sh exists" {
    assert_file_exist "$PROJECT_ROOT/scripts/bash/ssh-hardening.sh"
}

@test "registry: firewall-setup.sh exists" {
    assert_file_exist "$PROJECT_ROOT/scripts/bash/firewall-setup.sh"
}

@test "registry: config-backup.sh exists" {
    assert_file_exist "$PROJECT_ROOT/scripts/bash/config-backup.sh"
}

@test "registry: database-backup.sh exists" {
    assert_file_exist "$PROJECT_ROOT/scripts/bash/database-backup.sh"
}

# =============================================================================
# Script Metadata Tests
# =============================================================================

@test "registry: all bash scripts have metadata headers" {
    for script in "$PROJECT_ROOT/scripts/bash/"*.sh; do
        run grep -E "^# @id" "$script"
        assert_success
    done
}

# =============================================================================
# Validation Tool Tests
# =============================================================================

@test "registry: validate.sh exists and is executable" {
    assert_file_exist "$PROJECT_ROOT/tools/validate.sh"
    assert_file_executable "$PROJECT_ROOT/tools/validate.sh"
}

@test "registry: build-registry.sh exists and is executable" {
    assert_file_exist "$PROJECT_ROOT/tools/build-registry.sh"
    assert_file_executable "$PROJECT_ROOT/tools/build-registry.sh"
}

