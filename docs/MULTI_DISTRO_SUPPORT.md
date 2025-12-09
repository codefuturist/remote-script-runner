# Multi-Distribution Linux Support

## Overview

git-auto-sync supports multiple Linux distributions with automatic detection and adaptation to distro-specific conventions.

## Supported Distributions

### Debian Family
- **Debian** (8+, Jessie and newer)
- **Ubuntu** (15.04+)
- **Linux Mint**
- **Pop!_OS**
- **Elementary OS**

### Red Hat Family
- **RHEL** (Red Hat Enterprise Linux 7+)
- **CentOS** (7+)
- **Fedora** (all recent versions)
- **Rocky Linux**
- **AlmaLinux**
- **Oracle Linux**

### SUSE Family
- **openSUSE** (Leap, Tumbleweed)
- **SLES** (SUSE Linux Enterprise Server)

### Arch Family
- **Arch Linux**
- **Manjaro**
- **EndeavourOS**

### Other
- **Alpine Linux**
- **Gentoo**

## Automatic Detection

The script automatically detects:

1. **Distribution Family** - Debian, RHEL, SUSE, Arch, Alpine, etc.
2. **Package Manager** - apt, dnf, yum, zypper, pacman, apk
3. **Init System** - SystemD, OpenRC, SysVinit
4. **Configuration Paths** - Adapts to distro conventions

## Distribution-Specific Adaptations

### Configuration File Locations

#### Debian/Ubuntu Family
```
/etc/git-auto-sync/config.yaml          # Main configuration
/etc/default/git-auto-sync              # Environment variables
/etc/systemd/system/git-auto-sync.service  # SystemD service
```

#### RHEL/CentOS/Fedora Family
```
/etc/git-auto-sync/config.yaml          # Main configuration
/etc/sysconfig/git-auto-sync            # Environment variables (RHEL convention)
/etc/systemd/system/git-auto-sync.service  # SystemD service
```

#### SUSE Family
```
/etc/git-auto-sync/config.yaml          # Main configuration
/etc/sysconfig/git-auto-sync            # Environment variables (SUSE convention)
/etc/systemd/system/git-auto-sync.service  # SystemD service
```

#### Alpine Linux (OpenRC)
```
/etc/git-auto-sync/config.yaml          # Main configuration
/etc/init.d/git-auto-sync               # OpenRC init script
```

#### Arch Linux
```
/etc/git-auto-sync/config.yaml          # Main configuration
/etc/default/git-auto-sync              # Environment variables
/etc/systemd/system/git-auto-sync.service  # SystemD service
```

## Package Installation

### YAML Parser (Required)

#### Debian/Ubuntu
```bash
# Option 1: yq (recommended)
sudo apt update
sudo apt install yq

# Option 2: python3-yaml
sudo apt install python3-yaml
```

#### RHEL/CentOS/Fedora
```bash
# Fedora/RHEL 8+
sudo dnf install yq
# or
sudo dnf install python3-pyyaml

# CentOS 7/RHEL 7
sudo yum install python3-pyyaml
```

#### SUSE/openSUSE
```bash
sudo zypper install yq
# or
sudo zypper install python3-PyYAML
```

#### Arch Linux
```bash
sudo pacman -S yq
# or
sudo pacman -S python-yaml
```

#### Alpine Linux
```bash
sudo apk add yq
# or
sudo apk add py3-yaml
```

### Git (Required)

#### Debian/Ubuntu
```bash
sudo apt install git
```

#### RHEL/CentOS/Fedora
```bash
sudo dnf install git     # Fedora/RHEL 8+
sudo yum install git     # CentOS 7/RHEL 7
```

#### SUSE/openSUSE
```bash
sudo zypper install git
```

#### Arch Linux
```bash
sudo pacman -S git
```

#### Alpine Linux
```bash
sudo apk add git
```

## Installation by Distribution

### Debian/Ubuntu

```bash
# Install dependencies
sudo apt update
sudo apt install git yq

# Install git-auto-sync
sudo cp git-auto-sync.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/git-auto-sync.sh

# Setup configuration
sudo mkdir -p /etc/git-auto-sync
sudo cp examples/config.yaml /etc/git-auto-sync/
sudo cp examples/default-git-auto-sync /etc/default/git-auto-sync

# Setup SystemD service
sudo cp examples/systemd-service /etc/systemd/system/git-auto-sync.service
sudo systemctl daemon-reload
sudo systemctl enable --now git-auto-sync

# Check status
sudo systemctl status git-auto-sync
```

### RHEL/CentOS/Fedora

```bash
# Install dependencies
sudo dnf install git python3-pyyaml  # Fedora/RHEL 8+
# or
sudo yum install git python3-pyyaml  # CentOS 7/RHEL 7

# Install git-auto-sync
sudo cp git-auto-sync.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/git-auto-sync.sh

# Setup configuration
sudo mkdir -p /etc/git-auto-sync
sudo cp examples/config.yaml /etc/git-auto-sync/
sudo cp examples/sysconfig-git-auto-sync /etc/sysconfig/git-auto-sync

# Setup SystemD service
sudo cp examples/systemd-service /etc/systemd/system/git-auto-sync.service
# Edit service to use /etc/sysconfig instead of /etc/default
sudo sed -i 's|/etc/default/|/etc/sysconfig/|' /etc/systemd/system/git-auto-sync.service
sudo systemctl daemon-reload
sudo systemctl enable --now git-auto-sync

# Check status
sudo systemctl status git-auto-sync
```

### Alpine Linux (OpenRC)

```bash
# Install dependencies
sudo apk add git yq

# Install git-auto-sync
sudo cp git-auto-sync.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/git-auto-sync.sh

# Setup configuration
sudo mkdir -p /etc/git-auto-sync
sudo mkdir -p /var/log/git-auto-sync
sudo mkdir -p /var/lib/git-auto-sync
sudo cp examples/config.yaml /etc/git-auto-sync/

# Setup OpenRC service
sudo cp examples/openrc-init /etc/init.d/git-auto-sync
sudo chmod +x /etc/init.d/git-auto-sync

# Enable and start service
sudo rc-update add git-auto-sync default
sudo rc-service git-auto-sync start

# Check status
sudo rc-service git-auto-sync status
```

### Arch Linux

```bash
# Install dependencies
sudo pacman -S git yq

# Install git-auto-sync
sudo cp git-auto-sync.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/git-auto-sync.sh

# Setup configuration
sudo mkdir -p /etc/git-auto-sync
sudo cp examples/config.yaml /etc/git-auto-sync/
sudo cp examples/default-git-auto-sync /etc/default/git-auto-sync

# Setup SystemD service
sudo cp examples/systemd-service /etc/systemd/system/git-auto-sync.service
sudo systemctl daemon-reload
sudo systemctl enable --now git-auto-sync

# Check status
sudo systemctl status git-auto-sync
```

## Detection Utility

Use the distribution detection utility to see what the script detects:

```bash
bash scripts/bash/detect-distro.sh
```

Output example:
```
╔═══════════════════════════════════════════════════════════════╗
║           Linux Distribution Detection                         ║
╚═══════════════════════════════════════════════════════════════╝

✓ Operating System: Linux
✓ Distribution: Ubuntu 22.04 LTS
  ID: ubuntu
  Version: 22.04

✓ Distribution Family: debian
✓ Package Manager: apt

✓ Init System: SystemD (version 249)

YAML Parser Detection:
✓ yq: version 4.x
✓ python3-yaml: version 6.0

Installation Recommendations
Paths for this system:
  Config:      /etc/git-auto-sync/config.yaml
  Environment: /etc/default/git-auto-sync
  Service:     /etc/systemd/system/git-auto-sync.service
```

## Service Management

### SystemD (Debian, Ubuntu, RHEL, Fedora, Arch, SUSE)

```bash
# Start service
sudo systemctl start git-auto-sync

# Stop service
sudo systemctl stop git-auto-sync

# Restart service
sudo systemctl restart git-auto-sync

# Enable on boot
sudo systemctl enable git-auto-sync

# Disable on boot
sudo systemctl disable git-auto-sync

# Check status
sudo systemctl status git-auto-sync

# View logs
sudo journalctl -u git-auto-sync -f
```

### OpenRC (Alpine, Gentoo)

```bash
# Start service
sudo rc-service git-auto-sync start

# Stop service
sudo rc-service git-auto-sync stop

# Restart service
sudo rc-service git-auto-sync restart

# Enable on boot
sudo rc-update add git-auto-sync default

# Remove from boot
sudo rc-update del git-auto-sync default

# Check status
sudo rc-service git-auto-sync status

# View logs
sudo tail -f /var/log/git-auto-sync/git-auto-sync.log
```

## Configuration Files

All distributions use the same YAML configuration format:

```yaml
# /etc/git-auto-sync/config.yaml
validation:
  enabled: true
  max_retries: 3
  rollback_on_failure: true

quick_check:
  enabled: true
  interval: 30

repositories:
  - name: example
    path: /etc/example
    branch: main
    mode: safe
```

Environment files vary by distro but have the same variables:
- `/etc/default/git-auto-sync` (Debian, Ubuntu, Arch)
- `/etc/sysconfig/git-auto-sync` (RHEL, CentOS, Fedora, SUSE)

## Troubleshooting by Distribution

### Debian/Ubuntu

```bash
# Check service status
sudo systemctl status git-auto-sync

# View logs
sudo journalctl -u git-auto-sync -n 50

# Check config
sudo cat /etc/git-auto-sync/config.yaml
yq eval '.' /etc/git-auto-sync/config.yaml

# Test manually
sudo -u git-sync /usr/local/bin/git-auto-sync.sh --config /etc/git-auto-sync/config.yaml
```

### RHEL/CentOS/Fedora

```bash
# Check service status
sudo systemctl status git-auto-sync

# View logs
sudo journalctl -u git-auto-sync -n 50

# Check SELinux (if enabled)
sudo ausearch -m avc -ts recent

# Test manually
sudo -u git-sync /usr/local/bin/git-auto-sync.sh --config /etc/git-auto-sync/config.yaml
```

### Alpine Linux

```bash
# Check service status
sudo rc-service git-auto-sync status

# View logs
sudo tail -50 /var/log/git-auto-sync/git-auto-sync.log

# Test manually
sudo -u git-sync /usr/local/bin/git-auto-sync.sh --config /etc/git-auto-sync/config.yaml
```

## Distribution-Specific Notes

### RHEL/CentOS
- Uses `/etc/sysconfig/` instead of `/etc/default/`
- SELinux may need configuration for git operations
- RHEL 7 uses Python 3.6, ensure python3-pyyaml is installed

### Alpine Linux
- Uses OpenRC instead of SystemD
- Lightweight, minimal dependencies
- Uses musl libc instead of glibc

### Arch Linux
- Rolling release, always latest packages
- Package names may differ (python-yaml vs python3-yaml)

### SUSE
- Uses `/etc/sysconfig/` like RHEL
- zypper package manager

## Container Support

Works in containers on all distributions:

```dockerfile
# Debian-based
FROM debian:12
RUN apt-get update && apt-get install -y git yq

# Alpine-based
FROM alpine:latest
RUN apk add --no-cache git yq

# RHEL-based
FROM rockylinux:9
RUN dnf install -y git python3-pyyaml
```

## Summary

git-auto-sync automatically adapts to your Linux distribution:
- ✓ Auto-detects distribution family
- ✓ Uses correct package manager
- ✓ Follows distro-specific file layout conventions
- ✓ Supports SystemD and OpenRC init systems
- ✓ Works on Debian, RHEL, SUSE, Arch, Alpine, and more
