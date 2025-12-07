# Testing Guide for Remote Script Runner

This directory contains the comprehensive test suite for the Remote Script Runner project using [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System).

## Quick Start

```bash
# Install BATS (macOS)
brew install bats-core

# Or install BATS (Ubuntu/Debian)
sudo apt-get install bats

# Initialize git submodules (includes BATS libraries)
git submodule update --init --recursive

# Run all tests
./test/run_tests.sh

# Run specific test file
./test/run_tests.sh test/unit/disk-cleanup.bats

# Run with verbose output
./test/run_tests.sh --verbose
```

## Directory Structure

```
test/
├── README.md           # This file
├── run_tests.sh        # Main test runner
├── test_helper.bash    # Shared test utilities
├── libs/               # BATS libraries (git submodules)
│   ├── bats-core/
│   ├── bats-support/
│   ├── bats-assert/
│   └── bats-file/
├── unit/               # Unit tests (per script)
│   ├── disk-cleanup.bats
│   ├── ssl-checker.bats
│   ├── user-audit.bats
│   ├── system-update.bats
│   ├── security-audit.bats
│   ├── network-diagnostics.bats
│   ├── ssh-hardening.bats
│   ├── firewall-setup.bats
│   ├── config-backup.bats
│   └── database-backup.bats
├── integration/        # Integration tests
│   ├── rsr-cli.bats
│   ├── registry.bats
│   └── common-lib.bats
├── fixtures/           # Test data and fixtures
│   ├── domains.txt
│   ├── sshd_config.sample
│   └── passwd.sample
└── mocks/              # Mock commands for testing
    ├── apt-get
    ├── openssl
    ├── mysqldump
    ├── pg_dump
    ├── ufw
    └── systemctl
```

## Test Runner Options

```bash
./test/run_tests.sh [OPTIONS] [TEST_FILES...]

Options:
    -h, --help          Show help message
    -v, --verbose       Enable verbose output (show each test)
    -u, --unit          Run only unit tests
    -i, --integration   Run only integration tests
    -l, --list          List all available tests
    -j, --jobs N        Run N tests in parallel (default: auto)
    --no-parallel       Disable parallel execution
    --filter PATTERN    Run only tests matching pattern
    --tap               Output in TAP format
    --junit FILE        Output JUnit XML to file
```

## Writing Tests

### Basic Test Structure

```bash
#!/usr/bin/env bats

load '../test_helper'

setup() {
    # Runs before each test
    setup_test_env
}

teardown() {
    # Runs after each test
    teardown_test_env
}

@test "script shows help with -h flag" {
    run bash "$SCRIPT_DIR/disk-cleanup.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Usage:"
}

@test "script fails with invalid option" {
    run bash "$SCRIPT_DIR/disk-cleanup.sh" --invalid-option
    assert_failure
}
```

### Available Assertions

From `bats-assert`:
- `assert_success` - Exit code is 0
- `assert_failure` - Exit code is non-zero
- `assert_equal expected actual` - Values are equal
- `assert_output expected` - Output matches exactly
- `assert_output --partial text` - Output contains text
- `assert_line --index N expected` - Line N matches
- `refute_output --partial text` - Output does NOT contain

From `bats-file`:
- `assert_file_exist path`
- `assert_file_not_exist path`
- `assert_dir_exist path`
- `assert_file_executable path`
- `assert_file_contains path text`

### Helper Functions

From `test_helper.bash`:

```bash
# Strip ANSI color codes
output=$(strip_colors "$output")

# Run a script with colors stripped
run_script "disk-cleanup.sh" "-h"

# Run the main rsr command
run_rsr "health" "-a"

# Check platform
is_macos && echo "Running on macOS"
is_linux && echo "Running on Linux"

# Skip tests conditionally
require_linux      # Skip if not Linux
require_macos      # Skip if not macOS
require_root       # Skip if not root
require_command "openssl"  # Skip if command not found

# Work with fixtures
fixture_path "domains.txt"  # Get path to fixture
use_fixture "sample-config" "$TEST_TEMP_DIR/config"  # Copy fixture

# Create temporary files
temp_file "content here"
```

### Mocking External Commands

```bash
@test "detects apt package manager" {
    # Create mock apt-get that returns success
    mock_command "apt-get" "apt-get mock output" 0
    
    run bash "$SCRIPT_DIR/disk-cleanup.sh" -d -s cache
    assert_success
    assert_output --partial "APT"
}

@test "captures mysqldump arguments" {
    # Create mock that logs its arguments
    mock_command_capture "mysqldump" "-- MySQL dump"
    
    run bash "$SCRIPT_DIR/database-backup.sh" --mysql -A --dry-run
    
    # Verify mock was called with expected arguments
    assert_mock_called_with "mysqldump" "--all-databases"
}
```

### Testing with Fixtures

Fixtures are located in `test/fixtures/`:

```bash
@test "reads domains from file" {
    run bash "$SCRIPT_DIR/ssl-checker.sh" -f "$(fixture_path domains.txt)"
    assert_success
    assert_output --partial "example.com"
}
```

## Test Categories

### Unit Tests (`test/unit/`)

Test individual scripts in isolation:
- Argument parsing (valid/invalid inputs)
- Help output validation
- Option handling
- Exit codes
- Dry-run mode behavior
- Syntax validation

### Integration Tests (`test/integration/`)

Test how components work together:
- `rsr-cli.bats` - Main CLI command discovery and execution
- `registry.bats` - Registry validation and script existence
- `common-lib.bats` - Shared library functions

## Running in CI

The test suite runs automatically on GitHub Actions when you push to `main` or `develop` branches, or create a pull request.

Tests run on:
- Ubuntu (latest)
- macOS (latest)

The CI workflow:
1. Runs ShellCheck for static analysis
2. Validates bash syntax
3. Runs unit tests
4. Runs integration tests
5. Validates registry.json

See `.github/workflows/test.yml` for configuration.

## Coverage Goals

| Category | Target | Description |
|----------|--------|-------------|
| Argument parsing | 100% | All CLI options should be tested |
| Help output | 100% | Every script's -h flag |
| Exit codes | 100% | All documented exit codes |
| Dry-run safety | 100% | Verify dry-run prevents changes |
| Helper functions | 90% | Utility functions |
| System-modifying code | Skip | Use dry-run mode only |

## Best Practices

1. **Always test dry-run first** - Scripts default to dry-run mode for safety. Never test actual system modifications.

2. **Use fixtures** - Don't rely on system state. Use fixture files for predictable test data.

3. **Mock external commands** - Use `mock_command` helper for commands like `apt-get`, `openssl`, etc.

4. **Test exit codes** - Every documented exit code should have a test.

5. **Keep tests fast** - Skip slow operations using `skip` for conditional tests.

6. **Test both short and long options** - Test `-h` and `--help`, `-v` and `--verbose`, etc.

7. **Strip colors for assertions** - Use `strip_colors "$output"` before text assertions.

## Troubleshooting

### Tests fail with "command not found: bats"

Install BATS:
```bash
# macOS
brew install bats-core

# Ubuntu/Debian
sudo apt-get install bats

# Or use submodules
git submodule update --init --recursive
```

### Tests fail on Linux but pass on macOS (or vice versa)

Use platform detection:
```bash
@test "linux-specific test" {
    is_linux || skip "Linux only"
    # ... test code
}
```

### Mock not being used

Ensure setup function initializes test environment:
```bash
setup() {
    setup_test_env  # This adds mocks to PATH
}
```

### Tests are slow

Use parallel execution:
```bash
./test/run_tests.sh -j 4  # Run with 4 parallel jobs
```

### Need to debug a test

Run with verbose output:
```bash
./test/run_tests.sh --verbose test/unit/disk-cleanup.bats
```

Or add debug output in tests:
```bash
@test "debugging example" {
    run some_command
    echo "# Debug: status=$status" >&3
    echo "# Debug: output=$output" >&3
    assert_success
}
```

## Adding Tests for New Scripts

When adding a new script:

1. Create unit test file: `test/unit/<script-name>.bats`
2. Copy the template structure from an existing test file
3. Add tests for:
   - Help output (`-h`, `--help`)
   - All CLI options
   - Exit codes
   - Syntax validation
   - Script metadata
4. Run tests to verify: `./test/run_tests.sh test/unit/<script-name>.bats`
5. Add to CI if needed

Template:
```bash
#!/usr/bin/env bats

load '../test_helper'

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "script-name: shows help with -h flag" {
    run bash "$SCRIPT_DIR/script-name.sh" -h
    assert_success
    output=$(strip_colors "$output")
    assert_output --partial "Usage"
}

@test "script-name: has valid bash syntax" {
    run bash -n "$SCRIPT_DIR/script-name.sh"
    assert_success
}

@test "script-name: script is executable" {
    assert_file_executable "$SCRIPT_DIR/script-name.sh"
}
```

