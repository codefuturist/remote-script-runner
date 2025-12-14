# Examples Directory

This directory contains example configurations and files for Remote Script Runner scripts.

## Git Auto-Sync Examples

### Configuration File

[`git-auto-sync-config.json`](./git-auto-sync-config.json) - Example JSON configuration for multi-repository sync

```bash
# Use with the script
./scripts/bash/git-auto-sync.sh --config examples/git-auto-sync-config.json
```

### Post-Sync Hook

[`post-sync-hook-example.sh`](./post-sync-hook-example.sh) - Example post-sync hook script that runs after successful sync

```bash
# Reference in config or command line
./scripts/bash/git-auto-sync.sh -r /repo --hook examples/post-sync-hook-example.sh
```

## Systemd Integration

[`systemd/git-auto-sync.service`](./systemd/git-auto-sync.service) - SystemD service unit file for Linux

### Installation

```bash
# Copy service file
sudo cp examples/systemd/git-auto-sync.service /etc/systemd/system/

# Copy script to system location
sudo cp scripts/bash/git-auto-sync.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/git-auto-sync.sh

# Create config directory
sudo mkdir -p /etc/git-auto-sync
sudo cp examples/git-auto-sync-config.json /etc/git-auto-sync/repos.json

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable git-auto-sync
sudo systemctl start git-auto-sync

# Check status
sudo systemctl status git-auto-sync

# View logs
sudo journalctl -u git-auto-sync -f
```

## macOS LaunchAgent

[`launchd/com.user.git-auto-sync.plist`](./launchd/com.user.git-auto-sync.plist) - LaunchAgent for macOS

### Installation

```bash
# Copy script
sudo cp scripts/bash/git-auto-sync.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/git-auto-sync.sh

# Create config directory
mkdir -p ~/.config/git-auto-sync
cp examples/git-auto-sync-config.json ~/.config/git-auto-sync/repos.json

# Edit the plist to use your username
sed 's/username/YOUR_USERNAME/g' examples/launchd/com.user.git-auto-sync.plist > ~/Library/LaunchAgents/com.user.git-auto-sync.plist

# Load the agent
launchctl load ~/Library/LaunchAgents/com.user.git-auto-sync.plist

# Start the agent
launchctl start com.user.git-auto-sync

# Check if running
launchctl list | grep git-auto-sync

# View logs
tail -f /tmp/git-auto-sync.log
```

## Quick Start Examples

### Single Repository Sync

```bash
# Basic sync
./scripts/bash/git-auto-sync.sh -r /path/to/repo

# With specific branch
./scripts/bash/git-auto-sync.sh -r /path/to/repo -b develop

# Force mode (discard local changes)
./scripts/bash/git-auto-sync.sh -r /path/to/repo -m force
```

### Multiple Repositories

```bash
# Sync multiple repos at once
./scripts/bash/git-auto-sync.sh \
  -r /path/to/repo1 \
  -r /path/to/repo2 \
  -r /path/to/repo3
```

### Git LFS Support

```bash
# Enable Git LFS
./scripts/bash/git-auto-sync.sh -r /path/to/repo --lfs
```

### Daemon Mode

```bash
# Run continuously (every 5 minutes)
./scripts/bash/git-auto-sync.sh --daemon -r /path/to/repo

# Custom interval (every 10 minutes)
./scripts/bash/git-auto-sync.sh --daemon --interval 600 -r /path/to/repo

# With config file
./scripts/bash/git-auto-sync.sh --daemon --config examples/git-auto-sync-config.json
```

### Remote Execution

```bash
# Quick sync via curl
curl -fsSL https://codefuturist.github.io/remote-script-runner/scripts/bash/git-auto-sync.sh | bash -s -- \
  -r /path/to/repo

# With options
curl -fsSL https://codefuturist.github.io/remote-script-runner/scripts/bash/git-auto-sync.sh | bash -s -- \
  -r /var/www/mysite -m force --hook /usr/local/bin/deploy.sh -v
```

## Configuration File Format

The JSON configuration file supports multiple repositories with different settings:

```json
[
  {
    "name": "my-project",
    "path": "/home/user/projects/my-project",
    "branch": "main",
    "remote": "origin",
    "mode": "safe",
    "use_lfs": true,
    "post_hook": "/usr/local/bin/notify.sh"
  },
  {
    "name": "website",
    "path": "/var/www/html",
    "branch": "production",
    "remote": "origin",
    "mode": "force",
    "use_lfs": false,
    "post_hook": "/usr/local/bin/restart-webserver.sh"
  }
]
```

### Configuration Fields

- **name** (string): Unique identifier for the repository
- **path** (string): Absolute path to the git repository
- **branch** (string): Branch to sync (default: "main")
- **remote** (string): Remote name (default: "origin")
- **mode** (string): Sync mode - "safe", "force", or "pull" (default: "safe")
- **use_lfs** (boolean): Enable Git LFS (default: false)
- **post_hook** (string): Path to post-sync hook script (optional)

## Sync Modes

### Safe Mode (Recommended)

- Stashes local changes before syncing
- Attempts fast-forward merge
- Falls back to reset if needed
- **Best for:** Production environments

### Force Mode

- Hard resets to remote
- Discards all local changes
- **Best for:** Deployment servers, mirrors

### Pull Mode

- Standard git pull
- Falls back to reset on conflict
- **Best for:** Development environments

## See Also

- [Git Auto-Sync Documentation](../docs/GIT_AUTO_SYNC.md)
- [Remote Script Runner README](../README.md)
- [Scripts Documentation](../scripts/README.md)
