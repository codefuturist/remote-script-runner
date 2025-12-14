# Contributing to Remote Script Runner

Thank you for your interest in contributing! This document provides guidelines and instructions for contributing to the project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Code Style](#code-style)
- [Commit Guidelines](#commit-guidelines)
- [Pull Request Process](#pull-request-process)
- [Testing](#testing)
- [Adding New Scripts](#adding-new-scripts)

## Code of Conduct

Please be respectful and constructive in all interactions. We're all here to learn and improve.

## Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:

   ```bash
   git clone https://github.com/YOUR-USERNAME/remote-script-runner.git
   cd remote-script-runner
   ```

3. **Add the upstream remote**:

   ```bash
   git remote add upstream https://github.com/codefuturist/remote-script-runner.git
   ```

4. **Set up the development environment**:

   ```bash
   make install
   ```

## Development Setup

### Prerequisites

- **macOS** or **Linux** (Windows via WSL)
- **Bash** 4.0+ or **Zsh**
- **Git** 2.0+

### Install Development Tools

```bash
# One-command setup (installs all dependencies + pre-commit hooks)
make install

# Or install manually:
# macOS
brew install shellcheck shfmt bats-core jq pre-commit

# Ubuntu/Debian
sudo apt-get install shellcheck jq
pip install pre-commit
# shfmt: download from https://github.com/mvdan/sh/releases
```

### Initialize the Project

```bash
# Initialize BATS submodules for testing
make init-submodules

# Install pre-commit hooks
make setup-hooks

# Verify everything works
make all
```

## Code Style

### Shell Scripts

We follow the [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html) with these specifics:

- **Indentation**: 4 spaces (no tabs)
- **Line length**: 100 characters soft limit, 120 hard limit
- **Quotes**: Use double quotes for strings, single quotes for literals
- **Functions**: Use `function_name() {` style (no `function` keyword)
- **Variables**: Use lowercase with underscores for local, UPPERCASE for exports

### Formatting with shfmt

All shell scripts are formatted with [shfmt](https://github.com/mvdan/sh). The configuration is:

```bash
shfmt -i 4 -ci -bn -sr
```

- `-i 4`: 4-space indent
- `-ci`: Indent switch cases
- `-bn`: Binary operators at start of line
- `-sr`: Redirect operators followed by space

**Format your code:**

```bash
make format        # Auto-format all scripts
make format-check  # Check without changing
```

### Linting with ShellCheck

All scripts must pass [ShellCheck](https://www.shellcheck.net/) with no errors:

```bash
make lint
```

The `.shellcheckrc` file contains project-wide settings. You can disable specific warnings inline when necessary:

```bash
# shellcheck disable=SC2086
command $unquoted_var
```

### Script Metadata Headers

All scripts must include metadata headers:

```bash
#!/bin/bash
# =============================================================================
# @id           script-id
# @name         script-name
# @displayName  Human Readable Name
# @description  Brief description of what the script does
# @category     category
# @version      1.0.0
# @author       your-name
# @tags         tag1,tag2,tag3
# @shells       bash
# =============================================================================
```

## Commit Guidelines

We use [Conventional Commits](https://www.conventionalcommits.org/) for clear, structured commit history.

### Format

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

### Types

| Type | Description |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `style` | Formatting, no code change |
| `refactor` | Code change without feature/fix |
| `test` | Adding/updating tests |
| `chore` | Maintenance tasks |
| `ci` | CI/CD changes |
| `perf` | Performance improvement |

### Examples

```bash
feat(scripts): add docker-cleanup script
fix(rsr): handle spaces in script paths
docs(readme): add installation instructions
test(ssl-checker): add certificate expiry tests
chore(deps): update bats to v1.10.0
```

### Scope (optional)

Common scopes: `scripts`, `rsr`, `lib`, `test`, `ci`, `docs`

## Pull Request Process

### Before Submitting

1. **Create a feature branch**:

   ```bash
   git checkout -b feat/my-new-feature
   ```

2. **Make your changes** following the code style guidelines

3. **Run all checks**:

   ```bash
   make all  # Runs lint, test, validate
   ```

4. **Commit your changes** using conventional commits

5. **Push to your fork**:

   ```bash
   git push origin feat/my-new-feature
   ```

### PR Requirements

- [ ] All tests pass (`make test`)
- [ ] Linting passes (`make lint`)
- [ ] Validation passes (`make validate`)
- [ ] New features include tests
- [ ] Documentation updated if needed
- [ ] Commit messages follow conventions

### Review Process

1. Submit your PR against the `main` branch
2. Automated CI checks will run
3. A maintainer will review your code
4. Address any feedback
5. Once approved, your PR will be merged

## Testing

### Running Tests

```bash
make test              # Run all tests
make test-unit         # Unit tests only
make test-integration  # Integration tests only
make test-verbose      # Verbose output
```

### Writing Tests

Tests use [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System).

**Test file location:**

- Unit tests: `test/unit/<script-name>.bats`
- Integration tests: `test/integration/<feature>.bats`

**Example test:**

```bash
#!/usr/bin/env bats

load '../test_helper'

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "my-script: shows help with -h flag" {
    run bash "$SCRIPT_DIR/my-script.sh" -h
    assert_success
    assert_output --partial "Usage"
}

@test "my-script: handles invalid input" {
    run bash "$SCRIPT_DIR/my-script.sh" --invalid
    assert_failure
}
```

### Test Helpers

The `test/test_helper.bash` provides:

- `setup_test_env` / `teardown_test_env`: Temporary directory management
- `mock_command`: Create mock commands
- `strip_colors`: Remove ANSI codes from output
- `require_command`: Skip test if command unavailable

## Adding New Scripts

### 1. Create the Script

```bash
# Create from template
cp scripts/bash/disk-cleanup.sh scripts/bash/my-new-script.sh
```

### 2. Add Required Headers

```bash
#!/bin/bash
# =============================================================================
# @id           my-script
# @name         my-new-script
# @displayName  My New Script
# @description  What it does
# @category     category
# @version      1.0.0
# @author       your-name
# @tags         relevant,tags
# @shells       bash
# =============================================================================
```

### 3. Update Registry

Add to `scripts/registry.json`:

```json
{
  "id": "my-script",
  "name": "my-new-script",
  "displayName": "My New Script",
  "description": "What it does",
  "category": "category",
  "shells": {
    "bash": "scripts/bash/my-new-script.sh"
  },
  "aliases": ["my", "myscript"],
  "tags": ["relevant", "tags"]
}
```

### 4. Update rsr Command

Add to `rsr` file in `get_script_path()` and command case statement.

### 5. Add Tests

Create `test/unit/my-new-script.bats` with at least:

- Help flag test
- Syntax validation test
- Basic functionality tests

### 6. Validate

```bash
make validate  # Check registry and headers
make test      # Run all tests
make lint      # Check code quality
```

## Questions?

- Open an [issue](https://github.com/codefuturist/remote-script-runner/issues) for bugs or feature requests
- Start a [discussion](https://github.com/codefuturist/remote-script-runner/discussions) for questions

Thank you for contributing! 🎉
