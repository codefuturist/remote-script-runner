# RSR Scripts

Developer-friendly script organization for Remote Script Runner.

## Directory Structure

```
scripts/
├── _common.sh              # Common initialization (source this in scripts)
├── _templates/             # Script templates for new scripts
│   ├── bash-script.template.sh
│   └── powershell-script.template.ps1
├── registry.json           # Script metadata registry
│
├── security/               # Security auditing and hardening
│   ├── audit/              # Security and user audits
│   │   ├── security-audit.sh
│   │   └── user-audit.sh
│   ├── hardening/          # System hardening scripts
│   │   ├── ssh-hardening.sh
│   │   └── firewall-setup.sh
│   ├── certificates/       # SSL/TLS certificate management
│   │   └── ssl-checker.sh
│   └── ssh/                # SSH server management
│       ├── ssh-server.sh
│       ├── ssh-server.ps1
│       └── install-openssh.ps1
│
├── system/                 # System administration
│   ├── health/             # Health checks and monitoring
│   │   └── system-health-check.sh
│   ├── updates/            # Package and system updates
│   │   └── system-update.sh
│   ├── cleanup/            # Disk and cache cleanup
│   │   └── disk-cleanup.sh
│   └── info/               # System information
│       └── detect-distro.sh
│
├── users/                  # User management
│   ├── management/         # User CRUD operations
│   │   ├── user-management.sh
│   │   └── user-management.ps1
│   └── setup/              # Initial server setup
│       └── server-setup.sh
│
├── network/                # Network operations
│   ├── diagnostics/        # Network troubleshooting
│   │   └── network-diagnostics.sh
│   └── dns/                # DNS management
│       ├── dns-sync.sh
│       ├── install-dns-gitops.sh
│       └── check-dns-sync-health.sh
│
├── containers/             # Container orchestration
│   ├── docker/             # Docker management
│   │   └── docker-management.sh
│   └── compose/            # Docker Compose (future)
│
└── backup/                 # Backup operations
    ├── database/           # Database backups
    │   └── database-backup.sh
    ├── config/             # Configuration backups
    │   └── config-backup.sh
    └── git/                # Git-based sync/backup
        ├── git-auto-sync.sh
        └── git-auto-sync-manager.sh
```

## Naming Conventions

### Directory Names

- **Category**: Broad functional area (e.g., `security`, `system`, `network`)
- **Subcategory**: Specific function within category (e.g., `audit`, `hardening`)
- Use lowercase with hyphens if needed

### File Names

- Use lowercase with hyphens: `script-name.sh`
- Include extension: `.sh` for bash, `.ps1` for PowerShell
- Cross-platform scripts share the same base name

## Creating New Scripts

1. **Copy the template**:

   ```bash
   cp scripts/_templates/bash-script.template.sh scripts/category/subcategory/my-script.sh
   ```

2. **Update placeholders** in the new script:
   - `{{SCRIPT_NAME}}` → Your script name
   - `{{DESCRIPTION}}` → Brief description
   - `{{AUTHOR}}` → Your name

3. **Register in registry.json** (REQUIRED):

   ```json
   {
     "id": "my-script",
     "name": "My Script Name",
     "command": "my-cmd",
     "aliases": ["my-cmd", "my-script"],
     "description": "Brief description of what the script does",
     "example": "rsr my-cmd --option",
     "category": "system",
     "subcategory": "health",
     "path": "scripts/system/health/my-script.sh",
     "version": "1.0.0",
     "platforms": ["linux", "macos"],
     "requires": ["bash 4.0+"],
     "sudo": "optional",
     "tags": ["monitoring", "health"]
   }
   ```

4. **Generate code from registry**:

   ```bash
   make build-registry
   ```

   This auto-updates the `rsr` entrypoint with your new script.

5. **Test the script**:

   ```bash
   ./rsr my-cmd --help
   ```

## Using Scripts

### Direct Execution

```bash
# Run from repository root
./scripts/security/audit/security-audit.sh --help

# Or with bash explicitly
bash scripts/system/health/system-health-check.sh -a
```

### With RSR CLI (if installed)

```bash
rsr security-audit --help
rsr system-health -a
```

## RSR Library Integration

All scripts use the RSR library for common functionality:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Load RSR Library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RSR_LIB_DIR="${SCRIPT_DIR}/../../../lib"

if [[ -f "$RSR_LIB_DIR/rsr-lib.sh" ]]; then
    source "$RSR_LIB_DIR/rsr-lib.sh" validate  # Load specific modules
fi
```

### Available RSR Modules

- `validate` - Input validation functions
- `interactive` - Interactive prompts (bash 4+ only)
- `users` - User/group management
- `docker` - Docker operations
- `ssh` - SSH server management

## Cross-Platform Support

Scripts with both `.sh` and `.ps1` versions:

- `security/ssh/ssh-server` (.sh + .ps1)
- `users/management/user-management` (.sh + .ps1)

PowerShell scripts use the RSR PowerShell module:

```powershell
Import-Module "$PSScriptRoot/../../../lib/powershell/RSR.psd1"
```

## Registry (registry.json)

The registry provides metadata for all scripts:

- Script ID (unique identifier)
- Command and aliases for routing
- Display name and description
- Example usage
- Category and subcategory
- File paths
- Platform support
- Required dependencies
- Tags for searching

### Automated Code Generation

The `rsr` entrypoint script is automatically generated from `registry.json`:

**What gets auto-generated:**

- Script path mappings (`get_script_path` function)
- Script list output (`list_scripts` function)
- Command routing (`main` case statement)

**How to update:**

```bash
# After modifying registry.json
make build-registry

# Preview changes without modifying files
make build-registry-dry-run

# Check if files are in sync (CI)
make sync-check
```

**Pre-commit hook:**
A pre-commit hook automatically checks if `registry.json` and `rsr` are in sync. If you modify `registry.json`, you must run `make build-registry` before committing.

**DO NOT manually edit** the auto-generated sections in `rsr` (marked with `BEGIN AUTO-GENERATED` comments).

## Archive

The `_archive/` directory contains:

- Old directory structure (for reference)
- Previous versions of scripts
- Deprecated scripts

This directory is excluded from the main workflow.
