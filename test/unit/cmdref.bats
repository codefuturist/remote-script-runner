#!/usr/bin/env bats
# =============================================================================
# Unit Tests for cmdref.sh
# =============================================================================

load '../test_helper'

# Test script location
PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_DIRNAME}")/.." && pwd)"
CMDREF="$PROJECT_ROOT/scripts/system/tools/cmdref.sh"

setup() {
    # Create temporary config directory
    export XDG_CONFIG_HOME="$(mktemp -d)"
}

teardown() {
    # Clean up temporary config
    [[ -n "$XDG_CONFIG_HOME" ]] && rm -rf "$XDG_CONFIG_HOME"
}

# =============================================================================
# Basic Tests
# =============================================================================

@test "cmdref: script exists and is executable" {
    [[ -f "$CMDREF" ]]
    [[ -x "$CMDREF" ]]
}

@test "cmdref: shows version with -v flag" {
    run bash "$CMDREF" -v
    assert_success
    assert_output --partial "Command Reference version 2.1.0"
}

@test "cmdref: shows version with --version flag" {
    run bash "$CMDREF" --version
    assert_success
    assert_output --partial "Command Reference version 2.1.0"
}

@test "cmdref: shows help with -h flag" {
    run bash "$CMDREF" -h
    assert_success
    assert_output --partial "USAGE:"
    assert_output --partial "OPTIONS:"
}

@test "cmdref: shows help with --help flag" {
    run bash "$CMDREF" --help
    assert_success
    assert_output --partial "Browse commands by category"
}

# =============================================================================
# Search Tests
# =============================================================================

@test "cmdref: search finds git commands" {
    run bash "$CMDREF" --search "git"
    assert_success
    assert_output --partial "git"
}

@test "cmdref: search with no match shows warning" {
    run bash "$CMDREF" --search "xyznonexistent123"
    assert_failure
    assert_output --partial "No commands found"
}

# =============================================================================
# Configuration Tests
# =============================================================================

@test "cmdref: creates config directory on startup" {
    run bash "$CMDREF" --version
    assert_success
    [[ -d "$XDG_CONFIG_HOME/rsr/cmdref" ]]
}

@test "cmdref: creates history file on startup" {
    run bash "$CMDREF" --version
    assert_success
    [[ -f "$XDG_CONFIG_HOME/rsr/cmdref/history.txt" ]]
}

@test "cmdref: creates favorites file on startup" {
    run bash "$CMDREF" --version
    assert_success
    [[ -f "$XDG_CONFIG_HOME/rsr/cmdref/favorites.txt" ]]
}

# =============================================================================
# Integration with Repository
# =============================================================================

@test "cmdref: has proper shebang" {
    head -1 "$CMDREF" | grep -q "#!/bin/bash"
}

@test "cmdref: has header documentation" {
    head -20 "$CMDREF" | grep -q "@description"
}

@test "cmdref: includes Git Flow commands" {
    grep -q "gitflow_feature_start" "$CMDREF"
    grep -q "git flow feature start" "$CMDREF"
}

@test "cmdref: includes Make commands" {
    grep -q "make_build" "$CMDREF"
    grep -q "make build" "$CMDREF"
}

@test "cmdref: includes UV commands" {
    grep -q "uv_init" "$CMDREF"
    grep -q "uv init" "$CMDREF"
    grep -q "uv_add" "$CMDREF"
    grep -q "uv_sync" "$CMDREF"
    grep -q "uvx" "$CMDREF"
}

@test "cmdref: includes sed/regex replacement commands" {
    grep -q "sed_replace" "$CMDREF"
    grep -q "sed_regex" "$CMDREF"
    grep -q "sed_recursive" "$CMDREF"
    grep -q "sed_preview" "$CMDREF"
    grep -q "sed_backup" "$CMDREF"
    grep -q "awk_replace" "$CMDREF"
}

@test "cmdref: includes Yarn commands" {
    grep -q "yarn_init" "$CMDREF"
    grep -q "yarn_add" "$CMDREF"
    grep -q "yarn_upgrade" "$CMDREF"
}

@test "cmdref: includes pnpm commands" {
    grep -q "pnpm_init" "$CMDREF"
    grep -q "pnpm_add" "$CMDREF"
    grep -q "pnpm_update" "$CMDREF"
}

@test "cmdref: includes Go commands" {
    grep -q "go_mod_init" "$CMDREF"
    grep -q "go_build" "$CMDREF"
    grep -q "go_test" "$CMDREF"
}

@test "cmdref: includes Rust/Cargo commands" {
    grep -q "cargo_new" "$CMDREF"
    grep -q "cargo_build" "$CMDREF"
    grep -q "cargo_test" "$CMDREF"
}

@test "cmdref: includes Ruby/Bundler commands" {
    grep -q "bundle_init" "$CMDREF"
    grep -q "gem_install" "$CMDREF"
    grep -q "bundle_exec" "$CMDREF"
}

@test "cmdref: includes PHP/Composer commands" {
    grep -q "composer_init" "$CMDREF"
    grep -q "composer_require" "$CMDREF"
    grep -q "phpunit_test" "$CMDREF"
}

@test "cmdref: includes Java/Maven commands" {
    grep -q "mvn_compile" "$CMDREF"
    grep -q "mvn_test" "$CMDREF"
    grep -q "mvn_package" "$CMDREF"
}

@test "cmdref: includes Java/Gradle commands" {
    grep -q "gradle_init" "$CMDREF"
    grep -q "gradle_build" "$CMDREF"
    grep -q "gradle_test" "$CMDREF"
}

@test "cmdref: includes .NET commands" {
    grep -q "dotnet_new" "$CMDREF"
    grep -q "dotnet_build" "$CMDREF"
    grep -q "dotnet_run" "$CMDREF"
}

@test "cmdref: includes Swift commands" {
    grep -q "swift_init" "$CMDREF"
    grep -q "swift_build" "$CMDREF"
    grep -q "swift_test" "$CMDREF"
}

@test "cmdref: list mode works" {
    run bash "$CMDREF" --list
    assert_success
    assert_output --partial "All Available Commands"
}

# =============================================================================
# New Feature Tests (v2.0)
# =============================================================================

@test "cmdref: --tip shows random command" {
    run bash "$CMDREF" --tip
    assert_success
    assert_output --partial "Tip of the Day"
}

@test "cmdref: --category lists docker commands" {
    run bash "$CMDREF" --category docker
    assert_success
    assert_output --partial "Docker"
}

@test "cmdref: --category with invalid name shows error" {
    run bash "$CMDREF" --category nonexistent
    assert_failure
    assert_output --partial "Category not found"
}

@test "cmdref: --copy copies command to clipboard" {
    run bash "$CMDREF" --copy git_status
    assert_success
    assert_output --partial "git status"
}

@test "cmdref: --copy with invalid key shows error" {
    run bash "$CMDREF" --copy nonexistent_command_xyz
    assert_failure
    assert_output --partial "Command not found"
}

@test "cmdref: --json with --list outputs JSON" {
    run bash "$CMDREF" --json --list
    assert_success
    assert_output --partial '{"commands":['
}

@test "cmdref: --json with --tip outputs JSON" {
    run bash "$CMDREF" --json --tip
    assert_success
    assert_output --partial '"key":'
    assert_output --partial '"command":'
}

@test "cmdref: --stats works" {
    run bash "$CMDREF" --stats
    assert_success
}

@test "cmdref: creates custom_commands.yaml on startup" {
    run bash "$CMDREF" --version
    assert_success
    [[ -f "$XDG_CONFIG_HOME/rsr/cmdref/custom_commands.yaml" ]]
}

@test "cmdref: creates stats.json on startup" {
    run bash "$CMDREF" --version
    assert_success
    [[ -f "$XDG_CONFIG_HOME/rsr/cmdref/stats.json" ]]
}

@test "cmdref: creates aliases.txt on startup" {
    run bash "$CMDREF" --version
    assert_success
    [[ -f "$XDG_CONFIG_HOME/rsr/cmdref/aliases.txt" ]]
}

# =============================================================================
# History Feature Tests
# =============================================================================

@test "cmdref: --history with empty history shows warning" {
    run bash "$CMDREF" --history
    assert_success
    assert_output --partial "No history yet"
}

@test "cmdref: --from-history with empty history shows warning" {
    run bash "$CMDREF" --from-history
    assert_failure
    assert_output --partial "No history yet"
}

@test "cmdref: creates history.txt on startup" {
    run bash "$CMDREF" --version
    assert_success
    [[ -f "$XDG_CONFIG_HOME/rsr/cmdref/history.txt" ]]
}

@test "cmdref: view_favorites function exists" {
    grep -q "view_favorites()" "$CMDREF"
}

@test "cmdref: view_history function exists" {
    grep -q "view_history()" "$CMDREF"
}

@test "cmdref: add_command_from_history function exists" {
    grep -q "add_command_from_history()" "$CMDREF"
}

