#!/usr/bin/env bats
# test/lib/test_docker.bats - Tests for RSR Docker Module
#
# Run with: bats test/lib/test_docker.bats
# Note: Docker must be installed and running for some tests

setup() {
    export RSR_NO_COLOR=1
    source "${BATS_TEST_DIRNAME}/../../lib/core/init.sh"
    source "${BATS_TEST_DIRNAME}/../../lib/modules/docker.sh"
}

# =============================================================================
# Docker Detection Tests
# =============================================================================

@test "rsr_docker_is_installed returns appropriate value" {
    run rsr_docker_is_installed
    # Should succeed or fail depending on Docker installation
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "rsr_docker_version returns version or not_installed" {
    run rsr_docker_version
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^([0-9]+\.[0-9]+|not_installed) ]]
}

@test "rsr_docker_compose_version returns version or not_installed" {
    run rsr_docker_compose_version
    [ "$status" -eq 0 ]
    # Should return a version or not_installed
    [ -n "$output" ]
}

# =============================================================================
# Docker Running Tests (if Docker is installed)
# =============================================================================

@test "rsr_docker_is_running returns appropriate value" {
    if ! rsr_docker_is_installed; then
        skip "Docker not installed"
    fi

    run rsr_docker_is_running
    # Should succeed or fail depending on daemon status
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "rsr_docker_has_permissions returns appropriate value" {
    if ! rsr_docker_is_installed; then
        skip "Docker not installed"
    fi

    run rsr_docker_has_permissions
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

# =============================================================================
# Container Tests (if Docker is running)
# =============================================================================

@test "rsr_docker_container_exists returns 1 for nonexistent container" {
    if ! rsr_docker_is_installed || ! rsr_docker_is_running; then
        skip "Docker not running"
    fi

    run rsr_docker_container_exists "nonexistent_container_12345"
    [ "$status" -eq 1 ]
}

@test "rsr_docker_container_is_running returns 1 for nonexistent container" {
    if ! rsr_docker_is_installed || ! rsr_docker_is_running; then
        skip "Docker not running"
    fi

    run rsr_docker_container_is_running "nonexistent_container_12345"
    [ "$status" -eq 1 ]
}

@test "rsr_docker_container_list runs without error" {
    if ! rsr_docker_is_installed || ! rsr_docker_is_running; then
        skip "Docker not running"
    fi

    run rsr_docker_container_list
    [ "$status" -eq 0 ]
}

@test "rsr_docker_container_list all runs without error" {
    if ! rsr_docker_is_installed || ! rsr_docker_is_running; then
        skip "Docker not running"
    fi

    run rsr_docker_container_list all
    [ "$status" -eq 0 ]
}

# =============================================================================
# Image Tests (if Docker is running)
# =============================================================================

@test "rsr_docker_image_list runs without error" {
    if ! rsr_docker_is_installed || ! rsr_docker_is_running; then
        skip "Docker not running"
    fi

    run rsr_docker_image_list
    [ "$status" -eq 0 ]
}

# =============================================================================
# Volume Tests (if Docker is running)
# =============================================================================

@test "rsr_docker_volume_list runs without error" {
    if ! rsr_docker_is_installed || ! rsr_docker_is_running; then
        skip "Docker not running"
    fi

    run rsr_docker_volume_list
    [ "$status" -eq 0 ]
}

# =============================================================================
# Network Tests (if Docker is running)
# =============================================================================

@test "rsr_docker_network_list runs without error" {
    if ! rsr_docker_is_installed || ! rsr_docker_is_running; then
        skip "Docker not running"
    fi

    run rsr_docker_network_list
    [ "$status" -eq 0 ]
}

# =============================================================================
# Docker Compose Tests
# =============================================================================

@test "rsr_docker_compose_exists returns 1 for empty directory" {
    run rsr_docker_compose_exists "/tmp"
    [ "$status" -eq 1 ]
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "rsr_docker_container_start fails for nonexistent container" {
    if ! rsr_docker_is_installed || ! rsr_docker_is_running; then
        skip "Docker not running"
    fi

    run rsr_docker_container_start "nonexistent_container_12345"
    [ "$status" -ne 0 ]
}

@test "rsr_docker_container_logs fails for nonexistent container" {
    if ! rsr_docker_is_installed || ! rsr_docker_is_running; then
        skip "Docker not running"
    fi

    run rsr_docker_container_logs "nonexistent_container_12345"
    [ "$status" -ne 0 ]
}

@test "rsr_docker_container_exec fails for nonexistent container" {
    if ! rsr_docker_is_installed || ! rsr_docker_is_running; then
        skip "Docker not running"
    fi

    run rsr_docker_container_exec "nonexistent_container_12345" "echo test"
    [ "$status" -ne 0 ]
}

# =============================================================================
# Module Version
# =============================================================================

@test "Docker module version is set" {
    [ -n "$_RSR_DOCKER_VERSION" ]
}

