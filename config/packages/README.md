# RSR Package Management

Cross-platform package management with predefined profiles and interactive dependency handling.

## Quick Start

```bash
# List available profiles
./scripts/system/packages/install-packages.sh --list

# Install a profile
./scripts/system/packages/install-packages.sh development

# Install multiple profiles
./scripts/system/packages/install-packages.sh minimal security monitoring

# Auto-install without prompts
./scripts/system/packages/install-packages.sh --auto development
```

## Available Profiles

| Profile | Category | Description |
|---------|----------|-------------|
| `minimal` | essentials | curl, git, vim, htop, jq, unzip |
| `development` | development | Build tools, editors, shell utilities |
| `webserver` | infrastructure | nginx, certbot, SSL tools |
| `docker` | containers | Docker, docker-compose |
| `database` | data | MySQL, PostgreSQL, Redis clients |
| `monitoring` | monitoring | htop, iotop, iftop, sysstat |
| `security` | security | fail2ban, ufw, clamav, lynis |
| `python` | languages | Python 3, pip, venv, dev tools |
| `nodejs` | languages | Node.js, npm, yarn |
| `kubernetes` | containers | kubectl, helm, k9s |
| `network` | network | nmap, tcpdump, mtr, iftop |
| `devops` | devops | ansible, terraform, vault |
| `server` | infrastructure | Complete server (minimal + security + monitoring) |

## Using in Scripts

### Check Dependencies

```bash
#!/bin/bash
source lib/rsr-lib.sh packages

# Check and offer to install missing dependencies
rsr_pkg_check_deps "git" "curl" "jq"

# Or require them (exit if not available/installed)
rsr_pkg_require_deps "docker" "docker-compose"
```

### Install Packages

```bash
source lib/rsr-lib.sh packages

# Install single package
rsr_pkg_install "nginx"

# Install multiple packages
rsr_pkg_install_many "git" "curl" "vim"

# Install from profile
rsr_pkg_install_profile "development"

# Install from custom YAML file
rsr_pkg_install_from_yaml "/path/to/packages.yaml"
```

### Package Status

```bash
source lib/rsr-lib.sh packages

# Check if installed
if rsr_pkg_is_installed "docker"; then
    echo "Docker is installed"
fi

# Get version
version=$(rsr_pkg_version "nginx")
echo "nginx version: $version"
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RSR_PKG_AUTO_INSTALL` | `0` | Auto-install missing dependencies |
| `RSR_PKG_CONFIRM` | `1` | Prompt before installing |
| `RSR_PKG_UPDATE_CACHE` | `1` | Update package cache before install |
| `RSR_PKG_CACHE_MAX_AGE` | `3600` | Cache freshness in seconds |
| `RSR_PKG_LISTS_DIR` | `config/packages` | Package profiles directory |

### Examples

```bash
# Auto-install dependencies without prompts
RSR_PKG_AUTO_INSTALL=1 ./my-script.sh

# Skip confirmation prompts
RSR_PKG_CONFIRM=0 rsr_pkg_install_profile development

# Use custom package lists directory
RSR_PKG_LISTS_DIR=/etc/rsr/packages rsr_pkg_list_profiles
```

## Creating Custom Profiles

Create a YAML file in `config/packages/`:

```yaml
# config/packages/my-profile.yaml
name: my-profile
description: My custom package profile
version: "1.0.0"
category: custom

packages:
  - git
  - vim
  - curl
  - my-custom-package

optional:
  - extra-package

platforms:
  darwin:
    packages:
      - macos-specific-package
    skip:
      - linux-only-package
  
  debian:
    packages:
      - debian-specific-package
```

### YAML Structure

```yaml
name: string           # Profile name
description: string    # Human-readable description
version: string        # Profile version
category: string       # Category for grouping

packages:              # Main packages to install
  - package1
  - package2

optional:              # Optional packages (not installed by default)
  - opt-package1

platforms:             # Platform-specific overrides
  darwin:              # macOS
    packages: []       # Additional packages
    skip: []           # Packages to skip
    note: string       # Platform note
  
  debian:              # Debian/Ubuntu
    packages: []
    skip: []
  
  rhel:                # RHEL/CentOS/Fedora
    packages: []
    skip: []
  
  alpine:              # Alpine Linux
    packages: []
    skip: []

pip_packages: []       # Python packages to install via pip
npm_packages: []       # Node packages to install via npm

includes:              # Include other profiles
  - other-profile
```

## Package Name Mapping

Generic package names are automatically mapped to distro-specific names:

| Generic | apt (Debian) | dnf (RHEL) | brew (macOS) |
|---------|--------------|------------|--------------|
| `httpd` | `apache2` | `httpd` | `httpd` |
| `build-essential` | `build-essential` | `gcc gcc-c++ make` | `gcc make` |
| `python` | `python3` | `python3` | `python@3` |
| `mysql-client` | `mysql-client` | `mysql` | `mysql-client` |
| `netcat` | `netcat-openbsd` | `nmap-ncat` | `netcat` |

## Supported Package Managers

| Manager | Platforms | Detection |
|---------|-----------|-----------|
| `apt` | Debian, Ubuntu | `apt-get` command |
| `dnf` | Fedora, RHEL 8+ | `dnf` command |
| `yum` | CentOS, RHEL 7 | `yum` command |
| `pacman` | Arch Linux | `pacman` command |
| `zypper` | openSUSE | `zypper` command |
| `apk` | Alpine Linux | `apk` command |
| `brew` | macOS | `brew` command |
| `choco` | Windows | `choco` command |

## API Reference

### Core Functions

```bash
# Package manager detection
rsr_pkg_manager                    # Get package manager name
rsr_pkg_info                       # Show package manager info

# Installation
rsr_pkg_install "pkg"              # Install single package
rsr_pkg_install_many "p1" "p2"     # Install multiple packages
rsr_pkg_remove "pkg"               # Remove package

# Status
rsr_pkg_is_installed "pkg"         # Check if installed
rsr_pkg_version "pkg"              # Get installed version

# Dependencies
rsr_pkg_check_deps "p1" "p2"       # Check (offer to install)
rsr_pkg_require_deps "p1" "p2"     # Require (exit if missing)

# Profiles
rsr_pkg_install_profile "name"     # Install profile
rsr_pkg_list_profiles              # List available profiles
rsr_pkg_install_from_yaml "file"   # Install from YAML

# Maintenance
rsr_pkg_update_cache               # Update package cache
rsr_pkg_clean                      # Clean package cache

# Utilities
rsr_pkg_map_name "generic"         # Map to distro-specific name
```

## Integration Examples

### In a Script

```bash
#!/bin/bash
set -euo pipefail

source lib/rsr-lib.sh packages

# Ensure dependencies are available
rsr_pkg_require_deps "docker" "jq" "curl"

# Your script logic here
docker --version
```

### CI/CD Pipeline

```yaml
# .github/workflows/test.yml
- name: Install dependencies
  run: |
    RSR_PKG_AUTO_INSTALL=1 RSR_PKG_CONFIRM=0 \
      ./scripts/system/packages/install-packages.sh development
```

### Ansible Integration

```yaml
- name: Install RSR development packages
  shell: |
    RSR_PKG_AUTO_INSTALL=1 \
      ./scripts/system/packages/install-packages.sh development
  args:
    chdir: /opt/remote-script-runner
```

