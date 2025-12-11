#!/usr/bin/env bats
# test/lib/test_users.bats - Tests for RSR Users Module
#
# Run with: bats test/lib/test_users.bats
# Note: Some tests require root privileges

setup() {
    export RSR_NO_COLOR=1
    source "${BATS_TEST_DIRNAME}/../../lib/core/init.sh"
    source "${BATS_TEST_DIRNAME}/../../lib/modules/users.sh"
}

# =============================================================================
# User Existence Tests
# =============================================================================

@test "rsr_user_exists returns 0 for existing user" {
    # root/administrator always exists
    run rsr_user_exists "root"
    [ "$status" -eq 0 ]
}

@test "rsr_user_exists returns 1 for non-existing user" {
    run rsr_user_exists "nonexistent_user_12345"
    [ "$status" -eq 1 ]
}

@test "rsr_user_exists returns 1 for empty username" {
    run rsr_user_exists ""
    [ "$status" -eq 1 ]
}

# =============================================================================
# User Info Tests
# =============================================================================

@test "rsr_user_info returns info for existing user" {
    run rsr_user_info "root"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "rsr_user_uid returns numeric UID" {
    run rsr_user_uid "root"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+$ ]]
}

@test "rsr_user_home returns home directory" {
    run rsr_user_home "root"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

# =============================================================================
# User Listing Tests
# =============================================================================

@test "rsr_user_list_all returns users" {
    run rsr_user_list_all
    [ "$status" -eq 0 ]
    [[ "$output" == *"root"* ]]
}

@test "rsr_user_list_humans returns non-empty list" {
    run rsr_user_list_humans
    [ "$status" -eq 0 ]
    # Should have at least root or current user
    [ -n "$output" ]
}

# =============================================================================
# Group Existence Tests
# =============================================================================

@test "rsr_group_exists returns 0 for existing group" {
    # wheel or root group usually exists
    if [ "$(uname)" = "Darwin" ]; then
        run rsr_group_exists "admin"
    else
        run rsr_group_exists "root"
    fi
    [ "$status" -eq 0 ]
}

@test "rsr_group_exists returns 1 for non-existing group" {
    run rsr_group_exists "nonexistent_group_12345"
    [ "$status" -eq 1 ]
}

@test "rsr_group_exists returns 1 for empty groupname" {
    run rsr_group_exists ""
    [ "$status" -eq 1 ]
}

# =============================================================================
# Group Listing Tests
# =============================================================================

@test "rsr_group_list_all returns groups" {
    run rsr_group_list_all
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "rsr_user_groups returns groups for user" {
    run rsr_user_groups "$(whoami)"
    [ "$status" -eq 0 ]
    # User should be in at least one group
    [ -n "$output" ]
}

# =============================================================================
# Session Info Tests
# =============================================================================

@test "rsr_users_logged_in returns logged in users" {
    run rsr_users_logged_in
    [ "$status" -eq 0 ]
    # In a CI environment, might be empty, but shouldn't error
}

# =============================================================================
# Password Generation Tests
# =============================================================================

@test "rsr_password_generate creates password of default length" {
    run rsr_password_generate
    [ "$status" -eq 0 ]
    [ "${#output}" -eq 17 ]  # 16 chars + newline
}

@test "rsr_password_generate creates password of custom length" {
    run rsr_password_generate 24
    [ "$status" -eq 0 ]
    [ "${#output}" -eq 25 ]  # 24 chars + newline
}

# =============================================================================
# Sudo Check Tests
# =============================================================================

@test "rsr_user_has_sudo returns appropriate value for root" {
    if [ "$(id -u)" -eq 0 ]; then
        run rsr_user_has_sudo "root"
        [ "$status" -eq 0 ]
    else
        skip "Not running as root"
    fi
}

# =============================================================================
# User Creation/Deletion Tests (Require Root)
# =============================================================================

@test "rsr_user_create fails for existing user" {
    run rsr_user_create "root"
    [ "$status" -ne 0 ]
}

@test "rsr_user_delete fails for non-existing user" {
    run rsr_user_delete "nonexistent_user_12345"
    [ "$status" -ne 0 ]
}

@test "rsr_user_lock fails for non-existing user" {
    run rsr_user_lock "nonexistent_user_12345"
    [ "$status" -ne 0 ]
}

@test "rsr_user_unlock fails for non-existing user" {
    run rsr_user_unlock "nonexistent_user_12345"
    [ "$status" -ne 0 ]
}

# =============================================================================
# Group Creation/Deletion Tests (Require Root)
# =============================================================================

@test "rsr_group_create fails for existing group" {
    if [ "$(uname)" = "Darwin" ]; then
        run rsr_group_create "admin"
    else
        run rsr_group_create "root"
    fi
    [ "$status" -ne 0 ]
}

@test "rsr_group_delete fails for non-existing group" {
    run rsr_group_delete "nonexistent_group_12345"
    [ "$status" -ne 0 ]
}

# =============================================================================
# Module Version
# =============================================================================

@test "Users module version is set" {
    [ -n "$_RSR_USERS_VERSION" ]
}

