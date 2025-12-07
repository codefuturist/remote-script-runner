# Git-Sync Setup Script

Complete setup and management tool for automated git repository synchronization across multiple hosts.

## Overview

This script provides a comprehensive solution for managing the git-sync service, which automatically synchronizes Git repositories at configurable intervals. Perfect for keeping infrastructure-as-code, scripts, and configuration repositories up-to-date across multiple servers.

## Features

- 🚀 **One-command installation** - Install entire git-sync service
- 📦 **Repository management** - Add/remove repos with automatic configuration
- 🔄 **Multi-branch support** - Sync different branches per repository
- ⏰ **Configurable intervals** - Set sync frequency per repository
- 🌐 **Remote deployment** - Deploy to multiple hosts easily
- 🔍 **Status monitoring** - Check sync status and test connections
- 🧪 **Dry-run mode** - Preview changes before applying
- 📝 **Comprehensive logging** - Per-repository log files

## Quick Start

### Install via curl (Remote Execution)

```bash
# Install git-sync service
curl -fsSL https://codefuturist.github.io/remote-script-runner/scripts/bash/git-sync-setup.sh | sudo bash -s -- --install

# Add a repository
curl -fsSL https://codefuturist.github.io/remote-script-runner/scripts/bash/git-sync-setup.sh | sudo bash -s -- \
    --add-repo --repo-url git@github.com:user/repo.git
```

### Local Installation

```bash
# Download script
wget https://codefuturist.github.io/remote-script-runner/scripts/bash/git-sync-setup.sh
chmod +x git-sync-setup.sh

# Install service
sudo ./git-sync-setup.sh --install

# Add repositories
sudo ./git-sync-setup.sh --add-repo --repo-url git@github.com:user/automation-scripts.git
sudo ./git-sync-setup.sh --add-repo --repo-url git@github.com:user/iac-catalog.git --branch develop --interval 30
```

## Usage

### Installation Actions

#### Install Service
```bash
./git-sync-setup.sh --install
```

Installs:
- `/usr/local/bin/git-sync` - Core sync utility
- `/usr/local/bin/git-sync-manager` - Multi-repo management
- `/usr/local/bin/git-sync-branch` - Branch switching helper
- `/etc/git-sync.conf` - Configuration file
- `/var/log/git-sync/` - Log directory
- Cron jobs for automated syncing

#### Uninstall Service
```bash
./git-sync-setup.sh --uninstall
```

Removes binaries and cron jobs. Preserves configuration and repositories.

### Repository Management

#### Add Repository
```bash
# Basic usage (clones to /opt/repositories/repo-name)
./git-sync-setup.sh --add-repo --repo-url git@github.com:user/repo.git

# With custom settings
./git-sync-setup.sh --add-repo \
    --repo-url git@github.com:user/repo.git \
    --branch develop \
    --interval 30 \
    --repo-path /opt/custom/location
```

Parameters:
- `--repo-url` - Git repository URL (required)
- `--branch` - Branch to sync (default: main)
- `--interval` - Sync interval in minutes (default: 15)
- `--repo-path` - Custom clone location (default: /opt/repositories/[repo-name])

#### Remove Repository
```bash
./git-sync-setup.sh --remove-repo --repo-path /opt/repositories/my-repo
```

Removes from configuration and optionally deletes files.

### Monitoring & Management

#### List Configured Repositories
```bash
./git-sync-setup.sh --list
```

Shows:
- Configured repositories with branches and intervals
- Active cron jobs

#### Check Status
```bash
./git-sync-setup.sh --status
```

Displays current sync configuration and status.

#### Test All Syncs
```bash
./git-sync-setup.sh --test
```

Manually triggers sync for all configured repositories and shows results.

#### Update Cron Jobs
```bash
./git-sync-setup.sh --update
```

Re-reads configuration and updates cron jobs.

### Remote Deployment

#### Deploy to Another Host
```bash
./git-sync-setup.sh --deploy-to root@192.168.1.50
```

Copies:
- SSH keys
- git-sync tools
- Configuration file
- Sets up cron jobs on target host

### Options

#### Dry Run
```bash
./git-sync-setup.sh --install --dry-run
```

Shows what would be done without making changes.

#### Verbose Output
```bash
./git-sync-setup.sh --add-repo --repo-url git@github.com:user/repo.git --verbose
```

Enables detailed debug output.

## Examples

### Basic Setup

```bash
# 1. Install service
sudo ./git-sync-setup.sh --install

# 2. Add automation scripts (sync every 15 min from main)
sudo ./git-sync-setup.sh --add-repo \
    --repo-url git@github.com:myorg/automation-scripts.git

# 3. Add IaC catalog (sync every 30 min from develop)
sudo ./git-sync-setup.sh --add-repo \
    --repo-url git@github.com:myorg/iac-catalog.git \
    --branch develop \
    --interval 30

# 4. List configured repos
sudo ./git-sync-setup.sh --list

# 5. Test syncing
sudo ./git-sync-setup.sh --test
```

### Multi-Environment Setup

```bash
# Production configs (hourly from production branch)
sudo ./git-sync-setup.sh --add-repo \
    --repo-url git@github.com:myorg/configs.git \
    --branch production \
    --interval 60 \
    --repo-path /opt/repositories/configs-production

# Staging configs (every 15 min from staging branch)
sudo ./git-sync-setup.sh --add-repo \
    --repo-url git@github.com:myorg/configs.git \
    --branch staging \
    --interval 15 \
    --repo-path /opt/repositories/configs-staging

# Dev configs (every 5 min from develop branch)
sudo ./git-sync-setup.sh --add-repo \
    --repo-url git@github.com:myorg/configs.git \
    --branch develop \
    --interval 5 \
    --repo-path /opt/repositories/configs-dev
```

### Deploy Across Infrastructure

```bash
# Install on first host
sudo ./git-sync-setup.sh --install
sudo ./git-sync-setup.sh --add-repo --repo-url git@github.com:myorg/scripts.git

# Deploy to additional hosts
sudo ./git-sync-setup.sh --deploy-to root@host2.example.com
sudo ./git-sync-setup.sh --deploy-to root@host3.example.com
```

### Remote Installation (No Download Required)

```bash
# Install and add repo in one command
curl -fsSL https://codefuturist.github.io/remote-script-runner/scripts/bash/git-sync-setup.sh | \
sudo bash -s -- --install && \
curl -fsSL https://codefuturist.github.io/remote-script-runner/scripts/bash/git-sync-setup.sh | \
sudo bash -s -- --add-repo --repo-url git@github.com:myorg/automation.git
```

## Configuration

### Configuration File Format

`/etc/git-sync.conf`:
```
# Format: <repo_path>:<branch>:<interval_minutes>

# Automation scripts (main branch, every 15 min)
/opt/repositories/scripts:main:15

# IaC catalog (develop branch, every 30 min)
/opt/repositories/iac-catalog:develop:30

# Production configs (production branch, hourly)
/opt/repositories/configs-prod:production:60
```

### Log Files

Each repository has its own log file:
```
/var/log/git-sync/scripts.log
/var/log/git-sync/iac-catalog.log
/var/log/git-sync/configs-prod.log
```

View logs:
```bash
# Tail specific repo
tail -f /var/log/git-sync/scripts.log

# Check all logs
ls -lh /var/log/git-sync/

# Search for errors
grep ERROR /var/log/git-sync/*.log
```

### SSH Key Configuration

Default SSH key path: `~/.ssh/id_ed25519_proxmox`

Custom SSH key:
```bash
./git-sync-setup.sh --add-repo \
    --repo-url git@github.com:user/repo.git \
    --ssh-key ~/.ssh/custom_key
```

## Architecture

### Components

1. **git-sync** - Core utility for syncing a single repository
2. **git-sync-manager** - Manages multiple repositories and cron jobs
3. **git-sync-branch** - Helper for switching branches
4. **git-sync-setup.sh** - This script - installation and management tool

### Directory Structure

```
/opt/repositories/          # Default repository location
├── scripts/
├── iac-catalog/
└── configs/

/etc/git-sync.conf          # Configuration

/usr/local/bin/             # Tools
├── git-sync
├── git-sync-manager
└── git-sync-branch

/var/log/git-sync/          # Logs
├── scripts.log
├── iac-catalog.log
└── configs.log
```

## Troubleshooting

### Check Installation
```bash
which git-sync git-sync-manager git-sync-branch
cat /etc/git-sync.conf
```

### Test Manually
```bash
# Test single repo
sudo git-sync /opt/repositories/scripts main

# Test all repos
sudo git-sync-manager test
```

### View Logs
```bash
# Recent activity
tail -50 /var/log/git-sync/scripts.log

# Follow live
tail -f /var/log/git-sync/*.log
```

### Check Cron Jobs
```bash
sudo crontab -l | grep git-sync-manager
```

### SSH Issues
```bash
# Test SSH key
ssh -i ~/.ssh/id_ed25519_proxmox -T git@github.com

# Add GitHub to known_hosts
ssh-keyscan github.com >> ~/.ssh/known_hosts
```

### Re-sync Configuration
```bash
# Edit config
sudo nano /etc/git-sync.conf

# Update cron jobs
sudo git-sync-manager update

# Test
sudo git-sync-manager test
```

## Best Practices

1. **Use appropriate intervals**
   - Critical configs: 5-15 minutes
   - Regular scripts: 15-30 minutes
   - Documentation: 30-60 minutes

2. **Branch strategy**
   - Production: `production` or `main` branch
   - Staging: `staging` branch
   - Development: `develop` branch

3. **Monitor logs regularly**
   ```bash
   # Weekly check
   grep ERROR /var/log/git-sync/*.log
   ```

4. **Test before production**
   ```bash
   ./git-sync-setup.sh --add-repo --repo-url <url> --dry-run
   ```

5. **Backup configuration**
   ```bash
   cp /etc/git-sync.conf /root/git-sync.conf.backup
   ```

## Security Considerations

- Runs as root (be careful with repository permissions)
- SSH keys must be properly secured (600 permissions)
- Repositories are world-readable (755) by default
- Logs contain no secrets but show sync activity
- Consider using deploy keys instead of personal SSH keys

## Requirements

- Bash 4.0+
- Git
- SSH access to Git repository
- Root/sudo access for installation
- Cron daemon

## License

Part of the remote-script-runner project.

## Related Tools

- **git-sync** - Core sync utility
- **git-sync-manager** - Multi-repository manager
- **git-sync-branch** - Branch switching helper

## Support

For issues and questions:
- GitHub: https://github.com/codefuturist/remote-script-runner
- Documentation: https://codefuturist.github.io/remote-script-runner/
