# Script Header Convention

This document defines the comprehensive header conventions for the Remote Script Runner repository. Headers serve multiple purposes: documentation, metadata extraction for the registry, and searchability in the GitHub Pages web UI.

## Table of Contents

- [Overview](#overview)
- [Metadata Block Format](#metadata-block-format)
- [Required Metadata Fields](#required-metadata-fields)
- [Optional Metadata Fields](#optional-metadata-fields)
- [Script Structure](#script-structure)
- [Best Practices](#best-practices)
- [Examples](#examples)
- [Registry Integration](#registry-integration)
- [Web UI Searchability](#web-ui-searchability)

---

## Overview

All scripts in the `scripts/` directory MUST include a standardized metadata header block that:

1. **Documents the script** with clear usage instructions
2. **Provides metadata** for automatic registry.json generation
3. **Enables search** in the GitHub Pages web UI
4. **Follows conventions** for cross-platform compatibility

### Header Purposes

- **Documentation**: Inline help for script users
- **Registry Metadata**: Extracted by `tools/build-registry.sh`
- **Web UI**: Powers the searchable script catalog at GitHub Pages
- **Validation**: Checked by `tools/validate.sh`

---

## Metadata Block Format

### Standard Template

```bash
#!/bin/bash
# =============================================================================
# @id           unique-script-id
# @name         script-file-name
# @displayName  Human-Readable Script Name
# @description  Brief one-line description of what the script does
# @category     category-name
# @version      X.Y.Z
# @author       author-name
# @tags         tag1,tag2,tag3,tag4
# @shells       bash,zsh,sh,fish
# =============================================================================

# This script can be run remotely with curl and accepts arguments
# Example: /bin/bash -c "$(curl -fsSL https://codefuturist.github.io/remote-script-runner/scripts/bash/script-name.sh)" -- --option value

set -euo pipefail
```

### Metadata Syntax

- **Format**: `# @field value`
- **Location**: Lines 2-11 (immediately after shebang, within header block)
- **Required**: Must be within `# ===...===` header boundaries
- **Order**: Fields should appear in the order shown above
- **Parsing**: Extracted by build tools using pattern matching

---

## Required Metadata Fields

### @id (REQUIRED)

- **Purpose**: Unique identifier for the script
- **Format**: Lowercase, hyphen-separated (kebab-case)
- **Example**: `@id health`, `@id db-backup`, `@id ssh-harden`
- **Usage**: Used in `rsr` command: `rsr <id>`
- **Rules**:
  - Must be unique across all scripts
  - Short and memorable (prefer 1-2 words)
  - Alphanumeric and hyphens only
  - Should match the script's primary purpose

### @name (REQUIRED)

- **Purpose**: Script filename (without extension)
- **Format**: Lowercase, hyphen-separated
- **Example**: `@name system-health-check`, `@name database-backup`
- **Rules**:
  - Must match the actual filename
  - Used for cross-referencing script variants
  - Should be descriptive but concise

### @displayName (REQUIRED)

- **Purpose**: Human-readable name shown in web UI
- **Format**: Title Case with spaces
- **Example**: `@displayName System Health Check`, `@displayName Database Backup`
- **Rules**:
  - Use proper capitalization
  - Can include special characters and spaces
  - Displayed prominently in web UI cards

### @description (REQUIRED)

- **Purpose**: One-line explanation of script functionality
- **Format**: Plain text, complete sentence
- **Example**: `@description Check system health: CPU, memory, disk usage, network status`
- **Rules**:
  - Must be concise (max 100 characters recommended)
  - Should explain what the script does, not how
  - Used in search results and script listings
  - Include key features or checked items

### @category (REQUIRED)

- **Purpose**: Group scripts by functional area
- **Format**: Lowercase, single word or hyphenated
- **Example**: `@category monitoring`, `@category configuration`, `@category backup`
- **Valid Categories**:
  - `monitoring` - System health, metrics, diagnostics
  - `configuration` - Setup, installation, settings
  - `security` - Hardening, auditing, compliance
  - `backup` - Data backup and recovery
  - `maintenance` - Cleanup, updates, optimization
  - `networking` - Network diagnostics and configuration
  - `database` - Database operations

### @version (REQUIRED)

- **Purpose**: Script version for change tracking
- **Format**: Semantic versioning (MAJOR.MINOR.PATCH)
- **Example**: `@version 1.0.0`, `@version 2.1.3`
- **Rules**:
  - Follow semver: breaking.feature.bugfix
  - Update when changing functionality
  - Start new scripts at 1.0.0

### @author (REQUIRED)

- **Purpose**: Script author or maintainer
- **Format**: Username, real name, or organization
- **Example**: `@author codefuturist`, `@author john-smith`
- **Rules**:
  - Use consistent identifier across scripts
  - Can be GitHub username, email, or name

### @tags (REQUIRED)

- **Purpose**: Enable search and filtering in web UI
- **Format**: Comma-separated list, lowercase, no spaces
- **Example**: `@tags health,monitoring,cpu,memory,disk,network,system`
- **Rules**:
  - Minimum 3 tags, maximum 12 tags
  - Include synonyms and related terms
  - Use singular form (e.g., "disk" not "disks")
  - Include category as first tag
  - Add technology-specific tags (nginx, mysql, etc.)
  - Think about how users will search

**Tag Strategy**:
- Primary function (monitoring, backup, security)
- Resources affected (disk, memory, cpu, network)
- Technologies involved (docker, nginx, postgresql)
- Use cases (diagnostics, hardening, optimization)
- Related concepts (health, audit, cleanup)

### @shells (REQUIRED)

- **Purpose**: Declare which shell variants exist
- **Format**: Comma-separated list of supported shells
- **Example**: `@shells bash,zsh,sh,fish`, `@shells bash`
- **Valid Values**: `bash`, `zsh`, `sh`, `fish`, `powershell`
- **Rules**:
  - List all available variants
  - Must include at least one shell
  - Order doesn't matter
  - Corresponds to actual files in `scripts/<shell>/` directories

---

## Optional Metadata Fields

### @requires (OPTIONAL)

- **Purpose**: List external dependencies
- **Format**: Comma-separated list of commands/packages
- **Example**: `@requires curl,jq,systemctl`
- **Usage**: Can be used for validation and warnings

### @os (OPTIONAL)

- **Purpose**: Specify compatible operating systems
- **Format**: Comma-separated list
- **Example**: `@os linux,macos`, `@os ubuntu,debian`
- **Valid Values**: `linux`, `macos`, `ubuntu`, `debian`, `centos`, `freebsd`, `wsl`

### @sudo (OPTIONAL)

- **Purpose**: Indicate if script requires root privileges
- **Format**: Boolean (true/false) or "optional"
- **Example**: `@sudo true`, `@sudo optional`

### @deprecated (OPTIONAL)

- **Purpose**: Mark script as deprecated
- **Format**: Deprecation message or replacement script
- **Example**: `@deprecated Use 'new-health' instead`

---

## Script Structure

### Complete Header Template

```bash
#!/bin/bash
# =============================================================================
# @id           health
# @name         system-health-check
# @displayName  System Health Check
# @description  Check system health: CPU, memory, disk usage, network status
# @category     monitoring
# @version      1.0.0
# @author       codefuturist
# @tags         health,monitoring,cpu,memory,disk,network,system,diagnostics
# @shells       bash,zsh,sh,fish
# @requires     ps,df,free
# @os           linux,macos
# @sudo         false
# =============================================================================

# This script can be run remotely with curl and accepts arguments
# Example: /bin/bash -c "$(curl -fsSL https://codefuturist.github.io/remote-script-runner/scripts/bash/system-health-check.sh)" -- -v -s cpu memory

set -euo pipefail

# ============================================================================
# Script Metadata
# ============================================================================

SCRIPT_NAME="System Health Check"
SCRIPT_VERSION="1.0.0"
SCRIPT_URL="https://github.com/codefuturist/remote-script-runner"

# ============================================================================
# Default Configuration
# ============================================================================

VERBOSE=false
DRY_RUN=false
OUTPUT_FORMAT="text"
LOG_FILE=""

# ============================================================================
# Color Codes
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================================================
# Logging Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_debug() {
    [[ "$VERBOSE" == "true" ]] && echo -e "${CYAN}[DEBUG]${NC} $*"
}

# ============================================================================
# Usage/Help Function
# ============================================================================

usage() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION

DESCRIPTION:
    Check system health: CPU, memory, disk usage, network status

USAGE:
    $0 [OPTIONS] [ARGUMENTS]

OPTIONS:
    -h, --help              Display this help message
    -v, --verbose           Enable verbose output
    -d, --dry-run           Show what would be done without executing
    -f, --format FORMAT     Output format: text, json, csv (default: text)
    -l, --log FILE          Log output to file
    -s, --select CHECK      Select specific check (can be repeated)
    -a, --all               Run all available checks

AVAILABLE CHECKS:
    cpu                     CPU usage and load average
    memory                  Memory usage statistics
    disk                    Disk usage for all mounted filesystems
    network                 Network interface statistics
    services                Check status of common services
    uptime                  System uptime information

EXAMPLES:
    # Run all health checks with verbose output
    $0 -v -a

    # Check specific components
    $0 -s cpu -s memory -s disk

    # Output results as JSON to file
    $0 -a -f json -l /var/log/health-check.log

    # Remote execution with curl
    curl -fsSL $SCRIPT_URL/scripts/bash/$(basename "$0") | bash -s -- -v -a

MORE INFO:
    Repository: $SCRIPT_URL
    Issues:     $SCRIPT_URL/issues

EOF
}

# ============================================================================
# Argument Parsing
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# ============================================================================
# Main Function
# ============================================================================

main() {
    log_info "Starting $SCRIPT_NAME..."
    
    # Main script logic here
    
    log_success "$SCRIPT_NAME completed successfully"
}

# ============================================================================
# Cleanup Function
# ============================================================================

cleanup() {
    log_debug "Performing cleanup..."
    # Cleanup logic here
}

trap cleanup EXIT INT TERM

# ============================================================================
# Execute Main
# ============================================================================

main "$@"
```

---

## Best Practices

### Metadata Guidelines

1. **Keep @description concise**: Max 100 chars, focus on what not how
2. **Use specific @tags**: Include technology names, resources, use cases
3. **Update @version**: Increment when changing functionality
4. **Test all @shells**: Only list shells you've tested
5. **Be consistent**: Use same @author across your scripts

### Tag Selection Strategy

**Good Tags** (Specific, Searchable):
```
@tags postgresql,database,backup,restore,dump,pg_dump,data
@tags nginx,webserver,configuration,ssl,tls,https,certbot
@tags docker,container,cleanup,prune,image,volume,system
```

**Poor Tags** (Too Generic):
```
@tags script,system,linux,general,tool,utility
```

### Description Writing

**Good Descriptions**:
- ✅ "Check system health: CPU, memory, disk usage, network status"
- ✅ "Backup PostgreSQL databases with compression and encryption"
- ✅ "Harden SSH configuration: disable root login, key-only auth"

**Poor Descriptions**:
- ❌ "System script"
- ❌ "Backs up stuff"
- ❌ "Security configuration"

### Documentation Sections

Always include these sections after the header:

1. **Remote execution example** (line 14)
2. **Script metadata block** (constants for name, version, URL)
3. **Configuration defaults** (global variables)
4. **Color codes** (for consistent output)
5. **Logging functions** (info, warn, error, debug)
6. **Usage/help function** (comprehensive documentation)
7. **Argument parsing** (case statement for options)
8. **Main function** (primary logic)
9. **Cleanup function** (trap handlers)

---

## Examples

### Example 1: Monitoring Script

```bash
#!/bin/bash
# =============================================================================
# @id           health
# @name         system-health-check
# @displayName  System Health Check
# @description  Check system health: CPU, memory, disk usage, network status
# @category     monitoring
# @version      1.0.0
# @author       codefuturist
# @tags         health,monitoring,cpu,memory,disk,network,system,diagnostics,status
# @shells       bash,zsh,sh,fish
# @requires     ps,df,free,netstat
# @os           linux,macos
# @sudo         false
# =============================================================================
```

### Example 2: Backup Script

```bash
#!/bin/bash
# =============================================================================
# @id           db-backup
# @name         database-backup
# @displayName  Database Backup
# @description  Backup MySQL, PostgreSQL, or MongoDB databases with compression
# @category     backup
# @version      2.1.0
# @author       codefuturist
# @tags         backup,database,mysql,postgresql,mongodb,dump,restore,archive,data
# @shells       bash,zsh
# @requires     mysqldump,pg_dump,mongodump,gzip
# @os           linux,macos
# @sudo         optional
# =============================================================================
```

### Example 3: Security Script

```bash
#!/bin/bash
# =============================================================================
# @id           ssh-harden
# @name         ssh-hardening
# @displayName  SSH Hardening
# @description  Harden SSH configuration: disable root, key-only auth, fail2ban
# @category     security
# @version      1.2.0
# @author       codefuturist
# @tags         security,ssh,hardening,authentication,fail2ban,configuration,lockdown
# @shells       bash
# @requires     sshd,fail2ban,systemctl
# @os           linux,ubuntu,debian
# @sudo         true
# =============================================================================
```

### Example 4: Configuration Script

```bash
#!/bin/bash
# =============================================================================
# @id           setup
# @name         server-setup
# @displayName  Server Setup
# @description  Initial server setup: users, SSH hardening, firewall, common tools
# @category     configuration
# @version      1.0.0
# @author       codefuturist
# @tags         setup,configuration,server,initialization,users,ssh,firewall,install
# @shells       bash
# @requires     useradd,ufw,apt-get
# @os           linux,ubuntu,debian
# @sudo         true
# =============================================================================
```

---

## Registry Integration

### How Metadata is Used

The `tools/build-registry.sh` script extracts metadata from script headers and:

1. **Generates `scripts/registry.json`**: Central metadata database
2. **Updates `rsr` script**: Embeds script mappings and listings
3. **Builds web UI**: Creates searchable script cards in `index.html`

### Registry.json Structure

Each script entry in registry.json is built from header metadata:

```json
{
  "id": "health",                        // from @id
  "name": "system-health-check",         // from @name
  "displayName": "System Health Check",  // from @displayName
  "description": "Check system health...",// from @description
  "category": "monitoring",              // from @category
  "version": "1.0.0",                    // from @version
  "author": "codefuturist",              // from @author
  "shells": {                            // from @shells + file discovery
    "bash": "scripts/bash/system-health-check.sh",
    "zsh": "scripts/zsh/system-health-check.zsh"
  },
  "tags": ["health", "monitoring", ...], // from @tags (split by comma)
  "options": [...],                      // extracted from usage function
  "examples": [...]                      // extracted from usage function
}
```

### Build Process

```bash
# Extract metadata and rebuild registry
make build-registry

# Or manually:
./tools/build-registry.sh

# Validate all scripts have correct headers
./tools/validate.sh
```

### Validation

The `tools/validate.sh` script checks:
- ✅ All required metadata fields present
- ✅ Metadata format is correct
- ✅ Script IDs are unique
- ✅ File names match @name field
- ✅ Shell variants exist for @shells declaration
- ✅ Tags are properly formatted
- ✅ No orphan scripts (scripts not in registry)

---

## Web UI Searchability

### How Search Works

The GitHub Pages web UI (`index.html`) uses metadata for search:

1. **Script Cards**: Built from `registry.json` data
2. **Search Index**: Includes id, name, displayName, description, tags
3. **Filtering**: By category, tags, shell support
4. **Tag Cloud**: All unique tags across scripts

### Search-Friendly Metadata

To maximize searchability:

#### 1. Comprehensive Tags

Include all ways users might search:
```bash
# Database backup script
@tags backup,database,mysql,postgresql,mongodb,dump,restore,archive,snapshot,data

# Not just:
@tags backup,database
```

#### 2. Descriptive Names

Use clear, searchable terms:
```bash
# Good
@id ssh-harden
@name ssh-hardening
@displayName SSH Hardening

# Not
@id harden
@name secure-ssh
@displayName Secure Server
```

#### 3. Keyword-Rich Descriptions

Include searchable terms:
```bash
# Good
@description Backup PostgreSQL databases with compression, encryption, and S3 upload

# Not
@description Database backup utility
```

### Web UI Features Powered by Metadata

- **Script Cards**: Display name, description, category badge
- **Search Bar**: Filters by id, name, description, tags
- **Category Filters**: Group by @category
- **Tag Cloud**: Show all unique tags as filter buttons
- **Shell Badges**: Show supported shells from @shells
- **Copy Buttons**: Generate correct curl commands using metadata
- **Examples**: Show usage examples with proper script paths

### Example Web UI Card

The metadata:
```bash
@id           health
@displayName  System Health Check
@description  Check system health: CPU, memory, disk usage, network status
@category     monitoring
@tags         health,monitoring,cpu,memory,disk
@shells       bash,zsh,sh,fish
```

Generates this HTML:
```html
<div class="script-card" data-category="monitoring" data-tags="health,monitoring,cpu,memory,disk">
  <div class="category-badge">monitoring</div>
  <h3>System Health Check</h3>
  <p>Check system health: CPU, memory, disk usage, network status</p>
  <div class="shell-badges">
    <span class="shell-badge">bash</span>
    <span class="shell-badge">zsh</span>
    <span class="shell-badge">sh</span>
    <span class="shell-badge">fish</span>
  </div>
  <div class="tags">
    <span class="tag">health</span>
    <span class="tag">monitoring</span>
    <span class="tag">cpu</span>
    <span class="tag">memory</span>
    <span class="tag">disk</span>
  </div>
  <!-- Copy button with curl command -->
</div>
```

---

## Workflow

### Adding a New Script

1. **Create script file** in `scripts/bash/` (or appropriate shell directory)
2. **Add header metadata** following this convention
3. **Implement functionality** with proper documentation
4. **Test the script** locally
5. **Run validation**: `./tools/validate.sh`
6. **Build registry**: `./tools/build-registry.sh`
7. **Commit changes**: Script, updated registry.json, rsr, index.html

### Updating an Existing Script

1. **Modify script** as needed
2. **Update @version** (increment appropriately)
3. **Update @description** if functionality changed
4. **Add new @tags** if new features added
5. **Update @requires** if dependencies changed
6. **Rebuild registry**: `make build-registry`
7. **Test and commit**

### Creating Shell Variants

1. **Start with bash version** (reference implementation)
2. **Create variant** in appropriate directory (e.g., `scripts/zsh/`)
3. **Add shell to @shells** in all variants' headers
4. **Ensure identical behavior** across shells
5. **Test each variant** independently
6. **Rebuild registry** to update mappings

---

## Makefile Integration

The repository Makefile provides convenient commands:

```bash
# Validate all script headers
make validate

# Build/rebuild registry from metadata
make build-registry

# Run all checks (lint, test, validate)
make all

# Format shell scripts
make format

# Run tests
make test
```

---

## Quick Reference

### Header Checklist

- [ ] Shebang line (`#!/bin/bash` or appropriate shell)
- [ ] Header boundary markers (`# ===...===`)
- [ ] @id (unique, kebab-case, memorable)
- [ ] @name (matches filename without extension)
- [ ] @displayName (Title Case, descriptive)
- [ ] @description (concise, <100 chars, keyword-rich)
- [ ] @category (valid category name)
- [ ] @version (semantic versioning)
- [ ] @author (consistent identifier)
- [ ] @tags (min 3, max 12, comma-separated)
- [ ] @shells (all available variants)
- [ ] Remote execution example comment
- [ ] `set -euo pipefail` (strict mode)
- [ ] Usage/help function
- [ ] Logging functions
- [ ] Main function
- [ ] Cleanup/trap handlers

### Common Pitfalls

❌ **Don't:**
- Use generic tags like "script", "tool", "utility"
- Forget to update @version when changing functionality
- List shells in @shells that don't exist
- Make @description too long or too vague
- Use spaces in @tags list
- Skip the remote execution example
- Use non-standard @category values

✅ **Do:**
- Include synonyms and related terms in @tags
- Test all shell variants before listing in @shells
- Keep @description focused on what the script does
- Use consistent @author across all your scripts
- Update registry after any header changes
- Follow semantic versioning for @version
- Include technology-specific tags (nginx, mysql, etc.)

---

## References

- **Registry Schema**: `scripts/registry.json`
- **Build Tool**: `tools/build-registry.sh`
- **Validation Tool**: `tools/validate.sh`
- **Main Script**: `rsr`
- **Web UI**: `index.html`
- **Examples**: All scripts in `scripts/bash/`
- **Testing**: `test/` directory

---

## Questions?

For questions or suggestions about header conventions:

1. Check existing scripts for examples
2. Run `./tools/validate.sh --help` for validation guidance
3. Open an issue on GitHub
4. Review the contributing guide: `CONTRIBUTING.md`

---

**Last Updated**: 2025-12-07  
**Version**: 1.0.0
