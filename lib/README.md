# RSR Library

Modern, namespaced library for Remote Script Runner scripts.

## Structure

```
lib/
├── rsr-lib.sh              # Main loader - source this in your scripts
├── core/                   # Core functionality (always loaded)
│   ├── init.sh             # Logging, colors, OS detection, utilities
│   ├── validate.sh         # Input validation functions
│   └── interactive.sh      # Interactive prompts (bash 4+ only)
├── modules/                # Optional domain-specific modules
│   ├── users.sh            # User/group management
│   ├── docker.sh           # Docker operations
│   └── ssh.sh              # SSH server management
├── powershell/             # PowerShell modules
│   ├── RSR.psd1            # Module manifest
│   ├── RSR.psm1            # Main module
│   ├── Core/               # Core modules
│   │   ├── RSR.Core.psm1
│   │   ├── RSR.Validate.psm1
│   │   └── RSR.Interactive.psm1
│   └── Modules/            # Domain modules
│       ├── RSR.Users.psm1
│       ├── RSR.Docker.psm1
│       └── RSR.SSH.psm1
└── _archive/               # Old library files (deprecated)
```

## Usage

### Bash/Shell Scripts

```bash
#!/usr/bin/env bash
set -euo pipefail

# Locate library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RSR_LIB_DIR="${SCRIPT_DIR}/../lib"  # Adjust path as needed

# Load RSR library with required modules
if [[ -f "$RSR_LIB_DIR/rsr-lib.sh" ]]; then
    source "$RSR_LIB_DIR/rsr-lib.sh" validate users docker
else
    echo "ERROR: RSR library not found" >&2
    exit 1
fi

# Use library functions
rsr_log_info "Starting script..."
rsr_user_exists "john" && rsr_log_ok "User exists"
```

### PowerShell Scripts

```powershell
#Requires -Version 5.1

$RSRModulePath = Join-Path $PSScriptRoot '../lib/powershell/RSR.psd1'
Import-Module $RSRModulePath -Force

# Use library functions
Write-RSRInfo "Starting script..."
if (Test-RSRUserExists -Username "john") {
    Write-RSROk "User exists"
}
```

## Available Modules

### Core (Always Loaded)

**Logging:**

- `rsr_log_info` - Info message
- `rsr_log_ok` - Success message
- `rsr_log_warn` - Warning message
- `rsr_log_error` - Error message
- `rsr_log_debug` - Debug message (if verbose)
- `rsr_print_header` - Section header

**Colors:**

- `$RSR_COLOR_RED`, `$RSR_COLOR_GREEN`, `$RSR_COLOR_BLUE`, etc.
- `$RSR_COLOR_RESET`

**OS Detection:**

- `rsr_detect_os` - Detect OS (linux/darwin/windows)
- `rsr_detect_arch` - Detect architecture
- `rsr_detect_distro` - Detect Linux distribution
- `rsr_detect_shell` - Detect current shell

**Utilities:**

- `rsr_has_command` - Check if command exists
- `rsr_is_root` - Check if running as root
- `rsr_download` - Download file
- `rsr_string_*` - String manipulation
- `rsr_version_*` - Version comparison

### Validate Module

- `rsr_validate_username` - Validate username format
- `rsr_validate_password` - Validate password strength
- `rsr_validate_email` - Validate email address
- `rsr_validate_ipv4` - Validate IPv4 address
- `rsr_validate_port` - Validate port number
- `rsr_validate_url` - Validate URL format
- `rsr_validate_path` - Validate file path

### Interactive Module (Bash 4+ only)

- `rsr_prompt_confirm` - Yes/no confirmation
- `rsr_prompt_input` - Text input
- `rsr_prompt_password` - Password input
- `rsr_prompt_select` - Single selection menu
- `rsr_prompt_multiselect` - Multiple selection menu
- `rsr_show_spinner` - Show spinner animation
- `rsr_show_progress` - Show progress bar

### Users Module

- `rsr_user_exists` - Check if user exists
- `rsr_user_info` - Get user information
- `rsr_user_create` - Create user
- `rsr_user_delete` - Delete user
- `rsr_user_lock` / `rsr_user_unlock` - Lock/unlock account
- `rsr_group_exists` - Check if group exists
- `rsr_group_create` - Create group
- `rsr_group_add_member` - Add user to group

### Docker Module

- `rsr_docker_is_installed` - Check if Docker installed
- `rsr_docker_is_running` - Check if Docker running
- `rsr_docker_ensure` - Ensure Docker available
- `rsr_docker_version` - Get Docker version
- `rsr_docker_container_*` - Container operations
- `rsr_docker_image_*` - Image operations
- `rsr_docker_cleanup` - Clean up resources

### SSH Module

- `rsr_ssh_server_is_installed` - Check if SSH server installed
- `rsr_ssh_server_is_running` - Check if SSH server running
- `rsr_ssh_config_get` - Get SSH config value
- `rsr_ssh_config_set` - Set SSH config value
- `rsr_ssh_keygen` - Generate SSH key pair
- `rsr_ssh_authorized_key_add` - Add authorized key
- `rsr_ssh_authorized_key_remove` - Remove authorized key

## Version

Current version: **2.0.0**

Check version:

```bash
source lib/rsr-lib.sh --all
rsr_lib_version
```

## Migration from Old Library

The old library files (`common.sh`, `users.sh`, `docker.sh`, etc.) have been **deprecated** and moved to `_archive/`.

All scripts should now use:

- `rsr-lib.sh` as the single entry point
- `rsr_*` namespaced functions
- Module-based loading

**Old (Deprecated):**

```bash
source lib/common.sh
source lib/users.sh
log_info "Message"
user_exists "john"
```

**New (Current):**

```bash
source lib/rsr-lib.sh users
rsr_log_info "Message"
rsr_user_exists "john"
```

## Best Practices

1. **Always specify required modules:**

   ```bash
   source lib/rsr-lib.sh users docker  # Only load what you need
   ```

2. **Use proper error handling:**

   ```bash
   if [[ ! -f "$RSR_LIB_DIR/rsr-lib.sh" ]]; then
       echo "ERROR: RSR library not found" >&2
       exit 1
   fi
   ```

3. **Use namespaced functions:**
   - All library functions use `rsr_` prefix
   - Prevents naming conflicts

4. **Check module availability:**

   ```bash
   if type rsr_user_exists &>/dev/null; then
       # Users module is loaded
   fi
   ```

5. **Use exit codes:**

   ```bash
   exit $RSR_EXIT_SUCCESS  # 0
   exit $RSR_EXIT_ERROR    # 1
   exit $RSR_EXIT_USAGE    # 2
   ```

## Development

To add a new module:

1. Create `lib/modules/mymodule.sh`
2. Add functions with `rsr_mymodule_*` prefix
3. Export version: `_RSR_MYMODULE_VERSION="1.0.0"`
4. Add loading logic to `rsr-lib.sh`

Example module:

```bash
#!/bin/sh
# lib/modules/mymodule.sh - My Module

_RSR_MODULE_MYMODULE_LOADED=1
_RSR_MYMODULE_VERSION="1.0.0"

rsr_mymodule_hello() {
    rsr_log_info "Hello from mymodule!"
}
```

## Testing

Test library loading:

```bash
bash -c 'source lib/rsr-lib.sh --all && rsr_lib_version'
```

Test specific functions:

```bash
bash -c 'source lib/rsr-lib.sh users && rsr_user_exists "root" && echo OK'
```
