# Shell-Specific Script Versions

This directory contains shell-specific implementations of the remote-script-runner scripts, each optimized for its target shell with appropriate shebangs and features.

## Directory Structure

```
scripts/
├── bash/          # Bash scripts (#!/bin/bash)
├── zsh/           # Zsh scripts (#!/usr/bin/env zsh)
├── sh/            # POSIX sh scripts (#!/bin/sh)
├── fish/          # Fish shell scripts (#!/usr/bin/env fish)
├── powershell/    # PowerShell wrapper scripts
└── common/        # Shared functions and utilities
```

## Shell Comparison

| Shell | Shebang | Features | Use Case |
|-------|---------|----------|----------|
| **bash** | `#!/bin/bash` | Arrays, advanced string manipulation, process substitution | Most Linux distributions, Git Bash on Windows |
| **zsh** | `#!/usr/bin/env zsh` | Associative arrays, advanced globbing, zparseopts | macOS default, power users |
| **sh** | `#!/bin/sh` | POSIX compliant, maximum portability | Embedded systems, minimal environments |
| **fish** | `#!/usr/bin/env fish` | User-friendly syntax, built-in colors | Interactive use, modern terminals |

## Running Shell-Specific Scripts

### Direct Execution

```bash
# Bash version
./scripts/bash/system-health-check.sh -a

# Zsh version (with enhanced features)
./scripts/zsh/system-health-check.zsh -v -s cpu memory

# POSIX sh version (maximum compatibility)
./scripts/sh/system-health-check.sh -s uptime

# Fish version (with colors)
./scripts/fish/system-health-check.fish -a
```

### Remote Execution

```bash
# Bash (default)
curl -fsSL https://example.com/scripts/bash/system-health-check.sh | bash -s -- -a

# Zsh
curl -fsSL https://example.com/scripts/zsh/system-health-check.zsh | zsh -s -- -v -s cpu

# POSIX sh
curl -fsSL https://example.com/scripts/sh/system-health-check.sh | sh -s -- -s uptime

# Fish
curl -fsSL https://example.com/scripts/fish/system-health-check.fish | fish
```

## Shell-Specific Features

### Bash Scripts
- **Shebang**: `#!/bin/bash`
- **Features**: 
  - Arrays and associative arrays
  - Advanced parameter expansion
  - Process substitution
  - Bash-specific builtins

### Zsh Scripts  
- **Shebang**: `#!/usr/bin/env zsh`
- **Features**:
  - Enhanced arrays and associative arrays
  - zparseopts for argument parsing
  - Advanced globbing and pattern matching
  - Built-in math functions
  - Better color support with `print -P`

### POSIX sh Scripts
- **Shebang**: `#!/bin/sh`
- **Features**:
  - Maximum portability
  - No arrays (uses space-separated strings)
  - Basic POSIX features only
  - Works on minimal systems

### Fish Scripts
- **Shebang**: `#!/usr/bin/env fish`
- **Features**:
  - User-friendly syntax
  - Built-in color functions
  - Advanced command substitution
  - Lists instead of arrays
  - Different argument parsing

## Choosing the Right Shell

1. **Use Bash** when:
   - You need broad compatibility across Linux systems
   - Writing for Git Bash on Windows
   - Using advanced features but need stability

2. **Use Zsh** when:
   - Targeting macOS systems (default shell)
   - Need advanced features like associative arrays
   - Want better interactive features

3. **Use sh** when:
   - Maximum portability is required
   - Running on embedded or minimal systems
   - POSIX compliance is mandatory

4. **Use Fish** when:
   - User-friendliness is priority
   - Interactive use is primary
   - Modern terminal features are available

## Testing

Test scripts with their specific shells:

```bash
# Test all versions
for shell in bash zsh sh fish; do
    echo "Testing $shell version..."
    ./scripts/$shell/system-health-check.* -s uptime
done
```

## Notes

- All scripts implement the same functionality but use shell-specific features
- The bash version is the reference implementation
- POSIX sh version has some limitations due to POSIX compliance
- Fish version syntax differs significantly from other shells
