# Package Management System - Multi-Method Installation

**Date:** 2025-12-11  
**Version:** 2.0.0

## Overview

Comprehensive cross-platform package management system with:

- **Multi-method installation**: Specify different installation methods per package (homebrew, winget, apt, etc.)
- **Automatic fallback**: Try multiple methods until one succeeds
- **Windows support**: Added winget (Windows Package Manager) alongside Chocolatey
- **Cross-platform profiles**: Single YAML works on macOS, Linux, and Windows
- **YAML-based profiles**: Interactive dependency handling and automatic package name mapping

## What Was Implemented

### 1. Core Module (`lib/modules/packages.sh`)

A full-featured package management module with:

- ✅ **Cross-platform support**: apt, dnf, yum, pacman, zypper, apk, brew, **winget**, choco
- ✅ **Multi-method installation**: Try multiple installation methods per package with automatic fallback
- ✅ **Package manager abstraction**: Single API for all package managers
- ✅ **Dependency checking**: Interactive prompts for missing dependencies
- ✅ **Package name mapping**: Automatic translation (e.g., `httpd` → `apache2` on Debian)
- ✅ **YAML profile support**: Install packages from predefined profiles
- ✅ **Cache management**: Smart cache updates with age tracking
- ✅ **Installation functions**: Single package, multiple packages, from YAML
- ✅ **Status checking**: `rsr_pkg_is_installed`, `rsr_pkg_version`
- ✅ **Cleanup functions**: Cache cleaning and package removal

### 2. Package Profiles (13 YAML files in `config/packages/`)

| Profile | Packages | Description |
|---------|----------|-------------|
| `minimal.yaml` | 8 packages | Essential tools (curl, git, vim, htop, jq) |
| `development.yaml` | 20+ packages | Development tools, build essentials |
| `webserver.yaml` | 10+ packages | nginx, certbot, SSL utilities |
| `docker.yaml` | 5+ packages | Docker, docker-compose, container tools |
| `database.yaml` | 15+ packages | Database clients (MySQL, PostgreSQL, Redis) |
| `monitoring.yaml` | 20+ packages | System monitoring (htop, iotop, sysstat) |
| `security.yaml` | 15+ packages | Security tools (fail2ban, ufw, lynis) |
| `python.yaml` | 10+ packages | Python environment, pip, venv |
| `nodejs.yaml` | 8+ packages | Node.js, npm, yarn |
| `kubernetes.yaml` | 15+ packages | kubectl, helm, k9s |
| `network.yaml` | 25+ packages | Network diagnostics (nmap, tcpdump) |
| `devops.yaml` | 20+ packages | DevOps tools (ansible, terraform) |
| `server.yaml` | 30+ packages | Complete server (includes minimal+security+monitoring) |

### 3. User-Facing Script (`scripts/system/packages/install-packages.sh`)

Interactive command-line tool with:

- ✅ List available profiles (`--list`)
- ✅ Show profile details (`--info PROFILE`)
- ✅ Install single or multiple profiles
- ✅ Auto-install mode (`--auto`)
- ✅ Dry-run mode (`--dry-run`)
- ✅ Verbose output (`--verbose`)
- ✅ Help and version information

### 4. Documentation

- ✅ `config/packages/README.md` - Complete user guide
- ✅ Inline documentation in all YAML files
- ✅ API reference and examples

### 5. Integration

- ✅ Updated `lib/rsr-lib.sh` to load packages module
- ✅ Updated `scripts/registry.json` with new script entry
- ✅ Added "packages" subcategory to system category

## Usage Examples

### Basic Usage

```bash
# List available profiles
./scripts/system/packages/install-packages.sh --list

# Show profile details
./scripts/system/packages/install-packages.sh --info development

# Install a profile
./scripts/system/packages/install-packages.sh development

# Install multiple profiles
./scripts/system/packages/install-packages.sh minimal security monitoring

# Auto-install without prompts (for CI/CD)
./scripts/system/packages/install-packages.sh --auto development
```

### In Scripts

```bash
#!/bin/bash
source lib/rsr-lib.sh packages

# Check dependencies (offers to install if missing)
rsr_pkg_check_deps "git" "curl" "jq"

# Require dependencies (exits if not available)
rsr_pkg_require_deps "docker" "docker-compose"

# Install packages
rsr_pkg_install "nginx"
rsr_pkg_install_many "git" "vim" "htop"

# Install from profile
rsr_pkg_install_profile "development"

# Check status
if rsr_pkg_is_installed "docker"; then
    echo "Docker version: $(rsr_pkg_version docker)"
fi
```

### Environment Variables

```bash
# Auto-install dependencies without prompts
RSR_PKG_AUTO_INSTALL=1 ./my-script.sh

# Skip confirmation prompts
RSR_PKG_CONFIRM=0 rsr_pkg_install_profile development

# Custom package lists directory
RSR_PKG_LISTS_DIR=/etc/rsr/packages rsr_pkg_list_profiles
```

## Key Features

### 1. Cross-Platform Package Name Mapping

Automatically handles distro-specific package names:

| Generic Name | Debian/Ubuntu | RHEL/Fedora | macOS | Alpine |
|--------------|---------------|-------------|-------|--------|
| `build-essential` | `build-essential` | `gcc gcc-c++ make` | `gcc make` | `build-base` |
| `python` | `python3` | `python3` | `python@3` | `python3` |
| `httpd` | `apache2` | `httpd` | `httpd` | `apache2` |
| `mysql-client` | `mysql-client` | `mysql` | `mysql-client` | `mysql-client` |
| `netcat` | `netcat-openbsd` | `nmap-ncat` | `netcat` | `netcat-openbsd` |

### 2. Interactive Dependency Management

Scripts can check for dependencies and offer to install them:

```bash
# In your script
rsr_pkg_check_deps "git" "curl" "jq"

# Output:
# ⚠ Missing dependencies: git jq
# ? Install missing dependencies? [y/N]
```

### 3. Platform-Specific Handling

YAML profiles include platform overrides:

```yaml
packages:
  - build-essential
  - python3

platforms:
  darwin:
    packages:
      - python@3
    skip:
      - build-essential
    note: "Xcode Command Line Tools provides build essentials"
  
  alpine:
    packages:
      - build-base
    skip:
      - build-essential
```

### 4. Cache Management

Intelligent cache handling:

- Only updates cache if older than `RSR_PKG_CACHE_MAX_AGE` (default: 1 hour)
- Checks cache file modification time
- Supports all major package managers

## API Reference

### Package Management Functions

```bash
# Core functions
rsr_pkg_manager                      # Get package manager (apt, dnf, brew, etc.)
rsr_pkg_install "package"            # Install single package
rsr_pkg_install_many "p1" "p2" "p3"  # Install multiple packages
rsr_pkg_remove "package"             # Remove package

# Status functions
rsr_pkg_is_installed "package"       # Check if installed (returns 0/1)
rsr_pkg_version "package"            # Get installed version

# Dependency management
rsr_pkg_check_deps "p1" "p2"         # Check and offer to install
rsr_pkg_require_deps "p1" "p2"       # Require or exit

# Profile management
rsr_pkg_install_profile "name"       # Install from profile
rsr_pkg_list_profiles                # List available profiles
rsr_pkg_install_from_yaml "file"     # Install from YAML file

# Utilities
rsr_pkg_update_cache                 # Update package cache
rsr_pkg_clean                        # Clean package cache
rsr_pkg_map_name "generic"           # Map to distro-specific name
rsr_pkg_info                         # Show package manager info
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RSR_PKG_AUTO_INSTALL` | `0` | Auto-install without prompts (1=yes) |
| `RSR_PKG_CONFIRM` | `1` | Show confirmation prompts (0=skip) |
| `RSR_PKG_UPDATE_CACHE` | `1` | Update cache before install (0=skip) |
| `RSR_PKG_CACHE_MAX_AGE` | `3600` | Cache freshness in seconds |
| `RSR_PKG_LISTS_DIR` | `config/packages` | Package profiles directory |

## File Structure

```
config/packages/               # Package profile definitions
├── README.md                  # User documentation
├── minimal.yaml              # Essential packages
├── development.yaml          # Dev tools
├── webserver.yaml            # Web server
├── docker.yaml               # Container platform
├── database.yaml             # Database clients
├── monitoring.yaml           # Monitoring tools
├── security.yaml             # Security tools
├── python.yaml               # Python environment
├── nodejs.yaml               # Node.js environment
├── kubernetes.yaml           # K8s tools
├── network.yaml              # Network tools
├── devops.yaml               # DevOps tools
└── server.yaml               # Complete server

lib/modules/
└── packages.sh               # Core package management module

scripts/system/packages/
└── install-packages.sh       # User-facing CLI tool
```

## Testing

Test the package management system:

```bash
# Test library loading
bash -c 'source lib/rsr-lib.sh packages && rsr_pkg_info'

# Test profile listing
./scripts/system/packages/install-packages.sh --list

# Test profile details
./scripts/system/packages/install-packages.sh --info minimal

# Test dry-run
./scripts/system/packages/install-packages.sh --dry-run minimal

# Test actual installation (requires sudo for most packages)
sudo ./scripts/system/packages/install-packages.sh minimal
```

## Integration Examples

### CI/CD Pipeline

```yaml
# .github/workflows/setup.yml
- name: Install development dependencies
  run: |
    RSR_PKG_AUTO_INSTALL=1 RSR_PKG_CONFIRM=0 \
      ./scripts/system/packages/install-packages.sh development
```

### Ansible Playbook

```yaml
- name: Install RSR package profile
  shell: |
    RSR_PKG_AUTO_INSTALL=1 \
      /opt/rsr/scripts/system/packages/install-packages.sh {{ profile_name }}
  vars:
    profile_name: "server"
```

### Docker Dockerfile

```dockerfile
FROM ubuntu:22.04

# Install RSR
COPY . /opt/rsr

# Install minimal profile
RUN RSR_PKG_AUTO_INSTALL=1 RSR_PKG_CONFIRM=0 \
    /opt/rsr/scripts/system/packages/install-packages.sh minimal
```

## Benefits

### For Users

- ✅ Simple, consistent interface across platforms
- ✅ Predefined profiles for common use cases
- ✅ Interactive prompts for missing dependencies
- ✅ No manual package manager commands needed

### For Developers

- ✅ Easy dependency declaration in scripts
- ✅ Automatic package name translation
- ✅ Cross-platform compatibility
- ✅ Testable with dry-run mode

### For Operations

- ✅ Automated dependency installation
- ✅ CI/CD friendly (auto-install mode)
- ✅ Consistent environment setup
- ✅ Audit trail with verbose mode

## New Features (v2.0.0)

### Multi-Method Installation

Packages can now specify different installation methods:

```yaml
packages:
  - name: kubectl
    brew: kubectl
    winget: Kubernetes.kubectl
    choco: kubernetes-cli
    apt: kubectl
    dnf: kubectl
```

**Benefits:**

- Single profile works across macOS, Linux, and Windows
- Automatic fallback if preferred method unavailable
- Handles platform-specific package naming (e.g., `fd` vs `fd-find`)

### Windows Package Manager (winget)

Added full support for winget:

- Automatic detection (prioritized over Chocolatey on Windows 11+)
- Install, remove, check, version, and cache operations
- Integration with multi-method system

### Method Selection Logic

New functions:

- `rsr_pkg_install_with_method()` - Install using specific method
- `rsr_pkg_try_methods()` - Try multiple methods in order
- `rsr_pkg_available_methods()` - List available methods

### Bootstrap Architecture

Smart handling for minimal systems where YAML parser dependencies might be missing:

**Problem:** Can't offer to install a missing package if the parser itself is missing.

**Solution:** Three-tier parser architecture:

1. **Full parser** - Uses sed/grep/awk for extended format support
2. **Pure-shell parser** - POSIX builtins only, no external deps
3. **Bootstrap installer** - Direct package installation without parsing

```bash
# Check if bootstrap needed
rsr_pkg_needs_bootstrap

# Bootstrap the system
rsr_pkg_bootstrap
```

The bootstrap process:

1. Detects missing core tools (sed, grep, awk)
2. Attempts automatic installation via detected package manager
3. Falls back to pure-shell parser if tools unavailable
4. Installs `bootstrap.yaml` profile (simple format only)

New functions:

- `rsr_pkg_bootstrap()` - Bootstrap system with core tools
- `rsr_pkg_needs_bootstrap()` - Check if bootstrap needed
- `rsr_pkg_bootstrap_install()` - Direct install without YAML
- `_rsr_parse_yaml_pure_shell()` - Fallback parser

### Updated Profiles

Profiles updated with multi-method definitions:

- `kubernetes.yaml` - kubectl, helm, k9s, kubectx
- `devops.yaml` - terraform, ansible, vault, awscli
- `docker.yaml` - docker, docker-compose, podman
- `development.yaml` - neovim, fzf, ripgrep, bat, fd
- `bootstrap.yaml` - Core tools for minimal systems (simple format)

## Next Steps

### Potential Enhancements

1. **Version pinning**: Support `package@version` syntax
2. **Rollback support**: Track installed packages for undo
3. **Homebrew casks**: macOS GUI applications
4. **Post-install hooks**: Run commands after installation
5. **Dependency resolution**: Handle package dependencies
6. **Remote profiles**: Fetch profiles from URLs
7. **Profile validation**: JSON schema for YAML files

### Creating Custom Profiles

Users can create custom profiles in `config/packages/`:

```yaml
# config/packages/my-profile.yaml
name: my-profile
description: My custom setup
version: "1.0.0"
category: custom

packages:
  - git
  - vim
  - my-tool

platforms:
  darwin:
    skip:
      - my-tool
```

## Summary

✅ **Complete package management system implemented**

- 13 predefined package profiles
- Cross-platform support (Linux, macOS, Windows)
- Interactive dependency handling
- User-friendly CLI tool
- Comprehensive documentation
- Full integration with RSR library

**Status**: Ready for production use! 🎉
