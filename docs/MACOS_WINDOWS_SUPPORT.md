# macOS and Windows Support

## Overview

git-auto-sync now supports macOS and Windows in addition to Linux, providing cross-platform Git repository synchronization.

## macOS Support

### Requirements

- macOS 10.12 (Sierra) or later
- Bash 3.2+ (built-in) or Bash 5+ (via Homebrew)
- Git (Xcode Command Line Tools or Homebrew)
- YAML parser: `yq` or Python 3

### Installation on macOS

#### Option 1: Homebrew (Recommended)

```bash
# Install dependencies
brew install git yq

# Install git-auto-sync
sudo cp git-auto-sync.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/git-auto-sync.sh

# Setup configuration
sudo mkdir -p /usr/local/etc/git-auto-sync
sudo cp examples/config.yaml /usr/local/etc/git-auto-sync/

# For system-wide service (requires sudo)
sudo mkdir -p /var/log/git-auto-sync
sudo mkdir -p /var/lib/git-auto-sync
sudo cp examples/launchd-daemon.plist /Library/LaunchDaemons/com.gitautosync.daemon.plist
sudo launchctl load /Library/LaunchDaemons/com.gitautosync.daemon.plist
```

#### Option 2: User-Level Installation

```bash
# Install dependencies
brew install git yq

# Install git-auto-sync (user level, no sudo needed)
cp git-auto-sync.sh /usr/local/bin/  # or ~/bin/
chmod +x /usr/local/bin/git-auto-sync.sh

# Setup user configuration
mkdir -p "$HOME/Library/Application Support/git-auto-sync"
mkdir -p "$HOME/Library/Logs/git-auto-sync"
cp examples/config.yaml "$HOME/Library/Application Support/git-auto-sync/"

# Setup LaunchAgent (user service)
cp examples/launchd-agent.plist ~/Library/LaunchAgents/com.gitautosync.agent.plist
launchctl load ~/Library/LaunchAgents/com.gitautosync.agent.plist
```

### macOS File Locations

#### System-Level (requires sudo)
```
Configuration:    /usr/local/etc/git-auto-sync/config.yaml
Environment:      /usr/local/etc/git-auto-sync/environment
LaunchDaemon:     /Library/LaunchDaemons/com.gitautosync.daemon.plist
Logs:             /var/log/git-auto-sync/
State:            /var/lib/git-auto-sync/
Binary:           /usr/local/bin/git-auto-sync.sh
```

#### User-Level (no sudo)
```
Configuration:    ~/Library/Application Support/git-auto-sync/config.yaml
Environment:      ~/Library/Application Support/git-auto-sync/environment
LaunchAgent:      ~/Library/LaunchAgents/com.gitautosync.agent.plist
Logs:             ~/Library/Logs/git-auto-sync/
State:            ~/Library/Application Support/git-auto-sync/
Binary:           ~/bin/git-auto-sync.sh or /usr/local/bin/
```

### Service Management on macOS

#### LaunchDaemon (System-Wide)

```bash
# Load service
sudo launchctl load /Library/LaunchDaemons/com.gitautosync.daemon.plist

# Unload service
sudo launchctl unload /Library/LaunchDaemons/com.gitautosync.daemon.plist

# Start service
sudo launchctl start com.gitautosync.daemon

# Stop service
sudo launchctl stop com.gitautosync.daemon

# Check status
sudo launchctl list | grep gitautosync

# View logs
tail -f /var/log/git-auto-sync/stdout.log
tail -f /var/log/git-auto-sync/stderr.log
```

#### LaunchAgent (User-Level)

```bash
# Load service
launchctl load ~/Library/LaunchAgents/com.gitautosync.agent.plist

# Unload service
launchctl unload ~/Library/LaunchAgents/com.gitautosync.agent.plist

# Start service
launchctl start com.gitautosync.agent

# Stop service
launchctl stop com.gitautosync.agent

# Check status
launchctl list | grep gitautosync

# View logs
tail -f ~/Library/Logs/git-auto-sync/stdout.log
tail -f ~/Library/Logs/git-auto-sync/stderr.log
```

### macOS-Specific Features

- **Native launchd Integration**: Uses macOS's native service management
- **Application Support**: Follows macOS conventions for app data storage
- **Homebrew Support**: Easy installation via Homebrew
- **No Root Required**: Can run entirely as user without sudo
- **Logs in Standard Location**: ~/Library/Logs for user services

### Package Installation on macOS

```bash
# Homebrew (recommended)
brew install git yq

# Or using Python
brew install python3
pip3 install pyyaml

# Or using Ruby (pre-installed)
# Ruby YAML support is built-in on macOS
```

---

## Windows Support

### Requirements

- Windows 10 or later / Windows Server 2016 or later
- One of the following environments:
  - **Git Bash** (recommended, comes with Git for Windows)
  - **WSL2** (Windows Subsystem for Linux)
  - **MSYS2**
  - **Cygwin**
- Git for Windows
- YAML parser (varies by environment)

### Installation on Windows

#### Option 1: Git Bash (Recommended)

```bash
# Install Git for Windows from https://git-scm.com/download/win
# This includes Git Bash

# Open Git Bash

# Install YAML parser
# Option A: Install Python for Windows, then:
pip install pyyaml

# Option B: Install via MSYS2 (if available)
pacman -S yq

# Install git-auto-sync
mkdir -p /c/ProgramData/git-auto-sync
cp git-auto-sync.sh /c/ProgramData/git-auto-sync/
cp examples/config.yaml /c/ProgramData/git-auto-sync/

# Make it accessible
echo 'export PATH="/c/ProgramData/git-auto-sync:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

#### Option 2: WSL2 (Windows Subsystem for Linux)

```bash
# Install WSL2 and Ubuntu from Microsoft Store

# In WSL2 terminal, follow Linux installation:
sudo apt update
sudo apt install git yq

sudo cp git-auto-sync.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/git-auto-sync.sh

sudo mkdir -p /etc/git-auto-sync
sudo cp examples/config.yaml /etc/git-auto-sync/
sudo cp examples/systemd-service /etc/systemd/system/git-auto-sync.service

sudo systemctl daemon-reload
sudo systemctl enable --now git-auto-sync
```

#### Option 3: MSYS2

```bash
# Install MSYS2 from https://www.msys2.org/

# Open MSYS2 terminal

# Install dependencies
pacman -S git yq

# Install git-auto-sync (user level)
mkdir -p ~/.config/git-auto-sync
cp git-auto-sync.sh /usr/local/bin/  # or ~/bin/
chmod +x /usr/local/bin/git-auto-sync.sh
cp examples/config.yaml ~/.config/git-auto-sync/
```

### Windows File Locations

#### Git Bash / Native Windows
```
Configuration:    %LOCALAPPDATA%\git-auto-sync\config.yaml
                  (typically C:\Users\<username>\AppData\Local\git-auto-sync\)
Environment:      %LOCALAPPDATA%\git-auto-sync\environment
Logs:             %LOCALAPPDATA%\git-auto-sync\logs\
State:            %LOCALAPPDATA%\git-auto-sync\
Binary:           C:\ProgramData\git-auto-sync\git-auto-sync.sh
```

#### WSL2
```
Configuration:    /etc/git-auto-sync/config.yaml (system)
                  ~/.config/git-auto-sync/config.yaml (user)
Service:          /etc/systemd/system/git-auto-sync.service
Logs:             /var/log/git-auto-sync/ (system)
                  ~/.local/state/git-auto-sync/logs/ (user)
```

#### MSYS2
```
Configuration:    ~/.config/git-auto-sync/config.yaml
Logs:             ~/.local/state/git-auto-sync/logs/
Binary:           /usr/local/bin/git-auto-sync.sh
```

### Service Management on Windows

#### Windows Task Scheduler (Git Bash)

```powershell
# Import task (PowerShell as Administrator)
schtasks /Create /XML "C:\path\to\windows-task.xml" /TN "Git-Auto-Sync"

# Start task
schtasks /Run /TN "Git-Auto-Sync"

# Stop task
schtasks /End /TN "Git-Auto-Sync"

# Query status
schtasks /Query /TN "Git-Auto-Sync" /V /FO LIST

# Delete task
schtasks /Delete /TN "Git-Auto-Sync" /F
```

#### WSL2 Service Management

```bash
# Use standard Linux systemctl commands
sudo systemctl start git-auto-sync
sudo systemctl stop git-auto-sync
sudo systemctl status git-auto-sync
sudo systemctl enable git-auto-sync
```

#### Manual Daemon Mode (All Windows Environments)

```bash
# Run in daemon mode
git-auto-sync.sh --daemon --config ~/.config/git-auto-sync/config.yaml --interval 300 &

# Or in Git Bash with nohup
nohup git-auto-sync.sh --daemon --config ~/.config/git-auto-sync/config.yaml --interval 300 > /dev/null 2>&1 &

# Check running process
ps aux | grep git-auto-sync
```

### Windows-Specific Features

- **Multiple Environment Support**: Git Bash, WSL2, MSYS2, Cygwin
- **Windows Task Scheduler**: Native Windows service integration
- **%LOCALAPPDATA% Support**: Follows Windows conventions for app data
- **Path Translation**: Automatic Windows/Unix path conversion
- **Git for Windows Integration**: Works seamlessly with Git Bash

### Package Installation on Windows

#### Git Bash
```bash
# Install Python for Windows from python.org
pip install pyyaml

# Or download yq binary from https://github.com/mikefarah/yq/releases
# Place in C:\Program Files\Git\usr\bin\
```

#### WSL2
```bash
sudo apt install git yq python3-yaml
```

#### MSYS2
```bash
pacman -S git yq python-yaml
```

#### Cygwin
```bash
# Use Cygwin setup.exe to install:
# - git
# - python3
# - python3-yaml
```

---

## Cross-Platform Usage

### Running on All Platforms

The same commands work across Linux, macOS, and Windows:

```bash
# Single sync
git-auto-sync.sh --config /path/to/config.yaml

# Daemon mode
git-auto-sync.sh --daemon --config /path/to/config.yaml --interval 300

# Add repository
git-auto-sync.sh --repo /path/to/repo --branch main

# Check version
git-auto-sync.sh --version

# Help
git-auto-sync.sh --help
```

### Configuration File (Same Format)

```yaml
# Works on Linux, macOS, and Windows
validation:
  enabled: true
  max_retries: 3
  rollback_on_failure: true

quick_check:
  enabled: true
  interval: 30

repositories:
  - name: my-repo
    path: /path/to/repo  # Unix-style paths work in Git Bash/WSL
    branch: main
    mode: safe
```

### Path Considerations

#### Linux
```yaml
path: /etc/config
path: /home/user/repos/project
```

#### macOS
```yaml
path: /usr/local/etc/config
path: /Users/username/repos/project
```

#### Windows (Git Bash)
```yaml
path: /c/ProgramData/config
path: /c/Users/username/repos/project
# Or use ~ for home directory
path: ~/repos/project
```

#### Windows (WSL2)
```yaml
path: /mnt/c/Users/username/repos/project  # Windows drives
path: /home/username/repos/project         # WSL filesystem
```

---

## Platform Comparison

| Feature | Linux | macOS | Windows |
|---------|-------|-------|---------|
| **Init System** | SystemD/OpenRC | launchd | Task Scheduler/SystemD(WSL) |
| **Package Manager** | apt/dnf/pacman | Homebrew | pip/pacman(MSYS2) |
| **System Config** | /etc/ | /usr/local/etc/ | %PROGRAMDATA% |
| **User Config** | ~/.config/ | ~/Library/Application Support/ | %LOCALAPPDATA% |
| **Logs** | /var/log/ or ~/.local/state/ | ~/Library/Logs/ | %LOCALAPPDATA%/logs/ |
| **Service Management** | systemctl/rc-service | launchctl | schtasks/systemctl |
| **Auto-Start** | ✅ Yes | ✅ Yes | ✅ Yes |
| **User-Level Service** | ✅ Yes | ✅ Yes | ✅ Yes (WSL) |
| **No Admin Required** | ✅ Yes (user mode) | ✅ Yes (LaunchAgent) | ✅ Yes (user task) |

---

## Troubleshooting

### macOS

```bash
# Check if service is loaded
launchctl list | grep gitautosync

# Check logs
tail -50 ~/Library/Logs/git-auto-sync/stdout.log
tail -50 ~/Library/Logs/git-auto-sync/stderr.log

# Test manually
/usr/local/bin/git-auto-sync.sh --config "$HOME/Library/Application Support/git-auto-sync/config.yaml"

# Check permissions
ls -la ~/Library/LaunchAgents/com.gitautosync.agent.plist
```

### Windows (Git Bash)

```bash
# Check if process is running
ps aux | grep git-auto-sync

# Check logs
tail -50 $LOCALAPPDATA/git-auto-sync/logs/sync.log

# Test manually
bash /c/ProgramData/git-auto-sync/git-auto-sync.sh --config $LOCALAPPDATA/git-auto-sync/config.yaml

# Check Python/YAML
python -c "import yaml; print(yaml.__version__)"
```

### Windows (WSL2)

```bash
# Use standard Linux troubleshooting
sudo systemctl status git-auto-sync
sudo journalctl -u git-auto-sync -n 50

# Check WSL status
wsl --status
wsl --list --verbose
```

---

## Platform-Specific Notes

### macOS
- **Bash Version**: macOS ships with Bash 3.2 (GPL2). For Bash 5+, use Homebrew
- **SIP (System Integrity Protection)**: Limits modification of /usr/bin. Use /usr/local/bin instead
- **Gatekeeper**: May need to approve the script on first run
- **launchd**: More lightweight than SystemD, ideal for macOS

### Windows
- **Line Endings**: Git for Windows handles CRLF/LF conversion automatically
- **Path Separators**: Use forward slashes (/) in Git Bash/WSL, even on Windows
- **Permissions**: Windows permissions differ from Unix. Consider ACLs for shared repos
- **WSL vs Git Bash**: WSL2 provides full Linux environment; Git Bash is lighter

---

## Summary

✅ **Linux**: Full support with SystemD/OpenRC  
✅ **macOS**: Native launchd integration, Homebrew support  
✅ **Windows**: Git Bash, WSL2, MSYS2, Task Scheduler support  

🎯 **Universal Configuration**: Same YAML format across all platforms  
🎯 **Platform-Aware**: Automatically adapts to OS conventions  
🎯 **Service Integration**: Native service management on each platform  
🎯 **No-Sudo Options**: User-level installation available on all platforms  

git-auto-sync now works seamlessly on Linux, macOS, and Windows! 🚀
