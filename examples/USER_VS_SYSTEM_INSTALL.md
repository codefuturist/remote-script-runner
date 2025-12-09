# User-Level vs System-Level Installation Guide

## Overview

Git Auto-Sync supports both **user-level** and **system-level** installations, allowing you to manage repositories in your home directory as a regular user, or system-wide as root.

## Quick Comparison

| Aspect | User-Level | System-Level |
|--------|-----------|--------------|
| **Runs as** | Regular user | Root or system user |
| **Install location** | `~/.local/bin` | `/usr/local/bin` |
| **Config location** | `~/.config/git-auto-sync` | `/etc/git-auto-sync` |
| **Runtime files** | `~/.cache/git-auto-sync` | `/var/run/git-auto-sync` |
| **State files** | `~/.local/state/git-auto-sync` | `/var/lib/git-auto-sync` |
| **Logs** | `~/.local/state/git-auto-sync/logs` | `/var/log/git-auto-sync` |
| **Service (Linux)** | `systemctl --user` | `systemctl` (system) |
| **LaunchAgent (macOS)** | `~/Library/LaunchAgents` | `/Library/LaunchDaemons` |
| **Sudo required** | No | Yes (for install) |
| **Auto-start** | On user login | On system boot |

## User-Level Installation

### When to Use

✅ **Perfect for:**
- Managing repositories in your home directory
- Development environments
- Personal projects
- Testing and experimentation
- When you don't have root access
- Per-user Git repository synchronization

❌ **Not suitable for:**
- System-wide services
- Repositories outside your home directory
- Services that must run before user login

### Installation

```bash
# Interactive installer (detects user mode automatically)
bash git-auto-sync-manager.sh

# Or manual installation
mkdir -p ~/.local/bin
cp git-auto-sync.sh ~/.local/bin/
chmod +x ~/.local/bin/git-auto-sync.sh

# Add to PATH if not already there
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### Configuration

Create config in `~/.config/git-auto-sync/repos.json`:

```json
{
  "quick_check": {
    "enabled": true,
    "interval": 30
  },
  "repositories": [
    {
      "name": "my-dotfiles",
      "path": "/home/username/dotfiles",
      "branch": "main"
    },
    {
      "name": "my-projects",
      "path": "/home/username/projects/website",
      "branch": "develop"
    }
  ]
}
```

### Running

```bash
# One-time sync
git-auto-sync.sh --config ~/.config/git-auto-sync/repos.json

# Daemon mode (manual)
git-auto-sync.sh --daemon --config ~/.config/git-auto-sync/repos.json &

# Or use systemd user service (Linux)
systemctl --user enable git-auto-sync
systemctl --user start git-auto-sync

# Or use LaunchAgent (macOS)
launchctl load ~/Library/LaunchAgents/com.user.git-auto-sync.plist
```

### File Locations (User Mode)

```
~/.local/bin/git-auto-sync.sh              # Executable
~/.config/git-auto-sync/repos.json         # Configuration
~/.cache/git-auto-sync/git-auto-sync.lock  # Lock file
~/.cache/git-auto-sync/git-auto-sync.pid   # PID file
~/.local/state/git-auto-sync/metrics.json  # Metrics
~/.local/state/git-auto-sync/logs/sync.log # Logs
~/.config/systemd/user/git-auto-sync.service # SystemD (Linux)
~/Library/LaunchAgents/com.user.git-auto-sync.plist # LaunchAgent (macOS)
```

## System-Level Installation

### When to Use

✅ **Perfect for:**
- System-wide configuration management
- DNS zone synchronization (`/etc/bind/zones`)
- Web server configs (`/etc/nginx`, `/var/www`)
- Service configurations (`/etc/myapp`)
- Multiple users accessing same repos
- Services that must run on boot

❌ **Not suitable for:**
- Personal user repositories
- When you don't have root access

### Installation

```bash
# Interactive installer as root
sudo bash git-auto-sync-manager.sh

# Or set environment variable
export GIT_SYNC_SYSTEM_INSTALL=true
bash git-auto-sync-manager.sh

# Or manual installation
sudo mkdir -p /usr/local/bin
sudo cp git-auto-sync.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/git-auto-sync.sh
```

### Configuration

Create config in `/etc/git-auto-sync/repos.json`:

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
      "validator": "/usr/local/bin/validate-dns-zones.sh",
      "post_hook": "/usr/local/bin/reload-bind.sh"
    },
    {
      "name": "nginx-config",
      "path": "/etc/nginx/sites-available",
      "branch": "production",
      "validator": "/usr/local/bin/validate-nginx.sh",
      "post_hook": "/usr/local/bin/reload-nginx.sh"
    }
  ]
}
```

### Running

```bash
# One-time sync (as root)
sudo git-auto-sync.sh --config /etc/git-auto-sync/repos.json

# Or use systemd service (Linux)
sudo systemctl enable git-auto-sync
sudo systemctl start git-auto-sync

# Or use LaunchDaemon (macOS)
sudo launchctl load /Library/LaunchDaemons/com.system.git-auto-sync.plist
```

### File Locations (System Mode)

```
/usr/local/bin/git-auto-sync.sh           # Executable
/etc/git-auto-sync/repos.json             # Configuration
/var/run/git-auto-sync/git-auto-sync.lock # Lock file
/var/run/git-auto-sync/git-auto-sync.pid  # PID file
/var/lib/git-auto-sync/metrics.json       # Metrics
/var/log/git-auto-sync/sync.log           # Logs
/etc/systemd/system/git-auto-sync.service # SystemD (Linux)
/Library/LaunchDaemons/com.system.git-auto-sync.plist # LaunchDaemon (macOS)
```

## Permission Considerations

### User-Level Permissions

```bash
# Repositories must be owned by the user or readable
ls -la ~/dotfiles/
# drwxr-xr-x user user dotfiles/

# Config directory is user-owned
ls -ld ~/.config/git-auto-sync/
# drwxr-xr-x user user ~/.config/git-auto-sync/

# No sudo required for any operations
```

### System-Level Permissions

```bash
# Repositories should be owned by sync user
sudo chown -R git-sync:git-sync /etc/bind/zones/

# Config directory is root-owned
ls -ld /etc/git-auto-sync/
# drwxr-xr-x root root /etc/git-auto-sync/

# Service runs as specific user (not root!)
# See SystemD service User= directive

# Sudo required for service management
sudo systemctl restart git-auto-sync
```

## Mixed Mode (Advanced)

You can run both user and system instances simultaneously!

### Example: Personal + System Repos

```bash
# User instance for personal repos
systemctl --user start git-auto-sync

# System instance for DNS zones
sudo systemctl start git-auto-sync
```

They use different config files and lock files, so no conflicts!

## Migration Between Modes

### User to System

```bash
# 1. Stop user service
systemctl --user stop git-auto-sync

# 2. Copy config
sudo mkdir -p /etc/git-auto-sync
sudo cp ~/.config/git-auto-sync/repos.json /etc/git-auto-sync/

# 3. Update paths in config (if needed)
sudo vi /etc/git-auto-sync/repos.json

# 4. Install system-wide
sudo bash git-auto-sync-manager.sh

# 5. Start system service
sudo systemctl start git-auto-sync
```

### System to User

```bash
# 1. Stop system service
sudo systemctl stop git-auto-sync

# 2. Copy config
mkdir -p ~/.config/git-auto-sync
sudo cp /etc/git-auto-sync/repos.json ~/.config/git-auto-sync/
sudo chown $USER:$USER ~/.config/git-auto-sync/repos.json

# 3. Update paths in config
vi ~/.config/git-auto-sync/repos.json

# 4. Install user-level
bash git-auto-sync-manager.sh

# 5. Start user service
systemctl --user start git-auto-sync
```

## Troubleshooting

### Permission Denied Errors

**User mode:**
```bash
# Check ownership
ls -la ~/repository/

# Fix if needed
chown -R $USER:$USER ~/repository/

# Check config directory
ls -ld ~/.config/git-auto-sync/
```

**System mode:**
```bash
# Repository should be accessible by sync user
sudo -u git-sync ls -la /etc/bind/zones/

# Fix permissions
sudo chown -R git-sync:git-sync /etc/bind/zones/

# Check SELinux (if applicable)
sudo setenforce 0  # Temporarily for testing
```

### Lock File Issues

**User mode:**
```bash
# Remove stale lock
rm ~/.cache/git-auto-sync/git-auto-sync.lock
```

**System mode:**
```bash
# Remove stale lock
sudo rm /var/run/git-auto-sync/git-auto-sync.lock
```

### Service Not Starting

**User mode (SystemD):**
```bash
# Check service status
systemctl --user status git-auto-sync

# View logs
journalctl --user -u git-auto-sync -n 50

# Check if user lingering is enabled (for auto-start)
loginctl enable-linger $USER
```

**System mode (SystemD):**
```bash
# Check service status
sudo systemctl status git-auto-sync

# View logs
sudo journalctl -u git-auto-sync -n 50

# Check service file
sudo systemctl cat git-auto-sync
```

## Best Practices

### User-Level

1. ✅ Use for personal repositories in home directory
2. ✅ Keep sensitive configs in `~/.config/git-auto-sync/`
3. ✅ Use `systemctl --user` for automatic startup
4. ✅ Enable user lingering for always-on sync
5. ✅ Monitor with `journalctl --user -u git-auto-sync -f`

### System-Level

1. ✅ Run as dedicated user (not root!)
2. ✅ Use strict file permissions (644 for configs, 755 for scripts)
3. ✅ Enable validation for critical configs (DNS, nginx, etc.)
4. ✅ Set up monitoring and alerting
5. ✅ Regular testing of rollback mechanisms
6. ✅ Document post-sync hooks clearly

## Security Considerations

### User-Level

- ✅ Repos limited to user's permissions
- ✅ No privilege escalation possible
- ✅ Isolated from system services
- ⚠️ Only as secure as user account

### System-Level

- ⚠️ Runs with elevated permissions
- ✅ Use dedicated service user (not root!)
- ✅ Restrict config file permissions
- ✅ Use sudoers file for post-hooks if needed
- ✅ Enable validation to prevent bad configs
- ✅ Use rollback on failure

## Examples

### User-Level: Dotfiles Sync

```json
{
  "quick_check": {
    "enabled": true,
    "interval": 60
  },
  "repositories": [
    {
      "name": "dotfiles",
      "path": "/home/username/.dotfiles",
      "branch": "main",
      "mode": "safe"
    }
  ]
}
```

### System-Level: DNS + Nginx

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
      "validator": "/usr/local/bin/validate-dns-zones.sh",
      "post_hook": "/usr/local/bin/reload-bind.sh"
    },
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

## Summary

Choose the right installation mode for your use case:

- **User-level**: Personal repos, no root needed, runs on login
- **System-level**: System configs, runs as service user, boot startup
- **Both**: Run multiple instances for different purposes

The tool automatically detects the mode and configures paths accordingly! 🚀
