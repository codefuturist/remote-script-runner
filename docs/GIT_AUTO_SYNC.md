# Git Auto-Sync Documentation

## Overview

`git-auto-sync.sh` is a production-grade Git repository synchronization tool with advanced features including daemon mode, multi-repository support, Git LFS integration, and comprehensive error handling.

## Features

✅ **Multi-Repository Support** - Sync multiple repositories simultaneously  
✅ **Daemon Mode** - Continuous background synchronization  
✅ **Git LFS Support** - Automatic LFS file synchronization  
✅ **Multiple Sync Modes** - Safe, force, and pull strategies  
✅ **Internet Detection** - Waits for connectivity before syncing  
✅ **Retry Logic** - Exponential backoff on failures  
✅ **Lock Management** - Prevents concurrent sync processes  
✅ **Post-Sync Hooks** - Execute custom scripts after sync  
✅ **Metrics & Reporting** - JSON metrics file for monitoring  
✅ **Structured Logging** - Timestamped logs with log levels  
✅ **Remote Execution** - Run via curl for easy deployment  

## Installation

### Quick Start (Remote Execution)

```bash
# Single repository sync
curl -fsSL https://codefuturist.github.io/remote-script-runner/scripts/bash/git-auto-sync.sh | bash -s -- \
  -r /path/to/repo

# With Git LFS
curl -fsSL https://codefuturist.github.io/remote-script-runner/scripts/bash/git-auto-sync.sh | bash -s -- \
  -r /path/to/repo --lfs

# Daemon mode with config
curl -fsSL https://codefuturist.github.io/remote-script-runner/scripts/bash/git-auto-sync.sh | bash -s -- \
  --daemon --config /path/to/config.json --interval 300
```

### Local Installation

```bash
# Clone repository
git clone https://github.com/yourusername/remote-script-runner.git
cd remote-script-runner

# Run locally
./scripts/bash/git-auto-sync.sh -r /path/to/repo
```

## Usage

### Basic Usage

```bash
# Sync single repository
./git-auto-sync.sh -r /path/to/repo

# Sync specific branch
./git-auto-sync.sh -r /path/to/repo -b develop

# Force mode (discard local changes)
./git-auto-sync.sh -r /path/to/repo -m force

# Enable Git LFS
./git-auto-sync.sh -r /path/to/repo --lfs

# Verbose logging
./git-auto-sync.sh -r /path/to/repo -v
```

### Multiple Repositories

```bash
# Sync multiple repos at once
./git-auto-sync.sh \
  -r /path/to/repo1 \
  -r /path/to/repo2 \
  -r /path/to/repo3
```

### Daemon Mode

```bash
# Run continuously (every 5 minutes)
./git-auto-sync.sh --daemon -r /path/to/repo

# Custom interval (every 10 minutes)
./git-auto-sync.sh --daemon --interval 600 -r /path/to/repo

# With config file
./git-auto-sync.sh --daemon --config repos.json --interval 300
```

### Configuration File

Create a JSON configuration file for complex setups:

```json
[
  {
    "name": "my-project",
    "path": "/home/user/projects/my-project",
    "branch": "main",
    "remote": "origin",
    "mode": "safe",
    "use_lfs": true,
    "post_hook": "/usr/local/bin/notify-sync.sh"
  },
  {
    "name": "backup-repo",
    "path": "/home/user/backups/repo",
    "branch": "develop",
    "remote": "origin",
    "mode": "force",
    "use_lfs": false,
    "post_hook": ""
  }
]
```

Use with:

```bash
./git-auto-sync.sh --config repos.json
```

## Sync Modes

### Safe Mode (Recommended)

- Stashes local changes before syncing
- Attempts fast-forward merge first
- Falls back to reset if fast-forward fails
- **Best for:** Production environments

```bash
./git-auto-sync.sh -r /path/to/repo -m safe
```

### Force Mode

- Discards all local changes
- Hard resets to remote branch
- Cleans untracked files
- **Best for:** Deployments, mirrors

```bash
./git-auto-sync.sh -r /path/to/repo -m force
```

### Pull Mode

- Standard `git pull` behavior
- Falls back to reset on conflict
- **Best for:** Development environments

```bash
./git-auto-sync.sh -r /path/to/repo -m pull
```

## Command-Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `-c, --config FILE` | Configuration file (JSON) | - |
| `-d, --daemon` | Run in daemon mode | off |
| `-i, --interval SECONDS` | Sync interval for daemon | 300 |
| `-r, --repo PATH` | Repository path to sync | - |
| `-b, --branch NAME` | Branch to sync | main |
| `-m, --mode MODE` | Sync mode (safe/force/pull) | safe |
| `-l, --lfs` | Enable Git LFS support | off |
| `--remote NAME` | Remote name | origin |
| `--hook SCRIPT` | Post-sync hook script | - |
| `-v, --verbose` | Enable debug logging | off |
| `-h, --help` | Show help message | - |
| `--version` | Show version | - |

## Post-Sync Hooks

Execute custom scripts after successful sync:

### Hook Script Format

```bash
#!/bin/bash
# Post-sync hook script
# Arguments: repo_name repo_path old_commit new_commit

REPO_NAME="$1"
REPO_PATH="$2"
OLD_COMMIT="$3"
NEW_COMMIT="$4"

echo "Repository $REPO_NAME synced: $OLD_COMMIT → $NEW_COMMIT"

# Custom actions
cd "$REPO_PATH"
npm install
systemctl restart myapp
```

### Usage

```bash
./git-auto-sync.sh -r /path/to/repo --hook /path/to/hook.sh
```

## Monitoring & Metrics

### Metrics File

The script writes sync statistics to `/tmp/git-auto-sync-metrics.json`:

```json
{
  "daemon": {
    "started_at": "2025-12-09T14:27:00.000Z",
    "pid": 12345,
    "status": "running"
  },
  "sync_stats": {
    "total_runs": 42,
    "successful_runs": 40,
    "failed_runs": 2,
    "last_run": "2025-12-09T14:32:00.000Z"
  },
  "last_sync": {
    "repository": "my-project",
    "status": "success",
    "commit": "abc1234",
    "timestamp": "2025-12-09T14:32:00.000Z"
  }
}
```

### Log Levels

Set via environment variable or `-v` flag:

```bash
export LOG_LEVEL=DEBUG
./git-auto-sync.sh -r /path/to/repo

# Or
./git-auto-sync.sh -r /path/to/repo -v
```

Levels: `DEBUG`, `INFO` (default), `WARN`, `ERROR`, `FATAL`

## Systemd Integration

### Create Service File

```ini
# /etc/systemd/system/git-auto-sync.service
[Unit]
Description=Git Auto-Sync Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=gituser
ExecStart=/usr/local/bin/git-auto-sync.sh --daemon --config /etc/git-auto-sync/repos.json
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

### Enable Service

```bash
# Copy script
sudo cp git-auto-sync.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/git-auto-sync.sh

# Create config directory
sudo mkdir -p /etc/git-auto-sync
sudo cp repos.json /etc/git-auto-sync/

# Enable service
sudo systemctl enable git-auto-sync
sudo systemctl start git-auto-sync

# Check status
sudo systemctl status git-auto-sync

# View logs
sudo journalctl -u git-auto-sync -f
```

## macOS LaunchAgent

### Create LaunchAgent

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.git-auto-sync</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/git-auto-sync.sh</string>
        <string>--daemon</string>
        <string>--config</string>
        <string>/Users/username/.config/git-auto-sync/repos.json</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/git-auto-sync.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/git-auto-sync.err</string>
</dict>
</plist>
```

### Install LaunchAgent

```bash
# Copy to LaunchAgents
cp com.user.git-auto-sync.plist ~/Library/LaunchAgents/

# Load agent
launchctl load ~/Library/LaunchAgents/com.user.git-auto-sync.plist

# Start agent
launchctl start com.user.git-auto-sync

# Check status
launchctl list | grep git-auto-sync
```

## Docker Integration

### Dockerfile

```dockerfile
FROM alpine:latest

RUN apk add --no-cache bash git git-lfs jq curl

COPY git-auto-sync.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/git-auto-sync.sh

VOLUME ["/repos", "/config"]

ENTRYPOINT ["/usr/local/bin/git-auto-sync.sh"]
CMD ["--daemon", "--config", "/config/repos.json", "--interval", "300"]
```

### Docker Compose

```yaml
version: '3.8'

services:
  git-auto-sync:
    build: .
    container_name: git-auto-sync
    restart: unless-stopped
    volumes:
      - ./repos:/repos
      - ./config:/config:ro
      - ./ssh:/root/.ssh:ro
    environment:
      - LOG_LEVEL=INFO
      - GIT_SYNC_CONFIG=/config/repos.json
```

## Troubleshooting

### Permission Denied

```bash
# Fix SSH key permissions
chmod 600 ~/.ssh/id_rsa
chmod 644 ~/.ssh/id_rsa.pub

# Fix repository permissions
sudo chown -R $USER:$USER /path/to/repo
```

### Lock File Exists

```bash
# Remove stale lock
rm /tmp/git-auto-sync.lock

# Or wait for timeout (30 seconds)
```

### Git LFS Not Working

```bash
# Install Git LFS
brew install git-lfs  # macOS
apt-get install git-lfs  # Ubuntu

# Initialize LFS
cd /path/to/repo
git lfs install
```

### Internet Connection Issues

The script automatically waits for internet connection (up to 5 retries). To adjust:

Edit the `check_internet_connection()` function:

```bash
local max_retries=10  # Increase retries
local retry_delay=5   # Increase delay
```

## Security Considerations

### SSH Keys

```bash
# Generate deploy key (read-only)
ssh-keygen -t ed25519 -C "git-auto-sync" -f ~/.ssh/git-auto-sync

# Add to repository as deploy key (GitHub/GitLab)
cat ~/.ssh/git-auto-sync.pub
```

### HTTPS Tokens

```bash
# Use credential helper
git config --global credential.helper store

# Or use SSH URLs instead
git remote set-url origin git@github.com:user/repo.git
```

### File Permissions

```bash
# Restrict script permissions
chmod 700 git-auto-sync.sh

# Restrict config permissions
chmod 600 repos.json
```

## Best Practices

1. **Use Safe Mode** for production environments
2. **Enable Git LFS** if your repo uses large files
3. **Set appropriate intervals** (300-900 seconds recommended)
4. **Monitor metrics file** for sync health
5. **Use post-sync hooks** for deployment automation
6. **Test with dry-run** first (use `-v` for debugging)
7. **Use SSH keys** instead of passwords
8. **Run as non-root user** when possible
9. **Enable logging** to track sync history
10. **Use configuration file** for multiple repositories

## Examples

### Production Deployment

```bash
# Deploy website automatically
./git-auto-sync.sh \
  --daemon \
  -r /var/www/mysite \
  -b production \
  -m force \
  --hook /usr/local/bin/deploy-website.sh \
  --interval 600
```

### Development Environment

```bash
# Keep local dev in sync
./git-auto-sync.sh \
  -r ~/projects/myapp \
  -b develop \
  -m safe \
  --lfs \
  -v
```

### Backup System

```bash
# Mirror repositories for backup
./git-auto-sync.sh \
  --config backup-repos.json \
  --daemon \
  --interval 3600
```

## Support

For issues, questions, or contributions:
- GitHub Issues: https://github.com/yourusername/remote-script-runner/issues
- Documentation: https://codefuturist.github.io/remote-script-runner/

## License

MIT License - See LICENSE file for details.
