# Testing Documentation

This document describes the testing strategy and infrastructure for the Remote Script Runner project.

## Overview

The project uses [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System) for automated testing. BATS provides a simple way to test bash scripts with a clean TAP-compliant output format.

## Test Infrastructure

### Directory Structure

```
test/
├── run_tests.sh        # Main test runner
├── test_helper.bash    # Shared utilities and fixtures
├── libs/               # BATS libraries (git submodules)
├── unit/               # Unit tests for each script
├── integration/        # Integration tests
├── fixtures/           # Test data files
└── mocks/              # Mock external commands
```

### BATS Libraries

The following BATS libraries are included as git submodules:

- **bats-core**: Core testing framework
- **bats-support**: Support functions for assertions
- **bats-assert**: Assertion functions (assert_success, assert_output, etc.)
- **bats-file**: File-related assertions (assert_file_exist, etc.)

## Running Tests

### Prerequisites

```bash
# Install BATS (macOS)
brew install bats-core

# Install BATS (Ubuntu/Debian)
sudo apt-get install bats

# Initialize submodules
git submodule update --init --recursive
```

### Basic Usage

```bash
# Run all tests
./test/run_tests.sh

# Run unit tests only
./test/run_tests.sh --unit

# Run integration tests only
./test/run_tests.sh --integration

# Run specific test file
./test/run_tests.sh test/unit/disk-cleanup.bats

# Run with verbose output
./test/run_tests.sh --verbose

# List available tests
./test/run_tests.sh --list
```

### CI Integration

Tests run automatically on GitHub Actions for:
- Push to `main` or `develop` branches
- Pull requests to `main`

The CI workflow includes:
1. Syntax checking with `bash -n`
2. Static analysis with ShellCheck
3. Unit tests
4. Integration tests
5. Registry validation

## Test Categories

### Unit Tests

Unit tests validate individual script functionality:

| Script | Test File | Coverage |
|--------|-----------|----------|
| disk-cleanup.sh | disk-cleanup.bats | Help, options, sections, dry-run |
| ssl-checker.sh | ssl-checker.bats | Help, options, exit codes |
| user-audit.sh | user-audit.bats | Help, sections, filters |
| system-update.sh | system-update.bats | Help, options, pkg manager |
| security-audit.sh | security-audit.bats | Help, sections, severity |
| network-diagnostics.sh | network-diagnostics.bats | Help, options, sections |
| ssh-hardening.sh | ssh-hardening.bats | Help, options, safety |
| firewall-setup.sh | firewall-setup.bats | Help, presets, options |
| config-backup.sh | config-backup.bats | Help, sections, options |
| database-backup.sh | database-backup.bats | Help, db types, options |

### Integration Tests

Integration tests validate how components work together:

| Test File | Coverage |
|-----------|----------|
| rsr-cli.bats | CLI commands, help, version |
| registry.bats | Registry validation, script existence |
| common-lib.bats | Shared library functions |

## Test Helper

The `test_helper.bash` file provides:

### Setup/Teardown

```bash
setup_test_env()     # Create temp dirs, set PATH
teardown_test_env()  # Cleanup temp files
```

### Mocking

```bash
mock_command "apt-get" "output" 0       # Create mock command
mock_command_capture "mysqldump"        # Mock that logs args
assert_mock_called_with "cmd" "arg"     # Verify mock call
```

### Utilities

```bash
strip_colors "$output"          # Remove ANSI codes
run_script "script.sh" "-h"     # Run with color stripping
run_rsr "health" "-a"           # Run main CLI
fixture_path "file.txt"         # Get fixture path
```

### Platform Detection

```bash
is_macos            # Check if macOS
is_linux            # Check if Linux
require_linux       # Skip if not Linux
require_root        # Skip if not root
require_command "cmd"  # Skip if cmd missing
```

## Mocking Strategy

External commands are mocked to ensure tests are:
- Isolated from system state
- Reproducible across environments
- Fast to execute

### Available Mocks

| Mock | Purpose |
|------|---------|
| apt-get | Package manager operations |
| openssl | SSL certificate checks |
| mysqldump | MySQL database dumps |
| pg_dump | PostgreSQL database dumps |
| ufw | Firewall operations |
| systemctl | Service management |

### Creating New Mocks

```bash
#!/bin/bash
# test/mocks/my-command
echo "mock output"
exit 0
```

Make executable: `chmod +x test/mocks/my-command`

## Fixtures

Test fixtures provide consistent test data:

| Fixture | Purpose |
|---------|---------|
| domains.txt | List of domains for SSL tests |
| sshd_config.sample | SSH config for hardening tests |
| passwd.sample | User list for audit tests |

### Using Fixtures

```bash
@test "reads config file" {
    local config=$(fixture_path "sshd_config.sample")
    run bash "$SCRIPT_DIR/ssh-hardening.sh" --config "$config"
    assert_success
}
```

## Coverage Goals

| Area | Target | Rationale |
|------|--------|-----------|
| CLI Options | 100% | All options should be tested |
| Help Output | 100% | Basic functionality |
| Exit Codes | 100% | Contract with users |
| Dry-run Mode | 100% | Safety critical |
| Helper Functions | 90% | Core utilities |
| System Changes | 0% | Use dry-run only |

## Best Practices

### 1. Test Dry-Run First

Never test actual system modifications. Use dry-run mode:

```bash
@test "cleanup in dry-run mode" {
    run bash "$SCRIPT_DIR/disk-cleanup.sh" -d -a
    assert_success
    assert_output --partial "DRY RUN"
}
```

### 2. Use Fixtures

Don't rely on system state:

```bash
@test "parses domain list" {
    run bash "$SCRIPT_DIR/ssl-checker.sh" -f "$(fixture_path domains.txt)"
    assert_success
}
```

### 3. Mock External Commands

```bash
@test "detects apt" {
    mock_command "apt-get" "mock output"
    run detect_package_manager
    assert_output "apt"
}
```

### 4. Strip Colors for Assertions

```bash
@test "shows usage" {
    run bash "$SCRIPT_DIR/script.sh" -h
    output=$(strip_colors "$output")
    assert_output --partial "Usage"
}
```

### 5. Test Both Short and Long Options

```bash
@test "accepts -h flag" {
    run bash "$SCRIPT_DIR/script.sh" -h
    assert_success
}

@test "accepts --help flag" {
    run bash "$SCRIPT_DIR/script.sh" --help
    assert_success
}
```

## Troubleshooting

### BATS Not Found

```bash
# Install via package manager
brew install bats-core  # macOS
apt install bats        # Ubuntu

# Or use submodules
git submodule update --init --recursive
```

### Test Fails on Different Platform

Use platform checks:

```bash
@test "linux only" {
    is_linux || skip "Linux only"
    # test code
}
```

### Debugging Tests

```bash
# Verbose output
./test/run_tests.sh --verbose

# Debug in test
@test "debug example" {
    run some_command
    echo "# status=$status output=$output" >&3
    assert_success
}
```

## Adding New Tests

1. Create test file: `test/unit/new-script.bats`
2. Use standard template:

```bash
#!/usr/bin/env bats

load '../test_helper'

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "new-script: shows help" {
    run bash "$SCRIPT_DIR/new-script.sh" -h
    assert_success
}
```

3. Run tests: `./test/run_tests.sh test/unit/new-script.bats`
4. Add to CI if needed

