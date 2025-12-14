#!/bin/bash
# =============================================================================
# Migration Script: Architecture V2
# =============================================================================
#
# Migrates the remote-script-runner repository from flat structure to
# categorical organization based on ARCHITECTURE_V2.md
#
# Usage:
#   ./tools/migrate-to-v2.sh [OPTIONS]
#
# Options:
#   --dry-run       Show what would be done without making changes
#   --verbose       Show detailed output
#   --rollback      Revert migration using backup
#   --help          Show this help message
#
# =============================================================================

set -euo pipefail

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKUP_DIR="$ROOT_DIR/.migration-backup-$(date +%Y%m%d-%H%M%S)"
DRY_RUN=false
VERBOSE=false
ROLLBACK=false

# =============================================================================
# Logging
# =============================================================================

log_info() { printf "${BLUE}▸${NC} %s\n" "$1"; }
log_ok() { printf "${GREEN}✓${NC} %s\n" "$1"; }
log_warn() { printf "${YELLOW}⚠${NC} %s\n" "$1" >&2; }
log_error() { printf "${RED}✗${NC} %s\n" "$1" >&2; }
log_section() { printf "\n${BOLD}${CYAN}=== %s ===${NC}\n\n" "$1"; }
log_verbose() { $VERBOSE && printf "${DIM}  %s${NC}\n" "$1" || true; }

# =============================================================================
# Script Category Mappings
# =============================================================================
# Based on registry.json "category" field

declare -A SCRIPT_CATEGORIES=(
    # Monitoring
    ["system-health-check.sh"]="monitoring"
    ["check-dns-sync-health.sh"]="monitoring"
    ["network-diagnostics.sh"]="monitoring"

    # Configuration
    ["server-setup.sh"]="configuration"
    ["detect-distro.sh"]="configuration"
    ["user-management.sh"]="configuration"
    ["git-auto-sync-manager.sh"]="configuration"

    # Infrastructure
    ["docker-management.sh"]="infrastructure"

    # Security
    ["firewall-setup.sh"]="security"
    ["security-audit.sh"]="security"
    ["ssh-hardening.sh"]="security"
    ["ssh-server.sh"]="security"
    ["ssl-checker.sh"]="security"
    ["user-audit.sh"]="security"

    # Maintenance
    ["disk-cleanup.sh"]="maintenance"
    ["system-update.sh"]="maintenance"
    ["config-backup.sh"]="maintenance"
    ["database-backup.sh"]="maintenance"

    # Network
    ["dns-sync.sh"]="network"
    ["sync-dns-zones.py"]="network"
    ["install-dns-gitops.sh"]="network"

    # Data/Development
    ["git-auto-sync.sh"]="data"
)

# Multi-shell scripts (have versions in zsh, fish, sh)
declare -A MULTI_SHELL_SCRIPTS=(
    ["system-health-check"]="monitoring"
)

# PowerShell script mappings
declare -A PS_SCRIPT_CATEGORIES=(
    ["UserManagement.ps1"]="configuration"
    ["SSHServer.ps1"]="security"
    ["Install-OpenSSH.ps1"]="security"
    ["Invoke-RemoteScript.ps1"]="infrastructure"
)

# Library mappings
declare -A LIB_COMMON=(
    ["common.sh"]="common"
    ["config.sh"]="common"
    ["interactive.sh"]="common"
)

declare -A LIB_CONNECTORS=(
    ["docker.sh"]="connectors"
    ["ssh.sh"]="connectors"
    ["users.sh"]="connectors"
)

declare -A LIB_POWERSHELL=(
    ["users.ps1"]="powershell"
)

# =============================================================================
# Helper Functions
# =============================================================================

show_help() {
    cat << 'EOF'
Migration Script: Architecture V2

Migrates the remote-script-runner repository from flat structure to
categorical organization based on ARCHITECTURE_V2.md

Usage:
  ./tools/migrate-to-v2.sh [OPTIONS]

Options:
  --dry-run       Show what would be done without making changes
  --verbose       Show detailed output
  --rollback      Revert migration using most recent backup
  --help          Show this help message

What this script does:
  1. Creates backup of current structure
  2. Reorganizes scripts/ by category (monitoring, security, etc.)
  3. Restructures lib/ into common/, connectors/, powershell/
  4. Creates config/ directory structure
  5. Adds logs/ and tmp/ directories
  6. Updates registry.json with new paths
  7. Updates rsr CLI script paths
  8. Creates symlinks for backward compatibility (optional)

EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=true ;;
            --verbose) VERBOSE=true ;;
            --rollback) ROLLBACK=true ;;
            --help) show_help ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
        shift
    done
}

run_cmd() {
    local cmd="$*"
    if $DRY_RUN; then
        log_verbose "[DRY-RUN] $cmd"
    else
        log_verbose "$cmd"
        eval "$cmd"
    fi
}

ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        if $DRY_RUN; then
            log_verbose "[DRY-RUN] Would create: $dir"
        else
            mkdir -p "$dir"
            log_ok "Created: $dir"
        fi
    fi
}

move_file() {
    local src="$1"
    local dest="$2"
    if [[ -f "$src" ]]; then
        if $DRY_RUN; then
            log_verbose "[DRY-RUN] Would move: $(basename "$src") → $dest"
        else
            ensure_dir "$(dirname "$dest")"
            mv "$src" "$dest"
            log_ok "Moved: $(basename "$src") → $dest"
        fi
    else
        log_warn "Source not found: $src"
    fi
}

create_symlink() {
    local target="$1"
    local link="$2"
    if [[ ! -L "$link" ]] && [[ ! -e "$link" ]]; then
        run_cmd "ln -s '$target' '$link'"
        log_ok "Symlink: $link → $target"
    fi
}

# =============================================================================
# Backup Functions
# =============================================================================

create_backup() {
    log_section "Creating Backup"

    if $DRY_RUN; then
        log_info "[DRY-RUN] Would backup to: $BACKUP_DIR"
        return
    fi

    mkdir -p "$BACKUP_DIR"

    # Backup critical directories
    for dir in scripts lib; do
        if [[ -d "$ROOT_DIR/$dir" ]]; then
            cp -r "$ROOT_DIR/$dir" "$BACKUP_DIR/"
            log_ok "Backed up: $dir/"
        fi
    done

    # Backup critical files
    for file in rsr; do
        if [[ -f "$ROOT_DIR/$file" ]]; then
            cp "$ROOT_DIR/$file" "$BACKUP_DIR/"
            log_ok "Backed up: $file"
        fi
    done

    # Save backup location
    echo "$BACKUP_DIR" > "$ROOT_DIR/.last-migration-backup"
    log_ok "Backup complete: $BACKUP_DIR"
}

rollback_migration() {
    log_section "Rolling Back Migration"

    if [[ ! -f "$ROOT_DIR/.last-migration-backup" ]]; then
        log_error "No backup found. Cannot rollback."
        exit 1
    fi

    local backup_path
    backup_path=$(cat "$ROOT_DIR/.last-migration-backup")

    if [[ ! -d "$backup_path" ]]; then
        log_error "Backup directory not found: $backup_path"
        exit 1
    fi

    log_info "Restoring from: $backup_path"

    # Restore directories
    for dir in scripts lib; do
        if [[ -d "$backup_path/$dir" ]]; then
            rm -rf "$ROOT_DIR/$dir"
            cp -r "$backup_path/$dir" "$ROOT_DIR/"
            log_ok "Restored: $dir/"
        fi
    done

    # Restore files
    for file in rsr; do
        if [[ -f "$backup_path/$file" ]]; then
            cp "$backup_path/$file" "$ROOT_DIR/"
            log_ok "Restored: $file"
        fi
    done

    log_ok "Rollback complete!"
}

# =============================================================================
# Migration: Scripts Directory
# =============================================================================

migrate_scripts() {
    log_section "Migrating Scripts"

    cd "$ROOT_DIR"

    # Create category directories
    local categories=("monitoring" "configuration" "infrastructure" "security" "maintenance" "network" "data")

    for category in "${categories[@]}"; do
        ensure_dir "scripts/$category/bash"
        ensure_dir "scripts/$category/powershell"
    done

    # Migrate bash scripts
    log_info "Migrating bash scripts..."
    for script in "${!SCRIPT_CATEGORIES[@]}"; do
        local category="${SCRIPT_CATEGORIES[$script]}"
        local src="scripts/bash/$script"
        local dest="scripts/$category/bash/$script"

        if [[ -f "$src" ]]; then
            move_file "$src" "$dest"
        fi
    done

    # Handle DNS-GITOPS-README.md (documentation, move to network)
    if [[ -f "scripts/bash/DNS-GITOPS-README.md" ]]; then
        move_file "scripts/bash/DNS-GITOPS-README.md" "scripts/network/bash/DNS-GITOPS-README.md"
    fi

    # Migrate multi-shell scripts (zsh, fish, sh)
    log_info "Migrating multi-shell scripts..."
    for script_base in "${!MULTI_SHELL_SCRIPTS[@]}"; do
        local category="${MULTI_SHELL_SCRIPTS[$script_base]}"

        # zsh
        if [[ -f "scripts/zsh/${script_base}.zsh" ]]; then
            ensure_dir "scripts/$category/zsh"
            move_file "scripts/zsh/${script_base}.zsh" "scripts/$category/zsh/${script_base}.zsh"
        fi

        # fish
        if [[ -f "scripts/fish/${script_base}.fish" ]]; then
            ensure_dir "scripts/$category/fish"
            move_file "scripts/fish/${script_base}.fish" "scripts/$category/fish/${script_base}.fish"
        fi

        # sh
        if [[ -f "scripts/sh/${script_base}.sh" ]]; then
            ensure_dir "scripts/$category/sh"
            move_file "scripts/sh/${script_base}.sh" "scripts/$category/sh/${script_base}.sh"
        fi
    done

    # Handle install-dns-gitops.sh in sh/ (network category)
    if [[ -f "scripts/sh/install-dns-gitops.sh" ]]; then
        ensure_dir "scripts/network/sh"
        move_file "scripts/sh/install-dns-gitops.sh" "scripts/network/sh/install-dns-gitops.sh"
    fi

    # Migrate PowerShell scripts
    log_info "Migrating PowerShell scripts..."
    for script in "${!PS_SCRIPT_CATEGORIES[@]}"; do
        local category="${PS_SCRIPT_CATEGORIES[$script]}"
        local src="scripts/powershell/$script"
        local dest="scripts/$category/powershell/$script"

        if [[ -f "$src" ]]; then
            move_file "$src" "$dest"
        fi
    done

    # Clean up empty old directories
    log_info "Cleaning up old directories..."
    for dir in scripts/bash scripts/zsh scripts/fish scripts/sh scripts/powershell; do
        if [[ -d "$dir" ]] && [[ -z "$(ls -A "$dir" 2> /dev/null)" ]]; then
            run_cmd "rmdir '$dir'"
            log_ok "Removed empty: $dir"
        fi
    done
}

# =============================================================================
# Migration: Library Directory
# =============================================================================

migrate_lib() {
    log_section "Migrating Libraries"

    cd "$ROOT_DIR"

    # Create new structure
    ensure_dir "lib/common"
    ensure_dir "lib/connectors"
    ensure_dir "lib/powershell"

    # Move common libraries
    log_info "Migrating common libraries..."
    for lib in "${!LIB_COMMON[@]}"; do
        if [[ -f "lib/$lib" ]]; then
            move_file "lib/$lib" "lib/common/$lib"
        fi
    done

    # Move connector libraries
    log_info "Migrating connector libraries..."
    for lib in "${!LIB_CONNECTORS[@]}"; do
        if [[ -f "lib/$lib" ]]; then
            move_file "lib/$lib" "lib/connectors/$lib"
        fi
    done

    # Move PowerShell libraries
    log_info "Migrating PowerShell libraries..."
    for lib in "${!LIB_POWERSHELL[@]}"; do
        if [[ -f "lib/$lib" ]]; then
            move_file "lib/$lib" "lib/powershell/$lib"
        fi
    done
}

# =============================================================================
# Migration: Config Directory
# =============================================================================

migrate_config() {
    log_section "Creating Config Structure"

    cd "$ROOT_DIR"

    # Create config directory structure
    ensure_dir "config/environments/dev"
    ensure_dir "config/environments/staging"
    ensure_dir "config/environments/prod"
    ensure_dir "config/defaults"
    ensure_dir "config/schemas"

    # Move example config to defaults
    if [[ -f "examples/config.yaml" ]]; then
        if $DRY_RUN; then
            log_verbose "[DRY-RUN] Would copy: examples/config.yaml → config/defaults/base.yaml"
        else
            cp "examples/config.yaml" "config/defaults/base.yaml"
            log_ok "Created: config/defaults/base.yaml (from examples/config.yaml)"
        fi
    fi

    # Create environment-specific placeholder configs
    for env in dev staging prod; do
        local env_config="config/environments/$env/config.yaml"
        if [[ ! -f "$env_config" ]] && ! $DRY_RUN; then
            cat > "$env_config" << EOF
# $env Environment Configuration
# Extends: ../../../config/defaults/base.yaml

environment: $env

# Override settings for $env environment
# Add environment-specific configuration here
EOF
            log_ok "Created: $env_config"
        elif $DRY_RUN; then
            log_verbose "[DRY-RUN] Would create: $env_config"
        fi
    done

    # Create registry schema
    local schema_file="config/schemas/registry.schema.json"
    if [[ ! -f "$schema_file" ]] && ! $DRY_RUN; then
        cat > "$schema_file" << 'EOF'
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://scripts.pandia.io/schemas/registry.json",
  "title": "RSR Registry Schema",
  "description": "Schema for validating scripts/registry.json",
  "type": "object",
  "required": ["version", "scripts"],
  "properties": {
    "version": {
      "type": "string",
      "pattern": "^\\d+\\.\\d+\\.\\d+$"
    },
    "scripts": {
      "type": "array",
      "items": {
        "$ref": "#/$defs/script"
      }
    }
  },
  "$defs": {
    "script": {
      "type": "object",
      "required": ["id", "name", "description", "category", "shells"],
      "properties": {
        "id": { "type": "string" },
        "name": { "type": "string" },
        "displayName": { "type": "string" },
        "description": { "type": "string" },
        "category": {
          "type": "string",
          "enum": ["monitoring", "configuration", "infrastructure", "security", "maintenance", "network", "data", "development"]
        },
        "version": { "type": "string" },
        "author": { "type": "string" },
        "shells": {
          "type": "object",
          "additionalProperties": { "type": "string" }
        },
        "defaultShell": { "type": "string" },
        "options": { "type": "array" },
        "examples": { "type": "array" },
        "tags": {
          "type": "array",
          "items": { "type": "string" }
        }
      }
    }
  }
}
EOF
        log_ok "Created: $schema_file"
    elif $DRY_RUN; then
        log_verbose "[DRY-RUN] Would create: $schema_file"
    fi
}

# =============================================================================
# Migration: Local Directories
# =============================================================================

migrate_local_dirs() {
    log_section "Creating Local Directories"

    cd "$ROOT_DIR"

    # Create logs/ directory
    ensure_dir "logs"
    if [[ ! -f "logs/.gitkeep" ]] && ! $DRY_RUN; then
        touch "logs/.gitkeep"
        log_ok "Created: logs/.gitkeep"
    fi

    # Create tmp/ directory
    ensure_dir "tmp"
    if [[ ! -f "tmp/.gitkeep" ]] && ! $DRY_RUN; then
        touch "tmp/.gitkeep"
        log_ok "Created: tmp/.gitkeep"
    fi

    # Update .gitignore
    log_info "Updating .gitignore..."
    local gitignore="$ROOT_DIR/.gitignore"
    local additions=()

    if ! grep -q "^logs/$" "$gitignore" 2> /dev/null; then
        additions+=("logs/")
    fi
    if ! grep -q "^!logs/.gitkeep$" "$gitignore" 2> /dev/null; then
        additions+=("!logs/.gitkeep")
    fi
    if ! grep -q "^tmp/$" "$gitignore" 2> /dev/null; then
        additions+=("tmp/")
    fi
    if ! grep -q "^!tmp/.gitkeep$" "$gitignore" 2> /dev/null; then
        additions+=("!tmp/.gitkeep")
    fi

    if [[ ${#additions[@]} -gt 0 ]] && ! $DRY_RUN; then
        {
            echo ""
            echo "# Migration V2: Local directories"
            for item in "${additions[@]}"; do
                echo "$item"
            done
        } >> "$gitignore"
        log_ok "Updated .gitignore with logs/ and tmp/"
    elif $DRY_RUN; then
        log_verbose "[DRY-RUN] Would add to .gitignore: ${additions[*]}"
    fi
}

# =============================================================================
# Migration: Update Registry Paths
# =============================================================================

update_registry() {
    log_section "Updating Registry Paths"

    local registry="$ROOT_DIR/scripts/registry.json"

    if [[ ! -f "$registry" ]]; then
        log_error "Registry not found: $registry"
        return
    fi

    if $DRY_RUN; then
        log_info "[DRY-RUN] Would update paths in registry.json"
        log_verbose "  scripts/bash/*.sh → scripts/{category}/bash/*.sh"
        log_verbose "  scripts/zsh/*.zsh → scripts/{category}/zsh/*.zsh"
        log_verbose "  scripts/powershell/*.ps1 → scripts/{category}/powershell/*.ps1"
        return
    fi

    # Create a temp file for sed operations
    local tmp_registry
    tmp_registry=$(mktemp)
    cp "$registry" "$tmp_registry"

    # Update bash script paths
    for script in "${!SCRIPT_CATEGORIES[@]}"; do
        local category="${SCRIPT_CATEGORIES[$script]}"
        local old_path="scripts/bash/$script"
        local new_path="scripts/$category/bash/$script"
        sed -i.bak "s|\"$old_path\"|\"$new_path\"|g" "$tmp_registry"
    done

    # Update multi-shell script paths
    for script_base in "${!MULTI_SHELL_SCRIPTS[@]}"; do
        local category="${MULTI_SHELL_SCRIPTS[$script_base]}"

        # zsh
        sed -i.bak "s|\"scripts/zsh/${script_base}.zsh\"|\"scripts/$category/zsh/${script_base}.zsh\"|g" "$tmp_registry"

        # fish
        sed -i.bak "s|\"scripts/fish/${script_base}.fish\"|\"scripts/$category/fish/${script_base}.fish\"|g" "$tmp_registry"

        # sh
        sed -i.bak "s|\"scripts/sh/${script_base}.sh\"|\"scripts/$category/sh/${script_base}.sh\"|g" "$tmp_registry"
    done

    # Update PowerShell paths
    for script in "${!PS_SCRIPT_CATEGORIES[@]}"; do
        local category="${PS_SCRIPT_CATEGORIES[$script]}"
        local old_path="scripts/powershell/$script"
        local new_path="scripts/$category/powershell/$script"
        sed -i.bak "s|\"$old_path\"|\"$new_path\"|g" "$tmp_registry"
    done

    # Move updated registry back
    mv "$tmp_registry" "$registry"
    rm -f "${tmp_registry}.bak"

    log_ok "Updated paths in registry.json"
}

# =============================================================================
# Migration: Update RSR CLI
# =============================================================================

update_rsr_cli() {
    log_section "Updating RSR CLI"

    local rsr_file="$ROOT_DIR/rsr"

    if [[ ! -f "$rsr_file" ]]; then
        log_error "RSR CLI not found: $rsr_file"
        return
    fi

    if $DRY_RUN; then
        log_info "[DRY-RUN] Would update script paths in rsr CLI"
        return
    fi

    # Create backup
    cp "$rsr_file" "${rsr_file}.pre-migration"

    # Update get_script_path function
    # Map old paths to new categorical paths
    local replacements=(
        "scripts/bash/system-health-check.sh:scripts/monitoring/bash/system-health-check.sh"
        "scripts/zsh/system-health-check.zsh:scripts/monitoring/zsh/system-health-check.zsh"
        "scripts/sh/system-health-check.sh:scripts/monitoring/sh/system-health-check.sh"
        "scripts/fish/system-health-check.fish:scripts/monitoring/fish/system-health-check.fish"
        "scripts/bash/server-setup.sh:scripts/configuration/bash/server-setup.sh"
        "scripts/bash/disk-cleanup.sh:scripts/maintenance/bash/disk-cleanup.sh"
        "scripts/bash/ssl-checker.sh:scripts/security/bash/ssl-checker.sh"
        "scripts/bash/user-audit.sh:scripts/security/bash/user-audit.sh"
        "scripts/bash/system-update.sh:scripts/maintenance/bash/system-update.sh"
        "scripts/bash/security-audit.sh:scripts/security/bash/security-audit.sh"
        "scripts/bash/network-diagnostics.sh:scripts/monitoring/bash/network-diagnostics.sh"
        "scripts/bash/ssh-hardening.sh:scripts/security/bash/ssh-hardening.sh"
        "scripts/bash/firewall-setup.sh:scripts/security/bash/firewall-setup.sh"
        "scripts/bash/config-backup.sh:scripts/maintenance/bash/config-backup.sh"
        "scripts/bash/database-backup.sh:scripts/maintenance/bash/database-backup.sh"
        "scripts/bash/docker-management.sh:scripts/infrastructure/bash/docker-management.sh"
    )

    for replacement in "${replacements[@]}"; do
        local old_path="${replacement%%:*}"
        local new_path="${replacement##*:}"
        sed -i.bak "s|$old_path|$new_path|g" "$rsr_file"
    done

    rm -f "${rsr_file}.bak"
    log_ok "Updated paths in rsr CLI"
}

# =============================================================================
# Migration: Create Compatibility Symlinks
# =============================================================================

create_compat_symlinks() {
    log_section "Creating Compatibility Symlinks"

    cd "$ROOT_DIR"

    if $DRY_RUN; then
        log_info "[DRY-RUN] Would create backward-compatibility symlinks"
        return
    fi

    # Create symlinks from old locations to new
    # This allows existing references to continue working

    # Recreate old directories as symlink containers
    ensure_dir "scripts/bash"
    ensure_dir "scripts/powershell"

    # Create symlinks for bash scripts
    for script in "${!SCRIPT_CATEGORIES[@]}"; do
        local category="${SCRIPT_CATEGORIES[$script]}"
        local new_path="../$category/bash/$script"
        local link_path="scripts/bash/$script"

        if [[ -f "scripts/$category/bash/$script" ]] && [[ ! -e "$link_path" ]]; then
            create_symlink "$new_path" "$link_path"
        fi
    done

    # Create symlinks for PowerShell scripts
    for script in "${!PS_SCRIPT_CATEGORIES[@]}"; do
        local category="${PS_SCRIPT_CATEGORIES[$script]}"
        local new_path="../$category/powershell/$script"
        local link_path="scripts/powershell/$script"

        if [[ -f "scripts/$category/powershell/$script" ]] && [[ ! -e "$link_path" ]]; then
            create_symlink "$new_path" "$link_path"
        fi
    done

    # Lib symlinks
    for lib in "${!LIB_COMMON[@]}"; do
        local new_path="common/$lib"
        local link_path="lib/$lib"
        if [[ -f "lib/common/$lib" ]] && [[ ! -e "$link_path" ]]; then
            create_symlink "$new_path" "$link_path"
        fi
    done

    for lib in "${!LIB_CONNECTORS[@]}"; do
        local new_path="connectors/$lib"
        local link_path="lib/$lib"
        if [[ -f "lib/connectors/$lib" ]] && [[ ! -e "$link_path" ]]; then
            create_symlink "$new_path" "$link_path"
        fi
    done

    log_ok "Compatibility symlinks created"
}

# =============================================================================
# Summary
# =============================================================================

print_summary() {
    log_section "Migration Summary"

    if $DRY_RUN; then
        printf "${YELLOW}DRY RUN - No changes were made${NC}\n\n"
    fi

    cat << EOF
Directory Structure Changes:
  scripts/
    ├── monitoring/bash/      (health checks, diagnostics)
    ├── configuration/bash/   (server setup, user management)
    ├── infrastructure/bash/  (docker management)
    ├── security/bash/        (auditing, hardening, firewall)
    ├── maintenance/bash/     (cleanup, updates, backups)
    ├── network/bash/         (DNS, network tools)
    └── data/bash/            (git sync, data tools)

  lib/
    ├── common/               (common.sh, config.sh, interactive.sh)
    ├── connectors/           (docker.sh, ssh.sh, users.sh)
    └── powershell/           (users.ps1)

  config/
    ├── environments/{dev,staging,prod}/
    ├── defaults/base.yaml
    └── schemas/registry.schema.json

  logs/                       (gitignored)
  tmp/                        (gitignored)

Updated Files:
  - scripts/registry.json     (new script paths)
  - rsr                       (updated get_script_path)
  - .gitignore               (logs/, tmp/)

EOF

    if ! $DRY_RUN; then
        printf "${GREEN}Migration complete!${NC}\n\n"
        printf "Backup location: ${CYAN}%s${NC}\n" "$BACKUP_DIR"
        printf "To rollback: ${CYAN}./tools/migrate-to-v2.sh --rollback${NC}\n"
    else
        printf "Run without ${YELLOW}--dry-run${NC} to apply changes.\n"
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"

    printf "${BOLD}${CYAN}"
    cat << 'EOF'
 ____  ____  ____    __  __ _                 _   _
|  _ \/ ___||  _ \  |  \/  (_) __ _ _ __ __ _| |_(_) ___  _ __
| |_) \___ \| |_) | | |\/| | |/ _` | '__/ _` | __| |/ _ \| '_ \
|  _ < ___) |  _ <  | |  | | | (_| | | | (_| | |_| | (_) | | | |
|_| \_\____/|_| \_\ |_|  |_|_|\__, |_|  \__,_|\__|_|\___/|_| |_|
                              |___/  v2 Architecture Migration
EOF
    printf "${NC}\n"

    if $ROLLBACK; then
        rollback_migration
        exit 0
    fi

    # Verify we're in the right directory
    if [[ ! -f "$ROOT_DIR/rsr" ]] || [[ ! -d "$ROOT_DIR/scripts" ]]; then
        log_error "Must be run from the remote-script-runner repository root"
        exit 1
    fi

    create_backup
    migrate_scripts
    migrate_lib
    migrate_config
    migrate_local_dirs
    update_registry
    update_rsr_cli
    create_compat_symlinks
    print_summary
}

main "$@"
