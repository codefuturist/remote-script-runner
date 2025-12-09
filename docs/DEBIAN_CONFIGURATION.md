# Debian System Service Configuration Guide

## Overview

This guide shows you how to configure and manage git-auto-sync as a system service on Debian (and Ubuntu/derivatives).

## Quick Start

### Option 1: Interactive Installer (Recommended)

```bash
# Run as root or with sudo
sudo bash git-auto-sync-manager.sh
```

The interactive manager will:
1. Install dependencies
2. Install the script to `/usr/local/bin`
3. Create configuration in `/etc/git-auto-sync`
4. Set up SystemD service
5. Enable and start the service

### Option 2: Manual Configuration

If you prefer manual setup, follow the steps below.

## File Locations on Debian

### System-Level (Running as root or system service)

```
/usr/local/bin/git-auto-sync.sh           # Executable script
/etc/git-auto-sync/repos.json             # Configuration file
/etc/systemd/system/git-auto-sync.service # SystemD service unit
/var/run/git-auto-sync/                   # Runtime files (PID, lock)
/var/lib/git-auto-sync/                   # State files (metrics)
/var/log/git-auto-sync/                   # Log files
```

### User-Level (Running as regular user)

```
~/.local/bin/git-auto-sync.sh                      # Executable script
~/.config/git-auto-sync/repos.json                 # Configuration file
~/.config/systemd/user/git-auto-sync.service       # SystemD user service
~/.cache/git-auto-sync/                            # Runtime files
~/.local/state/git-auto-sync/                      # State files, logs
```

## Manual Installation Steps

### 1. Install Dependencies

```bash
# Update package list
sudo apt update

# Install required packages
sudo apt install -y git jq

# Optional: Install Git LFS if you manage large files
sudo apt install -y git-lfs
```

### 2. Install the Script

```bash
# Download or copy the script
sudo cp git-auto-sync.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/git-auto-sync.sh

# Verify installation
git-auto-sync.sh --version
```

### 3. Create Configuration Directory

```bash
# Create config directory
sudo mkdir -p /etc/git-auto-sync

# Create configuration file
sudo nano /etc/git-auto-sync/repos.json
```

### 4. Configure Repositories

Create `/etc/git-auto-sync/repos.json`:

```json
{
  "validation": {
    "enabled": true,
    "max_retries": 3,
    "rollback_on_failure": true
  },
  "quick_check": {
    "enabled": true,
    "interval": 30
  },
  "repositories": [
    {
      "name": "dns-zones",
      "path": "/etc/bind/zones",
      "branch": "main",
      "remote": "origin",
      "mode": "safe",
      "validator": "/usr/local/bin/validate-dns-zones.sh",
      "post_hook": "/usr/local/bin/reload-bind.sh"
    }
  ]
}
```

### 5. Create SystemD Service

Create `/etc/systemd/system/git-auto-sync.service`:

```ini
[Unit]
Description=Git Auto-Sync Service
Documentation=https://github.com/codefuturist/remote-script-runner
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=git-sync
Group=git-sync
ExecStart=/usr/local/bin/git-auto-sync.sh --daemon --config /etc/git-auto-sync/repos.json --interval 300
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/etc/bind /var/log/git-auto-sync /var/lib/git-auto-sync

[Install]
WantedBy=multi-user.target
```

### 6. Create Service User (Recommended)

```bash
# Create dedicated user for the service
sudo useradd -r -s /bin/false -d /var/lib/git-auto-sync git-sync

# Create necessary directories
sudo mkdir -p /var/lib/git-auto-sync
sudo mkdir -p /var/log/git-auto-sync
sudo mkdir -p /var/run/git-auto-sync

# Set ownership
sudo chown -R git-sync:git-sync /var/lib/git-auto-sync
sudo chown -R git-sync:git-sync /var/log/git-auto-sync
sudo chown -R git-sync:git-sync /var/run/git-auto-sync

# Give access to repositories
sudo chown -R git-sync:git-sync /etc/bind/zones  # Example for DNS
```

### 7. Enable and Start Service

```bash
# Reload systemd to pick up the new service
sudo systemctl daemon-reload

# Enable service to start on boot
sudo systemctl enable git-auto-sync.service

# Start the service now
sudo systemctl start git-auto-sync.service

# Check service status
sudo systemctl status git-auto-sync.service
```

## Service Management

### Check Service Status

```bash
# View current status
sudo systemctl status git-auto-sync.service

# Check if service is running
sudo systemctl is-active git-auto-sync.service

# Check if service is enabled
sudo systemctl is-enabled git-auto-sync.service
```

### View Logs

```bash
# View recent logs
sudo journalctl -u git-auto-sync.service -n 50

# Follow logs in real-time
sudo journalctl -u git-auto-sync.service -f

# View logs with timestamp
sudo journalctl -u git-auto-sync.service --since "1 hour ago"

# View only errors
sudo journalctl -u git-auto-sync.service -p err

# View log file directly
sudo tail -f /var/log/git-auto-sync/sync.log
```

### Control Service

```bash
# Start service
sudo systemctl start git-auto-sync.service

# Stop service
sudo systemctl stop git-auto-sync.service

# Restart service
sudo systemctl restart git-auto-sync.service

# Reload configuration (without stopping)
sudo systemctl reload-or-restart git-auto-sync.service

# Disable service (won't start on boot)
sudo systemctl disable git-auto-sync.service

# Re-enable service
sudo systemctl enable git-auto-sync.service
```

## Configuration Management

### Edit Configuration

```bash
# Edit main configuration
sudo nano /etc/git-auto-sync/repos.json

# After editing, restart service
sudo systemctl restart git-auto-sync.service
```

### Validate Configuration

```bash
# Test configuration syntax (if jq is installed)
jq '.' /etc/git-auto-sync/repos.json

# Test sync manually before enabling service
sudo -u git-sync git-auto-sync.sh --config /etc/git-auto-sync/repos.json
```

### Add New Repository

Edit `/etc/git-auto-sync/repos.json` and add to the `repositories` array:

```json
{
  "name": "nginx-config",
  "path": "/etc/nginx/sites-available",
  "branch": "production",
  "remote": "origin",
  "mode": "safe",
  "validator": "/usr/local/bin/validate-nginx.sh",
  "post_hook": "/usr/local/bin/reload-nginx.sh"
}
```

Then restart:

```bash
sudo systemctl restart git-auto-sync.service
```

## Security Considerations

### 1. Use Dedicated User

**Never run as root!** Create a dedicated user:

```bash
sudo useradd -r -s /bin/false -d /var/lib/git-auto-sync git-sync
```

### 2. Set Proper Permissions

```bash
# Config should be readable by service user
sudo chown root:git-sync /etc/git-auto-sync/repos.json
sudo chmod 640 /etc/git-auto-sync/repos.json

# Repositories should be owned by service user
sudo chown -R git-sync:git-sync /path/to/repo
```

### 3. Restrict File System Access

The service file includes:

```ini
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/etc/bind /var/log/git-auto-sync /var/lib/git-auto-sync
```

Only add paths that the service actually needs to write to.

### 4. Use Validators

Always enable validation for critical configurations:

```json
{
  "validation": {
    "enabled": true,
    "max_retries": 3,
    "rollback_on_failure": true
  }
}
```

### 5. Secure Git Credentials

```bash
# Use SSH keys instead of passwords
sudo -u git-sync ssh-keygen -t ed25519 -C "git-sync@yourdomain.com"

# Add public key to your Git server
sudo cat /home/git-sync/.ssh/id_ed25519.pub

# Test connection
sudo -u git-sync ssh -T git@github.com
```

## Troubleshooting

### Service Won't Start

```bash
# Check service status
sudo systemctl status git-auto-sync.service

# View detailed error logs
sudo journalctl -u git-auto-sync.service -n 100 --no-pager

# Check file permissions
ls -la /etc/git-auto-sync/
ls -la /var/lib/git-auto-sync/
ls -la /var/run/git-auto-sync/

# Test script manually
sudo -u git-sync /usr/local/bin/git-auto-sync.sh --config /etc/git-auto-sync/repos.json
```

### Permission Denied Errors

```bash
# Check repository ownership
ls -la /path/to/repo/

# Fix ownership
sudo chown -R git-sync:git-sync /path/to/repo/

# Check SELinux (if enabled)
sudo setenforce 0  # Temporarily disable for testing
sudo ausearch -m avc -ts recent  # Check for SELinux denials
```

### Configuration Errors

```bash
# Validate JSON syntax
jq '.' /etc/git-auto-sync/repos.json

# Check for typos in paths
ls -la $(jq -r '.repositories[].path' /etc/git-auto-sync/repos.json)

# Test with debug logging
sudo -u git-sync LOG_LEVEL=DEBUG /usr/local/bin/git-auto-sync.sh --config /etc/git-auto-sync/repos.json -v
```

### Service Runs But Doesn't Sync

```bash
# Check if repositories are accessible
sudo -u git-sync git -C /path/to/repo status

# Test Git credentials
sudo -u git-sync git -C /path/to/repo fetch origin

# Check network connectivity
sudo -u git-sync ping -c 3 github.com

# View service output
sudo journalctl -u git-auto-sync.service -f
```

## Example Use Cases

### 1. DNS Zone Management

```json
{
  "repositories": [
    {
      "name": "bind-zones",
      "path": "/etc/bind/zones",
      "branch": "main",
      "validator": "/usr/local/bin/validate-zones.sh",
      "post_hook": "/usr/local/bin/reload-bind.sh"
    }
  ]
}
```

Validator script (`/usr/local/bin/validate-zones.sh`):
```bash
#!/bin/bash
errors=0
for zone in /etc/bind/zones/*.zone; do
  zone_name=$(basename "$zone" .zone)
  if ! named-checkzone "$zone_name" "$zone" >/dev/null 2>&1; then
    echo "ERROR: Invalid zone: $zone" >&2
    ((errors++))
  fi
done
exit $errors
```

Post-hook script (`/usr/local/bin/reload-bind.sh`):
```bash
#!/bin/bash
systemctl reload bind9
```

### 2. Nginx Configuration

```json
{
  "repositories": [
    {
      "name": "nginx-sites",
      "path": "/etc/nginx/sites-available",
      "branch": "production",
      "validator": "/usr/local/bin/validate-nginx.sh",
      "post_hook": "/usr/local/bin/reload-nginx.sh"
    }
  ]
}
```

### 3. Application Configuration

```json
{
  "repositories": [
    {
      "name": "app-config",
      "path": "/etc/myapp/config",
      "branch": "main",
      "validator": "/usr/local/bin/validate-yaml.sh",
      "post_hook": "/usr/local/bin/restart-app.sh"
    }
  ]
}
```

## Performance Tuning

### Adjust Check Interval

For high-priority systems (DNS, etc.):
```json
{
  "quick_check": {
    "enabled": true,
    "interval": 15
  }
}
```

For low-priority systems:
```json
{
  "quick_check": {
    "enabled": true,
    "interval": 300
  }
}
```

### Resource Limits

Add to service file:
```ini
[Service]
CPUQuota=20%
MemoryMax=256M
TasksMax=10
```

## Monitoring

### Metrics File

Check metrics at `/var/lib/git-auto-sync/metrics.json`:

```bash
sudo cat /var/lib/git-auto-sync/metrics.json | jq
```

### Set Up Alerts

Example with systemd-notify:

```bash
# Create override
sudo systemctl edit git-auto-sync.service

# Add:
[Service]
NotifyAccess=main
WatchdogSec=60
```

### Integration with Monitoring Tools

- **Prometheus**: Export metrics from metrics.json
- **Nagios**: Check service status and log for errors
- **Zabbix**: Monitor systemd service state
- **Grafana**: Dashboard for sync statistics

## Backup and Recovery

### Backup Configuration

```bash
# Backup config
sudo cp /etc/git-auto-sync/repos.json /etc/git-auto-sync/repos.json.backup

# Backup service file
sudo cp /etc/systemd/system/git-auto-sync.service /etc/git-auto-sync/
```

### Restore from Backup

The script automatically creates backups before syncing. To restore:

```bash
# View available backups
ls -la /path/to/repo/.git-auto-sync-backups/

# Restore manually
cd /path/to/repo
git reset --hard <backup-commit-hash>
```

## Uninstall

```bash
# Stop and disable service
sudo systemctl stop git-auto-sync.service
sudo systemctl disable git-auto-sync.service

# Remove service file
sudo rm /etc/systemd/system/git-auto-sync.service
sudo systemctl daemon-reload

# Remove script
sudo rm /usr/local/bin/git-auto-sync.sh

# Remove configuration (optional)
sudo rm -rf /etc/git-auto-sync

# Remove user (optional)
sudo userdel git-sync
sudo rm -rf /var/lib/git-auto-sync
sudo rm -rf /var/log/git-auto-sync
```

## Additional Resources

- SystemD documentation: `man systemd.service`
- Git documentation: `man git`
- Project repository: https://github.com/codefuturist/remote-script-runner
- Report issues: https://github.com/codefuturist/remote-script-runner/issues

## Summary

**Quick Setup:**
```bash
sudo bash git-auto-sync-manager.sh
```

**Manual Setup:**
1. Install dependencies: `sudo apt install git jq`
2. Copy script: `sudo cp git-auto-sync.sh /usr/local/bin/`
3. Create config: `/etc/git-auto-sync/repos.json`
4. Create service: `/etc/systemd/system/git-auto-sync.service`
5. Enable: `sudo systemctl enable --now git-auto-sync.service`

**Management:**
```bash
sudo systemctl status git-auto-sync    # Check status
sudo journalctl -u git-auto-sync -f    # View logs
sudo systemctl restart git-auto-sync   # Restart
```

That's it! Your Debian system is now automatically syncing Git repositories! 🚀
