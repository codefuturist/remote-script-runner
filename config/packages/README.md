# RSR Package Management

Cross-platform package management with predefined profiles and interactive dependency handling.

## Quick Start

### Shell (Linux/macOS)

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

### PowerShell (Windows/Cross-platform)

```powershell
# Interactive wizard (recommended for first-time users)
.\rsr.ps1 pkg
Start-RSRPackageWizard

# List available profiles
.\rsr.ps1 pkg -List
.\scripts\packages\Install-PackageProfile.ps1 -List

# Install a profile (with interactive confirmation)
.\rsr.ps1 pkg -Profile core

# Install a profile (no prompts)
.\rsr.ps1 pkg -Profile core -Force

# Install a specific group
.\rsr.ps1 pkg -Profile development.languages.python

# Show profile information
.\rsr.ps1 pkg -Info development

# List groups in a profile
.\rsr.ps1 pkg -Groups development
```

## Interactive Mode

RSR supports interactive installation with guided wizards and confirmation prompts.

### PowerShell Interactive Wizard

The interactive wizard guides you through profile and group selection:

```powershell
# Launch wizard (no arguments)
.\rsr.ps1 pkg

# Or explicitly
Start-RSRPackageWizard
```

**Wizard Flow:**

1. Select a profile (core, development, infrastructure, etc.)
2. Optionally select specific groups within the profile
3. Review installation summary
4. Confirm and install

### Confirmation Prompts

By default, PowerShell package installation prompts for confirmation:

```powershell
# Will prompt: "Install package 'git' using winget?"
Install-RSRPackage 'git'

# Bypass prompts with -Force
Install-RSRPackage 'git' -Force
```

### Environment Variables

Control interactive behavior with environment variables:

```powershell
# Disable confirmation prompts
$env:RSR_PKG_CONFIRM = '0'

# Enable auto-install (bypass all prompts)
$env:RSR_PKG_AUTO_INSTALL = '1'

# Then install packages
Install-RSRPackageProfile 'core'
```

**Shell equivalent:**

```bash
# Disable confirmation
export RSR_PKG_CONFIRM=0

# Enable auto-install
export RSR_PKG_AUTO_INSTALL=1

rsr_pkg_install_profile core
```

## Package Groups (v2.0)

New consolidated profiles organize packages into hierarchical groups:

### Shell

```bash
# List groups in a profile
source lib/rsr-lib.sh packages
rsr_pkg_list_groups development

# Install entire profile (all groups)
rsr_pkg_install_profile development

# Install specific group
rsr_pkg_install_profile development.languages.python

# Install nested group
rsr_pkg_install_profile infrastructure.containers.docker

# Install multiple groups
rsr_pkg_install_profile core.minimal
rsr_pkg_install_profile development.tools.modern
```

### PowerShell

```powershell
# List groups in a profile
Get-RSRPackageGroups -Profile development

# Install entire profile (all groups)
Install-RSRPackageProfile -Profile development

# Install specific group
Install-RSRPackageProfile -Profile development.languages.python

# Install nested group
Install-RSRPackageProfile -Profile infrastructure.containers.docker
```

### New Consolidated Profiles

- **core.yaml** - Bootstrap, minimal, shell enhancements
- **development-v2.yaml** - Languages (python, nodejs, rust, go), tools (modern CLI, editors)
- **infrastructure-v2.yaml** - Containers, cloud (AWS, GCP, Azure), IaC, databases, monitoring
- **security.yaml** - Security tools (kept separate)

### Group Hierarchy Examples

```
core/
├── bootstrap   (sed, grep, awk, curl)
├── minimal     (git, vim, htop, jq)
├── shell       (zsh, tmux, screen)
└── runtimes/
    └── powershell  (PowerShell 7)

development/
├── essentials  (git, build tools, editors)
├── languages/
│   ├── python
│   ├── nodejs
│   ├── rust
│   └── go
└── tools/
    ├── modern  (fzf, ripgrep, bat, fd)
    ├── editors (vim, neovim, emacs)
    └── vcs     (git, mercurial)

infrastructure/
├── containers/
│   ├── docker
│   ├── kubernetes
│   └── alternative
├── cloud/
│   ├── aws
│   ├── gcp
│   └── azure
├── iac/
│   ├── terraform
│   ├── ansible
│   └── pulumi
└── databases/
    ├── postgresql
    ├── mysql
    └── redis
```

## Installing PowerShell 7

PowerShell 7 is a cross-platform shell and scripting language. RSR provides streamlined installation across all platforms.

### Quick Install

```bash
# Shell (Linux/macOS)
rsr pkg install core.runtimes.powershell

# Or using the script directly
./scripts/system/packages/install-packages.sh core.runtimes.powershell
```

```powershell
# PowerShell (Windows)
.\rsr.ps1 pkg -Profile core.runtimes.powershell
```

### Platform-Specific Installation

#### macOS (Homebrew)

PowerShell is installed as a Homebrew cask:

```bash
# Stable release
brew install --cask powershell

# Preview release
brew install --cask powershell-preview

# Launch PowerShell
pwsh
```

#### Windows (WinGet - Recommended)

```powershell
# Stable release
winget install --id Microsoft.PowerShell --source winget

# Preview release
winget install --id Microsoft.PowerShell.Preview --source winget
```

#### Windows (Chocolatey - Alternative)

```powershell
choco install powershell-core
```

#### Linux (Requires Repository Setup)

Linux distributions require adding Microsoft's repository first:

```bash
# Setup Microsoft repository (run once)
sudo ./scripts/packages/setup-powershell-repo.sh

# Then install PowerShell
# Debian/Ubuntu:
sudo apt-get install -y powershell

# RHEL/Fedora:
sudo dnf install -y powershell

# Or use RSR after repo setup:
rsr pkg install core.runtimes.powershell
```

### Linux Repository Setup Helper

The `setup-powershell-repo.sh` script automates Microsoft repository configuration:

```bash
# Check if repository is configured
./scripts/packages/setup-powershell-repo.sh --check

# Setup repository (auto-detects distribution)
sudo ./scripts/packages/setup-powershell-repo.sh

# Force reconfiguration
sudo ./scripts/packages/setup-powershell-repo.sh --force

# Remove repository
sudo ./scripts/packages/setup-powershell-repo.sh --remove
```

**Supported Linux distributions:**

- Ubuntu 20.04, 22.04, 24.04
- Debian 10, 11, 12
- RHEL/CentOS 7, 8, 9
- Fedora 38, 39, 40+
- Alpine Linux 3.17+

### Verifying Installation

```bash
# Check PowerShell version
pwsh --version

# Or from within PowerShell
$PSVersionTable.PSVersion
```

## Bootstrap (Minimal Systems)

For minimal systems (containers, fresh installs) that may be missing core tools:

```bash
source lib/rsr-lib.sh packages

# Check if bootstrap is needed
if rsr_pkg_needs_bootstrap; then
    rsr_pkg_bootstrap
fi

# Or bootstrap directly
rsr_pkg_bootstrap
```

The bootstrap process:

1. Detects missing core tools (sed, grep, awk)
2. Installs them using the detected package manager
3. Uses a pure-shell YAML parser that requires no external dependencies
4. Installs packages from `bootstrap.yaml` profile

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

### Shell Scripts

#### Check Dependencies

```bash
#!/bin/bash
source lib/rsr-lib.sh packages

# Check and offer to install missing dependencies
rsr_pkg_check_deps "git" "curl" "jq"

# Or require them (exit if not available/installed)
rsr_pkg_require_deps "docker" "docker-compose"
```

#### Install Packages

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

#### Package Status

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

### PowerShell Scripts

#### Check Dependencies

```powershell
#!/usr/bin/env pwsh
Import-Module ./lib/powershell/RSR.psd1

# Check if package is installed
if (Test-RSRPackageInstalled -Name 'git') {
    Write-Host "Git is installed"
} else {
    Write-Host "Git is not installed"
    Install-RSRPackage -Name 'git'
}
```

#### Install Packages

```powershell
Import-Module ./lib/powershell/RSR.psd1

# Install single package
Install-RSRPackage -Name 'git'

# Install multiple packages
Install-RSRPackages -Names @('git', 'curl', 'vim')

# Install from profile
Install-RSRPackageProfile -Profile 'development'

# Install specific group
Install-RSRPackageGroup -Profile 'development' -GroupPath 'languages.python'
```

#### Package Status

```powershell
Import-Module ./lib/powershell/RSR.psd1

# Check if installed
if (Test-RSRPackageInstalled -Name 'docker') {
    Write-Host "Docker is installed"
}

# Get version
$version = Get-RSRPackageVersion -Name 'git'
Write-Host "Git version: $version"

# Detect package manager
$mgr = Get-RSRPackageManager
Write-Host "Using package manager: $mgr"
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

Create a YAML file in `config/packages/`. Packages can be specified in two formats:

### Simple Format

Just list package names - uses detected package manager:

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

optional:
  - extra-package

platforms:
  darwin:
    packages:
      - macos-specific-package
    skip:
      - linux-only-package
```

### Extended Format (Multi-Method)

Specify different package names for different installation methods:

```yaml
packages:
  # Simple format still works
  - git
  - vim

  # Extended format with multiple methods
  - name: kubectl
    brew: kubectl
    winget: Kubernetes.kubectl
    choco: kubernetes-cli
    apt: kubectl
    dnf: kubectl

  # Partial method specification
  - name: neovim
    brew: neovim
    winget: Neovim.Neovim
    apt: neovim
```

**How it works:**

- System tries available methods in order until one succeeds
- Falls back to detected package manager if no method specified
- Logs which method was used for each package

### YAML Structure

```yaml
name: string           # Profile name
description: string    # Human-readable description
version: string        # Profile version
category: string       # Category for grouping

packages:              # Main packages to install
  # Simple format (backward compatible)
  - package1
  - package2

  # Extended format with multiple installation methods
  - name: package3
    brew: brew-package-name
    winget: Vendor.Package
    choco: choco-package
    apt: apt-package
    dnf: dnf-package
    yum: yum-package
    pacman: pacman-package

optional:              # Optional packages (not installed by default)
  - opt-package1

  # Can also use extended format in optional
  - name: opt-package2
    brew: opt-brew-pkg
    winget: Vendor.OptPackage

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

### Multi-Method Package Format

The extended package format allows specifying different package names for each installation method:

```yaml
packages:
  - name: terraform      # Generic/common name
    brew: terraform      # Homebrew (macOS)
    winget: Hashicorp.Terraform  # winget (Windows 11+)
    choco: terraform     # Chocolatey (Windows)
    apt: terraform       # APT (Debian/Ubuntu)
    dnf: terraform       # DNF (Fedora/RHEL 8+)
```

**Benefits:**

- Cross-platform profiles work on macOS, Linux, and Windows
- Automatic fallback if preferred method unavailable
- Package names can differ per platform (e.g., `fd` vs `fd-find`)
- Clear documentation of where each package comes from

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

| Manager | Platforms | Detection | User-space |
|---------|-----------|-----------|------------|
| `apt` | Debian, Ubuntu | `apt-get` command | No (requires sudo) |
| `dnf` | Fedora, RHEL 8+ | `dnf` command | No (requires sudo) |
| `yum` | CentOS, RHEL 7 | `yum` command | No (requires sudo) |
| `pacman` | Arch Linux | `pacman` command | No (requires sudo) |
| `zypper` | openSUSE | `zypper` command | No (requires sudo) |
| `apk` | Alpine Linux | `apk` command | No (requires sudo) |
| `brew` | macOS | `brew` command | Yes |
| `winget` | Windows 11+ | `winget` command | Yes |
| `choco` | Windows | `choco` command | Yes |

### Installation Method Priority

Each platform has a preferred order for trying installation methods:

- **macOS**: brew → script
- **Windows**: winget → choco → script
- **Debian/Ubuntu**: apt → script
- **RHEL/Fedora**: dnf → yum → script
- **Arch**: pacman → script
- **Alpine**: apk → script

See `config/packages/methods.yaml` for full priority configuration.

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
