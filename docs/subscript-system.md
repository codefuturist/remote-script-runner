# RSR Subscript System

The RSR subscript system allows scripts to reuse functionality from other scripts without code duplication. This promotes DRY principles and makes maintenance easier.

## Platform Support

| Feature | Linux/macOS | Windows |
|---------|-------------|---------|
| Bootstrap Script | `host-bootstrap.sh` | `Initialize-HostBootstrap.ps1` |
| Subscript Module | `lib/core/subscript.sh` | N/A (PowerShell modules) |
| Bootstrap Module | `lib/modules/bootstrap.sh` | Built into PS script |

## Overview

The system provides three main capabilities:

1. **Subscript Execution** - Run other scripts with context propagation
2. **Library Mode** - Source scripts to use their functions without execution
3. **Bootstrap Module** - Pre-built functions for common bootstrap operations

## Quick Start

### Using the Bootstrap Module (Linux/macOS)

```bash
#!/bin/bash
source "$RSR_LIB_DIR/rsr-lib.sh"
rsr_load_module bootstrap

# Use bootstrap functions
rsr_bootstrap_packages_essential
rsr_bootstrap_docker
rsr_bootstrap_ssh
```

### Using Bootstrap on Windows

```powershell
# Interactive wizard
.\Initialize-HostBootstrap.ps1

# With profile
.\Initialize-HostBootstrap.ps1 -Profile server

# Dry run
.\Initialize-HostBootstrap.ps1 -Profile dev -DryRun

# Via rsr entry point
.\rsr.ps1 bootstrap -Profile workstation
```

### Calling Subscripts (Linux/macOS)

```bash
#!/bin/bash
source "$RSR_LIB_DIR/rsr-lib.sh"
rsr_load_module subscript

# Run a subscript with context propagation
rsr_run_subscript "ssh-harden" --no-root --max-auth-tries 3

# Check if subscript exists
if rsr_subscript_exists "docker"; then
    rsr_run_subscript "docker" install engine
fi
```

### Importing Script Functions

```bash
#!/bin/bash
source "$RSR_LIB_DIR/rsr-lib.sh"
rsr_load_module subscript

# Import all functions from a script
rsr_import_script "ssh-harden"

# Now you can use functions from ssh-hardening.sh
# configure_ssh, apply_hardening, etc.
```

## Context Propagation

The subscript system automatically propagates execution context:

- `RSR_DRY_RUN` - Dry run mode
- `RSR_VERBOSE` - Verbose output
- `RSR_YES` - Auto-confirm prompts
- `RSR_INTERACTIVE` - Interactive mode

### Example

```bash
# Parent script
export RSR_DRY_RUN=true
rsr_run_subscript "docker" install engine
# ^ Docker install will run in dry-run mode
```

## Making Scripts Library-Compatible

To make your script work with the library mode:

```bash
#!/bin/bash

# ... your script code ...

main() {
    # Main logic here
}

# Support library mode
if [[ "${RSR_AS_LIBRARY:-0}" != "1" ]]; then
    main "$@"
fi
```

When sourced with `RSR_AS_LIBRARY=1`, the script's functions are available but `main()` is not executed.

## Available Bootstrap Functions

| Function | Description |
|----------|-------------|
| `rsr_bootstrap_packages_essential` | Install curl, wget, git, vim, htop |
| `rsr_bootstrap_packages_dev` | Install build tools, python, jq |
| `rsr_bootstrap_docker` | Install Docker engine |
| `rsr_bootstrap_ssh` | Configure SSH security |
| `rsr_bootstrap_firewall` | Configure firewall (ufw/firewalld) |
| `rsr_bootstrap_fail2ban` | Install and configure fail2ban |
| `rsr_bootstrap_user` | Create admin user |
| `rsr_bootstrap_hostname` | Set system hostname |
| `rsr_bootstrap_timezone` | Configure timezone |
| `rsr_bootstrap_profile` | Apply a preset profile |
| `rsr_bootstrap_full` | Complete bootstrap workflow |

## Bootstrap Profiles

```bash
# Available profiles
rsr_bootstrap_profile "minimal"     # Essential packages only
rsr_bootstrap_profile "server"      # + SSH + firewall + fail2ban
rsr_bootstrap_profile "workstation" # + dev tools + SSH
rsr_bootstrap_profile "dev"         # + Docker
```

## Helper Functions

```bash
# Run command respecting dry-run mode
rsr_maybe_run apt-get install -y nginx

# Run with sudo if needed
rsr_sudo_run systemctl restart nginx

# Confirm with RSR_YES support
if rsr_confirm "Proceed?"; then
    do_something
fi
```

## Example: Custom Bootstrap Script

```bash
#!/bin/bash
source "$RSR_LIB_DIR/rsr-lib.sh"
rsr_load_module bootstrap
rsr_load_module subscript

# Set context
export RSR_DRY_RUN="${DRY_RUN:-false}"

# Use bootstrap module for standard operations
rsr_bootstrap_packages_essential
rsr_bootstrap_docker

# Use subscript for complex operations
rsr_run_subscript "ssh-harden" --all -y

# Custom operations
install_custom_packages() {
    rsr_pkg_install_many nginx redis postgresql
}

install_custom_packages

echo "Custom bootstrap complete!"
```

## Best Practices

1. **Prefer module functions** - Use `rsr_bootstrap_*` functions when possible
2. **Use subscripts for complex operations** - Leverage existing scripts via `rsr_run_subscript`
3. **Support library mode** - Add the `RSR_AS_LIBRARY` check to your scripts
4. **Propagate context** - Export `RSR_DRY_RUN`, `RSR_VERBOSE`, etc. before calling subscripts
5. **Check existence** - Use `rsr_subscript_exists` before calling subscripts
